require_relative 'logging'
require 'fileutils'

module TD
  class Client
    include TD::Logging
    
    class << self
      include TD::Logging
    end
    
    # Configuration and setup
    def self.configure_for_bot(api_id: nil, api_hash: nil, base_dir: nil)
      TD.configure do |config|
        config.client.api_id   = api_id || ENV['TDLIB_API_ID']
        config.client.api_hash = api_hash || ENV['TDLIB_API_HASH']
        
        base   = base_dir || ENV['TDLIB_BASE_DIR'] || File.join(Dir.pwd, '.tdlib')
        db_dir = File.join(base, 'db')
        fs_dir = File.join(base, 'files')
        
        FileUtils.mkdir_p([db_dir, fs_dir]) rescue nil
        
        config.client.database_directory = db_dir
        config.client.files_directory    = fs_dir
      end
      
      dlog "[TD_CONF] api_id=#{ENV['TDLIB_API_ID'].to_s.sub(/\d{3}\d+/, '***')} api_hash=#{(ENV['TDLIB_API_HASH']||'')[0,3]}*** db=#{TD.config.client.database_directory} files=#{TD.config.client.files_directory}"
      dlog "[TD_ENV] present_api_id=#{!ENV['TDLIB_API_ID'].to_s.empty?} present_api_hash=#{!ENV['TDLIB_API_HASH'].to_s.empty?}"
      
      TD::Api.set_log_verbosity_level 0
    end
    
    # Authentication handling
    def setup_authentication_handlers
      on TD::Types::Update::AuthorizationState do |update|
        handle_auth_state(update.authorization_state)
      end
    end
    
    def wait_for_ready(timeout: 600)
      timeout.times do |i|
        auth_state = get_authorization_state.value.authorization_state rescue nil
        dlog "[AUTH_WAIT] poll #{i}: state=#{auth_state&.class&.name&.split('::')&.last}" if i % 50 == 0
        break if auth_state.is_a?(TD::Types::AuthorizationState::Ready)
        sleep 0.2
      end
      
      auth_state = get_authorization_state.value.authorization_state rescue nil
      auth_state.is_a?(TD::Types::AuthorizationState::Ready)
    end
    
    def get_self_id
      @self_id ||= begin
        opt = get_option(name: 'my_id').value(5) rescue nil
        if opt && opt.respond_to?(:value)
          dlog "[SELF_OPT] my_id=#{opt.value}"
          opt.value
        else
          me_result = get_me.value(15) rescue nil
          if me_result && me_result.respond_to?(:id)
            dlog "[SELF] user_id=#{me_result.id}"
            me_result.id
          else
            dlog "[SELF] failed to get self_id"
            nil
          end
        end
      end
    end
    
    def set_online_status
      dlog "[ONLINE] setting bot as online"
      set_option(name: 'online', value: TD::Types::OptionValue::Boolean.new(value: true)).value(10)
      
      # Enable message-related options
      set_option(name: 'use_message_database', value: TD::Types::OptionValue::Boolean.new(value: true)).value(5) rescue nil
      set_option(name: 'use_chat_info_database', value: TD::Types::OptionValue::Boolean.new(value: true)).value(5) rescue nil
      set_option(name: 'notification_group_count_max', value: TD::Types::OptionValue::Integer.new(value: 100)).value(5) rescue nil
      set_option(name: 'notification_group_size_max', value: TD::Types::OptionValue::Integer.new(value: 10)).value(5) rescue nil
      set_option(name: 'receive_all_update_messages', value: TD::Types::OptionValue::Boolean.new(value: true)).value(5) rescue nil
      
      dlog "[ONLINE] bot marked as online successfully"
    rescue => e
      dlog "[ONLINE] error setting online status: #{e.class}: #{e.message}"
    end
    
    def load_all_chats
      lists = [TD::Types::ChatList::Main.new, TD::Types::ChatList::Archive.new]
      lists.each do |lst|
        load_chats(chat_list: lst, limit: 1000).value(5) rescue nil
      end
    end
    
    private
    
    def handle_auth_state(state)
      state_name = state.class.name.split('::').last
      dlog "[AUTH] state=#{state_name}"
      
      case state
      when TD::Types::AuthorizationState::WaitTdlibParameters
        dlog "[AUTH] waiting tdlib params; api_id?=#{!ENV['TDLIB_API_ID'].to_s.empty?} api_hash?=#{!ENV['TDLIB_API_HASH'].to_s.empty?} db=#{TD.config.client.database_directory} files=#{TD.config.client.files_directory}"
        
        # Set TDLib parameters with all required fields
        params = TD.config.client.to_h
        params[:system_language_code] ||= 'en'
        params[:device_model] ||= 'Ruby TD client'
        params[:application_version] ||= '1.0'
        params[:system_version] ||= 'Unknown'
        
        set_tdlib_parameters(parameters: params)
        dlog "[AUTH] tdlib parameters set"
        
      when TD::Types::AuthorizationState::WaitPhoneNumber
        handle_phone_input
        
      when TD::Types::AuthorizationState::WaitCode
        handle_code_input
        
      when TD::Types::AuthorizationState::WaitPassword
        handle_password_input
        
      when TD::Types::AuthorizationState::Ready
        puts "[READY] TDLib authorization is READY"
        @auth_ready = true
      end
    end
    
    def handle_phone_input
      dlog "[AUTH] waiting phone number"
      phone = ENV['TDLIB_PHONE']
      unless phone && !phone.empty?
        print "Enter phone number with +CC (e.g. +15551234567): "
        STDOUT.flush
        phone = STDIN.gets&.strip
      end
      
      if phone && !phone.empty?
        set_authentication_phone_number phone_number: phone, settings: nil
        dlog "[AUTH] phone submitted"
      else
        dlog "[AUTH] phone not provided"
      end
    rescue => e
      dlog "[AUTH] phone_error: #{e.class}: #{e.message}"
    end
    
    def handle_code_input
      dlog "[AUTH] waiting login code"
      code = ENV['TDLIB_CODE']
      unless code && !code.empty?
        print "Enter code (from Telegram): "
        STDOUT.flush
        code = STDIN.gets&.strip
      end
      
      if code && !code.empty?
        check_authentication_code code: code
        dlog "[AUTH] code submitted"
      else
        dlog "[AUTH] code not provided"
      end
    rescue => e
      dlog "[AUTH] code_error: #{e.class}: #{e.message}"
    end
    
    def handle_password_input
      require 'io/console'
      dlog "[AUTH] waiting 2FA password"
      pass = ENV['TDLIB_PASSWORD']
      unless pass && !pass.empty?
        print "Enter 2FA password: "
        STDOUT.flush
        pass = STDIN.noecho(&:gets)&.strip
        puts
      end
      
      if pass && !pass.empty?
        check_authentication_password password: pass
        dlog "[AUTH] password submitted"
      else
        dlog "[AUTH] password not provided"
      end
    rescue => e
      dlog "[AUTH] password_error: #{e.class}: #{e.message}"
    end
  end
end
