# nekosama

nekosama is a Discord bot written in MoonBit on top of
[discord.mbt](https://github.com/gaato/discord.mbt). It onboards members,
translates messages with OpenAI, holds GPT-powered conversations in threads,
and runs the chores of a project server: events, scheduling polls, absence
notices, and forum indexes.

## Features

- `/ping` reports the current Discord gateway latency.
- `/role list` lists guild roles, and `/role members` finds the intersection
  of up to three roles.
- `/pick` chooses a random member from a role intersection.
- `/send-agree-button` posts a button that grants the member role, and
  `/send-role-menu` posts a select menu members use to pick their own roles.
- `/config` stores per-guild settings: `member-role`, `absence-channel`,
  `auto-translate`, and `show`.
- `/absence` posts an absence notice to the configured channel.
- `/schedule` posts a scheduling poll. Answers are kept in the poll message
  itself, so polls survive restarts.
- `/event` creates a voice scheduled event from a JST time such as
  `7/20 21:00`, reminds five minutes ahead, then starts the event and
  announces it.
- `/forum-index` places a pinned, self-updating thread index in a forum. New
  forum posts without a tag get the first tag whose name contains `実施前`.
- Messages in ordinary channels are translated with `gpt-5.6-luna`, except in
  channels whose topic contains `notl`.
- Translation replies stay in sync when their source message is edited or
  deleted. The bot's translation embeds can also be edited or deleted through
  message context-menu commands, and `Translate` translates any message
  privately on demand.
- Mentioning the bot starts or continues a `gpt-5.6-terra` conversation, while
  bot-owned threads use their latest 30 messages as context.

Menus, buttons, and polls posted by the earlier Python bot keep working: the
component ids and the `config.json` layout are unchanged.

## Prerequisites

- MoonBit toolchain `0.10.14+7d59c7ec9` (`moon 0.1.20260920`)
- A C toolchain plus OpenSSL and zlib development headers
- Node.js on `PATH` (the `gaato/discord` prebuild script runs on it, even
  though nekosama does not use voice)
- A Discord application with the Server Members Intent and Message Content
  Intent enabled

## Build and run

`discord.mbt` is resolved from mooncakes.io as `gaato/discord`. Update the
MoonBit package registry, then build the native release binary:

```fish
moon update
moon build --release --target native
```

Set the runtime configuration and start the bot:

```fish
set -x DISCORD_TOKEN "your Discord bot token"
set -x OPENAI_API_KEY "your OpenAI API key"
set -x GUILD_ID "the development guild ID"
moon run --release --target native src/main
```

`DISCORD_TOKEN` is required to connect to Discord. `OPENAI_API_KEY` is required
for translation and chat. `GUILD_ID` is optional: when present and valid,
application commands are synced only to that guild; otherwise they are synced
globally.

| Variable | Default | Purpose |
| --- | --- | --- |
| `NEKOSAMA_DATA_DIR` | `data` | Directory holding `config.json`, the per-guild settings and feature state. Keep it on persistent storage. |
| `MEMBER_ROLE_ID` | none | Fallback role for the agree button when `/config member-role` is unset. |
| `NEKOSAMA_TRANSLATE_MODEL` | `gpt-5.6-luna` | Model used for translation. |
| `NEKOSAMA_CHAT_MODEL` | `gpt-5.6-terra` | Model used for mention and thread chat. |

The bot needs the Server Members and Message Content privileged intents, and
the permissions to manage roles, events, and threads for the features above.

## Docker

The image builds the native executable in a pinned MoonBit builder and copies
only the executable and its runtime TLS dependencies into the final image.

```fish
docker build --tag nekosama .
docker run --rm \
  --env DISCORD_TOKEN \
  --env OPENAI_API_KEY \
  --env GUILD_ID \
  --volume nekosama-data:/data \
  nekosama
```

## Checks

```fish
moon check --target native
env MOON_CC=/usr/bin/gcc moon test --target native
moon fmt --check
```
