///|
fn legacy_delete_route() -> @discord.ComponentRoute[Unit] {
  @discord.component_route(id="delete", state=@discord.CustomIdCodec::unit())
}

///|
fn legacy_edit_route() -> @discord.ComponentRoute[Unit] {
  @discord.component_route(id="edit", state=@discord.CustomIdCodec::unit())
}

///|
fn register_legacy_buttons(app : @discord.App, runtime : Runtime) -> Unit {
  app.on_component(
    legacy_delete_route(),
    Immediate((ctx, _) => {
      Message(delete_translation(runtime, ctx.app().http(), ctx.message()))
    }),
  )
  app.on_component(
    legacy_edit_route(),
    Immediate((ctx, _) => {
      match edit_translation(runtime, ctx.message()) {
        Message(response) => Message(response)
        ShowModal(handle) => ShowModal(handle)
      }
    }),
  )
}
