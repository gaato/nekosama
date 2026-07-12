"""自動翻訳・オンデマンド翻訳・ChatGPT 応答。"""

import logging
import re
from collections import OrderedDict

import discord
from discord import app_commands
from discord.ext import commands

from .. import llm

log = logging.getLogger(__name__)

# URL・メンション・絵文字だけのメッセージを弾くための除去パターン
NOISE = re.compile(r"<.*?>|:.*?:|https?://[\w!?/\+\-_~=;\.,*&@#$%\(\)\'\[\]]+")
EMBED_COLOR = 0xBF65E8


class LimitedSizeDict(OrderedDict):
    def __init__(self, size_limit=None, *args, **kwds):
        self.size_limit = size_limit
        super().__init__(*args, **kwds)
        self._check_size_limit()

    def __setitem__(self, key, value):
        super().__setitem__(key, value)
        self._check_size_limit()

    def _check_size_limit(self):
        if self.size_limit is not None:
            while len(self) > self.size_limit:
                self.popitem(last=False)


class EditModal(discord.ui.Modal, title="Edit"):
    def __init__(self, message: discord.Message):
        super().__init__()
        self.message = message
        self.text = discord.ui.TextInput(
            label="Edit translation",
            default=message.embeds[0].description,
            style=discord.TextStyle.long,
        )
        self.add_item(self.text)

    async def on_submit(self, interaction: discord.Interaction):
        embed = self.message.embeds[0]
        embed.description = self.text.value
        embed.set_footer(
            text=f"Edited by {interaction.user.display_name}",
            icon_url=interaction.user.display_avatar.url,
        )
        await self.message.edit(embed=embed)
        await interaction.response.send_message("Edited!", ephemeral=True)


class TranslateResponseView(discord.ui.View):
    """旧メッセージ互換の永続 View (custom_id: delete / edit)。"""

    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(
        label="Delete", style=discord.ButtonStyle.danger, custom_id="delete"
    )
    async def delete_button(
        self, interaction: discord.Interaction, button: discord.ui.Button
    ):
        await interaction.message.delete()

    @discord.ui.button(
        label="Edit", style=discord.ButtonStyle.secondary, custom_id="edit"
    )
    async def edit_button(
        self, interaction: discord.Interaction, button: discord.ui.Button
    ):
        await interaction.response.send_modal(EditModal(interaction.message))


def _topic_of(channel) -> str | None:
    if isinstance(channel, discord.TextChannel):
        return channel.topic
    if isinstance(channel, discord.Thread) and isinstance(
        channel.parent, (discord.TextChannel, discord.ForumChannel)
    ):
        return channel.parent.topic
    return None


class Messages(commands.Cog):
    def __init__(self, bot):
        self.bot = bot
        self.translated_messages = LimitedSizeDict(size_limit=100)
        self.translate_menu = app_commands.ContextMenu(
            name="Translate", callback=self.translate_message
        )
        self.delete_menu = app_commands.ContextMenu(
            name="Delete", callback=self.delete_message
        )
        self.edit_menu = app_commands.ContextMenu(
            name="Edit", callback=self.edit_message
        )

    async def cog_load(self):
        self.bot.add_view(TranslateResponseView())
        for menu in (self.translate_menu, self.delete_menu, self.edit_menu):
            self.bot.tree.add_command(menu)

    async def cog_unload(self):
        for menu in (self.translate_menu, self.delete_menu, self.edit_menu):
            self.bot.tree.remove_command(menu.name, type=menu.type)

    # ------------------------------------------------------ context menus

    async def translate_message(
        self, interaction: discord.Interaction, message: discord.Message
    ):
        text = message.content
        if not text.strip():
            await interaction.response.send_message(
                "翻訳するテキストがありません。 Nothing to translate.", ephemeral=True
            )
            return
        await interaction.response.defer(ephemeral=True)
        translated = await llm.translate(text)
        embed = discord.Embed(description=translated, color=EMBED_COLOR)
        await interaction.followup.send(embed=embed, ephemeral=True)

    async def delete_message(
        self, interaction: discord.Interaction, message: discord.Message
    ):
        if message.author.id != self.bot.user.id:
            await interaction.response.send_message(
                "You can only delete messages sent by me.", ephemeral=True
            )
            return
        await message.delete()
        await interaction.response.send_message("Deleted!", ephemeral=True)

    async def edit_message(
        self, interaction: discord.Interaction, message: discord.Message
    ):
        if message.author.id != self.bot.user.id or not message.embeds:
            await interaction.response.send_message(
                "You can only edit messages sent by me.", ephemeral=True
            )
            return
        await interaction.response.send_modal(EditModal(message))

    # ---------------------------------------------------------- listeners

    @commands.Cog.listener()
    async def on_message(self, message: discord.Message):
        if message.author.bot or message.guild is None:
            return
        # 自分が作ったスレッドではメンションされなくても LLM で返信
        if (
            isinstance(message.channel, discord.Thread)
            and message.channel.owner == self.bot.user
        ):
            await self._chat_in_thread(message)
            return
        # メンションされたら LLM で返信
        if self.bot.user in message.mentions:
            await self._chat_on_mention(message)
            return
        await self._auto_translate(message)

    async def _chat_in_thread(self, message: discord.Message):
        async with message.channel.typing():
            history = [
                m
                async for m in message.channel.history(limit=30, oldest_first=True)
            ]
            if (
                history
                and history[0].type == discord.MessageType.thread_starter_message
                and history[0].reference
                and history[0].reference.resolved
            ):
                history[0] = history[0].reference.resolved
            content = await llm.chat(
                [
                    {
                        "role": "system",
                        "content": "Since this is a Discord, you can use Markdown.",
                    }
                ]
                + [
                    {
                        "role": "assistant"
                        if m.author == self.bot.user
                        else "user",
                        "content": re.sub(r"<@!?[0-9]+>", "", m.content),
                    }
                    for m in history
                ]
            )
            for i in range(0, len(content), 2000):
                await message.reply(content[i : i + 2000])

    async def _chat_on_mention(self, message: discord.Message):
        async with message.channel.typing():
            content = await llm.chat(
                [
                    {
                        "role": "user",
                        "content": re.sub(
                            r"<@!?[0-9]+>", "", message.content
                        ).strip(),
                    }
                ]
            )
            if isinstance(message.channel, discord.Thread):
                await message.channel.send(f"{message.author.mention}\n{content}")
                return
            thread = await message.channel.create_thread(
                name=f"Chat with {message.author.display_name}",
                message=message,
            )
            for i in range(0, len(content), 2000):
                if i == 0:
                    await thread.send(
                        f"{message.author.mention}\n{content[: 2000]}"
                    )
                else:
                    await thread.send(content[i : i + 2000])

    async def _auto_translate(self, message: discord.Message):
        if not self.bot.config_store.get(
            message.guild.id, "auto_translate", True
        ):
            return
        topic = _topic_of(message.channel)
        if topic is not None and "notl" in topic:
            return
        if len(NOISE.sub("", message.content).strip()) == 0:
            return
        translated = await llm.translate(message.content)
        embed = discord.Embed(description=translated, color=EMBED_COLOR)
        m = await message.reply(embed=embed, mention_author=False)
        self.translated_messages[message.id] = m

    @commands.Cog.listener()
    async def on_message_edit(self, before: discord.Message, after: discord.Message):
        if before.author.bot or before.content == after.content:
            return
        if len(NOISE.sub("", after.content).strip()) == 0:
            return
        response = self.translated_messages.get(before.id)
        if response is None:
            return
        translated = await llm.translate(after.content)
        embed = discord.Embed(description=translated, color=EMBED_COLOR)
        self.translated_messages[before.id] = await response.edit(embed=embed)

    @commands.Cog.listener()
    async def on_message_delete(self, message: discord.Message):
        response = self.translated_messages.pop(message.id, None)
        if response is not None:
            await response.delete()


async def setup(bot):
    await bot.add_cog(Messages(bot))
