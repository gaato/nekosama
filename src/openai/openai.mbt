///|
/// The chat message type of `gaato/openai`, so the bot builds messages with
/// `ChatMessage::system` / `user` / `assistant`.
pub using @llm {type ChatMessage}

///|
pub suberror OpenAIError {
  InvalidResponse(String)
} derive(Debug)

///|
/// A thin wrapper over `gaato/openai` with the two things this bot needs:
/// one chat completion call that returns the text, and a reasoning-effort
/// switch. Transport failures, HTTP errors and rate limits surface as
/// `@runtime.SdkError`, which carries the status code.
pub struct Client {
  priv api : @llm.OpenAI
}

///|
/// `transport` defaults to a pooled `AsyncTransport`; tests pass a
/// `FakeTransport`.
pub fn Client::Client(
  api_key : String,
  base_url? : String = "https://api.openai.com/v1",
  transport? : &@http.Transport,
) -> Client {
  let transport : &@http.Transport = match transport {
    Some(transport) => transport
    None => @transport.AsyncTransport::new()
  }
  {
    api: @llm.OpenAI::new(
      api_key~,
      transport,
      @transport.AsyncClock::new(),
      base_url~,
    ),
  }
}

///|
/// How much a reasoning model thinks before answering. Omitting it leaves the
/// model's default (`medium` for the GPT-5.6 family).
pub(all) enum ReasoningEffort {
  Off
  Low
  Medium
  High
  XHigh
  Max
} derive(Debug, Eq)

///|
pub fn ReasoningEffort::wire_name(self : ReasoningEffort) -> String {
  match self {
    Off => "none"
    Low => "low"
    Medium => "medium"
    High => "high"
    XHigh => "xhigh"
    Max => "max"
  }
}

///|
/// A message with a role decided at runtime ("user" or "assistant" from the
/// thread history); anything else is treated as a user message.
pub fn message(role : String, content : String) -> ChatMessage {
  match role {
    "system" => ChatMessage::system(content)
    "assistant" => ChatMessage::assistant(content)
    _ => ChatMessage::user(content)
  }
}

///|
pub async fn Client::chat_completion(
  self : Client,
  model : String,
  messages : Array[ChatMessage],
  reasoning_effort? : ReasoningEffort,
) -> String {
  let completion = self.api.chat_completion(
    @llm.ChatRequest::new(
      model~,
      messages~,
      reasoning_effort?=reasoning_effort.map(ReasoningEffort::wire_name),
    ),
  )
  guard !completion.text.is_empty() else {
    raise InvalidResponse("response has no text completion")
  }
  completion.text
}
