"""同意ボタン・班選択メニュー・ギルドごと設定。"""

import logging
import os

import discord
from discord import app_commands
from discord.ext import commands

log = logging.getLogger(__name__)


class AgreeButtonView(discord.ui.View):
    def __init__(self, bot):
        super().__init__(timeout=None)
        self.bot = bot

    @discord.ui.button(
        label="Agree", style=discord.ButtonStyle.primary, custom_id="agree"
    )
    async def agree_button(
        self, interaction: discord.Interaction, button: discord.ui.Button
    ):
        role_id = self.bot.config_store.get(
            interaction.guild.id, "member_role_id"
        ) or os.environ.get("MEMBER_ROLE_ID")
        role = interaction.guild.get_role(int(role_id)) if role_id else None
        if role is None:
            await interaction.response.send_message(
                "ロールが設定されていません。管理者は `/config member-role` で設定してください。",
                ephemeral=True,
            )
            return
        await interaction.user.add_roles(role, reason="Agreed the rules")
        await interaction.response.send_message("Verified!", ephemeral=True)


class RoleMenuSelect(discord.ui.Select):
    """メッセージ側の options がロール ID を持つ、永続ロール選択メニュー。"""

    def __init__(self):
        super().__init__(
            custom_id="nekosama:rolemenu",
            placeholder="ロールを選択… Pick your roles...",
            min_values=0,
            max_values=1,
            options=[discord.SelectOption(label="placeholder", value="0")],
        )

    async def callback(self, interaction: discord.Interaction):
        # 実際の選択肢はメッセージ側から読む（永続 View の options はダミーのため）
        component = interaction.message.components[0].children[0]
        option_ids = [int(o.value) for o in component.options]
        option_roles = [
            role
            for role_id in option_ids
            if (role := interaction.guild.get_role(role_id)) is not None
        ]
        selected = {int(v) for v in self.values}
        member = interaction.user
        to_add = [r for r in option_roles if r.id in selected and r not in member.roles]
        to_remove = [
            r for r in option_roles if r.id not in selected and r in member.roles
        ]
        try:
            if to_add:
                await member.add_roles(*to_add, reason="Role menu")
            if to_remove:
                await member.remove_roles(*to_remove, reason="Role menu")
        except discord.Forbidden:
            await interaction.response.send_message(
                "権限が足りずロールを変更できませんでした。管理者に連絡してください。",
                ephemeral=True,
            )
            return
        # add_roles/remove_roles 後も member.roles はこの Interaction 開始時の
        # スナップショットのままなので、確定した選択値から表示を作る。
        current = [r.mention for r in option_roles if r.id in selected]
        await interaction.response.send_message(
            "更新しました！ Updated!\n現在: " + (" ".join(current) or "なし / none"),
            ephemeral=True,
        )


class RoleMenuView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)
        self.add_item(RoleMenuSelect())


@app_commands.guild_only()
@app_commands.default_permissions(administrator=True)
class Config(commands.GroupCog, group_name="config"):
    """ギルドごとの設定コマンド。"""

    def __init__(self, bot):
        self.bot = bot

    @app_commands.command(
        name="member-role", description="同意ボタンで付与するロールを設定します"
    )
    async def member_role(
        self, interaction: discord.Interaction, role: discord.Role
    ):
        self.bot.config_store.set(interaction.guild.id, "member_role_id", role.id)
        await interaction.response.send_message(
            f"同意ボタンのロールを {role.mention} に設定しました。", ephemeral=True
        )

    @app_commands.command(
        name="absence-channel", description="不在連絡の投稿先チャンネルを設定します"
    )
    async def absence_channel(
        self, interaction: discord.Interaction, channel: discord.TextChannel
    ):
        self.bot.config_store.set(
            interaction.guild.id, "absence_channel_id", channel.id
        )
        await interaction.response.send_message(
            f"不在連絡の投稿先を {channel.mention} に設定しました。", ephemeral=True
        )

    @app_commands.command(
        name="auto-translate", description="自動翻訳の有効/無効を切り替えます"
    )
    async def auto_translate(
        self, interaction: discord.Interaction, enabled: bool
    ):
        self.bot.config_store.set(interaction.guild.id, "auto_translate", enabled)
        await interaction.response.send_message(
            f"自動翻訳を {'有効' if enabled else '無効'} にしました。"
            "（チャンネルごとに無効にするにはトピックに `notl` を含めてください）",
            ephemeral=True,
        )

    @app_commands.command(name="show", description="現在の設定を表示します")
    async def show(self, interaction: discord.Interaction):
        conf = self.bot.config_store.guild(interaction.guild.id)
        await interaction.response.send_message(
            f"```json\n{conf}\n```" if conf else "設定はまだありません。",
            ephemeral=True,
        )


class Onboarding(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

    async def cog_load(self):
        self.bot.add_view(AgreeButtonView(self.bot))
        self.bot.add_view(RoleMenuView())

    @app_commands.command(
        name="send-agree-button",
        description="ルール同意ボタンをこのチャンネルに送信します",
    )
    @app_commands.guild_only()
    @app_commands.default_permissions(administrator=True)
    async def send_agree_button(self, interaction: discord.Interaction):
        await interaction.channel.send(
            content="Please press the button below if you agree.\n"
            "同意する場合は以下のボタンを押してください。",
            view=AgreeButtonView(self.bot),
        )
        await interaction.response.send_message("Sent!", ephemeral=True)

    @app_commands.command(
        name="send-role-menu",
        description="ロール選択メニューをこのチャンネルに送信します",
    )
    @app_commands.guild_only()
    @app_commands.default_permissions(administrator=True)
    @app_commands.describe(title="メニューの上に表示する文章")
    async def send_role_menu(
        self,
        interaction: discord.Interaction,
        role1: discord.Role,
        role2: discord.Role | None = None,
        role3: discord.Role | None = None,
        role4: discord.Role | None = None,
        role5: discord.Role | None = None,
        role6: discord.Role | None = None,
        role7: discord.Role | None = None,
        role8: discord.Role | None = None,
        title: str = "班を選択してください / Select your team",
    ):
        roles = [
            r
            for r in (role1, role2, role3, role4, role5, role6, role7, role8)
            if r is not None
        ]
        top = interaction.guild.me.top_role
        too_high = [r.name for r in roles if r >= top]
        if too_high:
            await interaction.response.send_message(
                f"Botのロールより上のため付与できません: {', '.join(too_high)}",
                ephemeral=True,
            )
            return
        view = RoleMenuView()
        select: RoleMenuSelect = view.children[0]
        select.options = [
            discord.SelectOption(label=r.name, value=str(r.id)) for r in roles
        ]
        select.max_values = len(roles)
        await interaction.channel.send(content=f"**{title}**", view=view)
        await interaction.response.send_message("Sent!", ephemeral=True)


async def setup(bot):
    await bot.add_cog(Onboarding(bot))
    await bot.add_cog(Config(bot))
