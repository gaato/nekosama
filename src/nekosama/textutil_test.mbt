///|
test "translation probe removes Python-compatible ignored tokens" {
  inspect(
    translation_probe(
      "hello <@123> <:party:456> :wave: https://example.com/a?q=1&x=2 world",
    ),
    content="hello     world",
  )
  inspect(
    translation_probe("<@123> :wave: https://example.com/path"),
    content="  ",
  )
}

///|
test "translation probe preserves unmatched delimiters and URL terminators" {
  inspect(
    translation_probe("before <open :open after"),
    content="before <open :open after",
  )
  inspect(
    translation_probe("see https://example.com:8080/path now"),
    content="see :8080/path now",
  )
}

///|
test "blank detection follows Unicode whitespace" {
  inspect(is_blank(" \t\n　"), content="true")
  inspect(is_blank("　word"), content="false")
}

///|
test "split_codepoints does not split a surrogate pair" {
  let text = "a".repeat(1999) + "🤣" + "終"
  let chunks = split_codepoints(text)
  inspect(chunks.length(), content="2")
  inspect(chunks[0].iter().count(), content="2000")
  inspect(chunks[0].has_suffix("🤣"), content="true")
  inspect(chunks[1], content="終")
}

///|
test "split_codepoints handles empty input and a custom limit" {
  debug_inspect(split_codepoints(""), content="[]")
  debug_inspect(
    split_codepoints("abcdef", limit=2),
    content="[\"ab\", \"cd\", \"ef\"]",
  )
}
