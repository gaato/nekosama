import discord

from . import config


class AgreementButtonView(discord.ui.View):
    def __init__(self, log_channel: discord.TextChannel):
        self.log_channel = log_channel
        super().__init__(timeout=None)

    @discord.ui.button(label='Agree', custom_id='button-1', style=discord.ButtonStyle.primary)
    async def button_callback(self, button, interaction: discord.Interaction):
        role = interaction.guild.get_role(config.role_id)
        await interaction.user.add_roles(role)
        await interaction.response.send_message(f'Please read <#1082923642918289448> first!\nまずは<#1082278240535724064>をお読みください！', ephemeral=True)
