///|
const MESSAGE_LIMIT : Int = 1900

///|
const EMBED_DESCRIPTION_LIMIT : Int = 3900

///|
priv struct RoleMembersArgs {
  role1 : @model.RoleId
  role2 : @model.RoleId?
  role3 : @model.RoleId?
}

///|
fn selected_roles(args : RoleMembersArgs) -> Array[@model.RoleId] {
  let roles = [args.role1]
  if args.role2 is Some(role) {
    roles.push(role)
  }
  if args.role3 is Some(role) {
    roles.push(role)
  }
  roles
}

///|
fn contains_all_roles(
  member_roles : Array[@model.RoleId],
  required_roles : Array[@model.RoleId],
) -> Bool {
  for role in required_roles {
    if !member_roles.contains(role) {
      return false
    }
  }
  true
}

///|
async fn matching_members(
  client : @discord.Client,
  guild_id : @model.GuildId,
  required_roles : Array[@model.RoleId],
) -> Array[@model.GuildMember] {
  let matching : Array[@model.GuildMember] = []
  let members = client.guild_ref(guild_id).members(page_size=1000)
  members.each(guild_member => {
    if contains_all_roles(guild_member.roles, required_roles) {
      matching.push(guild_member)
    }
  })
  matching
}

///|
fn member_display_name(guild_member : @model.GuildMember) -> String {
  if @model.flatten(guild_member.nick) is Some(nick) {
    return nick
  }
  match guild_member.user {
    Some(user) => @model.flatten(user.global_name).unwrap_or(user.username)
    None => "Unknown member"
  }
}

///|
fn member_line(guild_member : @model.GuildMember) -> String {
  match guild_member.user {
    Some(user) => "- \{member_display_name(guild_member)} (<@\{user.id}>)"
    None => "- \{member_display_name(guild_member)}"
  }
}

///|
fn summarize_lines(lines : Array[String], limit : Int) -> String {
  if lines.is_empty() {
    return ""
  }
  let output = StringBuilder()
  let mut included = 0
  let mut output_length = 0
  for line in lines {
    let separator_length = if included == 0 { 0 } else { 1 }
    if output_length + separator_length + line.length() > limit {
      break
    }
    if included > 0 {
      output.write_string("\n")
    }
    output.write_string(line)
    output_length += separator_length + line.length()
    included += 1
  }
  let omitted = lines.length() - included
  if omitted > 0 {
    let suffix = "\n… and \{omitted} more"
    if output_length + suffix.length() <= limit {
      output.write_string(suffix)
    }
  }
  output.to_string()
}

///|
fn role_mentions(roles : Array[@model.RoleId]) -> String {
  roles.map(role => "<@&\{role}>").join(", ")
}

///|
fn role_list_command() -> @discord.SlashChild {
  @discord.subcommand(
    name="list",
    description="Show all roles.",
    description_localizations={ "ja": "ロール一覧を表示します" },
    args=@discord.Args::unit(),
    handler=Deferred(ephemeral=false, (ctx, _) => {
      let guild = ctx.guild_scope()
      let roles = ctx.app().http().guild_ref(guild.guild_id).roles()
      let description = summarize_lines(
        roles.map(role => "<@&\{role.id}>"),
        EMBED_DESCRIPTION_LIMIT,
      )
      let description = if description.is_empty() {
        "No roles found."
      } else {
        description
      }
      ctx.edit_original(embeds=[@model.Embed(title="Role list", description~)])
      |> ignore
    }),
  )
}

///|
fn role_members_command() -> @discord.SlashChild {
  @discord.subcommand(
    name="members",
    description="Show members who have all selected roles.",
    description_localizations={
      "ja": "ロールのメンバー一覧を表示します",
    },
    args=@discord.Args::map3(
      @discord.arg_role(name="role1", description="Required role"),
      @discord.arg_role(name="role2", description="Second required role").optional(),
      @discord.arg_role(name="role3", description="Third required role").optional(),
      (role1, role2, role3) => { role1, role2, role3, },
    ),
    handler=Deferred(ephemeral=false, (ctx, args) => {
      let guild = ctx.guild_scope()
      let roles = selected_roles(args)
      let members = matching_members(ctx.app().http(), guild.guild_id, roles)
      let member_lines = members.map(member_line)
      let body = if member_lines.is_empty() {
        "No members have all selected roles."
      } else {
        summarize_lines(member_lines, MESSAGE_LIMIT - 100)
      }
      ctx.edit_original(
        content="Roles: \{role_mentions(roles)}\n\{body}",
        allowed_mentions=@model.AllowedMentions::none(),
      )
      |> ignore
    }),
  )
}

///|
fn role_command() -> @discord.Command[Unit] {
  @discord.slash_group(name="role", description="Role commands", children=[
    role_list_command(),
    role_members_command(),
  ]).check(@discord.guild_only())
}

///|
fn pick_command() -> @discord.Command[@model.RoleId] {
  @discord.slash(
    name="pick",
    description="Pick a random member from a role.",
    description_localizations={
      "ja": "ロールからランダムにメンバーを選びます。",
    },
    args=@discord.Args::of(
      @discord.arg_role(name="role", description="Role to pick from"),
    ),
    handler=Deferred(ephemeral=false, (ctx, role) => {
      let guild = ctx.guild_scope()
      let members = matching_members(ctx.app().http(), guild.guild_id, [role])
      if members.is_empty() {
        ctx.edit_original(content="No members have that role.") |> ignore
        return
      }
      let rand = @random.Rand::chacha8()
      let guild_member = members[rand.int(limit=members.length())]
      let value = match guild_member.user {
        Some(user) => "<@\{user.id}>"
        None => "The selected member has no user data."
      }
      // Embed titles do not render mentions, so show the resolved role name.
      let role_name = match ctx.raw().options.resolved_role(role) {
        Some(resolved) => resolved.name
        None => "the role"
      }
      ctx.edit_original(
        embeds=[
          @model.Embed(
            title="Picked a random member from \{role_name}",
            color=0xB190FC,
            fields=[
              @model.EmbedField(
                member_display_name(guild_member),
                value,
                inline=false,
              ),
            ],
          ),
        ],
        allowed_mentions=@model.AllowedMentions::none(),
      )
      |> ignore
    }),
  ).check(@discord.guild_only())
}

///|
fn send_agree_button_command() -> @discord.Command[Unit] {
  @discord.slash(
    name="send-agree-button",
    description="Send the membership agreement button.",
    args=@discord.Args::unit(),
    handler=Deferred(ephemeral=true, (ctx, _) => {
      guard ctx.interaction().channel_id is Some(channel_id) else {
        ctx.edit_original(content="This command requires a channel.") |> ignore
        return
      }
      ctx
      .app()
      .http()
      .channel_ref(channel_id)
      .send(
        content="Please press the button below if you agree.\n" +
          "同意する場合は以下のボタンを押してください。",
        components=[
          @discord.action_row([
            @discord.button(
              custom_id=agree_route().custom_id(()),
              label="Agree",
              style=Primary,
            ),
          ]),
        ],
      )
      |> ignore
      ctx.edit_original(content="Sent!") |> ignore
    }),
    default_member_permissions=@model.Permissions::administrator(),
  ).check(@discord.guild_only())
}

///|
fn member_role_id() -> @model.RoleId? {
  match @env.get_env_var("MEMBER_ROLE_ID") {
    Some(raw) => Some(@model.Id::parse(raw)) catch { _ => None }
    None => None
  }
}

///|
/// The stateless route keeps the bare `agree` custom id, so buttons posted by
/// the Python bot keep working.
fn agree_route() -> @discord.ComponentRoute[Unit] {
  @discord.component_route(id="agree", state=@discord.CustomIdCodec::unit())
}

///|
fn register_agree_handler(app : @discord.App) -> Unit {
  app.on_component(
    agree_route(),
    DeferredMessage(ephemeral=true, (ctx, _) => {
      let guild = ctx.guild_scope()
      guard member_role_id() is Some(role_id) else {
        ctx.edit_original(content="MEMBER_ROLE_ID is not configured correctly.")
        |> ignore
        return
      }
      ctx
      .app()
      .http()
      .member_ref(guild.guild_id, ctx.user().id)
      .add_role(role_id, reason="Accepted the membership agreement")
      ctx.edit_original(content="Verified!") |> ignore
    }),
  )
}

///|
pub fn register_commands(app : @discord.App) -> Unit {
  app.command(role_command())
  app.command(pick_command())
  app.command(send_agree_button_command())
  register_agree_handler(app)
}
