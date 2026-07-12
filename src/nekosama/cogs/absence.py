"""不在連絡コマンド。定型フォーマットで掲示板に投稿する。"""

import discord
from discord import app_commands
from discord.ext import commands

EMBED_COLOR = 0xF1C40F


class Absence(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

    @app_commands.command(
        name="absence", description="不在連絡を投稿します（期間と理由は任意入力）"
    )
    @app_commands.guild_only()
    @app_commands.describe(
        period="不在期間（例: 7/20〜7/25、今週いっぱい）",
        reason="理由（任意・書ける範囲で）",
    )
    async def absence(
        self,
        interaction: discord.Interaction,
        period: str,
        reason: str | None = None,
    ):
        channel_id = self.bot.config_store.get(
            interaction.guild.id, "absence_channel_id"
        )
        channel = (
            interaction.guild.get_channel(channel_id) if channel_id else None
        ) or interaction.channel
        embed = discord.Embed(title="🙇 不在連絡 / Absence", color=EMBED_COLOR)
        embed.add_field(name="期間 Period", value=period, inline=False)
        if reason:
            embed.add_field(name="理由 Reason", value=reason, inline=False)
        embed.set_author(
            name=interaction.user.display_name,
            icon_url=interaction.user.display_avatar.url,
        )
        await channel.send(content=interaction.user.mention, embed=embed)
        await interaction.response.send_message(
            f"{channel.mention} に投稿しました。", ephemeral=True
        )


async def setup(bot):
    await bot.add_cog(Absence(bot))
