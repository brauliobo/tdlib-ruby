module TD::PublicChatResolver
  USERNAME_NOT_FOUND = %w[USERNAME_NOT_OCCUPIED USERNAME_INVALID].freeze

  def resolve_public_chat(username)
    username = normalize_public_username(username)
    search_public_chat(username: username).value!
  rescue TD::Error => error
    raise unless USERNAME_NOT_FOUND.include?(error.message)

    resolve_public_chat_from_search(username) || raise
  end

  private

  def normalize_public_username(username)
    value = username.to_s.strip.delete_prefix('@')
    raise ArgumentError, 'public chat username is required' if value.empty?

    value
  end

  def resolve_public_chat_from_search(username)
    result = search_public_chats(query: username).value!
    Array(result.chat_ids).each do |chat_id|
      chat = get_chat(chat_id: chat_id).value!
      return chat if public_chat_username?(chat, username)
    end
    nil
  end

  def public_chat_username?(chat, username)
    case chat.type
    when TD::Types::ChatType::Supergroup
      get_supergroup(supergroup_id: chat.type.supergroup_id).value!.usernames&.active?(username)
    when TD::Types::ChatType::Private
      get_user(user_id: chat.type.user_id).value!.usernames&.active?(username)
    else
      false
    end
  end
end
