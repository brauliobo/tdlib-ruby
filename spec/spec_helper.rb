require 'rspec'
require 'tdlib-ruby'

# Mock SymMash for testing
class SymMash < Hash
  def initialize(hash = {})
    super()
    hash.each { |k, v| self[k] = v }
  end
  
  def method_missing(name, *args)
    key = name.to_s.chomp('=').to_sym
    if name.to_s.end_with?('=')
      self[key] = args.first
    else
      self[key] || (self[key.to_s] if key != key.to_s)
    end
  end
  
  def respond_to_missing?(name, include_private = false)
    true
  end
end

include TD

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  
  # Filter out integration specs by default (they require real TDLib connection)
  config.filter_run_excluding :integration
  
  # Add timeout to prevent hanging specs
  config.around(:each) do |example|
    timeout_thread = Thread.new do
      sleep 3
      Thread.main.raise Timeout::Error, "Spec took longer than 3 seconds"
    end
    
    begin
      example.run
    ensure
      timeout_thread.kill
    end
  end
end
