///|
const TRANSLATION_MODEL : String = "gpt-5.6-luna"

///|
const TRANSLATION_COLOR : Int = 0xBF65E8

///|
const EDIT_MODAL_ID : String = "edit-translation"

///|
const TRANSLATION_PROMPT : String = "This is a direct translation task. " +
  "Translate the following text from Japanese to English or from English to Japanese. " +
  "Do not add any additional comments or language indicators."

///|
pub struct Runtime {
  openai : @openai.Client
  cache : @cache.InMemoryCache
  translations : LimitedSizeMap[@model.MessageId, TranslationRecord]
  bot_user_id : Ref[@model.UserId?]
  config : ConfigStore
}

///|
pub fn Runtime::Runtime(
  openai_api_key : String,
  config : ConfigStore,
) -> Runtime {
  {
    openai: @openai.Client(openai_api_key),
    // messages=true keeps recent revisions so MessageUpdateEvent::is_edit
    // can compare against `before` instead of the edited_timestamp heuristic.
    cache: @cache.InMemoryCache(resources=@cache.CacheResources(messages=true)),
    translations: LimitedSizeMap(100),
    bot_user_id: Ref(None),
    config,
  }
}

///|
pub fn Runtime::attach_cache(self : Runtime, bot : @discord.Bot) -> Unit {
  bot.attach_cache(self.cache)
}

///|
pub fn Runtime::set_bot_user_id(
  self : Runtime,
  bot_user_id : @model.UserId,
) -> Unit {
  self.bot_user_id.val = Some(bot_user_id)
}

///|
fn Runtime::is_own_message(self : Runtime, message : @model.Message) -> Bool {
  match self.bot_user_id.val {
    Some(bot_user_id) => message.author.id == bot_user_id
    None => false
  }
}

///|
async fn Runtime::translate(self : Runtime, content : String) -> String {
  // Translation runs on every message, so skip the reasoning pass.
  self.openai.chat_completion(
    TRANSLATION_MODEL,
    [
      { role: "system", content: TRANSLATION_PROMPT, },
      { role: "user", content, },
    ],
    reasoning_effort=Off,
  )
}

///|
fn translation_embed(description : String) -> @model.Embed {
  @model.Embed(description~, color=TRANSLATION_COLOR)
}

///|
fn channel_disables_translation(channel : @model.Channel) -> Bool {
  channel.typ == GuildText &&
  @model.flatten(channel.topic).map_or(false, topic => topic.contains("notl"))
}

///|
async fn Runtime::handle_translation(
  self : Runtime,
  ctx : @discord.GatewayCtx,
  event : @model.MessageCreateEvent,
  channel : @model.Channel,
) -> Unit {
  if event.guild_id is Some(guild_id) &&
    !self.config.get_bool(guild_id, AUTO_TRANSLATE_KEY, default=true) {
    return
  }
  if channel_disables_translation(channel) {
    return
  }
  if is_blank(translation_probe(event.message.content)) {
    return
  }
  let translated = self.translate(event.message.content)
  let reply = ctx
    .message_ref(event)
    .reply(
      embeds=[translation_embed(translated)],
      allowed_mentions=@model.AllowedMentions::none(),
    )
  self.translations.set(event.message.id, {
    original_content: event.message.content,
    reply_message_id: reply.id,
  })
}

///|
async fn Runtime::handle_message_update(
  self : Runtime,
  ctx : @discord.GatewayCtx,
  event : @model.MessageUpdateEvent,
) -> Unit {
  if !event.is_edit() {
    return
  }
  if event.message.author.bot.unwrap_or(false) {
    return
  }
  guard self.translations.get(event.message.id) is Some(record) else { return }
  if !should_retranslate(record, event.message.content) {
    return
  }
  let translated = self.translate(event.message.content)
  let reply = ctx
    .app()
    .http()
    .message_ref(event.message.channel_id, record.reply_message_id)
    .edit(embeds=[translation_embed(translated)])
  self.translations.set(event.message.id, {
    original_content: event.message.content,
    reply_message_id: reply.id,
  })
}

///|
fn should_retranslate(record : TranslationRecord, content : String) -> Bool {
  record.original_content != content && !is_blank(translation_probe(content))
}

///|
async fn Runtime::handle_message_delete(
  self : Runtime,
  ctx : @discord.GatewayCtx,
  event : @model.MessageDeleteEvent,
) -> Unit {
  guard self.translations.remove(event.id) is Some(record) else { return }
  ctx
  .app()
  .http()
  .message_ref(event.channel_id, record.reply_message_id)
  .delete()
}

///|
/// Discord caps a modal text input (and its prefilled value) at 4000
/// characters, below the 4096 an embed description can hold.
const MODAL_TEXT_LIMIT : Int = 4000

///|
priv struct EditForm {
  translation : String
}

///|
fn edit_modal() -> @discord.Modal[EditForm] {
  @discord.modal(
    custom_id=EDIT_MODAL_ID,
    title="Edit",
    fields=@discord.ModalFields::map1(
      @discord.text_field(
        custom_id="translation",
        label="Edit translation",
        style=Paragraph,
        max_length=MODAL_TEXT_LIMIT,
      ),
      translation => { translation, },
    ),
  )
}

///|
fn delete_command(runtime : Runtime) -> @discord.Command[@model.Message] {
  @discord.message_command(
    name="Delete",
    handler=Immediate((ctx, message) => {
      Message(delete_translation(runtime, ctx.app().http(), message))
    }),
  )
}

///|
async fn delete_translation(
  runtime : Runtime,
  client : @discord.Client,
  message : @model.Message,
) -> @discord.InitialResponse {
  guard runtime.is_own_message(message) else {
    return @discord.InitialResponse::message(
      content="You can only delete messages sent by me.",
      ephemeral=true,
    )
  }
  client.ref_of_message(message).delete()
  @discord.InitialResponse::message(content="Deleted!", ephemeral=true)
}

///|
fn edit_command(runtime : Runtime) -> @discord.Command[@model.Message] {
  @discord.message_command(
    name="Edit",
    handler=Immediate((_, message) => edit_translation(runtime, message)),
  )
}

///|
fn edit_translation(
  runtime : Runtime,
  message : @model.Message,
) -> @discord.CommandReply {
  guard runtime.is_own_message(message) else {
    return @discord.CommandReply::message(
      content="You can only edit messages sent by me.",
      ephemeral=true,
    )
  }
  guard !message.embeds.is_empty() &&
    message.embeds[0].description is Some(description) else {
    return @discord.CommandReply::message(
      content="That message has no editable translation.",
      ephemeral=true,
    )
  }
  guard description.length() <= MODAL_TEXT_LIMIT else {
    return @discord.CommandReply::message(
      content="That translation is too long to edit.",
      ephemeral=true,
    )
  }
  let handle = edit_modal().show(state="\{message.channel_id}/\{message.id}", values={
    "translation": description,
  }) catch {
    _ =>
      return @discord.CommandReply::message(
        content="The editor could not be opened.",
        ephemeral=true,
      )
  }
  ShowModal(handle)
}

///|
fn translation_request_error(content : String) -> String? {
  if is_blank(content) {
    Some("翻訳するテキストがありません。 Nothing to translate.")
  } else {
    None
  }
}

///|
fn translate_command(runtime : Runtime) -> @discord.Command[@model.Message] {
  @discord.message_command(
    name="Translate",
    handler=Deferred(ephemeral=true, (ctx, message) => {
      if translation_request_error(message.content) is Some(content) {
        ctx.edit_original(content~) |> ignore
        return
      }
      let translated = runtime.translate(message.content)
      ctx.edit_original(embeds=[translation_embed(translated)]) |> ignore
    }),
  )
}

///|
fn parse_message_location(
  state : String,
) -> (@model.ChannelId, @model.MessageId)? {
  let parts = state.split("/").to_array()
  guard parts.length() == 2 else { return None }
  let channel_id : @model.ChannelId = @model.Id::parse(parts[0]) catch {
    _ => return None
  }
  let message_id : @model.MessageId = @model.Id::parse(parts[1]) catch {
    _ => return None
  }
  Some((channel_id, message_id))
}

///|
fn interaction_display_name(ctx : @discord.ModalImmediateCtx) -> String {
  member_tools_display_name(ctx.user(), ctx.interaction().guild_member)
}

///|
fn register_edit_modal(app : @discord.App, runtime : Runtime) -> Unit {
  app.on_modal(
    edit_modal(),
    Immediate((ctx, form) => {
      let location = match ctx.state() {
        Some(state) => parse_message_location(state)
        None => None
      }
      guard location is Some((channel_id, message_id)) else {
        return @discord.InitialResponse::message(
          content="The edited message is unavailable.",
          ephemeral=true,
        )
      }
      let message_ref = ctx.app().http().message_ref(channel_id, message_id)
      let message = message_ref.fetch()
      guard runtime.is_own_message(message) else {
        return @discord.InitialResponse::message(
          content="You can only edit messages sent by me.",
          ephemeral=true,
        )
      }
      guard !message.embeds.is_empty() else {
        return @discord.InitialResponse::message(
          content="That message has no editable translation.",
          ephemeral=true,
        )
      }
      let embed = {
        ..message.embeds[0],
        description: Some(form.translation),
        footer: Some(
          @model.EmbedFooter(
            "Edited by \{interaction_display_name(ctx)}",
            icon_url=member_tools_avatar_url(
              ctx.user(),
              ctx.interaction().guild_id,
              ctx.interaction().guild_member,
            ),
          ),
        ),
      }
      message_ref.edit(embeds=[embed]) |> ignore
      @discord.InitialResponse::message(content="Edited!", ephemeral=true)
    }),
  )
}

///|
pub fn register_translation_commands(
  app : @discord.App,
  runtime : Runtime,
) -> Unit {
  app.command(delete_command(runtime))
  app.command(edit_command(runtime))
  register_edit_modal(app, runtime)
}
