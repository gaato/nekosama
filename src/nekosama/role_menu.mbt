///|
const ROLE_MENU_CUSTOM_ID : String = "nekosama:rolemenu"

///|
priv struct RoleMenuArgs {
  roles : Array[@model.RoleId]
  title : String
}

///|
priv struct RoleMenuChanges {
  add : Array[@model.RoleId]
  remove : Array[@model.RoleId]
  current : Array[@model.RoleId]
}

///|
fn role_menu_ids(values : Array[String]) -> Array[@model.RoleId] {
  let ids = []
  for value in values {
    if id_from_json(Json::string(value)) is Some(id) {
      ids.push(id)
    }
  }
  ids
}

///|
fn role_menu_option_ids(
  components : Array[@model.Component],
) -> Array[@model.RoleId] {
  for component in components {
    match component {
      ActionRow(row) => {
        let ids = role_menu_option_ids(row.components)
        if !ids.is_empty() {
          return ids
        }
      }
      StringSelect(menu) if menu.custom_id == ROLE_MENU_CUSTOM_ID =>
        return role_menu_ids(
          menu.options.unwrap_or([]).map(option => option.value),
        )
      _ => ()
    }
  }
  []
}

///|
fn role_menu_changes(
  options : Array[@model.RoleId],
  existing : Array[@model.RoleId],
  member_roles : Array[@model.RoleId],
  selected : Array[@model.RoleId],
) -> RoleMenuChanges {
  let options = options.filter(id => existing.contains(id))
  {
    add: options.filter(id => {
      selected.contains(id) && !member_roles.contains(id)
    }),
    remove: options.filter(id => {
      !selected.contains(id) && member_roles.contains(id)
    }),
    // The member snapshot does not change after role HTTP requests.
    current: options.filter(id => selected.contains(id)),
  }
}

///|
fn role_menu_confirmation(current : Array[@model.RoleId]) -> String {
  let mentions = current.map(id => "<@&\{id}>").join(" ")
  let current = if mentions.is_empty() { "なし / none" } else { mentions }
  "更新しました！ Updated!\n現在: \{current}"
}

///|
fn role_menu_error_reply(error : Error) -> String? {
  match error {
    @http.DiscordHttpError::Api(status=403, ..) =>
      Some(
        "権限が足りずロールを変更できませんでした。管理者に連絡してください。",
      )
    _ => None
  }
}

///|
async fn apply_role_menu_changes(
  changes : RoleMenuChanges,
  add_role~ : async (@model.RoleId) -> Unit,
  remove_role~ : async (@model.RoleId) -> Unit,
) -> String {
  try {
    for role in changes.add {
      add_role(role)
    }
    for role in changes.remove {
      remove_role(role)
    }
  } catch {
    error => {
      guard role_menu_error_reply(error) is Some(content) else { raise error }
      return content
    }
  }
  role_menu_confirmation(changes.current)
}

///|
/// Discord orders equal-position roles by reverse snowflake; @everyone is last.
fn role_at_least(
  role : @model.Role,
  other : @model.Role,
  guild_id : @model.GuildId,
) -> Bool {
  if role.id == other.id {
    return true
  }
  if role.id == guild_id.cast() {
    return false
  }
  if other.id == guild_id.cast() {
    return true
  }
  if role.position == other.position {
    role.id < other.id
  } else {
    role.position > other.position
  }
}

///|
fn member_top_role(
  roles : Array[@model.Role],
  member_roles : Array[@model.RoleId],
  guild_id : @model.GuildId,
) -> @model.Role? {
  let mut top = None
  for role in roles {
    if role.id == guild_id.cast() || member_roles.contains(role.id) {
      match top {
        Some(other) if !role_at_least(role, other, guild_id) => ()
        _ => top = Some(role)
      }
    }
  }
  top
}

///|
fn role_menu_hierarchy_error(
  roles : Array[@model.Role],
  top : @model.Role,
  guild_id : @model.GuildId,
) -> String? {
  let too_high = roles
    .filter(role => role_at_least(role, top, guild_id))
    .map(role => role.name)
  if too_high.is_empty() {
    None
  } else {
    Some(
      "Botのロールより上のため付与できません: \{too_high.join(", ")}",
    )
  }
}

///|
fn role_menu_components(roles : Array[@model.Role]) -> Array[@model.Component] {
  [
    @discord.action_row([
      @discord.string_select(
        custom_id=ROLE_MENU_CUSTOM_ID,
        placeholder="ロールを選択… Pick your roles...",
        min_values=0,
        max_values=roles.length(),
        options=roles.map(role => {
          @discord.select_option(label=role.name, value="\{role.id}")
        }),
      ),
    ]),
  ]
}

///|
fn role_menu_args() -> @discord.Args[RoleMenuArgs] {
  @discord.Args::map8(
    @discord.arg_role(name="role1", description="First role"),
    @discord.arg_role(name="role2", description="Second role").optional(),
    @discord.arg_role(name="role3", description="Third role").optional(),
    @discord.arg_role(name="role4", description="Fourth role").optional(),
    @discord.arg_role(name="role5", description="Fifth role").optional(),
    @discord.arg_role(name="role6", description="Sixth role").optional(),
    @discord.arg_role(name="role7", description="Seventh role").optional(),
    @discord.arg_role(name="role8", description="Eighth role").optional(),
    (role1, role2, role3, role4, role5, role6, role7, role8) => {
      let roles = [role1]
      for role in [role2, role3, role4, role5, role6, role7, role8] {
        if role is Some(role) {
          roles.push(role)
        }
      }
      roles
    },
  )
  .zip(
    @discord.Args::of(
      @discord.arg_string(
        name="title",
        description="Text displayed above the menu",
        description_localizations={
          "ja": "メニューの上に表示する文章",
        },
      ).with_default("班を選択してください / Select your team"),
    ),
  )
  .map(pair => { roles: pair.0, title: pair.1, })
}

///|
fn send_role_menu_command(runtime : Runtime) -> @discord.Command[RoleMenuArgs] {
  @discord.slash(
    name="send-role-menu",
    description="Send a role selection menu to this channel.",
    description_localizations={
      "ja": "ロール選択メニューをこのチャンネルに送信します",
    },
    args=role_menu_args(),
    default_member_permissions=@model.Permissions::administrator(),
    handler=Deferred(ephemeral=true, (ctx, args) => {
      let guild = ctx.guild_scope()
      guard ctx.interaction().channel_id is Some(channel_id) else {
        ctx.edit_original(content="This command requires a channel.") |> ignore
        return
      }
      let client = ctx.app().http()
      let all_roles = client.guild_ref(guild.guild_id).roles()
      let roles = args.roles.map(id => {
        guard all_roles.iter().find_first(role => role.id == id) is Some(role) else {
          raise @discord.HandlerError::InvalidArgument(
            "The selected role is unavailable.",
          )
        }
        role
      })
      let bot_id = match runtime.bot_user_id.val {
        Some(id) => id
        None => client.get_current_user().id
      }
      let bot_member = client.member_ref(guild.guild_id, bot_id).fetch()
      guard member_top_role(all_roles, bot_member.roles, guild.guild_id)
        is Some(top) else {
        raise @discord.HandlerError::InvalidArgument(
          "The bot's top role is unavailable.",
        )
      }
      if role_menu_hierarchy_error(roles, top, guild.guild_id) is Some(content) {
        ctx.edit_original(content~) |> ignore
        return
      }
      client
      .channel_ref(channel_id)
      .send(content="**\{args.title}**", components=role_menu_components(roles))
      |> ignore
      ctx.edit_original(content="Sent!") |> ignore
    }),
  ).check(@discord.guild_only())
}

///|
fn register_role_menu_handler(app : @discord.App, runtime : Runtime) -> Unit {
  // The legacy id contains ':', which typed route validation rejects in 0.3.1.
  app.on_component_raw(prefix=ROLE_MENU_CUSTOM_ID, ctx => {
    guard ctx.data.custom_id == ROLE_MENU_CUSTOM_ID else { return }
    guard ctx.guild_scope() is Some(guild) else {
      raise @discord.HandlerError::GuildOnly
    }
    let changes = role_menu_changes(
      role_menu_option_ids(ctx.message().components.unwrap_or([])),
      runtime.cache.roles(guild.guild_id).map(role => role.id),
      guild.member.roles,
      role_menu_ids(ctx.data.values.unwrap_or([])),
    )
    ctx.defer_response(ephemeral=true)
    let member_ref = ctx.client.member_ref(guild.guild_id, ctx.user().id)
    let content = apply_role_menu_changes(
      changes,
      add_role=role => member_ref.add_role(role, reason="Role menu"),
      remove_role=role => member_ref.remove_role(role, reason="Role menu"),
    )
    ctx.edit_response(content~) |> ignore
  })
}
