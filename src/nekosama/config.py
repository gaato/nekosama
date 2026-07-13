"""ギルドごとの設定を JSON ファイルで永続化する。"""

import json
import os
from pathlib import Path
from typing import Any


class ConfigStore:
    def __init__(self, path: Path | None = None):
        if path is None:
            path = Path(os.environ.get("NEKOSAMA_DATA_DIR", "data")) / "config.json"
        self.path = path
        self.data: dict[str, dict[str, Any]] = {}
        if self.path.exists():
            self.data = json.loads(self.path.read_text())

    def guild(self, guild_id: int) -> dict[str, Any]:
        return self.data.setdefault(str(guild_id), {})

    def get(self, guild_id: int, key: str, default: Any = None) -> Any:
        return self.data.get(str(guild_id), {}).get(key, default)

    def set(self, guild_id: int, key: str, value: Any) -> None:
        self.guild(guild_id)[key] = value
        self.save()

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        data = {key: value for key, value in self.data.items() if value}
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        tmp.replace(self.path)
