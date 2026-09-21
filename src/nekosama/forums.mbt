///|
const FORUM_INDEXES_KEY : String = "forum_indexes"

///|
const INDEX_THREAD_NAME : String = "📌 スレッド一覧 Thread Index"

///|
const AUTO_TAG_NAME : String = "実施前"

///|
const UNTAGGED : String = "（タグなし）"

///|
/// Tags named like 【…】 are labels, not categories; they get no heading of
/// their own in the index.
const LABEL_TAG_PREFIX : String = "【"

///|
const INDEX_MESSAGE_LIMIT : Int = 2000

///|
const ARCHIVED_FETCH_LIMIT : Int = 50

///|
const ARCHIVED_SHOWN : Int = 20

///|
/// Thread changes arrive in bursts, so the index is rebuilt once they settle.
const REFRESH_DELAY_MS : UInt64 = 5000

///|
const REFRESH_ALL_INTERVAL_MS : UInt64 = 1800000

///|
const FORUM_SERVICE_TICK_MS : Int = 1000

///|
/// The tag given to a new post that has none: the first whose name mentions
/// 実施前.
fn auto_tag(available_tags : Array[@model.ForumTag]) -> @model.ForumTag? {
  for tag in available_tags {
    if tag.name.contains(AUTO_TAG_NAME) {
      return Some(tag)
    }
  }
  None
}

///|
/// The name of the first applied tag the forum still defines.
fn first_tag_name(
  thread : @model.Channel,
  available_tags : Array[@model.ForumTag],
) -> String? {
  for tag_id in thread.applied_tags.unwrap_or([]) {
    for tag in available_tags {
      if tag.id == tag_id {
        return Some(tag.name)
      }
    }
  }
  None
}

///|
/// Threads grouped under their first tag, in the forum's tag order, then the
/// untagged ones, then any remaining label tags.
fn group_by_tag(
  available_tags : Array[@model.ForumTag],
  threads : Array[@model.Channel],
  index_thread_id : @model.ChannelId,
) -> Map[String, Array[@model.ChannelId]] {
  let groups : Map[String, Array[@model.ChannelId]] = Map([])
  for tag in available_tags {
    if !tag.name.has_prefix(LABEL_TAG_PREFIX) {
      groups[tag.name] = []
    }
  }
  groups[UNTAGGED] = []
  for thread in threads {
    if thread.id == index_thread_id {
      continue
    }
    let key = first_tag_name(thread, available_tags).unwrap_or(UNTAGGED)
    match groups.get(key) {
      Some(members) => members.push(thread.id)
      None => groups[key] = [thread.id]
    }
  }
  groups
}

///|
/// Cut to Discord's message limit, counting characters rather than UTF-16
/// units so a surrogate pair is never split.
fn clip_message(content : String) -> String {
  if content.char_length() <= INDEX_MESSAGE_LIMIT {
    return content
  }
  let clipped = StringBuilder()
  for index, ch in content {
    if index >= INDEX_MESSAGE_LIMIT - 10 {
      break
    }
    clipped.write_char(ch)
  }
  clipped.write_string("\n…")
  clipped.to_string()
}

///|
fn render_index(
  forum_id : @model.ChannelId,
  groups : Map[String, Array[@model.ChannelId]],
  archived : Array[@model.ChannelId],
) -> String {
  let lines = [
    "# <#\{forum_id}> のスレッド一覧",
    "*このメッセージは自動更新されます。 This message is updated automatically.*",
    "",
  ]
  for name, members in groups {
    if members.is_empty() {
      continue
    }
    lines.push("## \{name}")
    for thread_id in members {
      lines.push("- <#\{thread_id}>")
    }
  }
  if !archived.is_empty() {
    lines.push("## アーカイブ済み Archived")
    for index, thread_id in archived {
      if index >= ARCHIVED_SHOWN {
        break
      }
      lines.push("- <#\{thread_id}>")
    }
    if archived.length() > ARCHIVED_SHOWN {
      lines.push("- …他\{archived.length() - ARCHIVED_SHOWN}件")
    }
  }
  clip_message(lines.join("\n"))
}

///|
/// Archived threads that are not also live, without the index thread itself.
fn archived_only(
  archived : Array[@model.Channel],
  live : Array[@model.Channel],
  index_thread_id : @model.ChannelId,
) -> Array[@model.ChannelId] {
  archived
  .filter(thread => {
    thread.id != index_thread_id &&
    !live.iter().any(other => other.id == thread.id)
  })
  .map(thread => thread.id)
}

///|
/// Where a forum's index lives: `forum_indexes.<forum id>` in config.json.
priv struct ForumIndex {
  thread_id : @model.ChannelId
  message_id : @model.MessageId
}

///|
fn forum_index(
  config : ConfigStore,
  guild_id : @model.GuildId,
  forum_id : @model.ChannelId,
) -> ForumIndex? {
  guard config.get(guild_id, FORUM_INDEXES_KEY) is Some(Object(indexes)) else {
    return None
  }
  guard indexes.get("\{forum_id}") is Some(Object(fields)) else { return None }
  guard fields.get("thread_id").bind(id_from_json) is Some(thread_id) else {
    return None
  }
  guard fields.get("message_id").bind(id_from_json) is Some(message_id) else {
    return None
  }
  Some({ thread_id, message_id, })
}

///|
fn indexed_forums(
  config : ConfigStore,
  guild_id : @model.GuildId,
) -> Array[@model.ChannelId] {
  let forums = []
  if config.get(guild_id, FORUM_INDEXES_KEY) is Some(Object(indexes)) {
    for raw, _ in indexes {
      let forum_id : @model.ChannelId? = Some(@model.Id::parse(raw)) catch {
        _ => None
      }
      if forum_id is Some(forum_id) {
        forums.push(forum_id)
      }
    }
  }
  forums
}

///|
async fn save_forum_index(
  config : ConfigStore,
  guild_id : @model.GuildId,
  forum_id : @model.ChannelId,
  index : ForumIndex,
) -> Unit {
  let indexes : Map[String, Json] = match
    config.get(guild_id, FORUM_INDEXES_KEY) {
    Some(Object(existing)) => existing.copy()
    _ => Map([])
  }
  indexes["\{forum_id}"] = {
    "thread_id": id_to_json(index.thread_id),
    "message_id": id_to_json(index.message_id),
  }
  config.set(guild_id, FORUM_INDEXES_KEY, Json::object(indexes))
}

///|
/// Rebuild the index message from the forum's current threads.
async fn refresh_forum_index(
  http : @http.Client,
  config : ConfigStore,
  guild_id : @model.GuildId,
  forum_id : @model.ChannelId,
) -> Unit {
  guard forum_index(config, guild_id, forum_id) is Some(index) else { return }
  let forum = http.channel_ref(forum_id).fetch()
  let live = http.guild_ref(guild_id).active_threads().threads.filter(thread => {
    @model.flatten(thread.parent_id) == Some(forum_id)
  })
  live.sort_by((a, b) => a.id.compare(b.id))
  let archived = http
    .channel_ref(forum_id)
    .public_archived_threads(limit=ARCHIVED_FETCH_LIMIT).threads catch {
      _ => []
    }
  let content = render_index(
    forum_id,
    group_by_tag(forum.available_tags.unwrap_or([]), live, index.thread_id),
    archived_only(archived, live, index.thread_id),
  )
  http.message_ref(index.thread_id, index.message_id).edit(content~) |> ignore
}

///|
/// Forums waiting for a rebuild, with the time each one becomes due.
priv struct RefreshQueue {
  pending : Map[String, (@model.GuildId, @model.ChannelId, UInt64)]
}

///|
/// Later changes push the deadline back, so a burst causes one rebuild.
fn RefreshQueue::schedule(
  self : RefreshQueue,
  config : ConfigStore,
  guild_id : @model.GuildId,
  forum_id : @model.ChannelId,
  now_ms~ : UInt64,
) -> Unit {
  if forum_index(config, guild_id, forum_id) is Some(_) {
    self.pending["\{forum_id}"] = (
      guild_id,
      forum_id,
      now_ms + REFRESH_DELAY_MS,
    )
  }
}

///|
fn RefreshQueue::take_due(
  self : RefreshQueue,
  now_ms~ : UInt64,
) -> Array[(@model.GuildId, @model.ChannelId)] {
  let due = []
  for key, entry in self.pending {
    if entry.2 <= now_ms {
      due.push((key, entry.0, entry.1))
    }
  }
  due.map(item => {
    self.pending.remove(item.0)
    (item.1, item.2)
  })
}

///|
async fn refresh_logged(
  http : @http.Client,
  config : ConfigStore,
  guild_id : @model.GuildId,
  forum_id : @model.ChannelId,
) -> Unit {
  refresh_forum_index(http, config, guild_id, forum_id) catch {
    error =>
      println(
        "[forums] failed to refresh the index of \{forum_id}: \{Repr(error)}",
      )
  }
}

///|
fn forum_index_command(runtime : Runtime) -> @discord.Command[@model.ChannelId] {
  @discord.slash(
    name="forum-index",
    description="Place a self-updating thread index in a forum.",
    description_localizations={
      "ja": "フォーラムに自動更新されるスレッド一覧を設置します",
    },
    args=@discord.Args::of(
      @discord.arg_channel(name="forum", description="Forum to index", channel_types=[
        GuildForum,
      ]),
    ),
    handler=Deferred(ephemeral=true, (ctx, forum_id) => {
      let guild = ctx.guild_scope()
      let http = ctx.app().http()
      if forum_index(runtime.config, guild.guild_id, forum_id) is None {
        let thread = http
          .channel_ref(forum_id)
          .start_forum_thread(
            INDEX_THREAD_NAME,
            content="(準備中 preparing...)",
          )
        try
          http.channel_ref(thread.id).edit(flags=@model.ChannelFlags::pinned())
          |> ignore
        catch {
          _ => ()
        }
        // A forum post's starter message shares the thread's id.
        save_forum_index(runtime.config, guild.guild_id, forum_id, {
          thread_id: thread.id,
          message_id: @model.Id::parse("\{thread.id}"),
        })
      }
      refresh_logged(http, runtime.config, guild.guild_id, forum_id)
      ctx.edit_original(
        content="<#\{forum_id}> にスレッド一覧を設置・更新しました。",
      )
      |> ignore
    }),
    default_member_permissions=@model.Permissions::manage_threads(),
  ).check(@discord.guild_only())
}

///|
/// Tag a brand-new forum post that has no tag yet.
async fn auto_tag_new_post(
  ctx : @discord.GatewayCtx,
  thread : @model.Channel,
  parent_id : @model.ChannelId,
) -> Unit {
  guard thread.applied_tags.unwrap_or([]).is_empty() else { return }
  let parent = ctx.resolve_channel(parent_id)
  guard parent.typ == GuildForum else { return }
  guard auto_tag(parent.available_tags.unwrap_or([])) is Some(tag) else {
    return
  }
  ctx.channel_ref(thread.id).edit(applied_tags=[tag.id]) |> ignore
}

///|
pub fn register_forums(
  app : @discord.App,
  bot : @discord.Bot,
  runtime : Runtime,
) -> Unit {
  app.command(forum_index_command(runtime))
  let queue : RefreshQueue = { pending: Map([]), }
  bot.on(@discord.Events::thread_create(), (ctx, event) => {
    let thread = event.channel
    guard thread.guild_id is Some(guild_id) &&
      @model.flatten(thread.parent_id) is Some(parent_id) else {
      return
    }
    if event.newly_created == Some(true) {
      auto_tag_new_post(ctx, thread, parent_id) catch {
        error =>
          println("[forums] failed to auto-tag \{thread.id}: \{Repr(error)}")
      }
    }
    queue.schedule(runtime.config, guild_id, parent_id, now_ms=@env.now())
  })
  bot.on(@discord.Events::thread_update(), (_, thread) => {
    guard thread.guild_id is Some(guild_id) &&
      @model.flatten(thread.parent_id) is Some(parent_id) else {
      return
    }
    queue.schedule(runtime.config, guild_id, parent_id, now_ms=@env.now())
  })
  bot.on(@discord.Events::thread_delete(), (_, event) => {
    queue.schedule(
      runtime.config,
      event.guild_id,
      event.parent_id,
      now_ms=@env.now(),
    )
  })
  bot.service(name="forum-index", ctx => {
    let mut next_full_refresh = @env.now() + REFRESH_ALL_INTERVAL_MS
    for ;; {
      @async.sleep(FORUM_SERVICE_TICK_MS)
      let http = ctx.app().http()
      let now = @env.now()
      for entry in queue.take_due(now_ms=now) {
        refresh_logged(http, runtime.config, entry.0, entry.1)
      }
      if now >= next_full_refresh {
        next_full_refresh = now + REFRESH_ALL_INTERVAL_MS
        for guild_id in runtime.config.guilds_with(FORUM_INDEXES_KEY) {
          for forum_id in indexed_forums(runtime.config, guild_id) {
            refresh_logged(http, runtime.config, guild_id, forum_id)
          }
        }
      }
    }
  })
}
