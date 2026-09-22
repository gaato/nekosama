///|
fn completion_json(content : String) -> Json {
  {
    "id": "chatcmpl-1",
    "object": "chat.completion",
    "created": 1,
    "model": "gpt-5.6-luna",
    "choices": [
      {
        "index": 0,
        "message": { "role": "assistant", "content": content },
        "finish_reason": "stop",
      },
    ],
  }
}

///|
async test "chat completion sends the model, messages and reasoning effort, and returns the text" {
  let transport = @mock.FakeTransport::new()
  transport.expect("POST", "https://api.openai.com/v1/chat/completions", {
    status: 200,
    headers: @http.Headers::new(),
    body: @utf8.encode(completion_json("こんにちは").stringify()),
  })
  let client = @openai.Client("sk-test", transport~)
  let text = client.chat_completion(
    "gpt-5.6-luna",
    [
      @openai.ChatMessage::system("Translate."),
      @openai.ChatMessage::user("Hello"),
    ],
    reasoning_effort=Off,
  )
  inspect(text, content="こんにちは")
  transport.assert_complete()
  let sent = transport.sent()[0]
  assert_eq(sent.headers.get("authorization"), Some("Bearer sk-test"))
  guard @json.parse(@utf8.decode(sent.body)) is Object(fields) else {
    fail("expected a JSON object body")
  }
  assert_eq(fields.get("model"), Some(Json::string("gpt-5.6-luna")))
  assert_eq(fields.get("reasoning_effort"), Some(Json::string("none")))
  guard fields.get("messages") is Some(Array([_, Object(user)])) else {
    fail("expected two messages")
  }
  assert_eq(user.get("content"), Some(Json::string("Hello")))
}

///|
async test "an empty completion is rejected" {
  let transport = @mock.FakeTransport::new()
  transport.expect("POST", "https://api.openai.com/v1/chat/completions", {
    status: 200,
    headers: @http.Headers::new(),
    body: @utf8.encode(completion_json("").stringify()),
  })
  let client = @openai.Client("sk-test", transport~)
  try
    client.chat_completion("gpt-5.6-luna", [@openai.ChatMessage::user("x")])
  catch {
    @openai.OpenAIError::InvalidResponse(_) => ()
    _ => fail("expected InvalidResponse")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "reasoning effort wire names" {
  inspect(@openai.ReasoningEffort::Off.wire_name(), content="none")
  inspect(@openai.ReasoningEffort::XHigh.wire_name(), content="xhigh")
  inspect(@openai.ReasoningEffort::Max.wire_name(), content="max")
}
