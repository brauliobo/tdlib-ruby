require 'concurrent-ruby'
require 'tdlib-schema'
require_relative '../../lib/tdlib/errors'
require_relative '../../lib/tdlib/public_chat_resolver'

RSpec.describe TD::PublicChatResolver do
  subject(:resolver) do
    Class.new do
      include TD::PublicChatResolver
    end.new
  end

  let(:username) { 'materials_channel' }
  let(:chat_type) { TD::Types::ChatType::Supergroup.new(supergroup_id: 42, is_channel: true) }
  let(:chat) { instance_double(TD::Types::Chat, id: -10042, type: chat_type) }
  let(:chats) { instance_double(TD::Types::Chats, chat_ids: [-10042]) }
  let(:usernames) do
    TD::Types::Usernames.new(
      active_usernames:   [username],
      disabled_usernames: [],
      editable_username:  username
    )
  end
  let(:supergroup) { instance_double(TD::Types::Supergroup, usernames: usernames) }

  it 'returns the exact public chat result' do
    allow(resolver).to receive(:search_public_chat).with(username: username).and_return(fulfilled(chat))

    expect(resolver.resolve_public_chat("@#{username}")).to eq(chat)
  end

  it 'falls back to public search and verifies the active username' do
    allow(resolver).to receive(:search_public_chat).and_return(rejected('USERNAME_NOT_OCCUPIED'))
    allow(resolver).to receive(:search_public_chats).with(query: username).and_return(fulfilled(chats))
    allow(resolver).to receive(:get_chat).with(chat_id: -10042).and_return(fulfilled(chat))
    allow(resolver).to receive(:get_supergroup).with(supergroup_id: 42).and_return(fulfilled(supergroup))

    expect(resolver.resolve_public_chat(username)).to eq(chat)
  end

  def fulfilled(value)
    Concurrent::Promises.fulfilled_future(value)
  end

  def rejected(message)
    error = TD::Types::Error.new(code: 400, message: message)
    Concurrent::Promises.rejected_future(TD::Error.new(error))
  end
end
