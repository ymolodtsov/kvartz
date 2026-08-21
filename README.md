# Kvartz

Kvartz is a small native macOS menu-bar utility for short LLM queries. Press a global shortcut, type a question, and read a compact Markdown response in a floating black-glass panel.

## Included providers

- OpenAI (Responses API)
- Anthropic
- Google Gemini
- Qwen
- Kimi
- GLM
- OpenRouter
- Ollama
- OpenAI Codex via the local `codex app-server` and ChatGPT sign-in

API keys are stored in macOS Keychain. Provider models, base URLs, and the global shortcut are configurable.

## Build

Requires macOS 14 or later and Xcode 16 or later.

```sh
./scripts/build-app.sh
open dist/Kvartz.app
```

The script creates an ad-hoc signed app at `dist/Kvartz.app`. For distribution, replace the ad-hoc signature with your Developer ID and notarize the bundle.

To create a ZIP for Apple Silicon Macs:

```sh
./scripts/build-public.sh
```

By default, the public build is ad-hoc signed. Set `CODE_SIGN_IDENTITY` to a Developer ID Application certificate name to produce a hardened, timestamped distribution signature. Apple notarization still requires configured notary credentials.

## Interaction

- Default shortcut: `⌥Space`
- Return: submit
- Shift–Return: insert a new line
- Escape: hide Kvartz when the input field is empty
- The editor and panel grow with their content
- Ask follow-up questions without losing the conversation context
- Edit the response prompt under Settings → General
- The panel stays open until you click ×
