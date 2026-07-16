# nekosama

nekosama is a Discord bot written in MoonBit on top of
[discord.mbt](https://github.com/gaato/discord.mbt). It manages opt-in roles,
translates messages with OpenAI, and provides GPT-powered conversations in
Discord threads.

## Features

- `/ping` reports the current Discord gateway latency.
- `/role list` lists guild roles, and `/role members` finds the intersection
  of up to three roles.
- `/pick` chooses a random member from a role intersection.
- `/send-agree-button` posts a button that grants the configured member role.
- Messages in ordinary channels are translated with `gpt-4.1-nano`, except in
  channels whose topic contains `notl`.
- Translation replies stay in sync when their source message is edited or
  deleted. The bot's translation embeds can also be edited or deleted through
  message context-menu commands.
- Mentioning the bot starts or continues a `gpt-4` conversation, while
  bot-owned threads use their latest 30 messages as `gpt-4o` context.

## Prerequisites

- MoonBit toolchain `0.10.4+2cc641edf` (`moon 0.1.20260713`)
- A C toolchain plus OpenSSL and zlib development headers
- A Discord application with the Server Members Intent and Message Content
  Intent enabled

## Build and run

Clone the repository together with its `discord.mbt` submodule:

```fish
git clone --recurse-submodules https://github.com/gaato/nekosama.git
cd nekosama
```

For an existing clone, initialize or refresh the submodule first:

```fish
git submodule update --init --recursive
```

Update the MoonBit package registry, then build the native release binary:

```fish
moon update
moon build --release --target native
```

Set the runtime configuration and start the bot:

```fish
set -x DISCORD_TOKEN "your Discord bot token"
set -x OPENAI_API_KEY "your OpenAI API key"
set -x MEMBER_ROLE_ID "the role ID granted by the agree button"
set -x GUILD_ID "the development guild ID"
moon run --release --target native src/main
```

`DISCORD_TOKEN` is required to connect to Discord. `OPENAI_API_KEY` is required
for translation and chat. `MEMBER_ROLE_ID` is required by the agree button.
`GUILD_ID` is optional: when present and valid, application commands are synced
only to that guild; otherwise they are synced globally.

## Docker

The image builds the native executable in a pinned MoonBit builder and copies
only the executable and its runtime TLS dependencies into the final image.
The submodule must be initialized in the build context.

```fish
git submodule update --init --recursive
docker build --tag nekosama .
docker run --rm \
  --env DISCORD_TOKEN \
  --env OPENAI_API_KEY \
  --env MEMBER_ROLE_ID \
  --env GUILD_ID \
  nekosama
```

## Checks

```fish
moon check --target native
env MOON_CC=/usr/bin/gcc moon test --target native
moon fmt --check
```
