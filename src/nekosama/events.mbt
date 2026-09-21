///|
const EVENT_NOTIFY_KEY : String = "event_notify"

///|
const EVENT_TICK_MS : Int = 60000

///|
const REMINDER_LEAD_SECONDS : Int64 = 300

///|
/// What `/event` remembers about one scheduled event, stored under
/// `event_notify.<event id>` in the same shape the Python bot used.
priv struct EventState {
  role_id : @model.RoleId?
  channel_id : @model.ChannelId?
  reminded : Bool
  started : Bool
}

///|
fn EventState::from_json(json : Json) -> EventState {
  guard json is Object(fields) else {
    return { role_id: None, channel_id: None, reminded: false, started: false, }
  }
  {
    role_id: fields.get("role_id").bind(id_from_json),
    channel_id: fields.get("channel_id").bind(id_from_json),
    reminded: fields.get("reminded") is Some(True),
    started: fields.get("started") is Some(True),
  }
}

///|
fn EventState::to_json_value(self : EventState) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.role_id is Some(role_id) {
    fields["role_id"] = id_to_json(role_id)
  }
  if self.channel_id is Some(channel_id) {
    fields["channel_id"] = id_to_json(channel_id)
  }
  if self.reminded {
    fields["reminded"] = Json::boolean(true)
  }
  if self.started {
    fields["started"] = Json::boolean(true)
  }
  Json::object(fields)
}

///|
fn event_states(
  config : ConfigStore,
  guild_id : @model.GuildId,
) -> Map[String, EventState] {
  let states : Map[String, EventState] = Map([])
  if config.get(guild_id, EVENT_NOTIFY_KEY) is Some(Object(entries)) {
    for event_id, state in entries {
      states[event_id] = EventState::from_json(state)
    }
  }
  states
}

///|
async fn save_event_states(
  config : ConfigStore,
  guild_id : @model.GuildId,
  states : Map[String, EventState],
) -> Unit {
  let entries : Map[String, Json] = Map([])
  for event_id, state in states {
    entries[event_id] = state.to_json_value()
  }
  config.set(guild_id, EVENT_NOTIFY_KEY, Json::object(entries))
}

///|
/// Which notices are due for an event starting `seconds_until_start` from now.
/// The reminder fires inside the last five minutes; the start notice fires
/// once the start time has passed.
fn due_notices(state : EventState, seconds_until_start : Int64) -> (Bool, Bool) {
  let remind = !state.reminded &&
    seconds_until_start > 0L &&
    seconds_until_start <= REMINDER_LEAD_SECONDS
  let start = !state.started && seconds_until_start <= 0L
  (remind, start)
}

///|
/// Events that were already announced and no longer exist.
fn stale_event_ids(
  states : Map[String, EventState],
  live_ids : Array[String],
) -> Array[String] {
  let stale = []
  for event_id, state in states {
    if !live_ids.contains(event_id) && (state.reminded || state.started) {
      stale.push(event_id)
    }
  }
  stale
}

///|
fn event_url(event : @model.GuildScheduledEvent) -> String {
  "https://discord.com/events/\{event.guild_id}/\{event.id}"
}

///|
fn event_place(event : @model.GuildScheduledEvent) -> String {
  match event.channel_id.to_option() {
    Some(channel_id) => "<#\{channel_id}>"
    None =>
      match event.entity_metadata.to_option() {
        Some(metadata) => metadata.location.unwrap_or("")
        None => ""
      }
  }
}

///|
fn event_notice_text(
  event : @model.GuildScheduledEvent,
  mention~ : String,
  before~ : Bool,
) -> String {
  let place = event_place(event)
  let url = event_url(event)
  if before {
    "__**\{event.name}**__ が \{place} で **5分後** に始まります！\n\{url}"
  } else {
    "\{mention}\n__**\{event.name}**__ が始まりました！ \{place} へどうぞ！\n\{url}"
  }
}

///|
/// Text channels in the event channel's category, in display order. These are
/// the default places to announce an event, tried in turn.
fn sibling_text_channels(
  channels : Array[@model.Channel],
  event_channel_id : @model.ChannelId,
) -> Array[@model.ChannelId] {
  guard channels.search_by(channel => channel.id == event_channel_id)
    is Some(index) else {
    return []
  }
  guard @model.flatten(channels[index].parent_id) is Some(category_id) else {
    return []
  }
  let siblings = channels.filter(channel => {
    channel.typ == GuildText &&
    @model.flatten(channel.parent_id) == Some(category_id)
  })
  siblings.sort_by((a, b) => {
    let by_position = a.position.unwrap_or(0).compare(b.position.unwrap_or(0))
    if by_position != 0 {
      by_position
    } else {
      a.id.compare(b.id)
    }
  })
  siblings.map(channel => channel.id)
}

///|
/// Where to announce: the configured channel, then the text channels next to
/// the voice channel, then the system channel.
async fn notice_channels(
  http : @http.Client,
  event : @model.GuildScheduledEvent,
  state : EventState,
) -> Array[@model.ChannelId] {
  let candidates = []
  if state.channel_id is Some(channel_id) {
    candidates.push(channel_id)
  }
  let guild = http.guild_ref(event.guild_id)
  if event.channel_id.to_option() is Some(event_channel_id) {
    let channels = guild.channels() catch { _ => [] }
    candidates.append(sibling_text_channels(channels, event_channel_id))
  }
  let system_channel = guild.fetch().system_channel_id.to_option() catch {
    _ => None
  }
  if system_channel is Some(channel_id) {
    candidates.push(channel_id)
  }
  candidates
}

///|
/// Sends to the first channel that accepts the message. A channel the bot
/// cannot write to is skipped rather than checked up front.
async fn send_event_notice(
  http : @http.Client,
  event : @model.GuildScheduledEvent,
  state : EventState,
  before~ : Bool,
) -> Unit {
  let mention = match state.role_id {
    Some(role_id) => "<@&\{role_id}>"
    None => "@everyone"
  }
  let content = event_notice_text(event, mention~, before~)
  let allowed_mentions = @model.AllowedMentions(parse=[Everyone, Roles])
  for channel_id in notice_channels(http, event, state) {
    let sent = try {
      http.channel_ref(channel_id).send(content~, allowed_mentions~) |> ignore
      true
    } catch {
      error => {
        println(
          "[events] could not announce \{event.id} in \{channel_id}: \{Repr(error)}",
        )
        false
      }
    }
    if sent {
      return
    }
  }
  println("[events] no channel accepted the notice for \{event.id}")
}

///|
/// One pass over a guild's scheduled events: remind, auto-start, announce,
/// and forget events that are gone.
async fn tick_guild_events(
  http : @http.Client,
  config : ConfigStore,
  guild_id : @model.GuildId,
  now_unix_seconds : Int64,
) -> Unit {
  let events = http.guild_ref(guild_id).scheduled_events()
  let states = event_states(config, guild_id)
  let live_ids = []
  let mut changed = false
  for event in events {
    guard event.status is (Scheduled | Active) else { continue }
    let key = "\{event.id}"
    live_ids.push(key)
    let state = states
      .get(key)
      .unwrap_or({
        role_id: None,
        channel_id: None,
        reminded: false,
        started: false,
      })
    let starts_at_ms = event.scheduled_start_time.unix_ms() catch {
      _ => continue
    }
    let starts_at = starts_at_ms / 1000L
    let (remind, start) = due_notices(state, starts_at - now_unix_seconds)
    if remind {
      send_event_notice(http, event, state, before=true)
      states[key] = { ..state, reminded: true, }
      changed = true
    }
    if start {
      if event.status is Scheduled {
        try
          http
          .guild_ref(guild_id)
          .scheduled_event_ref(event.id)
          .edit(status=Active, reason="Start time reached")
          |> ignore
        catch {
          error =>
            println("[events] failed to start \{event.id}: \{Repr(error)}")
        }
      }
      send_event_notice(http, event, state, before=false)
      states[key] = { ..states.get(key).unwrap_or(state), started: true, }
      changed = true
    }
  }
  for event_id in stale_event_ids(states, live_ids) {
    states.remove(event_id)
    changed = true
  }
  if changed {
    save_event_states(config, guild_id, states)
  }
}

///|
/// The guilds the bot is in, kept from READY and GUILD_CREATE/DELETE so the
/// ticker needs no guild cache.
priv struct GuildRoster {
  ids : Map[String, @model.GuildId]
}

///|
fn GuildRoster::add(self : GuildRoster, guild_id : @model.GuildId) -> Unit {
  self.ids["\{guild_id}"] = guild_id
}

///|
fn start_validation(text : String) -> String? {
  let now = unix_now_seconds()
  match parse_when(text, now_unix_seconds=now) {
    None =>
      Some(
        "開始日時が読み取れませんでした。`7/20 21:00` のような形式で入力してください。",
      )
    Some(time) if time.unix_seconds() <= now =>
      Some("過去の日時は指定できません。")
    Some(_) => None
  }
}

///|
fn unix_now_seconds() -> Int64 {
  (@env.now() / 1000UL).reinterpret_as_int64()
}

///|
priv struct EventForm {
  name : String
  voice_channel : @model.ChannelId
  start : String
  mention : @model.RoleId?
  channel : @model.ChannelId?
  description : String?
}

///|
fn event_command(runtime : Runtime) -> @discord.Command[EventForm] {
  @discord.slash(
    name="event",
    description="Create a Discord event with a 5-minute reminder and a start notice.",
    description_localizations={
      "ja": "Discordイベントを作成します（5分前リマインドと開始通知つき）",
    },
    args=@discord.Args::map6(
      @discord.arg_string(
        name="name",
        description="イベント名（例: 第3回全体会議）",
      ),
      @discord.arg_channel(
        name="vc",
        description="開催するボイスチャンネル",
        channel_types=[GuildVoice],
      ),
      @discord.arg_string(
        name="start",
        description="開始日時・日本時間（例: 7/20 21:00）",
      ).validate(start_validation),
      @discord.arg_role(
        name="mention",
        description="開始通知でメンションするロール（省略時は @everyone）",
      ).optional(),
      @discord.arg_channel(
        name="channel",
        description="通知先チャンネル（省略時はVCと同じカテゴリの先頭テキストch）",
        channel_types=[GuildText],
      ).optional(),
      @discord.arg_string(
        name="description",
        description="イベントの説明（任意）",
      ).optional(),
      (name, voice_channel, start, mention, channel, description) => {
        name,
        voice_channel,
        start,
        mention,
        channel,
        description,
      },
    ),
    handler=Deferred(ephemeral=false, (ctx, form) => {
      let guild = ctx.guild_scope()
      guard parse_when(form.start, now_unix_seconds=unix_now_seconds())
        is Some(when) else {
        ctx.edit_original(
          content="開始日時が読み取れませんでした。",
        )
        |> ignore
        return
      }
      let user = ctx.user()
      let event = ctx
        .app()
        .http()
        .guild_ref(guild.guild_id)
        .create_scheduled_event(
          form.name,
          GuildOnly,
          @model.Timestamp(when.iso8601()),
          Voice,
          channel_id=form.voice_channel,
          description?=form.description,
          reason="/event by \{user.username}",
        )
      let states = event_states(runtime.config, guild.guild_id)
      states["\{event.id}"] = {
        role_id: form.mention,
        channel_id: form.channel,
        reminded: false,
        started: false,
      }
      save_event_states(runtime.config, guild.guild_id, states)
      ctx.edit_original(
        content="イベントを作成しました！ <t:\{when.unix_seconds()}:F> 開始、5分前と開始時にお知らせします。\n" +
          "「興味あり」を押すとDiscordからも通知が届きます。\n" +
          event_url(event),
      )
      |> ignore
    }),
  ).check(@discord.guild_only())
}

///|
pub fn register_events(
  app : @discord.App,
  bot : @discord.Bot,
  runtime : Runtime,
) -> Unit {
  app.command(event_command(runtime))
  let roster : GuildRoster = { ids: Map([]), }
  bot.on(@discord.Events::ready(), (_, ready) => {
    for guild in ready.guilds {
      roster.add(guild.id)
    }
  })
  bot.on(@discord.Events::guild_create(), (_, event) => {
    match event {
      Available(available) => roster.add(available.guild.id)
      Unavailable(unavailable) => roster.add(unavailable.id)
    }
  })
  bot.on(@discord.Events::guild_delete(), (_, guild) => {
    // An outage keeps the guild; only leaving or being removed drops it.
    if !guild.unavailable {
      roster.ids.remove("\{guild.id}")
    }
  })
  bot.on(@discord.Events::guild_scheduled_event_delete(), (_, event) => {
    let states = event_states(runtime.config, event.guild_id)
    if states.contains("\{event.id}") {
      states.remove("\{event.id}")
      save_event_states(runtime.config, event.guild_id, states)
    }
  })
  bot.service(name="event-notifier", ctx => {
    for ;; {
      @async.sleep(EVENT_TICK_MS)
      let http = ctx.app().http()
      for _, guild_id in roster.ids {
        tick_guild_events(http, runtime.config, guild_id, unix_now_seconds()) catch {
          error =>
            println("[events] tick failed for \{guild_id}: \{Repr(error)}")
        }
      }
    }
  })
}
