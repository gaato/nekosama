///|
/// The chat message type of `gaato/openai`, so the bot builds messages with
/// `ChatMessage::system` / `user` / `assistant`.
pub using @llm {type ChatMessage}

///|
#derive(Debug)
pub suberror OpenAIError {
  InvalidResponse(String)
  Api(@llm.OpenAIFailure)
}

///|
/// A thin wrapper over `gaato/openai` with the two things this bot needs:
/// one chat completion call that returns the text, and a reasoning-effort
/// switch. HTTP and decoding failures retain the SDK failure (including the
/// response status and body) in `OpenAIError::Api`; transport errors propagate.
pub struct Client {
  priv api : @llm.OpenAI
  priv owned_backend : &@http.Backend?
}

///|
/// `backend` defaults to an owned, pooled `AsyncBackend`, with the previous
/// 30-second exchange budget. Injected backends remain caller-owned.
pub fn Client::Client(
  api_key : String,
  base_url~ : String = "https://api.openai.com/v1",
  backend? : &@http.Backend,
) -> Client {
  let (backend, owned_backend) : (&@http.Backend, &@http.Backend?) = match
    backend {
    Some(backend) => (backend, None)
    None => {
      let backend : &@http.Backend = @backend.AsyncBackend::new()
      (backend, Some(backend))
    }
  }
  {
    api: @llm.OpenAI::new(
      api_key~,
      backend,
      @runtime.AsyncClock::new(),
      base_url~,
      timer=@runtime.ClockTimer::new(),
      timeout_ms=30000,
    ),
    owned_backend,
  }
}

///|
/// Release the connection pool on shutdown; supplied backends remain shared.
pub fn Client::close(self : Client) -> Unit {
  if self.owned_backend is Some(backend) {
    backend.close()
  }
}

///|
/// How much a reasoning model thinks before answering. Omitting it leaves the
/// model's default (`medium` for the GPT-5.6 family).
#derive(Debug, Eq)
pub(all) enum ReasoningEffort {
  Off
  Low
  Medium
  High
  XHigh
  Max
}

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
  let completion = match completion {
    Ok(completion) => completion
    Err(error) => raise Api(error)
  }
  guard !completion.text.is_empty() else {
    raise InvalidResponse("response has no text completion")
  }
  completion.text
}
