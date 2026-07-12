"""OpenAI API ラッパー。モデルは環境変数で差し替え可能。"""

import os
from functools import cache

from openai import AsyncOpenAI

TRANSLATE_MODEL = os.environ.get("NEKOSAMA_TRANSLATE_MODEL", "gpt-4.1-nano")
CHAT_MODEL = os.environ.get("NEKOSAMA_CHAT_MODEL", "gpt-4o")


@cache
def client() -> AsyncOpenAI:
    return AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"])


async def translate(text: str) -> str:
    response = await client().chat.completions.create(
        model=TRANSLATE_MODEL,
        messages=[
            {
                "role": "system",
                "content": "This is a direct translation task. "
                "Translate the following text from Japanese to English or from English to Japanese. "
                "Do not add any additional comments or language indicators.",
            },
            {"role": "user", "content": text},
        ],
    )
    return response.choices[0].message.content or ""


async def chat(messages: list[dict[str, str]]) -> str:
    response = await client().chat.completions.create(
        model=CHAT_MODEL,
        messages=messages,
    )
    return response.choices[0].message.content or ""
