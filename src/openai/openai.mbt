///|
pub(all) struct ChatMessage {
  role : String
  content : String
} derive(Debug, Eq)

///|
pub suberror OpenAIError {
  Http(status~ : Int, body~ : String)
  InvalidResponse(String)
} derive(Debug)

///|
pub struct Client {
  api_key : String
  base_url : String
}

///|
pub fn Client::Client(
  api_key : String,
  base_url? : String = "https://api.openai.com",
) -> Client {
  { api_key, base_url, }
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
fn ReasoningEffort::wire_name(self : ReasoningEffort) -> String {
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
pub fn chat_request_json(
  model : String,
  messages : Array[ChatMessage],
  reasoning_effort? : ReasoningEffort,
) -> Json {
  let request : Map[String, Json] = {
    "model": model,
    "messages": messages.map(message => {
      "role": message.role,
      "content": message.content,
    }),
  }
  if reasoning_effort is Some(effort) {
    request["reasoning_effort"] = Json::string(effort.wire_name())
  }
  Json::object(request)
}

///|
priv struct CompletionMessage {
  content : String?
} derive(FromJson)

///|
priv struct CompletionChoice {
  message : CompletionMessage
} derive(FromJson)

///|
priv struct CompletionResponse {
  choices : Array[CompletionChoice]
} derive(FromJson)

///|
pub fn parse_chat_response(body : String) -> String raise {
  let response : CompletionResponse = @json.from_json(@json.parse(body))
  guard !response.choices.is_empty() &&
    response.choices[0].message.content is Some(content) else {
    raise InvalidResponse("response has no text completion")
  }
  content
}

///|
pub async fn Client::chat_completion(
  self : Client,
  model : String,
  messages : Array[ChatMessage],
  reasoning_effort? : ReasoningEffort,
) -> String {
  let headers : Map[@ahttp.CaseInsensitiveString, String] = {
    "Authorization": "Bearer \{self.api_key}",
    "Content-Type": "application/json",
  }
  let client = @ahttp.Client(self.base_url, headers~)
  defer client.close()
  let request_body = chat_request_json(model, messages, reasoning_effort?).stringify()
  let response = client.post("/v1/chat/completions", request_body)
  let response_body = client.read_all().text()
  guard response.code is (200..<300) else {
    raise Http(status=response.code, body=response_body)
  }
  parse_chat_response(response_body)
}
