///|
async test "settings written by the Python bot survive a round trip" {
  let dir = "_build/test-data/config-round-trip"
  let path = "\{dir}/config.json"
  if !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  @fs.write_file(
    path,
    (
      #|{
      #|  "1525156408767676466": {
      #|    "member_role_id": 1525156408767676499,
      #|    "auto_translate": false
      #|  }
      #|}
    ),
  )
  let store = @nekosama.ConfigStore::load(path)
  let guild_id : @model.GuildId = @model.Id::parse("1525156408767676466")
  let role_id : @model.RoleId? = store.get_id(guild_id, "member_role_id")
  guard role_id is Some(role_id) else { fail("member_role_id was not read") }
  inspect(role_id, content="1525156408767676499")
  inspect(
    store.get_bool(guild_id, "auto_translate", default=true),
    content="false",
  )
  inspect(store.get_bool(guild_id, "missing", default=true), content="true")
  let channel_id : @model.ChannelId = @model.Id::parse("1525156408767676500")
  store.set(guild_id, "absence_channel_id", @nekosama.id_to_json(channel_id))
  let reloaded = @nekosama.ConfigStore::load(path)
  // Compare as text: a Json literal here would round the ids to a Double.
  inspect(
    Json::object(reloaded.guild(guild_id)).stringify(),
    content=(
      #|{"member_role_id":1525156408767676499,"auto_translate":false,"absence_channel_id":1525156408767676500}
    ),
  )
  reloaded.remove(guild_id, "member_role_id")
  reloaded.remove(guild_id, "auto_translate")
  reloaded.remove(guild_id, "absence_channel_id")
  inspect(@fs.read_file(path).text(), content="{}")
}

///|
test "guilds are found by the setting they hold" {
  let store = @nekosama.ConfigStore("unused.json")
  inspect(store.guilds_with("forum_indexes").length(), content="0")
}
