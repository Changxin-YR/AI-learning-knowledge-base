# Agent Tool Registry

The API exposes named tools with descriptions, required JSON arguments, and read/write flags. `/agents/run` executes caller-supplied structured tool calls through service functions, validates required arguments, enforces user ownership, and records `agent_runs`/`tool_calls` audit rows. When `OPENAI_BASE_URL`, `OPENAI_API_KEY`, and `OPENAI_MODEL` are configured, the same endpoint runs up to four OpenAI-compatible assistant/tool/result turns; without those variables, clients must supply structured calls in the local demo. Memory tools use the owned `memories` table.
