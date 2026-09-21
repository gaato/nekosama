///|
const MEMBER_ROLE_KEY : String = "member_role_id"

///|
const ABSENCE_CHANNEL_KEY : String = "absence_channel_id"

///|
const AUTO_TRANSLATE_KEY : String = "auto_translate"

///|
fn config_member_role_command(runtime : Runtime) -> @discord.SlashChild {
  @discord.subcommand(
    name="member-role",
    description="Set the role granted by the agree button.",
    description_localizations={
      "ja": "同意ボタンで付与するロールを設定します",
    },
    args=@discord.Args::of(
      @discord.arg_role(name="role", description="Role to grant"),
    ),
    handler=Immediate((ctx, role) => {
      let guild = ctx.guild_scope()
      runtime.config.set(guild.guild_id, MEMBER_ROLE_KEY, id_to_json(role))
      @discord.CommandReply::message(
        content="同意ボタンのロールを <@&\{role}> に設定しました。",
        ephemeral=true,
      )
    }),
  )
}

///|
fn config_absence_channel_command(runtime : Runtime) -> @discord.SlashChild {
  @discord.subcommand(
    name="absence-channel",
    description="Set the channel absence notices are posted to.",
    description_localizations={
      "ja": "不在連絡の投稿先チャンネルを設定します",
    },
    args=@discord.Args::of(
      @discord.arg_channel(name="channel", description="Channel to post to", channel_types=[
        GuildText,
      ]),
    ),
    handler=Immediate((ctx, channel) => {
      let guild = ctx.guild_scope()
      runtime.config.set(
        guild.guild_id,
        ABSENCE_CHANNEL_KEY,
        id_to_json(channel),
      )
      @discord.CommandReply::message(
        content="不在連絡の投稿先を <#\{channel}> に設定しました。",
        ephemeral=true,
      )
    }),
  )
}

///|
fn config_auto_translate_command(runtime : Runtime) -> @discord.SlashChild {
  @discord.subcommand(
    name="auto-translate",
    description="Turn automatic translation on or off.",
    description_localizations={
      "ja": "自動翻訳の有効/無効を切り替えます",
    },
    args=@discord.Args::of(
      @discord.arg_bool(name="enabled", description="Whether to translate"),
    ),
    handler=Immediate((ctx, enabled) => {
      let guild = ctx.guild_scope()
      runtime.config.set(
        guild.guild_id,
        AUTO_TRANSLATE_KEY,
        Json::boolean(enabled),
      )
      let state = if enabled { "有効" } else { "無効" }
      @discord.CommandReply::message(
        content="自動翻訳を \{state} にしました。" +
          "（チャンネルごとに無効にするにはトピックに `notl` を含めてください）",
        ephemeral=true,
      )
    }),
  )
}

///|
fn config_show_command(runtime : Runtime) -> @discord.SlashChild {
  @discord.subcommand(
    name="show",
    description="Show the current settings.",
    description_localizations={ "ja": "現在の設定を表示します" },
    args=@discord.Args::unit(),
    handler=Immediate((ctx, _) => {
      let guild = ctx.guild_scope()
      let settings = runtime.config.guild(guild.guild_id)
      let content = if settings.is_empty() {
        "設定はまだありません。"
      } else {
        "```json\n\{Json::object(settings).stringify(indent=2)}\n```"
      }
      @discord.CommandReply::message(content~, ephemeral=true)
    }),
  )
}

///|
fn config_command(runtime : Runtime) -> @discord.Command[Unit] {
  @discord.slash_group(
    name="config",
    description="Per-guild settings",
    description_localizations={ "ja": "ギルドごとの設定" },
    children=[
      config_member_role_command(runtime),
      config_absence_channel_command(runtime),
      config_auto_translate_command(runtime),
      config_show_command(runtime),
    ],
    default_member_permissions=@model.Permissions::administrator(),
  ).check(@discord.guild_only())
}
