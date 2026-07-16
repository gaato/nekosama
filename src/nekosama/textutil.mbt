///|
let non_translatable = re"<.*?>|:.*?:|https?://[[:word:]!?/+\-_~=;.,*&@#$%()'\[\]]+"

///|
pub fn translation_probe(text : String) -> String {
  non_translatable.replace_by(text, _ => "").to_owned()
}

///|
pub fn is_blank(text : String) -> Bool {
  for char in text {
    if !char.is_whitespace() {
      return false
    }
  }
  true
}

///|
pub fn split_codepoints(text : String, limit? : Int = 2000) -> Array[String] {
  guard limit > 0 else { panic() }
  if text.is_empty() {
    return []
  }
  let chunks : Array[String] = []
  let mut builder = StringBuilder()
  let mut length = 0
  for char in text {
    if length == limit {
      chunks.push(builder.to_string())
      builder = StringBuilder()
      length = 0
    }
    builder.write_char(char)
    length += 1
  }
  if length > 0 {
    chunks.push(builder.to_string())
  }
  chunks
}
