///|
/// Japan has no daylight saving time, so JST is a fixed offset.
const JST_OFFSET_SECONDS : Int64 = 32400

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
/// Days from 1970-01-01 to the given proleptic Gregorian date.
fn days_from_civil(year : Int, month : Int, day : Int) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let year_of_era = y - era * 400
  let shifted_month = if month > 2 { month - 3 } else { month + 9 }
  let day_of_year = (153 * shifted_month + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era.to_int64() * 146097L + day_of_era.to_int64() - 719468L
}

///|
/// The inverse of `days_from_civil`: (year, month, day).
fn civil_from_days(days : Int64) -> (Int, Int, Int) {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let day_of_era = (z - era * 146097L).to_int()
  let year_of_era = (
      day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096
    ) /
    365
  let day_of_year = day_of_era -
    (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  let shifted_month = (5 * day_of_year + 2) / 153
  let day = day_of_year - (153 * shifted_month + 2) / 5 + 1
  let month = if shifted_month < 10 {
    shifted_month + 3
  } else {
    shifted_month - 9
  }
  let year = year_of_era + era.to_int() * 400
  (if month <= 2 { year + 1 } else { year }, month, day)
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    2 =>
      if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 {
        29
      } else {
        28
      }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn CivilTime::is_valid(self : CivilTime) -> Bool {
  self.month >= 1 &&
  self.month <= 12 &&
  self.day >= 1 &&
  self.day <= days_in_month(self.year, self.month) &&
  self.hour >= 0 &&
  self.hour <= 23 &&
  self.minute >= 0 &&
  self.minute <= 59
}

///|
fn CivilTime::unix_seconds(self : CivilTime) -> Int64 {
  days_from_civil(self.year, self.month, self.day) * 86400L +
  self.hour.to_int64() * 3600L +
  self.minute.to_int64() * 60L -
  JST_OFFSET_SECONDS
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
  let shifted = unix_seconds + JST_OFFSET_SECONDS
  let days = if shifted >= 0L {
    shifted / 86400L
  } else {
    (shifted - 86399L) / 86400L
  }
  civil_from_days(days).0
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
