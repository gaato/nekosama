///|
const SCHEDULE_CUSTOM_ID : String = "nekosama:schedule"

///|
priv struct ScheduleArgs {
  title : String
  dates : String
  note : String?
}

///|
fn rebuild_schedule_field(
  value : String,
  user_id : @model.UserId,
  attending : Bool,
) -> String {
  let ids : Array[@model.UserId] = []
  user_mention.replace_by(value, matched => {
    let mention = matched.content()
    let start = if mention.has_prefix("<@!") { 3 } else { 2 }
    if id_from_json(
        Json::string(mention[start:mention.length() - 1].to_owned()),
      )
      is Some(id) {
      ids.push(id)
    }
    ""
  })
  |> ignore
  if attending && !ids.contains(user_id) {
    ids.push(user_id)
  }
  if !attending {
    for i, id in ids {
      if id == user_id {
        // Python list.remove removes only the first matching mention.
        ids.remove(i) |> ignore
        break
      }
    }
  }
  let mentions = ids.map(id => "<@\{id}>").join(" ")
  if mentions.is_empty() {
    "**0人**"
  } else {
    "**\{ids.length()}人** \{mentions}"
  }
}

///|
fn schedule_dates(dates : String) -> Array[String] {
  dates
  .replace(old="、", new=",")
  .replace(old="\n", new=",")
  .split(",")
  .map(date => {
    // StringView::trim only strips ASCII whitespace by default.
    let chars = date.to_owned().iter().to_array()
    let mut start = 0
    let mut end = chars.length()
    while start < end && chars[start].is_whitespace() {
      start += 1
    }
    while end > start && chars[end - 1].is_whitespace() {
      end -= 1
    }
    String::from_iter(chars[start:end].iter())
  })
  .filter(date => !date.is_empty())
  .to_array()
}

///|
fn schedule_dates_error(options : Array[String]) -> String? {
  if options.is_empty() {
    Some("候補日時が読み取れませんでした。")
  } else if options.length() > 25 {
    Some("候補は25個までです。")
  } else {
    None
  }
}

///|
fn schedule_embed(
  title : String,
  options : Array[String],
  note : String?,
  display_name : String,
  avatar_url : String,
) -> @model.Embed {
  let mut description = "参加できる日時を**すべて**選んで送信してください。\n" +
    "Select **all** the dates you can attend.\n" +
    "回答を消すには何も選ばずに送信します。"
  if note is Some(note) && !note.is_empty() {
    description += "\n\n📝 \{note}"
  }
  @model.Embed(
    title="🗓️ \{title}",
    description~,
    color=0x57F287,
    footer=@model.EmbedFooter("作成: \{display_name}", icon_url=avatar_url),
    fields=options.mapi((i, label) => {
      @model.EmbedField("\{i + 1}. \{label}", "**0人**", inline=false)
    }),
  )
}

///|
fn schedule_components(options : Array[String]) -> Array[@model.Component] {
  [
    @discord.action_row([
      @discord.string_select(
        custom_id=SCHEDULE_CUSTOM_ID,
        placeholder="参加できる日時をすべて選択… Select all dates you can attend...",
        min_values=0,
        max_values=options.length(),
        options=options.mapi((i, label) => {
          @discord.select_option(
            label=String::from_iter(label.iter().take(100)),
            value=i.to_string(),
          )
        }),
      ),
    ]),
  ]
}

///|
fn rebuild_schedule_embed(
  embed : @model.Embed,
  user_id : @model.UserId,
  values : Array[String],
) -> @model.Embed {
  let selected : Array[Int] = []
  for value in values {
    let index = @string.parse_int(value) catch { _ => continue }
    selected.push(index)
  }
  {
    ..embed,
    fields: Some(
      embed.fields
      .unwrap_or([])
      .mapi((i, field) => {
        ..field,
        value: rebuild_schedule_field(
          field.value,
          user_id,
          selected.contains(i),
        ),
        inline: Some(false),
      }),
    ),
  }
}

///|
fn schedule_command(_runtime : Runtime) -> @discord.Command[ScheduleArgs] {
  @discord.slash(
    name="schedule",
    description="Create a scheduling poll with comma-separated dates.",
    description_localizations={
      "ja": "日程調整を作成します（候補はカンマ区切り）",
    },
    args=@discord.Args::map3(
      @discord.arg_string(name="title", description="Poll title", description_localizations={
        "ja": "タイトル（例: 第3回全体会議）",
      }),
      @discord.arg_string(
        name="dates",
        description="Comma-separated candidate dates",
        description_localizations={
          "ja": "候補日時をカンマ区切りで（例: 7/20(月) 21:00, 7/21(火) 21:00）",
        },
      ),
      @discord.arg_string(
        name="note",
        description="Additional notes, such as a deadline",
        description_localizations={ "ja": "補足（締切など）" },
      ).optional(),
      (title, dates, note) => { title, dates, note, },
    ),
    handler=Immediate((ctx, args) => {
      let guild = ctx.guild_scope()
      let options = schedule_dates(args.dates)
      if schedule_dates_error(options) is Some(content) {
        return @discord.CommandReply::message(content~, ephemeral=true)
      }
      let user = ctx.user()
      @discord.CommandReply::message(
        embeds=[
          schedule_embed(
            args.title,
            options,
            args.note,
            member_tools_display_name(user, Some(guild.member)),
            member_tools_avatar_url(
              user,
              Some(guild.guild_id),
              Some(guild.member),
            ),
          ),
        ],
        components=schedule_components(options),
      )
    }),
  ).check(@discord.guild_only())
}

///|
fn register_schedule_handler(app : @discord.App) -> Unit {
  // App::validate rejects ':' in typed route ids in discord.mbt 0.3.1.
  app.on_component_raw(prefix=SCHEDULE_CUSTOM_ID, ctx => {
    guard ctx.data.custom_id == SCHEDULE_CUSTOM_ID else { return }
    guard ctx.guild_scope() is Some(_) else {
      raise @discord.HandlerError::GuildOnly
    }
    guard ctx.message().embeds.get(0) is Some(embed) else {
      raise @discord.HandlerError::InvalidArgument(
        "The schedule embed is unavailable.",
      )
    }
    ctx.update_message(embeds=[
      rebuild_schedule_embed(
        embed,
        ctx.user().id,
        ctx.data.values.unwrap_or([]),
      ),
    ])
    ctx.followup(
      content="回答を記録しました！ Recorded! （選び直すと上書きされます）",
      ephemeral=true,
    )
    |> ignore
  })
}
