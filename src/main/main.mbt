///|
fn ping_command() -> @discord.Command[Unit] {
  @discord.slash(
    name="ping",
    description="Check whether the bot is online",
    args=@discord.Args::unit(),
    handler=Immediate((ctx, _) => {
      let content = match ctx.app().latency_ms() {
        Some(latency) => "Pong! \{latency} ms"
        None => "Pong! Latency is not available yet."
      }
      @discord.CommandReply::message(content~)
    }),
  )
}

///|
fn command_scope() -> @discord.CommandScope {
  match @env.get_env_var("GUILD_ID") {
    Some(raw) => {
      let guild_id : @model.GuildId? = Some(@model.Id::parse(raw)) catch {
        _ => None
      }
      match guild_id {
        Some(value) => @discord.CommandScope::Guild(value)
        None => {
          println("[bot] invalid GUILD_ID, syncing globally")
          @discord.CommandScope::Global
        }
      }
    }
    None => @discord.CommandScope::Global
  }
}

///|
fn bot_intents() -> @model.Intents {
  @model.Intents::guilds() |
  @model.Intents::guild_messages() |
  @model.Intents::direct_messages() |
  @model.Intents::message_content() |
  @model.Intents::guild_members()
}

///|
async fn main {
  @signal.set_global_cancellation_signals([SIGINT, SIGTERM])
  @async.handle_cancellation(() => {
    let token = @env.get_env_var("DISCORD_TOKEN").unwrap_or("")
    let config = @nekosama.ConfigStore::load(@nekosama.config_path())
    let runtime = @nekosama.Runtime(
      @env.get_env_var("OPENAI_API_KEY").unwrap_or(""),
      config,
    )
    let app = @discord.App()
    app.command(ping_command())
    @nekosama.register_commands(app, runtime)
    @nekosama.register_translation_commands(app, runtime)
    let bot = @discord.Bot(
      app,
      token~,
      intents=bot_intents(),
      sync=command_scope(),
    )
    runtime.attach_cache(bot)
    @nekosama.register_translation_events(bot, runtime)
    @nekosama.register_events(app, bot, runtime)
    @nekosama.register_forums(app, bot, runtime)
    bot.on(@discord.Events::ready(), (_, ready) => {
      runtime.set_bot_user_id(ready.user.id)
      println("[bot] ready as \{ready.user.username}")
    })
    bot.run()
  })
  |> ignore
  println("[bot] shutting down")
}
