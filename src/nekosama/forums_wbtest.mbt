///|
fn test_tag(id : String, name : String) -> @model.ForumTag raise {
  @json.from_json({
    "id": id,
    "name": name,
    "moderated": false,
    "emoji_id": null,
    "emoji_name": null,
  })
}

///|
fn test_thread(id : String, tags : Array[String]) -> @model.Channel raise {
  @json.from_json({
    "id": id,
    "type": 11,
    "applied_tags": tags.map(tag => Json::string(tag)),
  })
}

///|
fn test_tags() -> Array[@model.ForumTag] raise {
  [
    test_tag("1", "実施前 Upcoming"),
    test_tag("2", "実施済み Done"),
    test_tag("3", "【重要】"),
  ]
}

///|
fn test_channel_id(raw : String) -> @model.ChannelId raise {
  @model.Id::parse(raw)
}

///|
test "new posts get the first tag that mentions 実施前" {
  guard auto_tag(test_tags()) is Some(tag) else { fail("no tag was chosen") }
  inspect(tag.name, content="実施前 Upcoming")
  inspect(
    auto_tag([test_tag("2", "実施済み Done")]) is None,
    content="true",
  )
}

///|
test "threads are grouped by their first known tag in forum order" {
  let threads = [
    test_thread("100", ["2"]),
    test_thread("101", []),
    test_thread("102", ["1", "2"]),
    test_thread("103", ["3"]),
    test_thread("104", ["999", "1"]),
    test_thread("900", ["1"]),
  ]
  let groups = group_by_tag(test_tags(), threads, test_channel_id("900"))
  debug_inspect(
    groups.to_array().map(entry => (entry.0, entry.1.map(id => id.to_string()))),
    content=(
      #|[
      #|  ("実施前 Upcoming", ["102", "104"]),
      #|  ("実施済み Done", ["100"]),
      #|  ("（タグなし）", ["101"]),
      #|  ("【重要】", ["103"]),
      #|]
    ),
  )
}

///|
test "the index lists groups, skips empty ones, and caps the archive" {
  let groups = group_by_tag(
    test_tags(),
    [test_thread("100", ["2"]), test_thread("101", ["2"])],
    test_channel_id("900"),
  )
  let archived = Array::makei(22, i => test_channel_id("\{500 + i}"))
  let content = render_index(test_channel_id("42"), groups, archived)
  let lines = content.split("\n").map(line => line.to_owned()).to_array()
  inspect(lines[0], content="# <#42> のスレッド一覧")
  debug_inspect(
    lines[3:6].to_owned(),
    content=(
      #|["## 実施済み Done", "- <#100>", "- <#101>"]
    ),
  )
  inspect(lines[6], content="## アーカイブ済み Archived")
  inspect(lines.length(), content="28")
  inspect(lines[lines.length() - 1], content="- …他2件")
}

///|
test "archived threads exclude live ones and the index itself" {
  let live = [test_thread("100", [])]
  let archived = [
    test_thread("100", []),
    test_thread("200", []),
    test_thread("900", []),
  ]
  debug_inspect(
    archived_only(archived, live, test_channel_id("900")).map(id => {
      id.to_string()
    }),
    content=(
      #|["200"]
    ),
  )
}

///|
test "an oversized index is clipped below the message limit" {
  let long = "あ".repeat(2500)
  let clipped = clip_message(long)
  inspect(clipped.char_length(), content="1992")
  inspect(clipped.has_suffix("\n…"), content="true")
  inspect(clip_message("short"), content="short")
}

///|
test "a burst of thread changes causes one rebuild after it settles" {
  let config = ConfigStore("unused.json")
  let guild_id : @model.GuildId = @model.Id::parse("1")
  let forum_id = test_channel_id("42")
  let queue : RefreshQueue = { pending: Map([]), }
  // Forums without an index are never queued.
  queue.schedule(config, guild_id, forum_id, now_ms=0)
  inspect(queue.pending.length(), content="0")
  config.data["1"] = {
    "forum_indexes": { "42": { "thread_id": 900, "message_id": 900 } },
  }
  queue.schedule(config, guild_id, forum_id, now_ms=1000)
  queue.schedule(config, guild_id, forum_id, now_ms=4000)
  inspect(queue.take_due(now_ms=6000).length(), content="0")
  inspect(queue.take_due(now_ms=9000).length(), content="1")
  inspect(queue.take_due(now_ms=20000).length(), content="0")
}
