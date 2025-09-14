require_relative 'logging'
require 'set'

module TD
  class MessageHandler
    include TD::Logging
    
    attr_reader :client, :known_chat_ids, :message_id_map
    
    def initialize(client)
      @client = client
      @known_chat_ids = Set.new
      @message_id_map = {}
      @pending_last_messages = []
    end
    
    def setup_handlers(&message_handler)
      @message_handler = message_handler
      setup_update_handlers
      setup_message_tracking
      setup_debug_logging if ENV['TDLOG'].to_i > 0
    end
    
    def should_process_message?(message)
      return false unless message
      
      # Skip outgoing messages
      return false if message.respond_to?(:is_outgoing) && message.is_outgoing
      
      # Skip messages from self
      self_id = client.get_self_id
      if self_id && message.sender_id&.respond_to?(:user_id)
        return false if message.sender_id.user_id == self_id
      end
      
      # Skip channel posts
      return false if message.respond_to?(:is_channel_post) && message.is_channel_post
      
      # Skip messages from chats (non-user senders)
      return false if message.sender_id&.respond_to?(:chat_id)
      
      # Skip Telegram service messages
      if message.sender_id&.respond_to?(:user_id)
        return false if message.sender_id.user_id == 777000
      end
      
      true
    end
    
    def extract_message_text(message)
      case message.content
      when TD::Types::MessageContent::Text
        message.content.text&.text
      when TD::Types::MessageContent::Photo,
           TD::Types::MessageContent::Video,
           TD::Types::MessageContent::Audio,
           TD::Types::MessageContent::Document
        message.content.caption&.text
      else
        nil
      end
    end
    
    def create_message_object(orig_msg)
      text = extract_message_text(orig_msg)
      
      msg = orig_msg.to_h.merge(
        chat_id: orig_msg.chat_id,
        chat: { id: orig_msg.chat_id },
        from: { id: (orig_msg.sender_id.respond_to?(:user_id) ? orig_msg.sender_id.user_id : nil) },
        text: text,
        id: orig_msg.id
      )
      
      # Add media attachments
      case orig_msg.content
      when TD::Types::MessageContent::Audio then msg[:audio] = orig_msg.content.audio
      when TD::Types::MessageContent::Video then msg[:video] = orig_msg.content.video
      when TD::Types::MessageContent::Document then msg[:document] = orig_msg.content.document
      end
      
      # Using OpenStruct as SymMash might not be available
      require 'ostruct'
      OpenStruct.new(msg)
    end
    
    def mark_as_read(message)
      client.view_messages(
        chat_id: message.chat_id,
        message_ids: [message.id],
        source: nil,
        force_read: true
      )
      dlog "[READ] chat=#{message.chat_id} id=#{message.id}"
    rescue => e
      dlog "[READ_ERROR] #{e.class}: #{e.message}"
    end
    
    def process_unread_messages
      return unless ENV['TDLIB_PROCESS_UNREAD'].to_s == '1'
      return unless client.wait_for_ready
      
      dlog "[UNREAD_PROCESS] starting unread message processing"
      client.set_online_status
      client.load_all_chats
      
      processed = 0
      self_id = client.get_self_id
      
      # Global search for recent messages
      processed += process_global_search(self_id)
      
      # Per-chat search fallback
      processed += process_known_chats(self_id) if processed < 10
      
      dlog "[UNREAD_COMPLETE] processed #{processed} unread messages"
    end
    
    private
    
    def setup_update_handlers
      client.on TD::Types::Update::NewMessage do |update|
        dlog "[NEW_MSG] received new message update"
        handle_incoming_message(update.message)
      end
      
      client.on TD::Types::Update::ChatLastMessage do |update|
        next unless update.respond_to?(:last_message) && update.last_message
        dlog "[FALLBACK] ChatLastMessage chat=#{update.chat_id} id=#{update.last_message.id}"
        @known_chat_ids << update.chat_id if update.respond_to?(:chat_id)
        @pending_last_messages << update.last_message
        handle_incoming_message(update.last_message) if ENV['TDLIB_PROCESS_UNREAD'].to_s == '1'
      end
    end
    
    def setup_message_tracking
      # Track message ID mapping for edits
      client.on TD::Types::Update::MessageSendSucceeded do |update|
        if update.respond_to?(:old_message_id) && update.respond_to?(:message) && update.message.respond_to?(:id)
          old_id = update.old_message_id
          new_id = update.message.id
          @message_id_map[old_id] = new_id
          dlog "[MSG_ID_UPDATE] #{old_id} -> #{new_id}"
        end
      end
      
      # Track chat IDs from various update sources
      client.on TD::Types::Update::NewChat do |update|
        cid = update.chat&.id rescue nil
        @known_chat_ids << cid if cid
        if update.chat && update.chat.respond_to?(:last_message) && update.chat.last_message
          dlog "[FALLBACK] NewChat last_message chat=#{cid} id=#{update.chat.last_message.id}"
          handle_incoming_message(update.chat.last_message)
        end
      end
      
      client.on TD::Types::Update::ChatAddedToList do |update|
        @known_chat_ids << update.chat_id if update.respond_to?(:chat_id)
      end
      
      client.on TD::Types::Update::ChatPosition do |update|
        @known_chat_ids << update.chat_id if update.respond_to?(:chat_id)
      end
    end
    
    def setup_debug_logging
      # Log connection state changes
      client.on TD::Types::Update::ConnectionState do |update|
        dlog "[NET] state=#{update.state.class.name.split('::').last}"
      end
      
      # Log unread counters
      client.on TD::Types::Update::UnreadMessageCount do |update|
        dlog "[UNREAD] messages=#{update.unread_count} unmuted=#{update.unread_unmuted_count}"
      end
      
      client.on TD::Types::Update::UnreadChatCount do |update|
        dlog "[UNREAD_CHAT] total=#{update.unread_count} unmuted=#{update.unread_unmuted_count}"
      end
      
      # Log option changes
      client.on TD::Types::Update::Option do |update|
        dlog "[OPT] #{update.name}=#{update.value.class.name.split('::').last}"
      end
      
      # Log all updates for debugging
      client.on TD::Types::Update do |update|
        log_update(update)
      end
    end
    
    def handle_incoming_message(orig_msg)
      return unless should_process_message?(orig_msg)
      
      dlog "[MSG] incoming id=#{orig_msg.id} chat=#{orig_msg.chat_id} type=#{orig_msg.content.class.name.split('::').last}"
      
      msg = create_message_object(orig_msg)
      mark_as_read(orig_msg)
      @message_handler&.call(msg)
    rescue => e
      dlog "[MSG_ERROR] #{e.class}: #{e.message}"
    end
    
    def process_global_search(self_id)
      processed = 0
      
      begin
        dlog "[GLOBAL] searching messages (schema signature)"
        global_search = client.search_messages(
          chat_list: TD::Types::ChatList::Main.new,
          only_in_channels: false,
          query: "",
          offset: 0,
          limit: 100,
          filter: nil,
          min_date: 0,
          max_date: 0
        ).value(20)
        
        if global_search && global_search.respond_to?(:messages) && global_search.messages && !global_search.messages.empty?
          dlog "[GLOBAL] found #{global_search.messages.size} messages"
          
          global_search.messages.first(30).each do |orig_msg|
            break if processed >= 10
            next unless should_process_message?(orig_msg)
            
            text = extract_message_text(orig_msg)
            next if text.nil? || text.empty?
            
            msg = create_message_object(orig_msg)
            puts "[UNREAD_MSG] chat=#{orig_msg.chat_id} id=#{orig_msg.id} #{text[0,80]}"
            STDOUT.flush rescue nil
            
            mark_as_read(orig_msg)
            
            begin
              dlog "[HANDLER] calling Bot#react for message id=#{orig_msg.id}"
              @message_handler.call(msg) if @message_handler
              dlog "[HANDLER] Bot#react completed for message id=#{orig_msg.id}"
              processed += 1
            rescue => e
              dlog "[HANDLER] error in Bot#react: #{e.class}: #{e.message}"
            end
          end
        else
          dlog "[GLOBAL] no messages returned"
        end
      rescue => e
        dlog "[GLOBAL] error: #{e.class}: #{e.message}"
      end
      
      processed
    end
    
    def process_known_chats(self_id)
      return 0 if @known_chat_ids.empty?
      
      processed = 0
      dlog "[CHAT_SEARCH] scanning #{@known_chat_ids.size} known chats"
      
      @known_chat_ids.first(50).each do |cid|
        break if processed >= 10
        
        begin
          found = client.search_chat_messages(
            chat_id: cid,
            query: "",
            sender_id: nil,
            from_message_id: 0,
            offset: 0,
            limit: 30,
            filter: nil,
            message_thread_id: 0,
            saved_messages_topic_id: 0
          ).value(10)
          
          msgs = found&.messages || []
          next if msgs.empty?
          
          dlog "[CHAT_SEARCH] chat=#{cid} messages=#{msgs.size}"
          
          msgs.each do |orig_msg|
            break if processed >= 10
            next unless should_process_message?(orig_msg)
            
            text = extract_message_text(orig_msg)
            next if text.nil? || text.empty?
            
            msg = create_message_object(orig_msg)
            puts "[UNREAD_MSG] chat=#{orig_msg.chat_id} id=#{orig_msg.id} #{text[0,80]}"
            STDOUT.flush rescue nil
            
            mark_as_read(orig_msg)
            
            begin
              @message_handler.call(msg) if @message_handler
              processed += 1
            rescue => e
              dlog "[HANDLER] error: #{e.class}: #{e.message}"
            end
          end
        rescue => e
          dlog "[CHAT_SEARCH] error chat=#{cid}: #{e.class}: #{e.message}"
        end
      end
      
      processed
    end
  end
end
