///|
const DEFAULT_CHAT_MODEL : String = "gpt-5.6-terra"

///|
/// `NEKOSAMA_CHAT_MODEL` replaces the model without a rebuild, so a model
/// shutdown on OpenAI's side is a configuration change.
fn chat_model() -> String {
  model_from_env("NEKOSAMA_CHAT_MODEL", DEFAULT_CHAT_MODEL)
}

///|
fn model_from_env(name : String, default : String) -> String {
  match @env.get_env_var(name) {
    Some(model) if !is_blank(model) => model
    _ => default
  }
}

///|
const THREAD_CHAT_PROMPT : String = "Since this is a Discord, you can use Markdown."

///|
fn is_bot_owned_thread_type(channel_type : @model.ChannelType?) -> Bool {
  channel_type is Some(PublicThread | PrivateThread)
}

///|
fn is_thread_type(channel_type : @model.ChannelType?) -> Bool {
  channel_type is Some(PublicThread | PrivateThread | AnnouncementThread)
}

///|
fn message_mentions(message : @model.Message, user_id : @model.UserId) -> Bool {
  message.mentions.any(user => user.id == user_id)
}

///|
fn chat_role(author_id : @model.UserId, bot_user_id : @model.UserId) -> String {
  if author_id == bot_user_id {
    "assistant"
  } else {
    "user"
  }
}

///|
fn resolved_thread_starter(message : @model.Message) -> @model.Message {
  if message.typ != ThreadStarterMessage {
    return message
  }
  match message.referenced_message {
    Some(reference) => reference.to_option().unwrap_or(message)
    None => message
  }
}

///|
fn thread_chat_messages(
  history : Array[@model.Message],
  bot_user_id : @model.UserId,
) -> Array[@openai.ChatMessage] {
  history.map(message => {
    let message = resolved_thread_starter(message)
    {
      role: chat_role(message.author.id, bot_user_id),
      content: remove_user_mentions(message.content),
    }
  })
}

///|
fn remove_bot_mention(content : String, bot_user_id : @model.UserId) -> String {
  content
  .replace_all(old="<@!\{bot_user_id}>", new="")
  .replace_all(old="<@\{bot_user_id}>", new="")
  .trim()
  .to_owned()
}

///|
fn author_display_name(event : @model.MessageCreateEvent) -> String {
  match event.guild_member {
    Some(guild_member) =>
      @model.flatten(guild_member.nick).unwrap_or(
        @model.flatten(event.message.author.global_name).unwrap_or(
          event.message.author.username,
        ),
      )
    None =>
      @model.flatten(event.message.author.global_name).unwrap_or(
        event.message.author.username,
      )
  }
}

///|
fn author_chunks(content : String, author_id : @model.UserId) -> Array[String] {
  let prefix = "<@\{author_id}>\n"
  let first_limit = 2000 - prefix.length()
  let first_pass = @util.split_content(content, limit=first_limit)
  if first_pass.is_empty() {
    return []
  }
  let chunks = [prefix + first_pass[0]]
  if first_pass.length() > 1 {
    let remaining = first_pass[1:].join("")
    chunks.push_iter(@util.split_content(remaining).iter())
  }
  chunks
}

///|
async fn Runtime::handle_owned_thread(
  self : Runtime,
  ctx : @discord.GatewayCtx,
  event : @model.MessageCreateEvent,
  bot_user_id : @model.UserId,
) -> Unit {
  let channel = ctx.channel_ref(event.message.channel_id)
  let response = channel.with_typing(() => {
    let history = channel.messages(page_size=30).collect(max=30).rev()
    let messages : Array[@openai.ChatMessage] = [
      { role: "system", content: THREAD_CHAT_PROMPT, },
    ]
    messages.push_iter(thread_chat_messages(history, bot_user_id).iter())
    self.openai.chat_completion(chat_model(), messages)
  })
  for chunk in @util.split_content(response) {
    ctx.message_ref(event).reply(content=chunk) |> ignore
  }
}

///|
async fn Runtime::handle_mention(
  self : Runtime,
  ctx : @discord.GatewayCtx,
  event : @model.MessageCreateEvent,
  bot_user_id : @model.UserId,
  channel_type : @model.ChannelType,
) -> Unit {
  let response = ctx
    .channel_ref(event.message.channel_id)
    .with_typing(() => {
      self.openai.chat_completion(chat_model(), [
        {
          role: "user",
          content: remove_bot_mention(event.message.content, bot_user_id),
        },
      ])
    })
  let destination = if is_thread_type(Some(channel_type)) {
    ctx.channel_ref(event.message.channel_id)
  } else {
    let thread = ctx
      .message_ref(event)
      .start_thread("Chat with \{author_display_name(event)}")
    ctx.channel_ref(thread.id)
  }
  for chunk in author_chunks(response, event.message.author.id) {
    destination.send(content=chunk) |> ignore
  }
}

///|
async fn Runtime::handle_message_create(
  self : Runtime,
  ctx : @discord.GatewayCtx,
  event : @model.MessageCreateEvent,
) -> Unit {
  if event.message.author.bot.unwrap_or(false) {
    return
  }
  guard self.bot_user_id.val is Some(bot_user_id) else { return }
  let channel = ctx.resolve_channel(event.message.channel_id)
  let channel_type = event.channel_type.unwrap_or(channel.typ)
  if is_bot_owned_thread_type(Some(channel_type)) {
    if channel.owner_id == Some(bot_user_id) {
      self.handle_owned_thread(ctx, event, bot_user_id)
      return
    }
  }
  if message_mentions(event.message, bot_user_id) {
    self.handle_mention(ctx, event, bot_user_id, channel_type)
    return
  }
  self.handle_translation(ctx, event, channel)
}

///|
pub fn register_translation_events(
  bot : @discord.Bot,
  runtime : Runtime,
) -> Unit {
  bot.on(@discord.Events::message_create(), (ctx, event) => {
    runtime.handle_message_create(ctx, event)
  })
  bot.on(@discord.Events::message_update(), (ctx, event) => {
    runtime.handle_message_update(ctx, event)
  })
  bot.on(@discord.Events::message_delete(), (ctx, event) => {
    runtime.handle_message_delete(ctx, event)
  })
}
