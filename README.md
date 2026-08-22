# Kvartz

Kvartz is a small native macOS menu-bar utility for short and ephemeral LLM queries. Click the shortcut, type a question, read the response. Copy if you need it; nothing is saved.

![Kvartz answering a query](Assets/Kvartz-screenshot.png)

## Included providers

- OpenAI (Responses API)
- OpenAI Codex via the local `codex app-server`
- Anthropic
- Google Gemini
- Qwen
- Kimi
- GLM
- OpenRouter
- Ollama

API keys are stored in macOS Keychain. Provider models, base URLs, and the activation shortcut are configurable.

## Install

Kvartz requires macOS 14 or later and an Apple Silicon Mac.

1. Download [`Kvartz-0.1.2-macOS-arm64.zip`](https://github.com/ymolodtsov/kvartz/releases/latest/download/Kvartz-0.1.2-macOS-arm64.zip).
2. Unzip it and move `Kvartz.app` to your Applications folder.
3. Open `Kvartz.app` once. Because this build is not notarized, macOS may block the first launch.
4. Open **System Settings → Privacy & Security**, scroll to **Security**, then click **Open Anyway** beside Kvartz.
5. Confirm by clicking **Open**. macOS saves Kvartz as an exception, so future launches work normally.

Only override Gatekeeper for a copy downloaded from this repository. Do not disable Gatekeeper globally. See [Apple's guidance for opening an app from an unidentified developer](https://support.apple.com/102445).

- Default shortcut: `⌥Space`

## Build from source

Requires Xcode 16 or later.

```sh
./scripts/build-app.sh
open dist/Kvartz.app
```

To create a ZIP for Apple Silicon Macs:

```sh
./scripts/build-public.sh
```
