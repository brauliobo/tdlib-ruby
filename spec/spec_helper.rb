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
end
