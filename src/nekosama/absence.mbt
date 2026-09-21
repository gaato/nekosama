///|
priv struct AbsenceArgs {
  period : String
  reason : String?
}

///|
fn absence_embed(
  args : AbsenceArgs,
  display_name : String,
  avatar_url : String,
) -> @model.Embed {
  let fields = [@model.EmbedField("期間 Period", args.period, inline=false)]
  if args.reason is Some(reason) && !reason.is_empty() {
    fields.push(@model.EmbedField("理由 Reason", reason, inline=false))
  }
  @model.Embed(
    title="🙇 不在連絡 / Absence",
    color=0xF1C40F,
    fields~,
    author=@model.EmbedAuthor(display_name, icon_url=avatar_url),
  )
}

///|
fn absence_destination(
  guild_id : @model.GuildId,
  configured : @model.Channel?,
  fallback : @model.ChannelId?,
) -> @model.ChannelId? {
  // Like guild.get_channel in Python, only use a channel in this guild,
  // excluding threads. A deleted channel falls back to this one.
  if configured is Some(channel) && channel.guild_id == Some(guild_id) {
    match channel.typ {
      AnnouncementThread | PublicThread | PrivateThread => ()
      _ => return Some(channel.id)
    }
  }
  fallback
}

///|
fn absence_command(runtime : Runtime) -> @discord.Command[AbsenceArgs] {
  @discord.slash(
    name="absence",
    description="Post an absence notice with a period and an optional reason.",
    description_localizations={
      "ja": "不在連絡を投稿します（期間と理由は任意入力）",
    },
    args=@discord.Args::map2(
      @discord.arg_string(name="period", description="Period of absence", description_localizations={
        "ja": "不在期間（例: 7/20〜7/25、今週いっぱい）",
      }),
      @discord.arg_string(
        name="reason",
        description="Reason (optional; share what you can)",
        description_localizations={
          "ja": "理由（任意・書ける範囲で）",
        },
      ).optional(),
      (period, reason) => { period, reason, },
    ),
    handler=Deferred(ephemeral=true, (ctx, args) => {
      let guild = ctx.guild_scope()
      let configured = match
        runtime.config.get_id(guild.guild_id, ABSENCE_CHANNEL_KEY) {
        Some(channel_id) =>
          // Guild-create channel payloads may omit guild_id, and the cache
          // does not expose its separate guild association. The guild REST
          // list resolves the destination without treating that as a miss.
          ctx
          .app()
          .http()
          .guild_ref(guild.guild_id)
          .channels()
          .iter()
          .find_first(channel => channel.id == channel_id)
          .map(channel => { ..channel, guild_id: Some(guild.guild_id), })
        None => None
      }
      guard absence_destination(
          guild.guild_id,
          configured,
          ctx.interaction().channel_id,
        )
        is Some(channel_id) else {
        ctx.edit_original(content="This command requires a channel.") |> ignore
        return
      }
      let user = ctx.user()
      let embed = absence_embed(
        args,
        member_tools_display_name(user, Some(guild.member)),
        member_tools_avatar_url(user, Some(guild.guild_id), Some(guild.member)),
      )
      ctx
      .app()
      .http()
      .channel_ref(channel_id)
      .send(content="<@\{user.id}>", embeds=[embed])
      |> ignore
      ctx.edit_original(content="<#\{channel_id}> に投稿しました。")
      |> ignore
    }),
  ).check(@discord.guild_only())
}
