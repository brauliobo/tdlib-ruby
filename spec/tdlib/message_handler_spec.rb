require 'spec_helper'

RSpec.describe TD::MessageHandler do
  StubSender = Struct.new(:user_id) unless const_defined?(:StubSender)
  TestMessage = Struct.new(:chat_id, :id, :sender_id, :content, keyword_init: true) do
    def is_outgoing = false
    def is_channel_post = false
    def to_h = {}
  end

  let(:client) do
    double(
      'TD::Client',
      get_self_id:    nil,
      view_messages:  nil
    )
  end

  let(:handler) { described_class.new(client) }
  let(:message) do
    TestMessage.new(
      chat_id:   123,
      id:        456,
      sender_id: StubSender.new(789),
      content:   Object.new
    )
  end

  before do
    allow(handler).to receive(:dlog)
    allow(handler).to receive(:create_message_object).and_return(SymMash.new)
    handler.instance_variable_set(:@message_handler, ->(msg) { handled << msg })
  end

  let(:handled) { [] }

  it 'dispatches each chat message id only once' do
    handler.send(:handle_incoming_message, message)
    handler.send(:handle_incoming_message, message)

    expect(handled.size).to eq(1)
    expect(client).to have_received(:view_messages).once
  end

  it 'builds a shallow message without converting the TDLib object graph' do
    allow(handler).to receive(:create_message_object).and_call_original
    expect(message).not_to receive(:to_h)

    result = handler.send(:create_message_object, message)

    expect(result).to include(
      chat_id: 123,
      chat: { id: 123 },
      from: { id: 789 },
      id: 456,
      text: nil,
      is_outgoing: false
    )
  end
end
