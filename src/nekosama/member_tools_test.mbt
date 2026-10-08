///|
test "member tools validate alongside all existing commands" {
  let runtime = @nekosama.Runtime(
    "unused",
    @nekosama.ConfigStore("unused.json"),
  )
  let app = @discord.AppBuilder()
  @nekosama.register_commands(app, runtime)
  @nekosama.register_translation_commands(app, runtime)
  app.build() |> ignore
}

///|
test "member tools can be installed independently" {
  let runtime = @nekosama.Runtime(
    "unused",
    @nekosama.ConfigStore("unused.json"),
  )
  let app = @discord.AppBuilder()
  @nekosama.register_member_tools(app, runtime)
  app.build() |> ignore
}
