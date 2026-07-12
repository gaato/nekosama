"""日程調整コマンド。回答は埋め込みに保存するので再起動しても消えない。"""

import re

import discord
from discord import app_commands
from discord.ext import commands

EMBED_COLOR = 0x57F287
MENTION = re.compile(r"<@!?(\d+)>")


def _rebuild_field(value: str, user_id: int, attending: bool) -> str:
    ids = [int(m) for m in MENTION.findall(value)]
    if attending and user_id not in ids:
        ids.append(user_id)
    if not attending and user_id in ids:
        ids.remove(user_id)
    mentions = " ".join(f"<@{i}>" for i in ids)
    return f"**{len(ids)}人** {mentions}".strip()


class ScheduleSelect(discord.ui.Select):
    def __init__(self):
        super().__init__(
            custom_id="nekosama:schedule",
            placeholder="参加できる日時をすべて選択… Select all dates you can attend...",
            min_values=0,
            max_values=1,
            options=[discord.SelectOption(label="placeholder", value="0")],
        )

    async def callback(self, interaction: discord.Interaction):
        embed = interaction.message.embeds[0]
        selected = {int(v) for v in self.values}
        for i, field in enumerate(embed.fields):
            embed.set_field_at(
                i,
                name=field.name,
                value=_rebuild_field(field.value, interaction.user.id, i in selected),
                inline=False,
            )
        await interaction.response.edit_message(embed=embed)
        await interaction.followup.send(
            "回答を記録しました！ Recorded! （選び直すと上書きされます）",
            ephemeral=True,
        )


class ScheduleView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)
        self.add_item(ScheduleSelect())


class Schedule(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

    async def cog_load(self):
        self.bot.add_view(ScheduleView())

    @app_commands.command(
        name="schedule",
        description="日程調整を作成します（候補はカンマ区切り）",
    )
    @app_commands.guild_only()
    @app_commands.describe(
        title="タイトル（例: 第3回全体会議）",
        dates="候補日時をカンマ区切りで（例: 7/20(月) 21:00, 7/21(火) 21:00）",
        note="補足（締切など）",
    )
    async def schedule(
        self,
        interaction: discord.Interaction,
        title: str,
        dates: str,
        note: str | None = None,
    ):
        options = [d.strip() for d in re.split(r"[,、\n]", dates) if d.strip()]
        if not options:
            await interaction.response.send_message(
                "候補日時が読み取れませんでした。", ephemeral=True
            )
            return
        if len(options) > 25:
            await interaction.response.send_message(
                "候補は25個までです。", ephemeral=True
            )
            return
        description = (
            "参加できる日時を**すべて**選んで送信してください。\n"
            "Select **all** the dates you can attend.\n"
            "回答を消すには何も選ばずに送信します。"
        )
        if note:
            description += f"\n\n📝 {note}"
        embed = discord.Embed(
            title=f"🗓️ {title}", description=description, color=EMBED_COLOR
        )
        embed.set_footer(
            text=f"作成: {interaction.user.display_name}",
            icon_url=interaction.user.display_avatar.url,
        )
        for i, label in enumerate(options):
            embed.add_field(name=f"{i + 1}. {label}", value="**0人**", inline=False)
        view = ScheduleView()
        select: ScheduleSelect = view.children[0]
        select.options = [
            discord.SelectOption(label=label[:100], value=str(i))
            for i, label in enumerate(options)
        ]
        select.max_values = len(options)
        await interaction.response.send_message(embed=embed, view=view)


async def setup(bot):
    await bot.add_cog(Schedule(bot))
