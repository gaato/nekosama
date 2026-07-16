///|
let gateway_ctx : Ref[@discord.GatewayCtx?] = Ref(None)

///|
fn ping_command() -> @discord.Command[Unit] {
  @discord.slash(
    name="ping",
    description="Check whether the bot is online",
    args=@discord.Args::unit(),
    handler=Immediate((_, _) => {
      let content = match gateway_ctx.val {
        Some(ctx) =>
          match ctx.shard_raw().latency_ms() {
            Some(latency) => "Pong! \{latency} ms"
            None => "Pong! Latency is not available yet."
          }
        None => "Pong! Latency is not available yet."
      }
      @discord.CommandReply::message(content~)
    }),
  )
}

///|
fn command_sync() -> @discord.CommandSync {
  match @env.get_env_var("GUILD_ID") {
    Some(raw) => {
      let guild_id : @model.GuildId? = Some(@model.Id::parse(raw)) catch {
        _ => None
      }
      match guild_id {
        Some(value) => Guild(value)
        None => {
          println("[bot] invalid GUILD_ID, syncing globally")
          Global
        }
      }
    }
    None => Global
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
  try {
    let token = @env.get_env_var("DISCORD_TOKEN").unwrap_or("")
    let app = @discord.App(sync=command_sync())
    app.command(ping_command())
    let bot = @discord.Bot(app, token~, intents=bot_intents())
    bot.on(@discord.Events::ready(), (ctx, ready) => {
      gateway_ctx.val = Some(ctx)
      println("[bot] ready as \{ready.user.username}")
    })
    bot.run()
  } catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      ()
    error => raise error
  }
  println("[bot] shutting down")
}
