///|
test "absence embeds preserve Python fields and optional reason semantics" {
  let embed = absence_embed(
    { period: "7/20〜7/25", reason: Some("旅行"), },
    "表示名",
    "https://example.com/avatar.png",
  )
  json_inspect(embed, content={
    "title": "🙇 不在連絡 / Absence",
    "color": 15844367,
    "author": {
      "name": "表示名",
      "icon_url": "https://example.com/avatar.png",
    },
    "fields": [
      { "name": "期間 Period", "value": "7/20〜7/25", "inline": false },
      { "name": "理由 Reason", "value": "旅行", "inline": false },
    ],
  })
  for reason in [None, Some("")] {
    assert_eq(
      absence_embed({ period: "今週", reason, }, "name", "url").fields
      .unwrap()
      .length(),
      1,
    )
  }
  assert_eq(
    absence_embed({ period: "今週", reason: Some(" "), }, "name", "url").fields
    .unwrap()
    .length(),
    2,
  )
}

///|
test "absence destination falls back for absent foreign and thread channels" {
  let guild_id : @model.GuildId = @model.Id::parse("123")
  let fallback : @model.ChannelId = @model.Id::parse("456")
  let configured : @model.Channel = @json.from_json({
    "id": "789",
    "guild_id": "123",
    "type": 0,
  })
  assert_eq(
    absence_destination(guild_id, Some(configured), Some(fallback)),
    Some(configured.id),
  )
  assert_eq(absence_destination(guild_id, None, Some(fallback)), Some(fallback))
  assert_eq(
    absence_destination(
      guild_id,
      Some({ ..configured, guild_id: Some(@model.Id::parse("999")), }),
      Some(fallback),
    ),
    Some(fallback),
  )
  for
    typ in [@model.ChannelType::AnnouncementThread, PublicThread, PrivateThread] {
    assert_eq(
      absence_destination(
        guild_id,
        Some({ ..configured, typ, }),
        Some(fallback),
      ),
      Some(fallback),
    )
  }
  assert_true(absence_destination(guild_id, None, None) is None)
}

///|
test "absence command keeps period required and reason optional" {
  let runtime = Runtime("unused", ConfigStore("unused.json"))
  guard absence_command(runtime).spec().to_json()
    is {
      "name": "absence",
      "description_localizations": {
        "ja": "不在連絡を投稿します（期間と理由は任意入力）",
        ..
      },
      "options": [
        { "name": "period", "required": true, .. },
        { "name": "reason", "required": false, .. },
      ],
      ..
    } else {
    fail("unexpected absence command schema")
  }
}
