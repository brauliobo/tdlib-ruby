require 'logger'

module TD
  module Logging
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def dlog(msg)
        puts msg if ENV['TDLOG'].to_i > 0
      end
    end

    def dlog(msg)
      puts msg if ENV['TDLOG'].to_i > 0
    end

    def log_update(update)
      type = update.class.name.split('::').last
      relevant = update_relevant?(update)
      
      payload = begin
        update.respond_to?(:to_h) ? update.to_h : update.inspect
      rescue
        update.inspect
      end

      if relevant
        puts "[UPDATE] received: #{type} #{payload}"
      else
        brief = payload.is_a?(String) ? payload[0,50] : payload.inspect[0,50]
        puts "[UPDATE] received: #{type} #{brief}..."
      end
    end

    private

    def update_relevant?(update)
      return true if update.respond_to?(:message) && update.message
      return true if update.respond_to?(:last_message) && update.last_message
      
      if update.respond_to?(:chat) && update.chat
        return true if update.chat.respond_to?(:last_message) && update.chat.last_message
      end
      
      type = update.class.name.split('::').last
      type.include?("Message") || type.include?("NewChat")
    rescue
      false
    end
  end
end
