import os
import random
import re
from collections import OrderedDict
from typing import Optional

from openai import AsyncOpenAI

import discord
from discord.ext import commands

intents = discord.Intents.default()
intents.members = True
intents.message_content = True
bot = commands.Bot(intents=intents)

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"])


guild: Optional[discord.Guild] = None


admin_only = discord.Permissions()
admin_only.administrator = True


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


jp_to_en_cache = LimitedSizeDict(size_limit=100)
en_to_jp_cache = LimitedSizeDict(size_limit=100)
translated_messages = LimitedSizeDict(size_limit=100)


async def translate(text: str):
    response = await client.chat.completions.create(
        model="gpt-4.1-nano",
        messages=[
            {
                "role": "system",
                "content": "This is a direct translation task. "
                "Translate the following text from Japanese to English or from English to Japanese. "
                "Do not add any additional comments or language indicators.",
            },
            {
                "role": "user",
                "content": text,
            },
        ],
    )
    return response.choices[0].message.content


class TranslateResponseView(discord.ui.View):
    def __init__(self, **kwargs):
        super().__init__(timeout=None, **kwargs)

    @discord.ui.button(
        label="Delete", style=discord.ButtonStyle.danger, custom_id="delete"
    )
    async def delete_button(
        self, button: discord.ui.Button, interaction: discord.Interaction
    ):
        await interaction.message.delete()

    @discord.ui.button(
        label="Edit", style=discord.ButtonStyle.secondary, custom_id="edit"
    )
    async def edit_button(
        self, button: discord.ui.Button, interaction: discord.Interaction
    ):
        await interaction.response.send_modal(EditModal(interaction.message))


class EditModal(discord.ui.Modal):
    def __init__(self, message: discord.Message, title="Edit", **kwargs):
        super().__init__(title=title, **kwargs)
        self.message = message
        self.add_item(
            discord.ui.InputText(
                label="Edit translation",
                value=message.embeds[0].description,
                style=discord.InputTextStyle.long,
            )
        )

    async def callback(self, interaction: discord.Interaction):
        embed = self.message.embeds[0]
        embed.description = self.children[0].value
        embed.set_footer(
            text=f"Edited by {interaction.user.display_name}",
            icon_url=interaction.user.display_avatar.url,
        )
        await self.message.edit(embed=embed)
        await interaction.response.send_message("Edited!", ephemeral=True)


class AgreeButtonView(discord.ui.View):
    def __init__(self, **kwargs):
        super().__init__(timeout=None, **kwargs)

    @discord.ui.button(
        label="Agree",
        style=discord.ButtonStyle.primary,
        custom_id="agree",
    )
    async def agree_button(
        self, button: discord.ui.Button, interaction: discord.Interaction
    ):
        role = interaction.guild.get_role(int(os.environ["MEMBER_ROLE_ID"]))
        await interaction.user.add_roles(role)
        await interaction.response.send_message("Verified!", ephemeral=True)


@bot.event
async def on_ready():
    print(f"Logged in as {bot.user} (ID: {bot.user.id})")
    print("------")
    bot.add_view(TranslateResponseView())
    bot.add_view(AgreeButtonView())
    global guild


@bot.event
async def on_message(message: discord.Message):
    if message.author.bot:
        return
    # 自分が作ったスレッドではメンションされなくても ChatGPT で返信
    if (
        isinstance(message.channel, discord.Thread)
        and message.channel.owner == bot.user
    ):
        with message.channel.typing():
            history = await message.channel.history(
                limit=30, oldest_first=True
            ).flatten()
            if history[0].type == discord.MessageType.thread_starter_message:
                history[0] = history[0].reference.resolved
            response = await client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {
                        "role": "system",
                        "content": "Since this is a Discord, you can use Markdown.",
                    }
                ]
                + [
                    {
                        "role": "assistant" if m.author == bot.user else "user",
                        "content": re.sub(r"<@!?[0-9]+>", "", m.content),
                    }
                    for m in history
                ],
            )
            content = response.choices[0].message.content
            # 2000 文字ごとに分割して送信
            for i in range(0, len(content), 2000):
                await message.reply(content[i : i + 2000])
        return
    # メンションされたら ChatGPT で返信
    if bot.user in message.mentions:
        with message.channel.typing():
            response = await client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {
                        "role": "user",
                        "content": message.content.replace(
                            f"<@!{bot.user.id}>", ""
                        ).strip(),
                    },
                ],
            )
            if isinstance(message.channel, discord.Thread):
                await message.channel.send(
                    f"{message.author.mention}\n{response.choices[0].message.content}",
                )
            else:
                thread = await message.channel.create_thread(
                    name=f"Chat with {message.author.nick or message.author.display_name}",
                    message=message,
                )
                content = response.choices[0].message.content
                # 2000 文字ごとに分割して送信
                for i in range(0, len(content), 2000):
                    if i == 0:
                        await thread.send(
                            f"{message.author.mention}\n{content[i : i + 2000]}"
                        )
                    else:
                        await thread.send(content[i : i + 2000])
        return

    # チャンネルトピックに notl が含まれていたら無視
    if (
        isinstance(message.channel, discord.TextChannel)
        and message.channel.topic is not None
        and "notl" in message.channel.topic
    ):
        return
    # message.content にURLとメンションと絵文字しかない場合は翻訳しない
    modified_text = re.sub(
        r"<.*?>|:.*?:|https?://[\w!?/\+\-_~=;\.,*&@#$%\(\)\'\[\]]+", "", message.content
    )
    if len(modified_text.strip()) == 0:
        return
    translated_text = await translate(message.content)
    embed = discord.Embed(description=translated_text, color=0xBF65E8)
    m = await message.reply(embed=embed, mention_author=False)
    translated_messages[message.id] = m


@bot.event
async def on_message_edit(before: discord.Message, after: discord.Message):
    if before.author.bot:
        return
    if before.content == after.content:
        return
    # message.content にURLとメンションと絵文字しかない場合は翻訳しない
    modified_text = re.sub(
        r"<.*?>|:.*?:|https?://[\w!?/\+\-_~=;\.,*&@#$%\(\)\'\[\]]+", "", after.content
    )
    if len(modified_text.strip()) == 0:
        return
    translated_text = await translate(after.content)
    embed = discord.Embed(description=translated_text, color=0xBF65E8)
    response = translated_messages.get(before.id)
    if response is None:
        return
    m = await response.edit(embed=embed)
    translated_messages[before.id] = m


@bot.event
async def on_message_delete(message: discord.Message):
    response = translated_messages.pop(message.id, None)
    if response is None:
        return
    await response.delete()


@bot.slash_command()
async def ping(ctx):
    await ctx.respond(f"Pong! ({bot.latency*1000}ms)")


@bot.slash_command(
    name="send-agree-button",
    default_member_permssions=admin_only,
)
async def send_agree_button(ctx: discord.ApplicationContext):
    await ctx.send(
        content="Please press the button below if you agree.\n同意する場合は以下のボタンを押してください。",
        view=AgreeButtonView(),
    )
    await ctx.respond("Sent!", ephemeral=True)


role = bot.create_group("role", description="Role commands")


@role.command(
    name="list",
    description="Show all roles.",
    description_localizations={
        "ja": "ロール一覧を表示します",
    },
)
async def role_list(ctx: discord.ApplicationContext):
    embed = discord.Embed(
        title="ロール一覧",
        description="\n".join([role.mention for role in ctx.guild.roles]),
    )
    await ctx.respond(embed=embed)


# 複数のロールを与えると AND 検索
@role.command(
    name="members",
    description="Show members of the role.",
    description_localizations={
        "ja": "ロールのメンバー一覧を表示します",
    },
)
async def role_members(
    ctx: discord.ApplicationContext,
    role1: discord.Role,
    role2: Optional[discord.Role] = None,
    role3: Optional[discord.Role] = None,
):
    roles = [role1, role2, role3]
    roles = [role for role in roles if role is not None]
    members = set.intersection(*(set(role.members) for role in roles))
    content = "\n".join([member.display_name for member in members])
    await ctx.respond(f"{[role.name for role in roles]}\n```\n{content}\n```")


@bot.slash_command(
    name="pick",
    description="Pick a random member from the role.",
    description_localizations={
        "ja": "ロールからランダムにメンバーを選びます。",
    },
)
async def pick(ctx: discord.ApplicationContext, role: discord.Role):
    members = role.members
    if not members:
        await ctx.respond("No members in the role.", ephemeral=True)
        return
    member = random.choice(members)
    embed = discord.Embed(
        color=0xB190FC, title=f"Picked a random member from {role.name}"
    )
    embed.add_field(name=member.display_name, value=member.mention)
    await ctx.respond(embed=embed)


@bot.message_command(name="Delete")
async def delete(ctx: discord.ApplicationContext, message: discord.Message):
    if message.author.id != bot.user.id:
        await ctx.respond("You can only delete messages sent by me.", ephemeral=True)
        return
    await message.delete()
    await ctx.respond("Deleted!", ephemeral=True)


@bot.message_command(name="Edit")
async def edit(ctx: discord.ApplicationContext, message: discord.Message):
    if message.author.id != bot.user.id:
        await ctx.respond("You can only edit messages sent by me.", ephemeral=True)
        return
    await ctx.send_modal(EditModal(message))


bot.run(os.environ["DISCORD_TOKEN"])
