///|
fn member_tools_display_name(
  user : @model.User,
  guild_member : @model.GuildMember?,
) -> String {
  if guild_member is Some(guild_member) &&
    @model.flatten(guild_member.nick) is Some(nick) {
    return nick
  }
  @model.flatten(user.global_name).unwrap_or(user.username)
}

///|
fn member_tools_avatar_url(
  user : @model.User,
  guild_id : @model.GuildId?,
  guild_member : @model.GuildMember?,
) -> String {
  if guild_id is Some(guild_id) &&
    guild_member is Some(guild_member) &&
    @model.flatten(guild_member.avatar) is Some(hash) {
    // discord.mbt has no guild-member avatar URL helper.
    let extension = if hash.is_animated() { "gif" } else { "png" }
    return "https://cdn.discordapp.com/guilds/\{guild_id}/users/\{user.id}/avatars/\{hash.to_string()}.\{extension}?size=1024"
  }
  if @model.flatten(Some(user.avatar)) is Some(hash) {
    return try! @util.user_avatar_url(
      user.id,
      hash,
      format=if hash.is_animated() { Gif } else { Png },
      size=1024,
    )
  }
  if user.discriminator != "0" {
    let discriminator = @string.parse_int(user.discriminator) catch { _ => 0 }
    return @util.legacy_default_user_avatar_url(discriminator)
  }
  @util.default_user_avatar_url(user.id)
}

///|
/// Register member commands and the persistent components posted by either bot.
pub fn register_member_tools(app : @discord.App, runtime : Runtime) -> Unit {
  app.command(absence_command(runtime))
  app.command(schedule_command(runtime))
  app.command(send_role_menu_command(runtime))
  app.command(translate_command(runtime))
  register_schedule_handler(app)
  register_role_menu_handler(app, runtime)
  register_legacy_buttons(app, runtime)
}
