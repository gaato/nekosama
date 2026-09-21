///|
fn tools_test_message_command(
  name : String,
  message : @model.Message,
) -> @model.Interaction raise {
  let messages : Map[String, Json] = Map([])
  messages[message.id.to_string()] = message.to_json()
  @json.from_json({
    "id": "1525156408767676700",
    "application_id": "1525156408767676800",
    "type": 2,
    "token": "unused",
    "version": 1,
    "user": tools_test_user().to_json(),
    "data": {
      "id": "1",
      "type": 3,
      "name": name,
      "target_id": message.id.to_string(),
      "resolved": { "messages": Json::object(messages) },
    },
  })
}

///|
test "Translate is a message context command with the existing translation embed" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  guard translate_command(runtime).spec().to_json()
    is { "name": "Translate", "type": 3, .. } else {
    fail("expected a Translate message command")
  }
  json_inspect(translation_embed("Hello!"), content={
    "description": "Hello!",
    "color": 12543464,
  })
  for text in ["", " \t\r\n　"] {
    assert_eq(
      translation_request_error(text),
      Some(
        "翻訳するテキストがありません。 Nothing to translate.",
      ),
    )
  }
  // Context-menu translation deliberately does not use the automatic noise filter.
  assert_true(translation_request_error("https://example.com") is None)
  assert_true(translation_request_error("<@123>") is None)
}

///|
test "edit modal state keeps full snowflakes and rejects malformed locations" {
  guard parse_message_location("1525156408767676466/1525156408767676499")
    is Some((channel_id, message_id)) else {
    fail("expected a valid location")
  }
  assert_eq(channel_id.to_string(), "1525156408767676466")
  assert_eq(message_id.to_string(), "1525156408767676499")
  for
    state in [
      "", "1", "1/2/3", "/2", "1/", "bad/2", "1/bad", "18446744073709551616/2",
    ] {
    assert_true(parse_message_location(state) is None)
  }
}

///|
async test "Delete and Edit commands retain ownership replies after sharing legacy logic" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  runtime.set_bot_user_id(@model.Id::parse("999"))
  for
    (name, content) in [
      ("Delete", "You can only delete messages sent by me."),
      ("Edit", "You can only edit messages sent by me."),
    ] {
    let app = @discord.App()
    register_translation_commands(app, runtime)
    json_inspect(
      tools_capture_reply(
        app,
        tools_test_message_command(name, tools_test_message()),
      ),
      content={ "type": 4, "data": { "content": content, "flags": 64 } },
    )
  }
}

///|
async test "Edit command and legacy button produce the same modal" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  let message = {
    ..tools_test_message(),
    embeds: [translation_embed("translation")],
  }
  runtime.set_bot_user_id(message.author.id)
  let app = @discord.App()
  register_translation_commands(app, runtime)
  register_legacy_buttons(app, runtime)
  let from_command = tools_capture_reply(
    app,
    tools_test_message_command("Edit", message),
  )
  let from_button = tools_capture_reply(
    app,
    tools_test_component("edit", message),
  )
  assert_eq(from_command.stringify(), from_button.stringify())
}
