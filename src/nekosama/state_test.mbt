///|
test "@nekosama.LimitedSizeMap evicts the oldest entry" {
  let values : @nekosama.LimitedSizeMap[String, Int] = @nekosama.LimitedSizeMap(
    2,
  )
  values.set("first", 1)
  values.set("second", 2)
  values.set("third", 3)
  debug_inspect(values.get("first"), content="None")
  debug_inspect(values.get("second"), content="Some(2)")
  debug_inspect(values.get("third"), content="Some(3)")
  inspect(values.length(), content="2")
}

///|
test "@nekosama.LimitedSizeMap preserves insertion order when overwritten" {
  let values : @nekosama.LimitedSizeMap[String, Int] = @nekosama.LimitedSizeMap(
    2,
  )
  values.set("first", 1)
  values.set("second", 2)
  values.set("first", 10)
  values.set("third", 3)
  debug_inspect(values.get("first"), content="None")
  debug_inspect(values.get("second"), content="Some(2)")
  debug_inspect(values.remove("second"), content="Some(2)")
  inspect(values.length(), content="1")
}
