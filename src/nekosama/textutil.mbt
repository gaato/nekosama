///|
let non_translatable = re"<.*?>|:.*?:|https?://[[:word:]!?/+\-_~=;.,*&@#$%()'\[\]]+"

///|
let user_mention = re"<@!?[0-9]+>"

///|
pub fn translation_probe(text : String) -> String {
  non_translatable.replace_by(text, _ => "").to_owned()
}

///|
fn remove_user_mentions(text : String) -> String {
  user_mention.replace_by(text, _ => "").to_owned()
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
