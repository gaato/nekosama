///|
test "legacy buttons keep exact Python custom IDs" {
  assert_eq(legacy_delete_route().custom_id(()), "delete")
  assert_eq(legacy_edit_route().custom_id(()), "edit")
  legacy_delete_route().decode("delete")
  legacy_edit_route().decode("edit")
  try legacy_edit_route().decode("edit:unexpected") catch {
    @discord.HandlerError::InvalidArgument(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("legacy buttons must not accept arbitrary state")
  }
}

///|
async test "old edit button opens the shared modal with the translation prefilled" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  let message = {
    ..tools_test_message(),
    embeds: [translation_embed("翻訳")],
  }
  runtime.set_bot_user_id(message.author.id)
  let app = @discord.App()
  register_legacy_buttons(app, runtime)
  let reply = tools_capture_reply(app, tools_test_component("edit", message))
  guard reply
    is {
      "type": 9,
      "data": {
        "custom_id": "edit-translation:1525156408767676600/1525156408767676500",
        "title": "Edit",
        "components": Array(components),
        ..
      },
      ..
    } else {
    fail("expected the shared edit modal")
  }
  // ModalField emits a labelled text input in this library release.
  let wire = Json::array(components).stringify()
  assert_true(wire.contains("\"value\":\"翻訳\""))
  assert_true(wire.contains("\"max_length\":4000"))
  assert_true(wire.contains("Edit translation"))
}

///|
async test "legacy edit rejects missing and overlong descriptions before opening a modal" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  let message = tools_test_message()
  runtime.set_bot_user_id(message.author.id)
  let cases : Array[(Array[@model.Embed], String)] = [
    ([], "That message has no editable translation."),
    (
      [@model.Embed(title="not a translation")],
      "That message has no editable translation.",
    ),
    (
      [translation_embed("a".repeat(4001))],
      "That translation is too long to edit.",
    ),
    (
      [translation_embed("😀".repeat(2001))],
      "That translation is too long to edit.",
    ),
  ]
  for (embeds, content) in cases {
    let app = @discord.App()
    register_legacy_buttons(app, runtime)
    json_inspect(
      tools_capture_reply(
        app,
        tools_test_component("edit", { ..message, embeds, }),
      ),
      content={ "type": 4, "data": { "content": content, "flags": 64 } },
    )
  }
  assert_true(
    edit_translation(runtime, {
      ..message,
      embeds: [translation_embed("a".repeat(4000))],
    })
    is ShowModal(_),
  )
  assert_true(
    edit_translation(runtime, {
      ..message,
      embeds: [translation_embed("😀".repeat(2000))],
    })
    is ShowModal(_),
  )
}

///|
async test "legacy buttons share the commands' bot-ownership checks" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  runtime.set_bot_user_id(@model.Id::parse("999"))
  for
    (id, content) in [
      ("delete", "You can only delete messages sent by me."),
      ("edit", "You can only edit messages sent by me."),
    ] {
    let app = @discord.App()
    register_legacy_buttons(app, runtime)
    json_inspect(
      tools_capture_reply(app, tools_test_component(id, tools_test_message())),
      content={ "type": 4, "data": { "content": content, "flags": 64 } },
    )
  }
}
