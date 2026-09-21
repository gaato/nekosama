///|
/// 2026-09-21 12:00 JST.
const TEST_NOW : Int64 = 1789959600

///|
fn when_text(text : String) -> String {
  match parse_when(text, now_unix_seconds=TEST_NOW) {
    Some(time) => time.iso8601()
    None => "None"
  }
}

///|
test "event times convert to Unix seconds in JST" {
  let noon : CivilTime = { year: 2026, month: 9, day: 21, hour: 12, minute: 0, }
  inspect(noon.unix_seconds(), content="1789959600")
  inspect(jst_year_at(TEST_NOW), content="2026")
  let epoch : CivilTime = { year: 1970, month: 1, day: 1, hour: 9, minute: 0, }
  inspect(epoch.unix_seconds(), content="0")
  inspect(jst_year_at(-32401), content="1969")
  inspect(jst_year_at(-32400), content="1970")
}

///|
test "the year rolls over at midnight JST, not UTC" {
  let new_year : CivilTime = {
    year: 2027,
    month: 1,
    day: 1,
    hour: 0,
    minute: 30,
  }
  inspect(jst_year_at(new_year.unix_seconds()), content="2027")
  inspect(jst_year_at(new_year.unix_seconds() - 3600), content="2026")
}

///|
test "event times are read as JST" {
  inspect(when_text("12/24 21:00"), content="2026-12-24T21:00:00+09:00")
  inspect(
    when_text("2027/2/22(火) 20:00"),
    content="2027-02-22T20:00:00+09:00",
  )
  inspect(when_text("2027-02-22 20:05"), content="2027-02-22T20:05:00+09:00")
  inspect(
    when_text("2027年2月22日 9:00"),
    content="2027-02-22T09:00:00+09:00",
  )
  inspect(
    when_text("12月24日（木） 21:00"),
    content="2026-12-24T21:00:00+09:00",
  )
  inspect(when_text("  12/24   21:00  "), content="2026-12-24T21:00:00+09:00")
}

///|
test "a date without a year means its next occurrence" {
  inspect(when_text("7/20 21:00"), content="2027-07-20T21:00:00+09:00")
  inspect(when_text("9/21 11:59"), content="2027-09-21T11:59:00+09:00")
  inspect(when_text("9/21 12:00"), content="2027-09-21T12:00:00+09:00")
  inspect(when_text("9/21 12:01"), content="2026-09-21T12:01:00+09:00")
  // An explicit year is taken as written, even in the past.
  inspect(when_text("2020/1/1 0:00"), content="2020-01-01T00:00:00+09:00")
}

///|
test "leap years and input year boundaries retain their meaning" {
  inspect(when_text("2000/2/29 0:00"), content="2000-02-29T00:00:00+09:00")
  inspect(when_text("1900/2/29 0:00"), content="None")
  inspect(when_text("2100/2/29 0:00"), content="None")
  inspect(when_text("0000/2/29 0:00"), content="0-02-29T00:00:00+09:00")
  inspect(when_text("9999/12/31 23:59"), content="9999-12-31T23:59:00+09:00")
}

///|
test "malformed or impossible times are rejected" {
  inspect(when_text(""), content="None")
  inspect(when_text("tomorrow"), content="None")
  inspect(when_text("7/20"), content="None")
  inspect(when_text("7/20 21"), content="None")
  inspect(when_text("7/20 21:00 JST"), content="None")
  inspect(when_text("2/30 10:00"), content="None")
  inspect(when_text("13/1 10:00"), content="None")
  inspect(when_text("7/20 24:00"), content="None")
  inspect(when_text("7/20 21:60"), content="None")
  inspect(when_text("2027年2/22 20:00"), content="2027-02-22T20:00:00+09:00")
  // Feb 29 without a year only exists when the chosen year is a leap year.
  inspect(when_text("2/29 10:00"), content="None")
}
