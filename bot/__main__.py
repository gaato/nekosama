import datetime
import os
import random
import re
import traceback
import uuid
from collections import OrderedDict
from typing import Optional

import aiohttp
import discord
import openai
from discord.ext import commands, tasks
from dotenv import load_dotenv
from googletrans import Translator

from .config import guild_id, teams

load_dotenv()
intents = discord.Intents.default()
intents.members = True
intents.message_content = True
bot = commands.Bot(intents=intents)

translator = Translator()

guild: Optional[discord.Guild] = None

openai.api_key = os.environ["OPENAI_API_KEY"]


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


async def detect(text: str):
    return translator.detect(text).lang, 200
    # key = os.environ['TL_KEY']
    # endpoint = 'https://api.cognitive.microsofttranslator.com'
    # path = '/detect'
    # constructed_url = endpoint + path
    # region = 'japaneast'
    # params = [('api-version', '3.0')]
    # headers = {
    #     'Ocp-Apim-Subscription-Key': key,
    #     'Ocp-Apim-Subscription-Region': region,
    #     'Content-type': 'application/json',
    #     'X-ClientTraceId': str(uuid.uuid4())
    # }
    # body = [{'text': text}]

    # async with aiohttp.ClientSession() as session:
    #     async with session.post(url=constructed_url, params=params, headers=headers, json=body) as response:
    #         if response.status != 200:
    #             print(await response.text())
    #             return None, response.status
    #         res = await response.json()
    #         return res[0]['language'], response.status


async def translate(text, dest=["en", "ja"], src=None):
    return translator.translate(text, dest=dest, src=src).text, 200
    # key = os.environ['TL_KEY']
    # endpoint = 'https://api.cognitive.microsofttranslator.com'
    # path = '/translate'
    # constructed_url = endpoint + path
    # region = 'japaneast'
    # params = [('api-version', '3.0')]
    # if src is not None:
    #     params.append(('from', src))
    # if isinstance(dest, list):
    #     for d in dest:
    #         params.append(('to', d))
    # else:
    #     params.append(('to', dest))
    # headers = {
    #     'Ocp-Apim-Subscription-Key': key,
    #     'Ocp-Apim-Subscription-Region': region,
    #     'Content-type': 'application/json',
    #     'X-ClientTraceId': str(uuid.uuid4())
    # }
    # body = [{'text': text}]

    # async with aiohttp.ClientSession() as session:
    #     async with session.post(url=constructed_url, params=params, headers=headers, json=body) as response:
    #         if response.status != 200:
    #             print(await response.text())
    #             return None, response.status
    #         res = await response.json()
    #         if src is None:
    #             match res[0]['detectedLanguage']['language']:
    #                 case 'ja':
    #                     return res[0]['translations'][0]['text'], response.status
    #                 case 'en':
    #                     return res[0]['translations'][1]['text'], response.status
    #         else:
    #             return res[0]['translations'][0]['text'], response.status


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


@bot.event
async def on_ready():
    print(f"Logged in as {bot.user} (ID: {bot.user.id})")
    print("------")
    bot.add_view(TranslateResponseView())
    global guild
    guild = bot.get_guild(guild_id)
    fetch_events.start()


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
                limit=10, oldest_first=True
            ).flatten()
            if history[0].type == discord.MessageType.thread_starter_message:
                history[0] = history[0].reference.resolved
            response = openai.ChatCompletion.create(
                model="gpt-4",
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
            response = openai.ChatCompletion.create(
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

    # message.content にURLとメンションと絵文字しかない場合は翻訳しない
    modified_text = re.sub(
        r"<.*?>|:.*?:|https?://[\w!?/\+\-_~=;\.,*&@#$%\(\)\'\[\]]+", "", message.content
    )
    if len(modified_text.strip()) == 0:
        return
    detected_lang, status = await detect(message.content)
    if status != 200:
        return
    if detected_lang in ("ja", "zh-Hans"):
        color = 0x87CEEB
        translated_text, status = await translate(message.content, src="ja", dest="en")
    else:
        color = 0x90EE90
        translated_text, status = await translate(message.content, src="en", dest="ja")
    if status != 200:
        return
    embed = discord.Embed(description=translated_text, color=color)
    # view = TranslateResponseView()
    # m = await message.reply(translated_text, mention_author=False, view=view)
    m = await message.reply(embed=embed, mention_author=False)
    translated_messages[message.id] = m


@bot.event
async def on_message_edit(before: discord.Message, after: discord.Message):
    if before.author.bot:
        return
    if before.content == after.content:
        return
    # after.content にURLとメンションと絵文字しかない場合は翻訳しない
    modified_text = re.sub(
        r"<.*?>|:.*?:|https?://[\w!?/\+\-_~=;\.,*&@#$%\(\)\'\[\]]+", "", after.content
    )
    if len(modified_text.strip()) == 0:
        return
    detected_lang, status = await detect(after.content)
    if status != 200:
        return
    if detected_lang in ("ja", "zh-Hans"):
        color = 0x87CEEB
        translated_text, status = await translate(after.content, src="ja", dest="en")
    else:
        color = 0x90EE90
        translated_text, status = await translate(after.content, src="en", dest="ja")
    if status != 200:
        return
    response = translated_messages.get(before.id)
    if response is None:
        return
    embed = discord.Embed(description=translated_text, color=color)
    # view = TranslateResponseView()
    # m = await response.edit(content=translated_text, view=view, embed=None)
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


# @bot.message_command(name='JP -> EN')
# async def jp_to_en(ctx: discord.ApplicationContext, message: discord.Message):
#     if message.content in jp_to_en_cache:
#         await ctx.respond(jp_to_en_cache[message.content], ephemeral=True)
#         return
#     translated_text, status = await translate(message.content, src='ja', dest='en')
#     if status != 200:
#         await ctx.respond(f'Error: {status}')
#         return
#     jp_to_en_cache[message.content] = translated_text
#     await ctx.respond(translated_text, ephemeral=True)


# @bot.message_command(name='EN -> JP')
# async def en_to_jp(ctx: discord.ApplicationContext, message: discord.Message):
#     if message.content in en_to_jp_cache:
#         await ctx.respond(en_to_jp_cache[message.content], ephemeral=True)
#         return
#     translated_text, status = await translate(message.content, src='en', dest='ja')
#     if status != 200:
#         await ctx.respond(f'Error: {status}')
#         return
#     en_to_jp_cache[message.content] = translated_text
#     await ctx.respond(translated_text, ephemeral=True)


@bot.slash_command(
    name="unixtimestamp",
    description="Convert datetime to unix timestamp format.",
    description_localizations={
        "ja": "日時をUNIXタイムスタンプに変換します。",
    },
)
async def unixtimestamp(
    ctx: discord.ApplicationContext,
    dt: discord.Option(
        name="datetime",
        input_type=str,
        description="The format must be `yyyymmdd-HHMMSS`. (ex: 20190406-205700)",
        description_localizations={
            "ja": "書式は`yyyymmdd-HHMMSS`です。 (例: 20190406-205700)",
        },
        required=True,
    ),
    timezone: discord.Option(
        input_type=str,
        description="the timezone of the entered date and time.",
        description_localizations={
            "ja": "入力した日時のタイムゾーン。",
        },
        choices=[
            discord.OptionChoice("UTC", "+0000"),
            discord.OptionChoice("JST (UTC+9)", "+0900"),
            discord.OptionChoice("PST (UTC-8)", "-0800"),
            discord.OptionChoice("MST (UTC-7)", "-0700"),
            discord.OptionChoice("CST (UTC-6)", "-0600"),
            discord.OptionChoice("EST (UTC-5)", "-0500"),
            discord.OptionChoice("CET・BST (UTC+1)", "+0100"),
            discord.OptionChoice("EET・CEST (UTC+2)", "+0200"),
            discord.OptionChoice("MSK・EEST (UTC+3)", "+0300"),
            discord.OptionChoice("IST (UTC+5.5)", "+0530"),
            discord.OptionChoice("WIB (UTC+7)", "+0700"),
            discord.OptionChoice("WITA・AWST (UTC+8)", "+0800"),
            discord.OptionChoice("KST・AWDT (UTC+9)", "+0900"),
            discord.OptionChoice("AEST (UTC+10)", "+1000"),
            discord.OptionChoice("AEDT (UTC+11)", "+1100"),
            discord.OptionChoice("NZST (UTC+12)", "+1200"),
            discord.OptionChoice("NZDT (UTC+13)", "+1300"),
        ],
        required=True,
    ),
    style: discord.Option(
        input_type=str,
        description="the style of the timestamp.",
        description_localizations={
            "ja": "タイムスタンプの表示形式。",
        },
        choices=[
            discord.OptionChoice(
                "Short Time (ex: 8:57 PM)",
                "t",
                name_localizations={"ja": "Short Time (ex: 20:57)"},
            ),
            discord.OptionChoice(
                "Long Time (ex: 8:57:00 PM)",
                "T",
                name_localizations={"ja": "Long Time (ex: 20:57:00)"},
            ),
            discord.OptionChoice(
                "Short Date (ex: 4/6/2019)",
                "d",
                name_localizations={"ja": "Short Date (ex: 2019/4/6)"},
            ),
            discord.OptionChoice(
                "Long Date (ex: April 6, 2019)",
                "D",
                name_localizations={"ja": "Long Date (ex: 2019年4月6日)"},
            ),
            discord.OptionChoice(
                "Short Date/Time (ex: April 6, 2019 8:57 PM)",
                "f",
                name_localizations={"ja": "Short Date/Time (ex: 2019/4/6 20:57)"},
            ),
            discord.OptionChoice(
                "Long Date/Time (ex: Saturday, April 6, 2019 8:57 PM)",
                "F",
                name_localizations={"ja": "Long Date/Time (ex: 2019年4月6日 土曜日 20:57)"},
            ),
            discord.OptionChoice(
                "Relative Time (ex: 4 years ago)",
                "R",
                name_localizations={"ja": "Relative Time (ex: 4年前)"},
            ),
        ],
    ),
):
    try:
        dt_obj = datetime.datetime.strptime(dt + timezone, "%Y%m%d-%H%M%S%z")
    except ValueError as e:
        print(e)
        await ctx.respond(
            "The format must be `yyyymmdd-HHMMSS`. (ex: 20190406-2057)", ephemeral=True
        )
    timestamp = f"<t:{int(dt_obj.timestamp())}:{style}>"
    embed = discord.Embed(color=0xB190FC)
    embed.add_field(name="Input (with timezone)", value=f"```\n{dt}{timezone}\n```")
    embed.add_field(name="Unix Timestamp", value=f"```\n{timestamp}\n```")
    await ctx.respond(timestamp, embed=embed)


@tasks.loop(minutes=1)
async def fetch_events():
    events = await guild.fetch_scheduled_events()
    upcomming_events = filter(
        lambda e: datetime.datetime.now(datetime.timezone.utc)
        + datetime.timedelta(minutes=4)
        < e.start_time
        < datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=5),
        await guild.fetch_scheduled_events(),
    )
    for event in upcomming_events:
        if (
            datetime.timedelta(minutes=4)
            < event.start_time - datetime.datetime.now(datetime.timezone.utc)
            < datetime.timedelta(minutes=5)
        ):
            if ids := teams.get(event.location.value.id):
                role = guild.get_role(ids[0]) if ids[0] else None
                channel = guild.get_channel(ids[1])
                await channel.send(
                    f'{role.mention if role else "@everyone"}\n__**{event.name}**__ が {event.location.value.jump_url} で __**5 分後**__に始まります！\n{event.url}'
                )
                try:
                    await event.start()
                except Exception:
                    traceback.print_exc()


bot.run(os.environ["DISCORD_TOKEN"])
