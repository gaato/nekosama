import os

import discord
from discord.ext import commands
from dotenv import load_dotenv

from .views import RoleSelectView


load_dotenv()
intents = discord.Intents.default()
intents.members = True
bot = commands.Bot(intents=intents)


@bot.event
async def on_ready():
    print(f"Logged in as {bot.user} (ID: {bot.user.id})")
    print("------")
    bot.add_view(RoleSelectView(bot))

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
    embed = discord.Embed(
        title=f'{role.name}のメンバー一覧',
        description='\n'.join([member.mention for member in role.members]),
    )
    await ctx.respond(embed=embed)


bot.run(os.environ.get('DISCORD_TOKEN'))
