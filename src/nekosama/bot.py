import logging

import discord
from discord.ext import commands

from .config import ConfigStore

log = logging.getLogger(__name__)

EXTENSIONS = [
    "nekosama.cogs.messages",
    "nekosama.cogs.onboarding",
    "nekosama.cogs.roles",
    "nekosama.cogs.schedule",
    "nekosama.cogs.forums",
    "nekosama.cogs.absence",
    "nekosama.cogs.events",
]


class Nekosama(commands.Bot):
    def __init__(self, config_store: ConfigStore | None = None):
        intents = discord.Intents.default()
        intents.members = True
        intents.message_content = True
        super().__init__(
            command_prefix=commands.when_mentioned,
            intents=intents,
            help_command=None,
        )
        self.config_store = config_store or ConfigStore()

    async def setup_hook(self) -> None:
        for ext in EXTENSIONS:
            await self.load_extension(ext)
        synced = await self.tree.sync()
        log.info("synced %d application commands", len(synced))

    async def on_ready(self) -> None:
        log.info("logged in as %s (ID: %s)", self.user, self.user.id)

    async def on_command_error(self, ctx, error) -> None:
        if isinstance(error, commands.CommandNotFound):
            return
        raise error
