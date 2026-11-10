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
  let backend = @testing.BackendStub::new().expect(
    request => {
      request.meth == Post &&
      request.url == "https://api.openai.com/v1/chat/completions"
    },
    @testing.Canned::bytes(
      200,
      body=@utf8.encode(completion_json("こんにちは").stringify()),
    ),
  )
  let client = @openai.Client("sk-test", backend~)
  defer backend.close()
  defer client.close()
  let text = client.chat_completion(
    "gpt-5.6-luna",
    [
      @openai.ChatMessage::system("Translate."),
      @openai.ChatMessage::user("Hello"),
    ],
    reasoning_effort=Off,
  )
  inspect(text, content="こんにちは")
  backend.verify()
  let sent = backend.sent()[0]
  assert_eq(sent.request.headers.get("authorization"), Some("Bearer sk-test"))
  assert_eq(sent.options.timeout_ms, Some(30000))
  guard sent.body is Some(body) &&
    @json.parse(@utf8.decode(body)) is Object(fields) else {
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
  let backend = @testing.BackendStub::new().expect(
    request => {
      request.meth == Post &&
      request.url == "https://api.openai.com/v1/chat/completions"
    },
    @testing.Canned::bytes(
      200,
      body=@utf8.encode(completion_json("").stringify()),
    ),
  )
  let client = @openai.Client("sk-test", backend~)
  defer backend.close()
  defer client.close()
  try
    client.chat_completion("gpt-5.6-luna", [@openai.ChatMessage::user("x")])
  catch {
    @openai.OpenAIError::InvalidResponse(_) => ()
    _ => fail("expected InvalidResponse")
  } noraise {
    _ => fail("expected an error")
  }
  backend.verify()
}

///|
test "reasoning effort wire names" {
  inspect(@openai.ReasoningEffort::Off.wire_name(), content="none")
  inspect(@openai.ReasoningEffort::XHigh.wire_name(), content="xhigh")
  inspect(@openai.ReasoningEffort::Max.wire_name(), content="max")
}

///|
async test "HTTP failures retain the status and diagnostic body" {
  let body = b"{\"error\":{\"message\":\"denied\",\"type\":\"permission_error\"}}"
  let backend = @testing.BackendStub::new().expect(
    _ => true,
    @testing.Canned::bytes(403, body~),
  )
  defer backend.close()
  let client = @openai.Client("sk-test", backend~)
  defer client.close()
  try
    client.chat_completion("test-model", [@openai.ChatMessage::user("x")])
  catch {
    @openai.OpenAIError::Api(
      Response(@client.ResponseFailure::UnexpectedStatus(head, body=actual))
    ) => {
      assert_eq(head.status, 403)
      assert_eq(actual, body)
    }
    _ => fail("expected an HTTP failure")
  } noraise {
    _ => fail("expected an error")
  }
  backend.verify()
}

///|
async test "invalid completion JSON retains the response head" {
  let backend = @testing.BackendStub::new().expect(
    _ => true,
    @testing.Canned::bytes(200, body=b"not JSON"),
  )
  defer backend.close()
  let client = @openai.Client("sk-test", backend~)
  defer client.close()
  try
    client.chat_completion("test-model", [@openai.ChatMessage::user("x")])
  catch {
    @openai.OpenAIError::Api(
      Response(@client.ResponseFailure::Deserialization(head, body~, ..))
    ) => {
      assert_eq(head.status, 200)
      assert_eq(body, b"not JSON")
    }
    _ => fail("expected a decoding failure")
  } noraise {
    _ => fail("expected an error")
  }
  backend.verify()
}

///|
async test "rate limits retry and custom base URLs are preserved" {
  let backend = @testing.BackendStub::new()
    .expect(
      request => request.url == "https://compatible.example/v1/chat/completions",
      @testing.Canned::bytes(
        429,
        headers=@http.Headers::of([("retry-after-ms", "1")]),
        body=b"{\"error\":{\"message\":\"slow down\"}}",
      ),
    )
    .expect(
      request => request.url == "https://compatible.example/v1/chat/completions",
      @testing.Canned::bytes(
        200,
        body=@utf8.encode(completion_json("ok").stringify()),
      ),
    )
  defer backend.close()
  let client = @openai.Client(
    "sk-test",
    backend~,
    base_url="https://compatible.example/v1",
  )
  defer client.close()
  assert_eq(
    client.chat_completion("test-model", [@openai.ChatMessage::user("x")]),
    "ok",
  )
  backend.verify()
  assert_eq(backend.sent().length(), 2)
}

///|
async test "transport failures propagate and supplied backends stay caller-owned" {
  let backend = @testing.BackendStub::new().expect(
    _ => true,
    Failure(
      @http.TransportError(kind=Invalid, phase=Pool, detail="invalid request"),
    ),
  )
  defer backend.close()
  let client = @openai.Client("sk-test", backend~)
  client.close()
  client.close()
  try
    client.chat_completion("test-model", [@openai.ChatMessage::user("x")])
  catch {
    @http.TransportError(kind=Invalid, phase=Pool, detail~) =>
      assert_eq(detail, "invalid request")
    _ => fail("expected the backend's transport error")
  } noraise {
    _ => fail("expected an error")
  }
  backend.verify()
}
