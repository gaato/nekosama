import os
import pathlib

import discord
from dotenv import load_dotenv

from ..views import AgreementButtonView
from .. import config


HERE = pathlib.Path(__file__).parent

load_dotenv()
intents = discord.Intents.default()
client = discord.Client(intents=intents)


@client.event
async def on_ready():
    print(f"Logged in as {client.user} (ID: {client.user.id})")
    print("------")
    button_channel = client.get_channel(config.channel_id)
    view = AgreementButtonView(client)
    message = await button_channel.send('After carefully reading the above information, please click the button below.\n上記の内容をよく読んだら以下のボタンを押してください。', view=view)
    print(f'BUTTON_MESSAGE_ID = {message.id}')
    await client.close()


client.run(os.environ.get('DISCORD_TOKEN'))
