///|
fn tools_test_user() -> @model.User raise {
  @json.from_json({
    "id": "1525156408767676466",
    "username": "username",
    "discriminator": "0",
    "global_name": "表示名",
    "avatar": null,
  })
}

///|
fn tools_test_member() -> @model.GuildMember raise {
  @json.from_json({
    "user": tools_test_user().to_json(),
    "nick": "ニックネーム",
    "avatar": "a_guildhash",
    "roles": [],
    "joined_at": null,
  })
}

///|
fn tools_test_role(
  id : String,
  name : String,
  position : Int,
) -> @model.Role raise {
  @json.from_json({
    "id": id,
    "name": name,
    "color": 0,
    "hoist": false,
    "position": position,
    "permissions": "0",
    "managed": false,
    "mentionable": false,
  })
}

///|
fn tools_test_message() -> @model.Message raise {
  @json.from_json({
    "id": "1525156408767676500",
    "channel_id": "1525156408767676600",
    "author": tools_test_user().to_json(),
    "content": "hello",
    "timestamp": "2026-09-21T00:00:00Z",
    "edited_timestamp": null,
    "tts": false,
    "mention_everyone": false,
    "mentions": [],
    "mention_roles": [],
    "attachments": [],
    "embeds": [],
    "pinned": false,
    "type": 0,
  })
}

///|
fn tools_test_component(
  custom_id : String,
  message : @model.Message,
) -> @model.Interaction raise {
  @json.from_json({
    "id": "1525156408767676700",
    "application_id": "1525156408767676800",
    "type": 3,
    "token": "unused",
    "version": 1,
    "user": tools_test_user().to_json(),
    "message": message.to_json(),
    "data": { "custom_id": custom_id, "component_type": 2 },
  })
}

///|
// Only initial callbacks are captured here. No bot, endpoint server, or REST
// call is run; handlers tested with this helper must return before any I/O.
async fn tools_capture_reply(
  app : @discord.App,
  interaction : @model.Interaction,
) -> Json {
  let client = @discord.Client(
    "unused",
    base_url="http://127.0.0.1:1",
    max_retries=0,
  )
  defer client.close()
  let framework = @framework.Framework(client, interaction.application_id)
  let errors : Array[String] = []
  app.error_policy((_, error) => errors.push("\{Repr(error)}"))
  app.validate()
  app.attach(framework, client~, application_id=interaction.application_id)
  |> ignore
  let (gate, capture) = @framework.ResponseGate::capture(interaction)
  assert_true(framework.process_with(interaction, gate~))
  assert_eq(errors, [])
  guard capture.try_get() is Some(captured) else {
    fail("expected a captured initial response")
  }
  captured.response.to_json()
}

///|
test "member display names use nickname then global name then username" {
  let user = tools_test_user()
  let guild_member = tools_test_member()
  assert_eq(
    member_tools_display_name(user, Some(guild_member)),
    "ニックネーム",
  )
  assert_eq(
    member_tools_display_name(
      user,
      Some({ ..guild_member, nick: None, user: None, }),
    ),
    "表示名",
  )
  assert_eq(member_tools_display_name(user, None), "表示名")
  assert_eq(
    member_tools_display_name({ ..user, global_name: None, }, None),
    "username",
  )
}

///|
test "display avatars use guild then user then modern or legacy defaults" {
  let user = tools_test_user()
  let guild_id : @model.GuildId = @model.Id::parse("123")
  let guild_member = tools_test_member()
  assert_eq(
    member_tools_avatar_url(user, Some(guild_id), Some(guild_member)),
    "https://cdn.discordapp.com/guilds/123/users/1525156408767676466/avatars/a_guildhash.gif?size=1024",
  )
  assert_eq(
    member_tools_avatar_url(
      user,
      Some(guild_id),
      Some({ ..guild_member, avatar: Some(Value(@model.ImageHash("static"))), }),
    ),
    "https://cdn.discordapp.com/guilds/123/users/1525156408767676466/avatars/static.png?size=1024",
  )
  assert_eq(
    member_tools_avatar_url(
      { ..user, avatar: Value(@model.ImageHash("a_userhash")), },
      None,
      Some(guild_member),
    ),
    "https://cdn.discordapp.com/avatars/1525156408767676466/a_userhash.gif?size=1024",
  )
  assert_eq(
    member_tools_avatar_url(
      { ..user, avatar: Value(@model.ImageHash("static")), },
      None,
      None,
    ),
    "https://cdn.discordapp.com/avatars/1525156408767676466/static.png?size=1024",
  )
  assert_eq(
    member_tools_avatar_url(user, None, None),
    @util.default_user_avatar_url(user.id),
  )
  assert_eq(
    member_tools_avatar_url({ ..user, discriminator: "1234", }, None, None),
    "https://cdn.discordapp.com/embed/avatars/4.png",
  )
}

///|
test "colon IDs validate as typed routes since discord 0.4.0" {
  // The legacy menu IDs contain the state separator. discord 0.3.1 rejected
  // them as typed routes, which is why the handlers are registered raw; 0.4.0
  // accepts them and only rejects ids nested at a ':' boundary.
  for id in [SCHEDULE_CUSTOM_ID, ROLE_MENU_CUSTOM_ID] {
    let route = @discord.component_route(
      id~,
      state=@discord.CustomIdCodec::unit(),
    )
    assert_eq(route.custom_id(()), id)
    route.decode(id)
    let app = @discord.App()
    app.on_component(
      route,
      Immediate((_, _) => @discord.ComponentReply::message(content="unused")),
    )
    app.validate()
  }
}

///|
async test "raw legacy menu IDs reach their handlers and ignore prefix siblings" {
  let app = @discord.App()
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  register_schedule_handler(app)
  register_role_menu_handler(app, runtime)
  let errors : Array[String] = []
  app.error_policy((_, error) => {
    guard error is @discord.HandlerError::GuildOnly else { raise error }
    errors.push("guild required")
  })
  app.validate()
  let client = @discord.Client(
    "unused",
    base_url="http://127.0.0.1:1",
    max_retries=0,
  )
  defer client.close()
  let application_id : @model.ApplicationId = @model.Id::parse(
    "1525156408767676800",
  )
  let framework = @framework.Framework(client, application_id)
  app.attach(framework, client~, application_id~) |> ignore
  // No guild means the matched handler must fail before reaching any HTTP call.
  for id in [SCHEDULE_CUSTOM_ID, ROLE_MENU_CUSTOM_ID] {
    let interaction = tools_test_component(id, tools_test_message())
    let (gate, capture) = @framework.ResponseGate::capture(interaction)
    assert_true(framework.process_with(interaction, gate~))
    assert_true(capture.try_get() is None)
  }
  assert_eq(errors, ["guild required", "guild required"])
  errors.clear()
  for id in ["nekosama:schedule-other", "nekosama:rolemenu-other"] {
    let interaction = tools_test_component(id, tools_test_message())
    let (gate, capture) = @framework.ResponseGate::capture(interaction)
    assert_true(framework.process_with(interaction, gate~))
    assert_true(capture.try_get() is None)
  }
  assert_eq(errors, [])
}
