name = "gaato/nekosama"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/gaato/nekosama"

license = "BlueOak-1.0.0"

description = "A Discord bot built with MoonBit and discord.mbt."

source = "src"

preferred_target = "native"

// Trait methods are never promoted to regular methods implicitly.

warnings = "-implicit_impl_as_method"

import {
  "gaato/discord@0.8.0",
  "gaato/http@0.1.2",
  "gaato/http-async@0.1.4",
  "gaato/openai@0.2.1",
  "gaato/sdk-runtime@0.2.2",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.5",
}
