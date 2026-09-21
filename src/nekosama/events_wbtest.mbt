///|
fn blank_state() -> EventState {
  { role_id: None, channel_id: None, reminded: false, started: false, }
}

///|
test "the reminder fires only inside the last five minutes" {
  debug_inspect(due_notices(blank_state(), 301), content="(false, false)")
  debug_inspect(due_notices(blank_state(), 300), content="(true, false)")
  debug_inspect(due_notices(blank_state(), 1), content="(true, false)")
  debug_inspect(due_notices(blank_state(), 0), content="(false, true)")
  debug_inspect(due_notices(blank_state(), -3600), content="(false, true)")
}

///|
test "each notice is sent once" {
  let reminded = { ..blank_state(), reminded: true, }
  debug_inspect(due_notices(reminded, 60), content="(false, false)")
  let started = { ..reminded, started: true, }
  debug_inspect(due_notices(started, -60), content="(false, false)")
}

///|
test "event state keeps the Python bot's JSON shape" {
  let json = @json.parse(
    (
      #|{"role_id": 1525156408767676499, "channel_id": 1525156408767676500, "reminded": true}
    ),
  )
  let state = EventState::from_json(json)
  inspect(state.reminded, content="true")
  inspect(state.started, content="false")
  inspect(
    state.to_json_value().stringify(),
    content=(
      #|{"role_id":1525156408767676499,"channel_id":1525156408767676500,"reminded":true}
    ),
  )
  inspect(blank_state().to_json_value().stringify(), content="{}")
  inspect(
    EventState::from_json(Json::null()).to_json_value().stringify(),
    content="{}",
  )
}

///|
test "only announced events are forgotten once they disappear" {
  let states : Map[String, EventState] = {
    "1": { ..blank_state(), reminded: true, },
    "2": { ..blank_state(), started: true, },
    "3": blank_state(),
    "4": { ..blank_state(), started: true, },
  }
  debug_inspect(
    stale_event_ids(states, ["4"]),
    content=(
      #|["1", "2"]
    ),
  )
}
