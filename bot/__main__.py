import datetime
import os
import uuid
from collections import OrderedDict
from typing import List, Optional

import aiohttp
import discord
from discord.ext import commands, tasks
from dotenv import load_dotenv

from .views import AgreementButtonView
from .config import guild_id, teams

load_dotenv()
intents = discord.Intents.default()
intents.members = True
intents.message_content = True
bot = commands.Bot(intents=intents)

guild: Optional[discord.Guild] = None
events: List[discord.ScheduledEvent] = []


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


async def translate(text, dest=['en', 'ja'], src=None):
    key = os.environ['TL_KEY']
    endpoint = 'https://api.cognitive.microsofttranslator.com'
    path = '/translate'
    constructed_url = endpoint + path
    region = 'japaneast'
    params = [('api-version', '3.0')]
    if src is not None:
        params.append(('from', src))
    if isinstance(dest, list):
        for d in dest:
            params.append(('to', d))
    else:
        params.append(('to', dest))
    headers = {
        'Ocp-Apim-Subscription-Key': key,
        'Ocp-Apim-Subscription-Region': region,
        'Content-type': 'application/json',
        'X-ClientTraceId': str(uuid.uuid4())
    }
    body = [{'text': text}]

    async with aiohttp.ClientSession() as session:
        async with session.post(url=constructed_url, params=params, headers=headers, json=body) as response:
            if response.status != 200:
                print(await response.text())
                return None, response.status
            res = await response.json()
            if src is None:
                match res[0]['detectedLanguage']['language']:
                    case 'ja':
                        return res[0]['translations'][0]['text'], response.status
                    case 'en':
                        return res[0]['translations'][1]['text'], response.status
            else:
                return res[0]['translations'][0]['text'], response.status


@bot.event
async def on_ready():
    print(f"Logged in as {bot.user} (ID: {bot.user.id})")
    print("------")
    bot.add_view(AgreementButtonView(bot))
    global guild
    guild = bot.get_guild(guild_id)
    get_events.start()
    check_events.start()


@bot.event
async def on_message(message: discord.Message):
    if message.author.bot:
        return
    translated_text, status = await translate(message.content)
    if status != 200:
        return
    sent_message = await message.reply(translated_text, mention_author=False)
    await sent_message.add_reaction('🗑️')


@bot.event
async def on_reaction_add(reaction: discord.Reaction, user: discord.User):
    if user.bot:
        return
    if reaction.message.author.id == bot.user.id and reaction.emoji == '🗑️':
        await reaction.message.delete()

@bot.slash_command()
async def ping(ctx):
    await ctx.respond(f"Pong! ({bot.latency*1000}ms)")


role = bot.create_group('role', description='Role commands')

@role.command(
    name='list',
    description='Show all roles.',
    description_localizations={
        'ja': 'ロール一覧を表示します',
    },
)
async def role_list(ctx: discord.ApplicationContext):
    embed = discord.Embed(
        title='ロール一覧',
        description='\n'.join([role.mention for role in ctx.guild.roles]),
    )
    await ctx.respond(embed=embed)


# 複数のロールを与えると AND 検索
@role.command(
    name='members',
    description='Show members of the role.',
    description_localizations={
        'ja': 'ロールのメンバー一覧を表示します',
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
    content = '\n'.join([member.display_name for member in members])
    await ctx.respond(f'{[role.name for role in roles]}\n```\n{content}\n```')


@bot.message_command(name='JP -> EN')
async def jp_to_en(ctx: discord.ApplicationContext, message: discord.Message):
    if message.content in jp_to_en_cache:
        await ctx.respond(jp_to_en_cache[message.content], ephemeral=True)
        return
    translated_text, status = await translate(message.content, src='ja', dest='en')
    if status != 200:
        await ctx.respond(f'Error: {status}')
        return
    jp_to_en_cache[message.content] = translated_text
    await ctx.respond(translated_text, ephemeral=True)


@bot.message_command(name='EN -> JP')
async def en_to_jp(ctx: discord.ApplicationContext, message: discord.Message):
    if message.content in en_to_jp_cache:
        await ctx.respond(en_to_jp_cache[message.content], ephemeral=True)
        return
    translated_text, status = await translate(message.content, src='en', dest='ja')
    if status != 200:
        await ctx.respond(f'Error: {status}')
        return
    en_to_jp_cache[message.content] = translated_text
    await ctx.respond(translated_text, ephemeral=True)


@bot.slash_command(
    name='unixtimestamp',
    description='Convert datetime to unix timestamp format.',
    description_localizations={
        'ja': '日時をUNIXタイムスタンプに変換します。',
    },
)
async def unixtimestamp(
        ctx: discord.ApplicationContext,
        dt: discord.Option(
            name='datetime',
            input_type=str,
            description='The format must be `yyyymmdd-HHMMSS`. (ex: 20190406-205700)',
            description_localizations={
                'ja': '書式は`yyyymmdd-HHMMSS`です。 (例: 20190406-205700)',
            },
            required=True,
        ),
        timezone: discord.Option(
            input_type=str,
            description='the timezone of the entered date and time.',
            description_localizations={
                'ja': '入力した日時のタイムゾーン。',
            },
            choices=[
                discord.OptionChoice('UTC', '+0000'),
                discord.OptionChoice('JST (UTC+9)', '+0900'),
                discord.OptionChoice('PST (UTC-8)', '-0800'),
                discord.OptionChoice('MST (UTC-7)', '-0700'),
                discord.OptionChoice('CST (UTC-6)', '-0600'),
                discord.OptionChoice('EST (UTC-5)', '-0500'),
                discord.OptionChoice('CET・BST (UTC+1)', '+0100'),
                discord.OptionChoice('EET・CEST (UTC+2)', '+0200'),
                discord.OptionChoice('MSK・EEST (UTC+3)', '+0300'),
                discord.OptionChoice('IST (UTC+5.5)', '+0530'),
                discord.OptionChoice('WIB (UTC+7)', '+0700'),
                discord.OptionChoice('WITA・AWST (UTC+8)', '+0800'),
                discord.OptionChoice('KST・AWDT (UTC+9)', '+0900'),
                discord.OptionChoice('AEST (UTC+10)', '+1000'),
                discord.OptionChoice('AEDT (UTC+11)', '+1100'),
                discord.OptionChoice('NZST (UTC+12)', '+1200'),
                discord.OptionChoice('NZDT (UTC+13)', '+1300'),
            ],
            required=True,
        ),
        style: discord.Option(
            input_type=str,
            description='the style of the timestamp.',
            description_localizations={
                'ja': 'タイムスタンプの表示形式。',
            },
            choices=[
                discord.OptionChoice('Short Time (ex: 8:57 PM)', 't', name_localizations={'ja': 'Short Time (ex: 20:57)'}),
                discord.OptionChoice('Long Time (ex: 8:57:00 PM)', 'T', name_localizations={'ja': 'Long Time (ex: 20:57:00)'}),
                discord.OptionChoice('Short Date (ex: 4/6/2019)', 'd', name_localizations={'ja': 'Short Date (ex: 2019/4/6)'}),
                discord.OptionChoice('Long Date (ex: April 6, 2019)', 'D', name_localizations={'ja': 'Long Date (ex: 2019年4月6日)'}),
                discord.OptionChoice('Short Date/Time (ex: April 6, 2019 8:57 PM)', 'f', name_localizations={'ja': 'Short Date/Time (ex: 2019/4/6 20:57)'}),
                discord.OptionChoice('Long Date/Time (ex: Saturday, April 6, 2019 8:57 PM)', 'F', name_localizations={'ja': 'Long Date/Time (ex: 2019年4月6日 土曜日 20:57)'}),
                discord.OptionChoice('Relative Time (ex: 4 years ago)', 'R', name_localizations={'ja': 'Relative Time (ex: 4年前)'}),
            ],
        ),
    ):
    try:
        dt_obj = datetime.datetime.strptime(dt + timezone, '%Y%m%d-%H%M%S%z')
    except ValueError as e:
        print(e)
        await ctx.respond('The format must be `yyyymmdd-HHMMSS`. (ex: 20190406-2057)', ephemeral=True)
    timestamp = f'<t:{int(dt_obj.timestamp())}:{style}>'
    embed = discord.Embed(color=0xb190fc)
    embed.add_field(name='Input (with timezone)', value=f'```\n{dt}{timezone}\n```')
    embed.add_field(name='Unix Timestamp', value=f'```\n{timestamp}\n```')
    await ctx.respond(timestamp, embed=embed)


@tasks.loop(minutes=1)
async def get_events():
    global events
    events = await guild.fetch_scheduled_events()
    print(events)


@tasks.loop(seconds=10)
async def check_events():
    global events
    for event in events:
        if datetime.timedelta(minutes=4) < event.start_time - datetime.datetime.now(datetime.timezone.utc) < datetime.timedelta(minutes=5):
            if ids := teams.get(event.location.value.id):
                role = guild.get_role(ids[0]) if ids[0] else None
                channel = guild.get_channel(ids[1])
                await channel.send(f'{role.mention if role else "@everyone"}\n__**{event.name}**__ が {event.location.value.jump_url} で __**5 分後**__に始まります！\n{event.url}')
                events.remove(event)


bot.run(os.environ.get('DISCORD_TOKEN'))
