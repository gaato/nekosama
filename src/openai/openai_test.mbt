///|
test "encode a chat completion request" {
  json_inspect(
    chat_request_json("gpt-4.1-nano", [
      { role: "system", content: "Translate to English." },
      { role: "user", content: "こんにちは" },
    ]),
    content={
      "model": "gpt-4.1-nano",
      "messages": [
        { "role": "system", "content": "Translate to English." },
        { "role": "user", "content": "こんにちは" },
      ],
    },
  )
}

///|
test "parse the first chat completion" {
  let body =
    #|{
    #|  "id": "chatcmpl-test",
    #|  "choices": [{
    #|    "index": 0,
    #|    "message": {"role": "assistant", "content": "Hello!"},
    #|    "finish_reason": "stop"
    #|  }]
    #|}
  inspect(parse_chat_response(body), content="Hello!")
}

///|
test "reject a chat completion without text" {
  let body =
    #|{"choices": []}
  try ignore(parse_chat_response(body)) catch {
    OpenAIError::InvalidResponse(message) =>
      inspect(message, content="response has no text completion")
    error => fail("unexpected error: \{to_repr(error)}")
  } noraise {
    _ => fail("expected InvalidResponse")
  }
}
