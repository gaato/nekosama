///|
test "encode a chat completion request" {
  json_inspect(
    @openai.chat_request_json("gpt-5.6-luna", [
      { role: "system", content: "Translate to English.", },
      { role: "user", content: "こんにちは", },
    ]),
    content={
      "model": "gpt-5.6-luna",
      "messages": [
        { "role": "system", "content": "Translate to English." },
        { "role": "user", "content": "こんにちは" },
      ],
    },
  )
}

///|
test "encode the reasoning effort only when it is given" {
  json_inspect(
    @openai.chat_request_json("gpt-5.6-luna", [], reasoning_effort=Off),
    content={
      "model": "gpt-5.6-luna",
      "messages": [],
      "reasoning_effort": "none",
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
  inspect(@openai.parse_chat_response(body), content="Hello!")
}

///|
test "reject a chat completion without text" {
  let body =
    #|{"choices": []}
  try ignore(@openai.parse_chat_response(body)) catch {
    @openai.OpenAIError::InvalidResponse(message) =>
      inspect(message, content="response has no text completion")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidResponse")
  }
}
