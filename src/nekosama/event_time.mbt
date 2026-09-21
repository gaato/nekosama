///|
/// Japan has no daylight saving time, so JST is a fixed offset.
let jst_zone : @time.Zone = try! @time.fixed_zone("JST", 32400)

///|
/// A wall-clock time in JST, as typed into `/event`.
priv struct CivilTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
}

///|
fn CivilTime::zoned(self : CivilTime) -> @time.ZonedDateTime raise {
  @time.date_time(
    self.year,
    self.month,
    self.day,
    hour=self.hour,
    minute=self.minute,
    zone=jst_zone,
  )
}

///|
fn CivilTime::is_valid(self : CivilTime) -> Bool {
  // x/time accepts 24:00; /event has always required hours in 0..23.
  guard self.hour >= 0 && self.hour < 24 else { return false }
  try self.zoned() catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn CivilTime::unix_seconds(self : CivilTime) -> Int64 {
  // Called only after validation by parse_when.
  (try! self.zoned()).to_unix_second()
}

///|
fn two_digits(value : Int) -> String {
  if value < 10 {
    "0\{value}"
  } else {
    "\{value}"
  }
}

///|
/// ISO 8601 with the JST offset, as the scheduled event API accepts it.
fn CivilTime::iso8601(self : CivilTime) -> String {
  "\{self.year}-\{two_digits(self.month)}-\{two_digits(self.day)}" +
  "T\{two_digits(self.hour)}:\{two_digits(self.minute)}:00+09:00"
}

///|
fn jst_year_at(unix_seconds : Int64) -> Int {
  (try! @time.unix(unix_seconds, zone=jst_zone)).year()
}

///|
/// Reads up to `max` leading ASCII digits. `None` when there are none, or when
/// more than `max` digits follow.
fn take_number(text : StringView, max~ : Int) -> (Int, StringView)? {
  let mut value = 0
  let mut count = 0
  let mut rest = text
  while rest is [ch, .. tail] && ch >= '0' && ch <= '9' {
    value = value * 10 + (ch.to_int() - '0'.to_int())
    count += 1
    rest = tail
  }
  if count == 0 || count > max {
    None
  } else {
    Some((value, rest))
  }
}

///|
fn skip_spaces(text : StringView) -> (Int, StringView) {
  let mut count = 0
  let mut rest = text
  while rest is [' ' | '\t' | '　', .. tail] {
    count += 1
    rest = tail
  }
  (count, rest)
}

///|
/// Parses "7/20 21:00" or "2027/2/22(火) 20:00" as JST. Separators may be
/// `/`, `-`, or 年月日. Without a year, the next future occurrence is used.
fn parse_when(text : String, now_unix_seconds~ : Int64) -> CivilTime? {
  let text = text.trim(chars=" \t　")
  guard take_number(text, max=4) is Some((first, rest)) else { return None }
  guard rest is ['/' | '-' | '年' | '月' as first_separator, .. rest] else {
    return None
  }
  guard take_number(rest, max=2) is Some((second, rest)) else { return None }
  // Three date numbers mean the first one was a year.
  let (year, month, day, rest) = match rest {
    ['/' | '-' | '月', .. after] if first_separator != '月' =>
      match take_number(after, max=2) {
        Some((third, after)) => (Some(first), second, third, after)
        None => return None
      }
    _ => {
      guard first_separator != '年' && first <= 99 else { return None }
      (None, first, second, rest)
    }
  }
  let rest = match rest {
    ['日', .. after] => after
    _ => rest
  }
  let (_, rest) = skip_spaces(rest)
  let rest = match rest {
    ['(' | '（', .. after] => {
      let mut inner = after
      while inner is [ch, .. tail] && ch != ')' && ch != '）' {
        inner = tail
      }
      guard inner is [_, .. after_close] else { return None }
      after_close
    }
    _ => rest
  }
  // The time must be separated from the date by whitespace, unless a
  // weekday in parentheses already separates them.
  let (_, rest) = skip_spaces(rest)
  guard take_number(rest, max=2) is Some((hour, rest)) else { return None }
  guard rest is [':' | '：', .. rest] else { return None }
  guard take_number(rest, max=2) is Some((minute, rest)) else { return None }
  guard rest.is_empty() else { return None }
  let candidate = {
    year: year.unwrap_or(jst_year_at(now_unix_seconds)),
    month,
    day,
    hour,
    minute,
  }
  guard candidate.is_valid() else { return None }
  if year is None && candidate.unix_seconds() <= now_unix_seconds {
    let next_year = { ..candidate, year: candidate.year + 1, }
    guard next_year.is_valid() else { return None }
    return Some(next_year)
  }
  Some(candidate)
}
