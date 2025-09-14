require_relative 'logging'
require_relative 'file_manager'

module TD
  class MessageSender
    include TD::Logging
    
    attr_reader :client, :file_manager, :message_id_map
    
    def initialize(client)
      @client = client
      @file_manager = TD::FileManager.new(client)
      @message_id_map = {}
      setup_message_tracking
    end
    
    def send_text(chat_id, text, parse_mode: 'MarkdownV2')
      formatted_text = parse_markdown_text(text.to_s, parse_mode)
      
      content = TD::Types::InputMessageContent::Text.new(
        text: formatted_text,
        link_preview_options: nil,
        clear_draft: false
      )
      
      dlog "[TD_SEND_TEXT] chat=#{chat_id} text=#{text[0,50]}..."
      
      sent = client.send_message(
        chat_id: chat_id,
        message_thread_id: 0,
        reply_to: nil,
        options: nil,
        reply_markup: nil,
        input_message_content: content
      ).value(15)
      
      msg_id = sent&.id || 0
      dlog "[TD_SEND_TEXT] sent id=#{msg_id}"
      
      # Track message ID for editing
      if msg_id > 0
        @message_id_map[msg_id] = msg_id
      end
      
      { message_id: msg_id, text: text }
    rescue => e
      dlog "[TD_SEND_TEXT_ERROR] #{e.class}: #{e.message}"
      { message_id: 0, text: text }
    end
    
    def send_video(chat_id, caption, video:, duration: 0, width: 0, height: 0, supports_streaming: false)
      path = file_manager.extract_local_path(video)
      raise 'video path missing' unless path && !path.empty?
      
      # Copy file to safe location to prevent cleanup issues
      safe_path = file_manager.copy_to_safe_location(path)
      
      content = TD::Types::InputMessageContent::Video.new(
        video: TD::Types::InputFile::Local.new(path: safe_path),
        thumbnail: file_manager.create_dummy_thumbnail,
        added_sticker_file_ids: [],
        duration: duration.to_i,
        width: width.to_i,
        height: height.to_i,
        supports_streaming: supports_streaming,
        caption: parse_markdown_text(caption.to_s),
        show_caption_above_media: false,
        self_destruct_type: nil,
        has_spoiler: false
      )
      
      dlog "[TD_SEND_VIDEO] chat=#{chat_id} path=#{safe_path}"
      
      sent = client.send_message(
        chat_id: chat_id,
        message_thread_id: 0,
        reply_to: nil,
        options: nil,
        reply_markup: nil,
        input_message_content: content
      ).value(60)
      
      { message_id: sent&.id || 0, text: caption }
    rescue => e
      dlog "[TD_SEND_VIDEO_ERROR] #{e.class}: #{e.message}"
      { message_id: 0, text: caption }
    end
    
    def send_document(chat_id, caption, document:)
      path = file_manager.extract_local_path(document)
      raise 'document path missing' unless path && !path.empty?
      
      # Copy file to safe location to prevent cleanup issues
      safe_path = file_manager.copy_to_safe_location(path)
      
      content = TD::Types::InputMessageContent::Document.new(
        document: TD::Types::InputFile::Local.new(path: safe_path),
        thumbnail: file_manager.create_dummy_thumbnail,
        disable_content_type_detection: false,
        caption: parse_markdown_text(caption.to_s)
      )
      
      dlog "[TD_SEND_DOC] chat=#{chat_id} path=#{safe_path}"
      
      sent = client.send_message(
        chat_id: chat_id,
        message_thread_id: 0,
        reply_to: nil,
        options: nil,
        reply_markup: nil,
        input_message_content: content
      ).value(60)
      
      { message_id: sent&.id || 0, text: caption }
    rescue => e
      dlog "[TD_SEND_DOC_ERROR] #{e.class}: #{e.message}"
      { message_id: 0, text: caption }
    end
    
    def edit_message(chat_id, message_id, text, parse_mode: 'MarkdownV2')
      # Use the correct message ID from mapping if available
      actual_id = @message_id_map[message_id] || message_id
      
      dlog "[TD_EDIT] chat=#{chat_id} id=#{message_id}->#{actual_id} text=#{text.to_s[0,50]}..."
      return if actual_id.to_i <= 0 || text.to_s.empty?
      
      # Parse markdown to get proper formatting entities
      formatted_text = parse_markdown_text(text.to_s, parse_mode)
      
      client.edit_message_text(
        chat_id: chat_id,
        message_id: actual_id,
        input_message_content: TD::Types::InputMessageContent::Text.new(
          text: formatted_text,
          link_preview_options: nil,
          clear_draft: false
        ),
        reply_markup: nil
      ).value(15)
      
      dlog "[TD_EDIT] success"
    rescue => e
      dlog "[TD_EDIT_ERROR] #{e.class}: #{e.message}"
    end
    
    def delete_message(chat_id, message_id)
      client.delete_messages(chat_id: chat_id, message_ids: [message_id], revoke: true)
      dlog "[TD_DELETE] chat=#{chat_id} id=#{message_id}"
    rescue => e
      dlog "[TD_DELETE_ERROR] #{e.class}: #{e.message}"
    end
    
    private
    
    def setup_message_tracking
      client.on TD::Types::Update::MessageSendSucceeded do |update|
        if update.respond_to?(:old_message_id) && update.respond_to?(:message) && update.message.respond_to?(:id)
          old_id = update.old_message_id
          new_id = update.message.id
          @message_id_map[old_id] = new_id
          dlog "[MSG_ID_UPDATE] #{old_id} -> #{new_id}"
        end
      end
    end
    
    def parse_markdown_text(text, parse_mode = 'MarkdownV2')
      return TD::Types::FormattedText.new(text: '', entities: []) if text.to_s.empty?
      
      # Use TDBot::Markdown if available, otherwise fallback to TDLib's parser
      if defined?(TDBot::Markdown)
        result = TDBot::Markdown.parse(client, text.to_s)
        dlog "[MARKDOWN_PARSE] '#{text[0,30]}...' -> #{result.entities.length} entities"
        result
      else
        # Fallback to TDLib's built-in parser
        parse_mode_obj = case parse_mode.to_s.downcase
        when 'markdownv2', 'markdown'
          TD::Types::TextParseMode::Markdown.new(version: 2)
        when 'html'
          TD::Types::TextParseMode::HTML.new
        else
          TD::Types::TextParseMode::Markdown.new(version: 2)
        end
        
        client.parse_text_entities(text: text.to_s, parse_mode: parse_mode_obj).value(5)
      end
    rescue => e
      dlog "[PARSE_MARKDOWN_ERROR] #{e.class}: #{e.message}"
      # Fallback to plain text
      TD::Types::FormattedText.new(text: text.to_s, entities: [])
    end
  end
end
