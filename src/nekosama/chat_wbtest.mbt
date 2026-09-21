///|
test "thread type classification follows chat branches" {
  assert_true(is_bot_owned_thread_type(Some(PublicThread)))
  assert_true(is_bot_owned_thread_type(Some(PrivateThread)))
  assert_false(is_bot_owned_thread_type(Some(AnnouncementThread)))
  assert_true(is_thread_type(Some(AnnouncementThread)))
  assert_false(is_thread_type(Some(GuildText)))
}

///|
test "bot mentions are removed from a mention prompt" {
  let bot_id : @model.UserId = @model.Id::parse("123")
  inspect(remove_bot_mention(" <@!123> hello <@123> ", bot_id), content="hello")
}

///|
test "history mention removal matches the Python regex" {
  inspect(
    remove_user_mentions("hello <@123> <@!456> <@&789>"),
    content="hello   <@&789>",
  )
}

///|
test "chat history roles distinguish the bot from users" {
  let bot_id : @model.UserId = @model.Id::parse("123")
  let user_id : @model.UserId = @model.Id::parse("456")
  inspect(chat_role(bot_id, bot_id), content="assistant")
  inspect(chat_role(user_id, bot_id), content="user")
}

///|
test "new thread chunks mention the author only once" {
  let author_id : @model.UserId = @model.Id::parse("456")
  let chunks = author_chunks("a".repeat(2001), author_id)
  inspect(chunks.length(), content="2")
  assert_true(chunks[0].has_prefix("<@456>\n"))
  assert_false(chunks[1].has_prefix("<@456>\n"))
  inspect(chunks[0].iter().count(), content="2000")
  inspect(chunks[1].iter().count(), content="8")
}

///|
test "translation updates require a meaningful content change" {
  let reply_message_id : @model.MessageId = @model.Id::parse("789")
  let record : TranslationRecord = {
    original_content: "original",
    reply_message_id,
  }
  assert_false(should_retranslate(record, "original"))
  assert_false(should_retranslate(record, "https://example.com"))
  assert_true(should_retranslate(record, "changed"))
}
