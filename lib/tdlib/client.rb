require 'securerandom'
require_relative 'logging'
require 'fileutils'

# Simple client for TDLib.
class TD::Client
  include Concurrent
  include TD::ClientMethods
  include TD::Logging

  TIMEOUT = 20
  
  class << self
    include TD::Logging
  end

  def self.ready(*args)
    new(*args).connect
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

  # @param [FFI::Pointer] td_client
  # @param [TD::UpdateManager] update_manager
  # @param [Numeric] timeout
  # @param [Hash] extra_config optional configuration hash that will be merged into tdlib client configuration
  def initialize(td_client = TD::Api.client_create,
                 update_manager = TD::UpdateManager.new(td_client),
                 timeout: TIMEOUT,
                 **extra_config)
    @td_client = td_client
    @ready = false
    @alive = true
    @update_manager = update_manager
    @timeout = timeout
    @config = TD.config.client.to_h.merge(extra_config)
    @ready_condition_mutex = Mutex.new
    @ready_condition = ConditionVariable.new
  end

  # Adds initial authorization state handler and runs update manager
  # Returns future that will be fulfilled when client is ready
  # @return [Concurrent::Promises::Future]
  def connect
    setup_authentication_handlers
    @update_manager.run(callback: method(:handle_update))
    ready
  end

  # Authentication handling
  def setup_authentication_handlers
    on TD::Types::Update::AuthorizationState do |update|
      handle_auth_state(update.authorization_state)
    end
  end

  # Sends asynchronous request to the TDLib client and returns Promise object
  # @see TD::ClientMethods List of available queries as methods
  # @see https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md
  #   Concurrent::Promise documentation
  # @example
  #   client.broadcast(some_query).then { |result| puts result }.rescue { |error| puts [error.code, error.message] }
  # @param [Hash] query
  # @return [Concurrent::Promises::Future]
  def broadcast(query)
    return dead_client_promise if dead?

    Promises.future do
      condition = ConditionVariable.new
      extra = SecureRandom.uuid
      result = nil
      mutex = Mutex.new

      @update_manager << TD::UpdateHandler.new(TD::Types::Base, extra, disposable: true) do |update|
        mutex.synchronize do
          result = update
          condition.signal
        end
      end

      query['@extra'] = extra

      mutex.synchronize do
        send_to_td_client(query)
        condition.wait(mutex, @timeout)
        error = nil
        error = result if result.is_a?(TD::Types::Error)
        error = timeout_error if result.nil?
        raise TD::Error.new(error) if error
        result
      end
    end
  end

  # Sends asynchronous request to the TDLib client and returns received update synchronously
  # @param [Hash] query
  # @return [Hash]
  def fetch(query)
    broadcast(query).value!
  end

  alias broadcast_and_receive fetch

  # Synchronously executes TDLib request
  # Only a few requests can be executed synchronously
  # @param [Hash] query
  def execute(query)
    return dead_client_error if dead?
    TD::Api.client_execute(@td_client, query)
  end

  # Binds passed block as a handler for updates with type of *update_type*
  # @param [String, Class] update_type
  # @yield [update] yields update to the block as soon as it's received
  def on(update_type, &action)
    if update_type.is_a?(String)
      if (type_const = TD::Types::LOOKUP_TABLE[update_type])
        update_type = TD::Types.const_get("TD::Types::#{type_const}")
      else
        raise ArgumentError.new("Can't find class for #{update_type}")
      end
    end

    unless update_type < TD::Types::Base
      raise ArgumentError.new("Wrong type specified (#{update_type}). Should be of kind TD::Types::Base")
    end

    @update_manager << TD::UpdateHandler.new(update_type, &action)
  end

  # returns future that will be fulfilled when client is ready
  # @return [Concurrent::Promises::Future]
  def ready
    return dead_client_promise if dead?
    return Promises.fulfilled_future(self) if ready?

    Promises.future do
      @ready_condition_mutex.synchronize do
        next self if @ready || (@ready_condition.wait(@ready_condition_mutex, @timeout) && @ready)
        raise TD::Error.new(timeout_error)
      end
    end
  end

  # @deprecated
  def on_ready(&action)
    ready.then(&action).value!
  end

  # Stops update manager and destroys TDLib client
  def dispose
    return if dead?
    close.then { get_authorization_state }
  end

  def alive?
    @alive
  end

  def dead?
    !alive?
  end

  def ready?
    @ready
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

  def handle_update(update)
    return unless update.is_a?(TD::Types::Update::AuthorizationState) && update.authorization_state.is_a?(TD::Types::AuthorizationState::Closed)
    @alive = false
    @ready = false
    sleep 0.001
    TD::Api.client_destroy(@td_client)
    throw(:client_closed)
  end

  def send_to_td_client(query)
    return unless alive?
    TD::Api.client_send(@td_client, query)
  end

  def timeout_error
    TD::Types::Error.new(code: 0, message: 'Timeout error')
  end

  def dead_client_promise
    Promises.rejected_future(dead_client_error)
  end

  def dead_client_error
    TD::Error.new(TD::Types::Error.new(code: 0, message: 'TD client is dead'))
  end

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
      
      set_tdlib_parameters(**params)
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
      @ready_condition_mutex.synchronize do
        @ready = true
        @ready_condition.broadcast
      end
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
