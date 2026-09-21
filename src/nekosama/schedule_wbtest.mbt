///|
test "schedule fields add retain and remove attendance" {
  let user_id : @model.UserId = @model.Id::parse("1525156408767676466")
  assert_eq(
    rebuild_schedule_field("**0人**", user_id, true),
    "**1人** <@1525156408767676466>",
  )
  assert_eq(
    rebuild_schedule_field("**1人** <@1525156408767676466>", user_id, true),
    "**1人** <@1525156408767676466>",
  )
  assert_eq(
    rebuild_schedule_field("**1人** <@1525156408767676466>", user_id, false),
    "**0人**",
  )
  assert_eq(rebuild_schedule_field("**0人**", user_id, false), "**0人**")
}

///|
test "schedule rebuilding derives counts from mentions and preserves other voters" {
  let user_id : @model.UserId = @model.Id::parse("123")
  assert_eq(
    rebuild_schedule_field("**99人** <@!456> <@123> <@!789>", user_id, true),
    "**3人** <@456> <@123> <@789>",
  )
  assert_eq(
    rebuild_schedule_field("**99人** <@!456> <@123> <@!789>", user_id, false),
    "**2人** <@456> <@789>",
  )
  assert_eq(
    rebuild_schedule_field("<@!00456> <@789>", user_id, true),
    "**3人** <@456> <@789> <@123>",
  )
  assert_eq(
    rebuild_schedule_field("noise <@&123> <#456> <@invalid>", user_id, false),
    "**0人**",
  )
  assert_eq(rebuild_schedule_field("", user_id, true), "**1人** <@123>")
}

///|
test "schedule rebuilding retains Python duplicate mention semantics" {
  let user_id : @model.UserId = @model.Id::parse("123")
  assert_eq(
    rebuild_schedule_field("<@123> <@!123> <@456>", user_id, true),
    "**3人** <@123> <@123> <@456>",
  )
  assert_eq(
    rebuild_schedule_field("<@123> <@!123> <@456>", user_id, false),
    "**2人** <@123> <@456>",
  )
}

///|
test "schedule date splitting and candidate limits match Python" {
  assert_eq(
    schedule_dates(" 7/20(月) 21:00, 7/21(火) 21:00、\n7/22\r\n ,　7/23　"),
    ["7/20(月) 21:00", "7/21(火) 21:00", "7/22", "7/23"],
  )
  assert_eq(schedule_dates("a,a"), ["a", "a"])
  assert_eq(
    schedule_dates_error(schedule_dates(" ,、\n\t ")),
    Some("候補日時が読み取れませんでした。"),
  )
  assert_true(schedule_dates_error(Array::make(25, "day")) is None)
  assert_eq(
    schedule_dates_error(Array::make(26, "day")),
    Some("候補は25個までです。"),
  )
}

///|
test "schedule embed and select preserve Japanese text and Python wire IDs" {
  let options = ["7/20", "7/21"]
  let embed = schedule_embed(
    "会議",
    options,
    Some("締切は明日"),
    "作成者",
    "avatar",
  )
  json_inspect(embed, content={
    "title": "🗓️ 会議",
    "description": "参加できる日時を**すべて**選んで送信してください。\nSelect **all** the dates you can attend.\n回答を消すには何も選ばずに送信します。\n\n📝 締切は明日",
    "color": 5763719,
    "footer": { "text": "作成: 作成者", "icon_url": "avatar" },
    "fields": [
      { "name": "1. 7/20", "value": "**0人**", "inline": false },
      { "name": "2. 7/21", "value": "**0人**", "inline": false },
    ],
  })
  json_inspect(schedule_components(options), content=[
    {
      "components": [
        {
          "custom_id": "nekosama:schedule",
          "placeholder": "参加できる日時をすべて選択… Select all dates you can attend...",
          "min_values": 0,
          "max_values": 2,
          "options": [
            { "label": "7/20", "value": "0" },
            { "label": "7/21", "value": "1" },
          ],
          "type": 3,
        },
      ],
      "type": 1,
    },
  ])
  assert_eq(
    schedule_embed("会議", options, None, "name", "url").description,
    schedule_embed("会議", options, Some(""), "name", "url").description,
  )
}

///|
test "schedule labels truncate at 100 Unicode code points without changing fields" {
  let label = "😀".repeat(101)
  guard schedule_components([label])
    is [ActionRow({ components: [StringSelect(menu)], .. })] else {
    fail("expected a select in an action row")
  }
  assert_eq(menu.options.unwrap()[0].label, "😀".repeat(100))
  assert_eq(
    schedule_embed("title", [label], None, "name", "url").fields.unwrap()[0].name,
    "1. \{label}",
  )
}

///|
test "poll answers reload from Python embed JSON across interactions" {
  let original : @model.Embed = @json.from_json({
    "title": "🗓️ Python poll",
    "description": "persistent",
    "color": 5763719,
    "footer": { "text": "作成: old bot" },
    "fields": [
      { "name": "1. Monday", "value": "**1人** <@!456>", "inline": false },
      { "name": "2. Tuesday", "value": "**1人** <@123>", "inline": false },
    ],
  })
  let user_id : @model.UserId = @model.Id::parse("123")
  let first = rebuild_schedule_embed(original, user_id, ["0"])
  assert_eq(first.fields.unwrap().map(field => field.value), [
    "**2人** <@456> <@123>", "**0人**",
  ])
  assert_eq(original.fields.unwrap()[0].value, "**1人** <@!456>")
  let reloaded : @model.Embed = @json.from_json(
    @json.parse(first.to_json().stringify()),
  )
  let second = rebuild_schedule_embed(reloaded, user_id, [])
  assert_eq(second.fields.unwrap().map(field => field.value), [
    "**1人** <@456>", "**0人**",
  ])
  assert_eq(second.title, original.title)
  assert_eq(second.description, original.description)
  assert_eq(second.footer.unwrap().text, "作成: old bot")
  assert_eq(second.fields.unwrap().map(field => field.name), [
    "1. Monday", "2. Tuesday",
  ])
  assert_eq(
    rebuild_schedule_embed(original, user_id, ["0", "0", "1", "999", "bad"]).fields
    .unwrap()
    .map(field => field.value),
    ["**2人** <@456> <@123>", "**1人** <@123>"],
  )
}
