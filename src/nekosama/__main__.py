import os
from pathlib import Path

import discord


def _load_dotenv() -> None:
    env = Path(".env")
    if not env.exists():
        return
    for line in env.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"'))


def main() -> None:
    _load_dotenv()
    token = os.environ.get("DISCORD_TOKEN") or os.environ.get("DISCORD_BOT_TOKEN")
    if not token:
        raise SystemExit("DISCORD_TOKEN or DISCORD_BOT_TOKEN is required")
    discord.utils.setup_logging()

    from .bot import Nekosama

    Nekosama().run(token, log_handler=None)


if __name__ == "__main__":
    main()
