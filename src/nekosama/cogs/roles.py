"""ロール関連コマンド（旧 /role list, /role members, /pick の移植）。"""

import random

import discord
from discord import app_commands
from discord.ext import commands


@app_commands.guild_only()
class Roles(commands.GroupCog, group_name="role"):
    def __init__(self, bot):
        self.bot = bot

    @app_commands.command(name="list", description="ロール一覧を表示します")
    async def role_list(self, interaction: discord.Interaction):
        embed = discord.Embed(
            title="ロール一覧",
            description="\n".join(
                role.mention for role in interaction.guild.roles
            ),
        )
        await interaction.response.send_message(embed=embed)

    @app_commands.command(
        name="members",
        description="ロールのメンバー一覧を表示します（複数指定で AND 検索）",
    )
    async def role_members(
        self,
        interaction: discord.Interaction,
        role1: discord.Role,
        role2: discord.Role | None = None,
        role3: discord.Role | None = None,
    ):
        roles = [r for r in (role1, role2, role3) if r is not None]
        members = set.intersection(*(set(r.members) for r in roles))
        content = "\n".join(m.display_name for m in sorted(members, key=lambda m: m.display_name))
        await interaction.response.send_message(
            f"{[r.name for r in roles]}\n```\n{content or '(none)'}\n```"
        )


class Pick(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

    @app_commands.command(
        name="pick", description="ロールからランダムにメンバーを選びます"
    )
    @app_commands.guild_only()
    async def pick(self, interaction: discord.Interaction, role: discord.Role):
        if not role.members:
            await interaction.response.send_message(
                "No members in the role.", ephemeral=True
            )
            return
        member = random.choice(role.members)
        embed = discord.Embed(
            color=0xB190FC, title=f"Picked a random member from {role.name}"
        )
        embed.add_field(name=member.display_name, value=member.mention)
        await interaction.response.send_message(embed=embed)


async def setup(bot):
    await bot.add_cog(Roles(bot))
    await bot.add_cog(Pick(bot))
