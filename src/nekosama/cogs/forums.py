"""フォーラム支援: 新規スレへの自動タグ付け、スレッド一覧インデックスの自動維持。"""

import asyncio
import logging

import discord
from discord import app_commands
from discord.ext import commands, tasks

log = logging.getLogger(__name__)

INDEX_THREAD_NAME = "📌 スレッド一覧 Thread Index"
AUTO_TAG_NAME = "実施前"
UNTAGGED = "（タグなし）"


def _group_by_tag(forum: discord.ForumChannel, threads, index_thread_id):
    """タグ定義順で {タグ名: [thread, ...]} を作る。スレは最初のタグで分類。"""
    groups = {tag.name: [] for tag in forum.available_tags if not tag.name.startswith("【")}
    groups[UNTAGGED] = []
    for t in threads:
        if t.id == index_thread_id:
            continue
        key = t.applied_tags[0].name if t.applied_tags else UNTAGGED
        groups.setdefault(key, []).append(t)
    return groups


async def build_index(forum: discord.ForumChannel, index_thread_id: int) -> str:
    threads = list(forum.threads)
    archived = []
    try:
        async for t in forum.archived_threads(limit=50):
            archived.append(t)
    except discord.HTTPException:
        pass
    lines = [
        f"# {forum.mention} のスレッド一覧",
        "*このメッセージは自動更新されます。 This message is updated automatically.*",
        "",
    ]
    groups = _group_by_tag(forum, threads, index_thread_id)
    for name, ts in groups.items():
        if not ts:
            continue
        lines.append(f"## {name}")
        lines.extend(f"- {t.mention}" for t in ts)
    live_ids = {t.id for t in threads}
    old = [t for t in archived if t.id not in live_ids and t.id != index_thread_id]
    if old:
        lines.append("## アーカイブ済み Archived")
        lines.extend(f"- {t.mention}" for t in old[:20])
        if len(old) > 20:
            lines.append(f"- …他{len(old) - 20}件")
    content = "\n".join(lines)
    return content[:1990] + "\n…" if len(content) > 2000 else content


class Forums(commands.Cog):
    def __init__(self, bot):
        self.bot = bot
        self._pending: dict[int, asyncio.Task] = {}

    async def cog_load(self):
        self.refresh_all.start()

    async def cog_unload(self):
        self.refresh_all.cancel()

    # ------------------------------------------------------- auto tagging

    @commands.Cog.listener()
    async def on_thread_create(self, thread: discord.Thread):
        parent = thread.parent
        if not isinstance(parent, discord.ForumChannel):
            return
        if not thread.applied_tags:
            tag = discord.utils.find(
                lambda t: AUTO_TAG_NAME in t.name, parent.available_tags
            )
            if tag is not None:
                try:
                    await thread.edit(applied_tags=[tag])
                except discord.HTTPException:
                    log.exception("failed to auto-tag thread %s", thread.id)
        self._schedule_refresh(parent)

    @commands.Cog.listener()
    async def on_thread_update(self, before: discord.Thread, after: discord.Thread):
        if isinstance(after.parent, discord.ForumChannel):
            self._schedule_refresh(after.parent)

    @commands.Cog.listener()
    async def on_raw_thread_delete(self, payload: discord.RawThreadDeleteEvent):
        channel = self.bot.get_channel(payload.parent_id)
        if isinstance(channel, discord.ForumChannel):
            self._schedule_refresh(channel)

    # -------------------------------------------------------------- index

    def _index_conf(self, forum: discord.ForumChannel) -> dict | None:
        indexes = self.bot.config_store.get(forum.guild.id, "forum_indexes", {})
        return indexes.get(str(forum.id))

    def _schedule_refresh(self, forum: discord.ForumChannel):
        if self._index_conf(forum) is None:
            return
        old = self._pending.pop(forum.id, None)
        if old is not None:
            old.cancel()

        async def _later():
            await asyncio.sleep(5)
            await self._refresh(forum)

        self._pending[forum.id] = asyncio.create_task(_later())

    async def _refresh(self, forum: discord.ForumChannel):
        conf = self._index_conf(forum)
        if conf is None:
            return
        thread = forum.get_thread(conf["thread_id"]) or self.bot.get_channel(
            conf["thread_id"]
        )
        if thread is None:
            try:
                thread = await self.bot.fetch_channel(conf["thread_id"])
            except discord.NotFound:
                return
        try:
            message = await thread.fetch_message(conf["message_id"])
            await message.edit(content=await build_index(forum, thread.id))
        except discord.HTTPException:
            log.exception("failed to refresh index for forum %s", forum.id)

    @tasks.loop(minutes=30)
    async def refresh_all(self):
        for guild_id, conf in list(self.bot.config_store.data.items()):
            for forum_id in conf.get("forum_indexes", {}):
                forum = self.bot.get_channel(int(forum_id))
                if isinstance(forum, discord.ForumChannel):
                    await self._refresh(forum)

    @refresh_all.before_loop
    async def before_refresh_all(self):
        await self.bot.wait_until_ready()

    @app_commands.command(
        name="forum-index",
        description="フォーラムに自動更新されるスレッド一覧を設置します",
    )
    @app_commands.guild_only()
    @app_commands.default_permissions(manage_threads=True)
    async def forum_index(
        self, interaction: discord.Interaction, forum: discord.ForumChannel
    ):
        await interaction.response.defer(ephemeral=True)
        conf = self._index_conf(forum)
        if conf is None:
            twm = await forum.create_thread(
                name=INDEX_THREAD_NAME, content="(準備中 preparing...)"
            )
            try:
                await twm.thread.edit(pinned=True)
            except discord.HTTPException:
                pass
            indexes = self.bot.config_store.get(
                interaction.guild.id, "forum_indexes", {}
            )
            indexes[str(forum.id)] = {
                "thread_id": twm.thread.id,
                "message_id": twm.message.id,
            }
            self.bot.config_store.set(
                interaction.guild.id, "forum_indexes", indexes
            )
        await self._refresh(forum)
        await interaction.followup.send(
            f"{forum.mention} にスレッド一覧を設置・更新しました。", ephemeral=True
        )


async def setup(bot):
    await bot.add_cog(Forums(bot))
