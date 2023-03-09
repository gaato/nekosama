import datetime
import os
from collections import OrderedDict

import discord
from discord.ext import commands
from dotenv import load_dotenv
from googletrans import Translator

from .views import AgreementButtonView


load_dotenv()
intents = discord.Intents.default()
intents.members = True
bot = commands.Bot(intents=intents)
translator = Translator()


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


translation_cache = LimitedSizeDict(size_limit=100)


@bot.event
async def on_ready():
    print(f"Logged in as {bot.user} (ID: {bot.user.id})")
    print("------")
    bot.add_view(AgreementButtonView(bot))

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


@role.command(
    name='members',
    description='Show members of the role.',
    description_localizations={
        'ja': 'ロールのメンバー一覧を表示します',
    },
)
async def role_members(ctx: discord.ApplicationContext, role: discord.Role):
    content = f'{role.name}のメンバー一覧\n```\n' + \
        '\n'.join([member.display_name for member in role.members]) + \
        '\n```'
    await ctx.respond(content)


@bot.message_command(name='JP -> EN')
async def jp_to_en(ctx: discord.ApplicationContext, message: discord.Message):
    if message.content in translation_cache:
        await ctx.respond(translation_cache[message.content], ephemeral=True)
        return
    translation_cache[message.content] = translator.translate(message.content, dest='en', src='ja').text
    await ctx.respond(translation_cache[message.content], ephemeral=True)


@bot.message_command(name='EN -> JP')
async def en_to_jp(ctx: discord.ApplicationContext, message: discord.Message):
    if message.content in translation_cache:
        await ctx.respond(translation_cache[message.content], ephemeral=True)
        return
    translation_cache[message.content] = translator.translate(message.content, dest='ja', src='en').text
    await ctx.respond(translation_cache[message.content], ephemeral=True)


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


bot.run(os.environ.get('DISCORD_TOKEN'))
