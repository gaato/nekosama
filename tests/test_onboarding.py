import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from nekosama.cogs.onboarding import RoleMenuSelect
from nekosama.config import ConfigStore


class FakeRole:
    def __init__(self, role_id: int):
        self.id = role_id
        self.mention = f"<@&{role_id}>"


class FakeMember:
    def __init__(self, roles):
        self.roles = roles
        self.added = []
        self.removed = []

    async def add_roles(self, *roles, **_kwargs):
        self.added.extend(roles)

    async def remove_roles(self, *roles, **_kwargs):
        self.removed.extend(roles)


class FakeResponse:
    async def send_message(self, message, **_kwargs):
        self.message = message


class ConfigStoreTest(unittest.TestCase):
    def test_set_persists_and_reloads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            store = ConfigStore(path)
            store.set(123, "member_role_id", 456)

            reloaded = ConfigStore(path)
            self.assertEqual(reloaded.get(123, "member_role_id"), 456)


class RoleMenuSelectTest(unittest.IsolatedAsyncioTestCase):
    async def test_confirmation_uses_selection_instead_of_stale_member_roles(self):
        old_role = FakeRole(1)
        new_role = FakeRole(2)
        member = FakeMember([old_role])
        response = FakeResponse()
        component = SimpleNamespace(
            options=[SimpleNamespace(value="1"), SimpleNamespace(value="2")]
        )
        interaction = SimpleNamespace(
            message=SimpleNamespace(
                components=[SimpleNamespace(children=[component])]
            ),
            guild=SimpleNamespace(get_role={1: old_role, 2: new_role}.get),
            user=member,
            response=response,
        )
        select = RoleMenuSelect()
        select._values = ["2"]

        await select.callback(interaction)

        self.assertEqual(member.added, [new_role])
        self.assertEqual(member.removed, [old_role])
        self.assertEqual(
            response.message,
            "更新しました！ Updated!\n現在: <@&2>",
        )


if __name__ == "__main__":
    unittest.main()
