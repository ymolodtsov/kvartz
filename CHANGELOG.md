# Changelog

## 0.1.5

- Fix answers freezing after their first few characters while the query panel resizes. Conversation rows now observe answer updates directly.
- Limit answer reveals to 40 layout updates and reuse unchanged Markdown views.
- Increase provider output budgets and report incomplete responses as retryable errors instead of displaying them as finished answers.
- Bound Codex executable probes and idle sessions; drain final output before ending a session and distinguish server requests from client replies.
- Keep manually entered model IDs as drafts until Save; trim saved model IDs and preserve the previous choice when the field is blank.
- Ignore image drops that finish after their conversation is closed, reduce individual upload sizes, and cap preview-cache memory.
- Clamp the panel width when opening on a narrow display.

Validation: 64 tests, including native rendered-text assertions, follow-ups, retry handling, long-answer scrolling, all HTTP provider adapters with local fixtures, and a handshake with the installed Codex app-server.

```sh
KVARTZ_UI_SNAPSHOTS=/tmp/kvartz-ui KVARTZ_TEST_INSTALLED_CODEX=1 swift test
./scripts/build-public.sh
```

The HTTP output-budget and completion-status handling follows the [OpenAI Responses documentation](https://developers.openai.com/api/docs/guides/reasoning), [Claude Messages reference](https://platform.claude.com/docs/en/api/messages/create), and [Gemini generation reference](https://ai.google.dev/api/generate-content). Codex transport handling follows the [app-server protocol](https://learn.chatgpt.com/docs/app-server).
