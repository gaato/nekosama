"""Discordイベント連携: /event で作成、5分前リマインドと開始通知（自動開始つき）。"""

import datetime
import logging
import re
from zoneinfo import ZoneInfo

import discord
from discord import app_commands
from discord.ext import commands, tasks

log = logging.getLogger(__name__)

JST = ZoneInfo("Asia/Tokyo")
WHEN = re.compile(
    r"^(?:(\d{4})[/\-年])?(\d{1,2})[/\-月](\d{1,2})日?\s*(?:\([^)]*\))?\s+(\d{1,2}):(\d{2})$"
)


def parse_when(text: str) -> datetime.datetime | None:
    """「7/20 21:00」「2027/2/22(火) 20:00」を JST の datetime に。年省略時は次の未来。"""
    m = WHEN.match(text.strip())
    if m is None:
        return None
    year, month, day, hour, minute = m.groups()
    now = datetime.datetime.now(JST)
    try:
        dt = datetime.datetime(
            int(year) if year else now.year,
            int(month),
            int(day),
            int(hour),
            int(minute),
            tzinfo=JST,
        )
    except ValueError:
        return None
    if year is None and dt <= now:
        dt = dt.replace(year=now.year + 1)
    return dt


class Events(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

    async def cog_load(self):
        self.tick.start()

    async def cog_unload(self):
        self.tick.cancel()

    # ------------------------------------------------------------- helpers

    def _states(self, guild_id: int) -> dict:
        return self.bot.config_store.get(guild_id, "event_notify", {})

    def _notify_target(self, event: discord.ScheduledEvent):
        """通知先チャンネルとメンションを決める。既定はVCと同カテゴリの先頭テキストch＋@everyone。"""
        conf = self._states(event.guild.id).get(str(event.id), {})
        channel = None
        if conf.get("channel_id"):
            channel = event.guild.get_channel(conf["channel_id"])
        if channel is None and event.channel is not None and event.channel.category:
            channel = next(
                (
                    c
                    for c in event.channel.category.text_channels
                    if c.permissions_for(event.guild.me).send_messages
                ),
                None,
            )
        if channel is None:
            channel = event.guild.system_channel
        if conf.get("role_id"):
            role = event.guild.get_role(conf["role_id"])
            mention = role.mention if role else "@everyone"
        else:
            mention = "@everyone"
        return channel, mention

    async def _notify(self, event: discord.ScheduledEvent, *, before: bool):
        channel, mention = self._notify_target(event)
        if channel is None:
            return
        place = event.channel.mention if event.channel else (event.location or "")
        if before:
            text = f"__**{event.name}**__ が {place} で **5分後** に始まります！\n{event.url}"
        else:
            text = f"{mention}\n__**{event.name}**__ が始まりました！ {place} へどうぞ！\n{event.url}"
        await channel.send(
            text,
            allowed_mentions=discord.AllowedMentions(everyone=True, roles=True),
        )

    # ---------------------------------------------------------------- loop

    @tasks.loop(seconds=60)
    async def tick(self):
        now = discord.utils.utcnow()
        for guild in self.bot.guilds:
            states = self._states(guild.id)
            changed = False
            live_ids = set()
            for event in guild.scheduled_events:
                if event.status not in (
                    discord.EventStatus.scheduled,
                    discord.EventStatus.active,
                ):
                    continue
                live_ids.add(str(event.id))
                state = states.setdefault(str(event.id), {})
                delta = event.start_time - now
                try:
                    if not state.get("reminded") and (
                        datetime.timedelta(0)
                        < delta
                        <= datetime.timedelta(minutes=5)
                    ):
                        await self._notify(event, before=True)
                        state["reminded"] = True
                        changed = True
                    if not state.get("started") and delta <= datetime.timedelta(0):
                        if event.status is discord.EventStatus.scheduled:
                            try:
                                await event.start()
                            except discord.HTTPException:
                                log.exception("failed to start event %s", event.id)
                        await self._notify(event, before=False)
                        state["started"] = True
                        changed = True
                except discord.HTTPException:
                    log.exception("failed to notify for event %s", event.id)
            # 通知済みで既に存在しないイベントの状態を掃除
            stale = [
                k
                for k, v in states.items()
                if k not in live_ids and (v.get("reminded") or v.get("started"))
            ]
            for k in stale:
                states.pop(k)
                changed = True
            if changed:
                self.bot.config_store.set(guild.id, "event_notify", states)

    @tick.before_loop
    async def before_tick(self):
        await self.bot.wait_until_ready()

    @commands.Cog.listener()
    async def on_scheduled_event_delete(self, event: discord.ScheduledEvent):
        states = self._states(event.guild.id)
        if states.pop(str(event.id), None) is not None:
            self.bot.config_store.set(event.guild.id, "event_notify", states)

    # ------------------------------------------------------------- command

    @app_commands.command(
        name="event",
        description="Discordイベントを作成します（5分前リマインドと開始通知つき）",
    )
    @app_commands.guild_only()
    @app_commands.describe(
        name="イベント名（例: 第3回全体会議）",
        vc="開催するボイスチャンネル",
        start="開始日時・日本時間（例: 7/20 21:00）",
        mention="開始通知でメンションするロール（省略時は @everyone）",
        channel="通知先チャンネル（省略時はVCと同じカテゴリの先頭テキストch）",
        description="イベントの説明（任意）",
    )
    async def event(
        self,
        interaction: discord.Interaction,
        name: str,
        vc: discord.VoiceChannel,
        start: str,
        mention: discord.Role | None = None,
        channel: discord.TextChannel | None = None,
        description: str | None = None,
    ):
        when = parse_when(start)
        if when is None:
            await interaction.response.send_message(
                "開始日時が読み取れませんでした。`7/20 21:00` のような形式で入力してください。",
                ephemeral=True,
            )
            return
        if when <= datetime.datetime.now(JST):
            await interaction.response.send_message(
                "過去の日時は指定できません。", ephemeral=True
            )
            return
        await interaction.response.defer()
        kwargs = {}
        if description:
            kwargs["description"] = description
        event = await interaction.guild.create_scheduled_event(
            name=name,
            start_time=when,
            channel=vc,
            entity_type=discord.EntityType.voice,
            privacy_level=discord.PrivacyLevel.guild_only,
            reason=f"/event by {interaction.user}",
            **kwargs,
        )
        states = self._states(interaction.guild.id)
        conf = {}
        if mention is not None:
            conf["role_id"] = mention.id
        if channel is not None:
            conf["channel_id"] = channel.id
        states[str(event.id)] = conf
        self.bot.config_store.set(interaction.guild.id, "event_notify", states)
        when_str = discord.utils.format_dt(when, style="F")
        await interaction.followup.send(
            f"イベントを作成しました！ {when_str} 開始、5分前と開始時にお知らせします。\n"
            "「興味あり」を押すとDiscordからも通知が届きます。\n"
            f"{event.url}"
        )


async def setup(bot):
    await bot.add_cog(Events(bot))
