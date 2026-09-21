///|
test "role confirmation uses the submitted selection instead of stale member roles" {
  let old_role : @model.RoleId = @model.Id::parse("1")
  let new_role : @model.RoleId = @model.Id::parse("2")
  let changes = role_menu_changes(
    [old_role, new_role],
    [old_role, new_role],
    [old_role],
    [new_role],
  )
  assert_eq(changes.add, [new_role])
  assert_eq(changes.remove, [old_role])
  assert_eq(
    role_menu_confirmation(changes.current),
    "更新しました！ Updated!\n現在: <@&2>",
  )
}

///|
test "role changes only affect existing roles offered by the message" {
  let ids = role_menu_ids(["1", "2", "3", "4"])
  let changes = role_menu_changes(
    [ids[0], ids[1], ids[2]],
    [ids[0], ids[1], ids[3]],
    [ids[0], ids[3]],
    [ids[1], ids[2], ids[3]],
  )
  assert_eq(changes.add, [ids[1]])
  assert_eq(changes.remove, [ids[0]])
  assert_eq(changes.current, [ids[1]])
  let empty = role_menu_changes([ids[0], ids[1]], ids, [ids[0], ids[3]], [])
  assert_eq(empty.add, [])
  assert_eq(empty.remove, [ids[0]])
  assert_eq(
    role_menu_confirmation(empty.current),
    "更新しました！ Updated!\n現在: なし / none",
  )
  let unchanged = role_menu_changes([ids[1], ids[0]], ids, [ids[0], ids[1]], [
    ids[0],
    ids[1],
  ])
  assert_eq(unchanged.add, [])
  assert_eq(unchanged.remove, [])
  assert_eq(
    role_menu_confirmation(unchanged.current),
    "更新しました！ Updated!\n現在: <@&2> <@&1>",
  )
}

///|
test "role menu reads real options from Python message components" {
  let components : Array[@model.Component] = @json.from_json([
    {
      "type": 1,
      "components": [
        {
          "type": 3,
          "custom_id": "nekosama:rolemenu",
          "options": [
            { "label": "one", "value": "1525156408767676466" },
            { "label": "two", "value": "1525156408767676499" },
          ],
        },
      ],
    },
  ])
  assert_eq(role_menu_option_ids(components).map(id => id.to_string()), [
    "1525156408767676466", "1525156408767676499",
  ])
  assert_eq(
    role_menu_option_ids([
      @discord.action_row([
        @discord.string_select(custom_id="unrelated", options=[
          @discord.select_option(label="ignore", value="5"),
        ]),
      ]),
    ]),
    [],
  )
  assert_eq(role_menu_option_ids([]), [])
  assert_eq(
    role_menu_ids(["bad", "18446744073709551616", "1525156408767676466"]).map(id => {
      id.to_string()
    }),
    ["1525156408767676466"],
  )
}

///|
test "Forbidden maps to the exact Python reply and other errors propagate" {
  let api_error : @http.ApiError = {
    code: 50013,
    message: "Missing Permissions",
    errors: None,
  }
  assert_eq(
    role_menu_error_reply(
      @http.DiscordHttpError::Api(status=403, error=api_error),
    ),
    Some(
      "権限が足りずロールを変更できませんでした。管理者に連絡してください。",
    ),
  )
  assert_true(
    role_menu_error_reply(
      @http.DiscordHttpError::Api(status=404, error=api_error),
    )
    is None,
  )
  assert_true(
    role_menu_error_reply(@http.DiscordHttpError::Transport(message="offline"))
    is None,
  )
}

///|
test "role hierarchy handles equal positions everyone and missing member role IDs" {
  let guild_id : @model.GuildId = @model.Id::parse("1")
  let everyone = tools_test_role("1", "@everyone", 0)
  let top = tools_test_role("10", "Bot", 5)
  let same_position_higher = tools_test_role("9", "Higher", 5)
  let same_position_lower = tools_test_role("11", "Lower", 5)
  let above = tools_test_role("20", "Above", 6)
  assert_true(role_at_least(top, top, guild_id))
  assert_true(role_at_least(same_position_higher, top, guild_id))
  assert_false(role_at_least(same_position_lower, top, guild_id))
  assert_true(role_at_least(above, top, guild_id))
  assert_false(role_at_least(everyone, top, guild_id))
  assert_true(role_at_least(top, everyone, guild_id))
  assert_eq(
    role_menu_hierarchy_error([same_position_lower, top, above], top, guild_id),
    Some("Botのロールより上のため付与できません: Bot, Above"),
  )
  assert_true(
    role_menu_hierarchy_error([same_position_lower], top, guild_id) is None,
  )
  assert_eq(
    member_top_role(
      [everyone, same_position_lower, top, above],
      [top.id, same_position_lower.id, @model.Id::parse("999")],
      guild_id,
    ).unwrap().id,
    top.id,
  )
  assert_eq(
    member_top_role([everyone, top], [], guild_id).unwrap().id,
    everyone.id,
  )
  assert_true(member_top_role([], [], guild_id) is None)
}

///|
test "role menu has eight role options plus a defaulted title" {
  let data : @model.CommandData = @json.from_json({
    "id": "1",
    "name": "send-role-menu",
    "type": 1,
    "options": [
      { "name": "role1", "type": 8, "value": "1525156408767676466" },
      { "name": "role3", "type": 8, "value": "3" },
      { "name": "role8", "type": 8, "value": "8" },
    ],
  })
  let args = role_menu_args().decode(
    @interaction.CommandOptions::from_data(data),
  )
  assert_eq(args.roles.map(id => id.to_string()), [
    "1525156408767676466", "3", "8",
  ])
  assert_eq(args.title, "班を選択してください / Select your team")
  let definitions = role_menu_args().definitions()
  assert_eq(definitions.map(option => option.name), [
    "role1", "role2", "role3", "role4", "role5", "role6", "role7", "role8", "title",
  ])
  assert_eq(definitions[0].required, Some(true))
  assert_eq(definitions[8].required, Some(false))
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  guard send_role_menu_command(runtime).spec().to_json()
    is {
      "default_member_permissions": "8",
      "description_localizations": {
        "ja": "ロール選択メニューをこのチャンネルに送信します",
        ..
      },
      ..
    } else {
    fail("role menu must require administrator permission by default")
  }
}

///|
test "role menus serialize role IDs without losing precision" {
  let role = tools_test_role("1525156408767676466", "班", 1)
  guard role_menu_components([role])
    is [ActionRow({ components: [StringSelect(menu)], .. })] else {
    fail("expected a role menu")
  }
  assert_eq(menu.custom_id, "nekosama:rolemenu")
  assert_eq(menu.min_values, Some(0))
  assert_eq(menu.max_values, Some(1))
  assert_eq(menu.placeholder, Some("ロールを選択… Pick your roles..."))
  assert_eq(menu.options.unwrap()[0].value, "1525156408767676466")
  assert_eq(menu.options.unwrap()[0].label, "班")
}

///|
async test "role updates add then remove and confirm selection even with a stale snapshot" {
  let ids = role_menu_ids(["1", "2", "3"])
  let snapshot = [ids[0], ids[2]]
  let changes = role_menu_changes([ids[0], ids[1]], ids, snapshot, [ids[1]])
  let requests : Array[String] = []
  let reply = apply_role_menu_changes(
    changes,
    add_role=role => requests.push("add \{role}"),
    remove_role=role => requests.push("remove \{role}"),
  )
  assert_eq(requests, ["add 2", "remove 1"])
  assert_eq(snapshot, [ids[0], ids[2]])
  assert_eq(reply, "更新しました！ Updated!\n現在: <@&2>")
}

///|
async test "Forbidden during either role operation stops updates with the Python error" {
  let ids = role_menu_ids(["1", "2"])
  let changes = role_menu_changes(ids, ids, [ids[0]], [ids[1]])
  let forbidden = @http.DiscordHttpError::Api(status=403, error={
    code: 50013,
    message: "Missing Permissions",
    errors: None,
  })
  for fail_on_add in [true, false] {
    let requests : Array[String] = []
    let reply = apply_role_menu_changes(
      changes,
      add_role=role => {
        requests.push("add \{role}")
        if fail_on_add {
          raise forbidden
        }
      },
      remove_role=role => {
        requests.push("remove \{role}")
        raise forbidden
      },
    )
    assert_eq(
      reply, "権限が足りずロールを変更できませんでした。管理者に連絡してください。",
    )
    assert_eq(
      requests,
      if fail_on_add {
        ["add 2"]
      } else {
        ["add 2", "remove 1"]
      },
    )
  }
  try
    ignore(
      apply_role_menu_changes(
        changes,
        add_role=_ => raise @http.DiscordHttpError::Transport(message="offline"),
        remove_role=_ => fail("must stop after the failure"),
      ),
    )
  catch {
    @http.DiscordHttpError::Transport(message~) => assert_eq(message, "offline")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected transport failure to propagate")
  }
}
