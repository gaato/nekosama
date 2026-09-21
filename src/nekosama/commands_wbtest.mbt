///|
test "role intersection requires every selected role" {
  let role1 : @model.RoleId = @model.Id::parse("1")
  let role2 : @model.RoleId = @model.Id::parse("2")
  let role3 : @model.RoleId = @model.Id::parse("3")
  assert_true(contains_all_roles([role1, role2, role3], [role1, role3]))
  assert_false(contains_all_roles([role1, role2], [role1, role3]))
}

///|
test "selected roles preserve optional argument order" {
  let role1 : @model.RoleId = @model.Id::parse("1")
  let role2 : @model.RoleId = @model.Id::parse("2")
  let role3 : @model.RoleId = @model.Id::parse("3")
  assert_eq(
    selected_roles({ role1, role2: Some(role2), role3: Some(role3), }),
    [role1, role2, role3],
  )
  assert_eq(selected_roles({ role1, role2: None, role3: Some(role3), }), [
    role1, role3,
  ])
}

///|
test "line summaries stop at complete lines" {
  inspect(
    summarize_lines(["alpha", "beta", "gamma"], 10),
    content="alpha\nbeta",
  )
  inspect(summarize_lines([], 10), content="")
}

///|
test "agree command requires administrator permission by default" {
  guard send_agree_button_command().spec().to_json()
    is { "default_member_permissions": String(permissions), .. } else {
    fail("default_member_permissions was not serialized")
  }
  inspect(permissions, content="8")
}
