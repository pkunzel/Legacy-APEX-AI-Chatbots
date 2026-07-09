# Object Map

## Tables

| Object | File | Purpose |
| --- | --- | --- |
| `CB_CHATBOTS` | `tables/cb_chatbots.sql` | Stores chatbot definitions, prompts, welcome text, summary prompt, current summary, and created date. |
| `CB_AI_MODELS` | `tables/cb_ai_models.sql` | Stores AI model connection configurations, including signature type, endpoint URL, raw API secret, provider model ID, and optional token limit. |
| `CB_CHATBOT_CONVERSATIONS` | `tables/cb_chatbot_conversations.sql` | Stores chatbot conversation messages, message role, `VARCHAR2(8000 CHAR)` message text, optional message embedding, summary status, and created date. |
| `CB_TOOLS` | `tables/cb_tools.sql` | Stores chatbot-owned read-only agent tool definitions exposed to LLMs. Tool use is optional scaffolding in Phase 1. |
| `CB_LOGS` | `tables/cb_logs.sql` | Lightweight dump table for non-blocking proof-of-concept errors, currently embedding failures. |

## Package Specs

| Object | File | Purpose |
| --- | --- | --- |
| `CB_AGENT` | `packages/cb_agent.sql` | Public facade API for getting provider-backed text responses and creating conversation summaries. |
| `CB_AGENT_UTIL` | `packages/cb_agent_util.sql` | Shared validation, JSON array/message helpers, and HTTP request helper. |
| `CB_ADAPTER_OPENAI` | `packages/cb_adapter_openai.sql` | OpenAI-compatible payload, request, and response parsing API. |
| `CB_ADAPTER_CLAUDE` | `packages/cb_adapter_claude.sql` | Anthropic/Claude-compatible payload, request, and response parsing API. |
| `CB_MEMORY` | `packages/cb_memory.sql` | Conversation memory helper API using the APEX AI service static ID `db_onnx_model` to embed messages, log embedding failures, and recall summarized messages. |
| `CB_TOOL_RUNNER` | `packages/cb_tool_runner.sql` | Tool registry and execution API for optional agent behavior. |

## Package Bodies

| Object | File | Purpose |
| --- | --- | --- |
| `CB_AGENT` | `package bodies/cb_agent.plb` | Loads optional AI model configuration, normalizes provider signatures, fetches prompt/history, creates provider subtype, dispatches chat requests, and owns summary creation updates. |
| `CB_AGENT_UTIL` | `package bodies/cb_agent_util.plb` | Implements shared validation, message parsing/appending, and HTTP POST behavior. |
| `CB_ADAPTER_OPENAI` | `package bodies/cb_adapter_openai.plb` | Builds OpenAI-compatible chat-completion payloads and extracts assistant text. |
| `CB_ADAPTER_CLAUDE` | `package bodies/cb_adapter_claude.plb` | Builds Anthropic Messages API payloads and extracts assistant text. |
| `CB_MEMORY` | `package bodies/cb_memory.plb` | Calls `APEX_AI.GET_VECTOR_EMBEDDINGS` for nonblank message text, logs embedding failures to `CB_LOGS`, and recalls relevant summarized messages. |
| `CB_TOOL_RUNNER` | `package bodies/cb_tool_runner.plb` | Checks enabled tools, emits tool instructions, and executes agent-invoked conversation memory lookups. |

## Triggers

| Object | File | Purpose |
| --- | --- | --- |
| `CB_CHATBOT_CONVERSATIONS_BIU` | `triggers/cb_chatbot_conversations_biu.sql` | Populates `MESSAGE_EMBEDDING` before insert or message update. |

## Type Specs

| Object | File | Purpose |
| --- | --- | --- |
| `CB_PROVIDER_T` | `types/cb_provider_t.sql` | Abstract provider contract with URL, API key, model, max tokens, and polymorphic text response methods. |
| `CB_OPENAI_PROVIDER_T` | `types/cb_openai_provider_t.sql` | Final subtype for OpenAI-compatible calls. |
| `CB_CLAUDE_PROVIDER_T` | `types/cb_claude_provider_t.sql` | Final subtype for Anthropic/Claude calls. |

## Type Bodies

| Object | File | Purpose |
| --- | --- | --- |
| `CB_OPENAI_PROVIDER_T` | `type bodies/cb_openai_provider_t.plb` | Implements OpenAI provider identity and delegates text response work to `CB_ADAPTER_OPENAI`. |
| `CB_CLAUDE_PROVIDER_T` | `type bodies/cb_claude_provider_t.plb` | Implements Claude provider identity and delegates text response work to `CB_ADAPTER_CLAUDE`. |

## Install Order

The current install driver is `install.sql`.

1. `tables/cb_chatbots.sql`
2. `tables/cb_ai_models.sql`
3. `tables/cb_chatbot_conversations.sql`
4. `tables/cb_tools.sql`
5. `tables/cb_logs.sql`
6. `types/cb_provider_t.sql`
7. `types/cb_openai_provider_t.sql`
8. `types/cb_claude_provider_t.sql`
9. `packages/cb_agent_util.sql`
10. `packages/cb_adapter_openai.sql`
11. `packages/cb_adapter_claude.sql`
12. `packages/cb_memory.sql`
13. `packages/cb_tool_runner.sql`
14. `packages/cb_agent.sql`
15. `type bodies/cb_openai_provider_t.plb`
16. `type bodies/cb_claude_provider_t.plb`
17. `package bodies/cb_agent_util.plb`
18. `package bodies/cb_adapter_openai.plb`
19. `package bodies/cb_adapter_claude.plb`
20. `package bodies/cb_memory.plb`
21. `package bodies/cb_tool_runner.plb`
22. `package bodies/cb_agent.plb`
23. `triggers/cb_chatbot_conversations_biu.sql`

`install.sql` also runs object-status and `USER_ERRORS` checks after installation.
