import os

import discord
from discord.ext import commands
from dotenv import load_dotenv

from .views import AgreementButtonView


load_dotenv()
intents = discord.Intents.default()
intents.members = True
bot = commands.Bot(intents=intents)


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
    description='ロール一覧を表示します',
)
async def role_list(ctx: discord.ApplicationContext):
    embed = discord.Embed(
        title='ロール一覧',
        description='\n'.join([role.mention for role in ctx.guild.roles]),
    )
    await ctx.respond(embed=embed)


@role.command(
    name='members',
    description='ロールのメンバー一覧を表示します',
)
async def role_members(ctx: discord.ApplicationContext, role: discord.Role):
    content = f'{role.name}のメンバー一覧\n```\n' + \
        '\n'.join([member.display_name for member in role.members]) + \
        '\n```'
    await ctx.respond(content)


bot.run(os.environ.get('DISCORD_TOKEN'))
