# AI Chatbots Database Object Map

## Current Understanding

This project is an Oracle Database / APEX-oriented chatbot proof of concept for one APEX application. It stores chatbot definitions, conversation messages, and optional agent tool configuration, then exposes a single facade package, `BOT_AGENT`, that routes a text request to either an OpenAI-compatible adapter or an Anthropic/Claude-compatible adapter.

The design appears intentionally provider-neutral:

1. The APEX application saves the user's question to the database before calling `BOT_AGENT`.
2. The caller supplies provider details such as signature type, endpoint URL, API key/header value, model, and token limit.
3. `BOT_AGENT` uses the saved current user message ID to load its vector, then retrieves unsummarized conversation history, relevant summarized messages, and the current summary.
4. `BOT_AGENT` creates a concrete provider object type behind the abstract `BOT_PROVIDER_T` contract.
5. The provider subtype delegates request construction, HTTP execution, and response parsing to a provider adapter package.
6. `BOT_AGENT` returns assistant responses for normal chat calls. The APEX application is responsible for inserting the assistant message after the call.
7. Shared validation, JSON message handling, and HTTP POST logic live in `BOT_AGENT_UTIL`.
8. Message embeddings are generated automatically for every message row by a conversation-table trigger that delegates to `BOT_RAG`.
9. `BOT_AGENT.create_summary` is the API used by the APEX summary button. It calls the requested provider/model, appends the raw summary to `CB_CHATBOTS.CURRENT_SUMMARY`, and marks included rows summarized.
10. Bots with no enabled tools keep the normal one-call behavior. Bots with enabled tools enter a bounded JSON tool-calling loop through `BOT_TOOL_RUNNER`.

## Object Inventory

### Tables

| Object | File | Purpose |
| --- | --- | --- |
| `CB_CHATBOTS` | `tables/cb_chatbots.sql` | Stores chatbot definitions, prompts, welcome text, summary prompt, current summary, and created date. |
| `CB_CHATBOT_CONVERSATIONS` | `tables/cb_chatbot_conversations.sql` | Stores chatbot conversation messages, message role, `VARCHAR2(4000)` message text, optional vector embedding, summary status, and created date. |
| `CB_TOOLS` | `tables/cb_tools.sql` | Stores reusable read-only agent tool definitions exposed to LLMs. |
| `CB_CHATBOT_TOOLS` | `tables/cb_chatbot_tools.sql` | Maps enabled tools to chatbots, allowing zero, one, or many tools per bot. |

### Package Specs

| Object | File | Purpose |
| --- | --- | --- |
| `BOT_AGENT` | `packages/bot_agent.sql` | Public facade API for getting provider-backed text responses and creating conversation summaries. |
| `BOT_AGENT_UTIL` | `packages/bot_agent_util.sql` | Shared validation, JSON array/message helpers, and HTTP request helper. |
| `BOT_ADAPTER_OPENAI` | `packages/bot_adapter_openai.sql` | OpenAI-compatible payload, request, and response parsing API. |
| `BOT_ADAPTER_CLAUDE` | `packages/bot_adapter_claude.sql` | Anthropic/Claude-compatible payload, request, and response parsing API. |
| `BOT_RAG` | `packages/bot_rag.sql` | Embedding/vector helper API using the APEX AI service static ID `onnx-model`. |
| `BOT_TOOL_RUNNER` | `packages/bot_tool_runner.sql` | Tool registry and execution API for optional agent behavior. |

### Package Bodies

| Object | File | Purpose |
| --- | --- | --- |
| `BOT_AGENT` | `package bodies/bot_agent.plb` | Normalizes provider signatures, fetches prompt/history, creates provider subtype, dispatches chat requests, and owns summary creation updates. |
| `BOT_AGENT_UTIL` | `package bodies/bot_agent_util.plb` | Implements shared validation, message parsing/appending, and HTTP POST behavior. |
| `BOT_ADAPTER_OPENAI` | `package bodies/bot_adapter_openai.plb` | Builds OpenAI-compatible chat-completion payloads and extracts assistant text. |
| `BOT_ADAPTER_CLAUDE` | `package bodies/bot_adapter_claude.plb` | Builds Anthropic Messages API payloads and extracts assistant text. |
| `BOT_RAG` | `package bodies/bot_rag.plb` | Calls `APEX_AI.GET_VECTOR_EMBEDDINGS` for nonblank message text. |
| `BOT_TOOL_RUNNER` | `package bodies/bot_tool_runner.plb` | Checks enabled tools, emits tool instructions, and executes contextual memory lookups. |

### Triggers

| Object | File | Purpose |
| --- | --- | --- |
| `CB_CHATBOT_CONVERSATIONS_BIU` | `triggers/cb_chatbot_conversations_biu.sql` | Populates `MESSAGE_VECTOR` before insert or message update. |

### Type Specs

| Object | File | Purpose |
| --- | --- | --- |
| `BOT_PROVIDER_T` | `types/bot_provider_t.sql` | Abstract provider contract with URL, API key, model, max tokens, and polymorphic text response methods. |
| `BOT_OPENAI_PROVIDER_T` | `types/bot_openai_provider_t.sql` | Final subtype for OpenAI-compatible calls. |
| `BOT_CLAUDE_PROVIDER_T` | `types/bot_claude_provider_t.sql` | Final subtype for Anthropic/Claude calls. |

### Type Bodies

| Object | File | Purpose |
| --- | --- | --- |
| `BOT_OPENAI_PROVIDER_T` | `type bodies/bot_openai_provider_t.plb` | Implements OpenAI provider identity and delegates text response work to `BOT_ADAPTER_OPENAI`. |
| `BOT_CLAUDE_PROVIDER_T` | `type bodies/bot_claude_provider_t.plb` | Implements Claude provider identity and delegates text response work to `BOT_ADAPTER_CLAUDE`. |

## Dependency Order

Likely install order:

1. `tables/cb_chatbots.sql`
2. `tables/cb_chatbot_conversations.sql`
3. `tables/cb_tools.sql`
4. `tables/cb_chatbot_tools.sql`
5. `types/bot_provider_t.sql`
6. `types/bot_openai_provider_t.sql`
7. `types/bot_claude_provider_t.sql`
8. `packages/bot_agent_util.sql`
9. `packages/bot_adapter_openai.sql`
10. `packages/bot_adapter_claude.sql`
11. `packages/bot_rag.sql`
12. `packages/bot_tool_runner.sql`
13. `packages/bot_agent.sql`
14. `type bodies/bot_openai_provider_t.plb`
15. `type bodies/bot_claude_provider_t.plb`
16. `package bodies/bot_agent_util.plb`
17. `package bodies/bot_adapter_openai.plb`
18. `package bodies/bot_adapter_claude.plb`
19. `package bodies/bot_rag.plb`
20. `package bodies/bot_tool_runner.plb`
21. `package bodies/bot_agent.plb`
22. `triggers/cb_chatbot_conversations_biu.sql`

## Open Issues Spotted From The Files

1. The IDE shows `database objects/README.md`, but no `README.md` currently exists on disk under `database objects`.
2. The IDE shows a root-level `database objects/cb_chabot_conversations.sql`, but the file currently exists under `database objects/tables` with the corrected name `cb_chatbot_conversations.sql`.
3. There is no install driver script by design right now; current priority is testing the individual packages as-is.
4. Credentials are caller-supplied to `BOT_AGENT` for now. A secure credential store can be revisited later.
5. `MESSAGE_VECTOR` is declared as flexible `vector` for the POC. It can be tightened to the exact ONNX model dimension later, especially before adding a vector index.

## Decisions From Interview Round 1

| Topic | Decision |
| --- | --- |
| Scope | One chatbot proof of concept for one APEX application. |
| Caller | An APEX process calls `BOT_AGENT` after saving the user question in the database. |
| Chat persistence | `BOT_AGENT.get_text_response` should only return the model response. It should not insert messages. |
| Conversation ordering | `conversation_num` was a migration workaround and has been removed from the package API/filter. |
| Users | Multiple users are out of scope for the POC. |
| Providers | Most calls will go through Claude and Novita's web server. |
| Credentials | Passed into the package for now. |
| Vectors | Generated by `BOT_RAG` through `APEX_AI.GET_VECTOR_EMBEDDINGS` and maintained by a before-row trigger. |
| Message storage | Conversation `MESSAGE` is capped at `VARCHAR2(4000 CHAR)` for POC simplicity. |
| Install driver | Not needed yet. |

## Decisions From Interview Round 2

| Topic | Decision |
| --- | --- |
| APEX scope | APEX owns chatbot CRUD, message CRUD, chat-page model selection, assistant-message insert after `BOT_AGENT.get_text_response`, and screen refresh. SQL exports are intentionally not kept here. |
| Message vectorization | Every message role is vectorized, including user and assistant rows. |
| Update behavior | Updating a message only updates its vector through the trigger. It does not call the LLM or create another assistant response. |
| Assistant persistence | `BOT_AGENT.get_text_response` returns text only; APEX inserts the assistant message. |
| Message pairing | `ID` order is good enough for the POC. |
| RAG query input | RAG uses the last saved/current message vector provided through `p_current_message_id`. |
| RAG source | RAG retrieves only summarized rows, while all unsummarized rows stay in the live history. |
| Summary ownership | `BOT_AGENT.create_summary` owns summary creation because it is not an in-page DML process. |
| Summary append | Summary creation appends the raw LLM summary text to `CURRENT_SUMMARY`; no timestamp header or structured separator is added. |
| Summary cutoff | Summary creation takes `p_keep_latest_message_count` and summarizes older unsummarized rows by `ID`, regardless of role. |
| Summary model | Summary creation accepts provider/model parameters separately from the chat call for screen-level flexibility. |
| Summary flags | Summary creation summarizes both user and assistant rows, then marks all included rows as summarized. |
| Delete prevention | Delete prevention is not needed for the POC. |
| Role constraint | A database role check constraint is not needed for the POC. |
| Thread model | `CHATBOT_ID` alone is enough to identify the single conversation thread per bot. |

## Decisions From Interview Round 3

| Topic | Decision |
| --- | --- |
| Tool scope | Tools are reusable across bots. Each bot enables a subset through `CB_CHATBOT_TOOLS`. |
| Bot-specific overrides | No bot-specific tool overrides for the POC. |
| First tool | Implement only one tool type for now: `CONTEXTUAL_MEMORY`. |
| No-tool bots | Bots with no enabled tools keep the existing chat behavior. |
| Tool decision | The LLM decides whether a tool is needed. |
| Multi-tool turns | A bot may call tools in sequence when necessary. |
| Max tool steps | A tool-enabled turn allows up to 5 tool calls by default. |
| Disabled tool requests | If the LLM requests a tool not enabled for the bot, log with `APEX_DEBUG` and ask the model to answer normally. |
| LLM contract | Use a simple JSON contract instead of native provider tool-calling for now. |
| Tool model | Tool decision and final answer use the same selected chat model. |
| Tool safety | Tools are read-only for this POC. |
| Tool limits | Tool definitions include high `MAX_ROWS` and `MAX_RESULT_CHARS` limits for future tuning. |
| Tool logging | Use `APEX_DEBUG` only for now. Dedicated run/step tables can come later. |
| Tool failure | Real tool execution failures raise an error so APEX can show it. |

## Retrieval Design

`BOT_AGENT.get_text_response` now expects the current saved user-message ID instead of the raw user text. The current user message remains part of the unsummarized transcript, and the ID is used to load its vector for RAG.

The context sent to providers is assembled in this order:

1. Bot system prompt from `CB_CHATBOTS.PROMPT`.
2. Current summary from `CB_CHATBOTS.CURRENT_SUMMARY`, when present.
3. Plain-text relevant earlier messages from RAG, when present.
4. Unsummarized conversation rows from `CB_CHATBOT_CONVERSATIONS`, including the current user message.

Because the current message is already in the unsummarized transcript, `BOT_AGENT` passes `null` for the adapter-level `p_user_message`. The adapters still support a non-null `p_user_message` for direct package tests.

RAG candidates are summarized rows only: `IS_SUMMARIZED = 'Y'`. This keeps the main live transcript and semantic recall from duplicating each other. Both user and assistant messages are eligible for RAG.

## Agent Tool Design

Tool-enabled bots use the same `BOT_AGENT.get_text_response` API as no-tool bots. `BOT_AGENT` checks `BOT_TOOL_RUNNER.has_enabled_tools`; when no tools are enabled it follows the original one-call path.

When tools are enabled, `BOT_AGENT` adds a JSON response contract to the system prompt. The model must return either:

```json
{"type":"final","message":"user-facing answer"}
```

or:

```json
{"type":"tool_call","tool_name":"contextual_memory","arguments":{"query":"focused search question"}}
```

The first implemented tool type is `CONTEXTUAL_MEMORY`. It embeds the model-selected `query`, searches summarized messages for the same bot through `BOT_RAG.GET_RELEVANT_MESSAGES`, returns the result to the LLM, and lets the LLM produce the final user-facing answer. The loop can run multiple tool calls, capped by `p_max_tool_steps` with default `5`.

## Summary Design

`BOT_AGENT.create_summary` summarizes older unsummarized rows while preserving the latest `p_keep_latest_message_count` unsummarized rows in live history. Eligibility is based on `ID` order, regardless of role.

The summary call uses the same provider abstraction as chat. It loads `CB_CHATBOTS.SUMMARY_PROMPT`, falls back to a default summary prompt when blank, sends the eligible transcript as a single user message, appends the raw model response to `CB_CHATBOTS.CURRENT_SUMMARY`, and sets `IS_SUMMARIZED = 'Y'` plus `SUMMARIZED_DATE = SYSDATE` for the included rows. The package does not commit, so APEX or the caller controls transaction boundaries.

## Remaining Interview Questions

### Product And User Context

1. Who is the primary user of this chatbot backend: APEX app users, admins, developers, or another system?
2. Is the goal a reusable chatbot framework for many bots, or a focused implementation for one application?
3. Should users be able to create and configure bots themselves, or is bot configuration developer/admin-managed only?
4. What does a successful first version need to do end to end?

### Conversation Model

1. Should system messages be stored in `CB_CHATBOT_CONVERSATIONS`, or should system instructions live only in `CB_CHATBOTS.PROMPT`?

### AI Provider Strategy

1. Should Novita be treated as OpenAI-compatible behind `BOT_ADAPTER_OPENAI`, or should it get its own named provider adapter?
2. Should `p_api_key` include the full header value, such as `Bearer ...`, or just the raw secret?
3. Do you expect provider-specific options beyond model and max tokens, such as temperature, top_p, thinking mode, tools, image input, or JSON response mode?

### Data And Vector Search

1. Which exact dimension does the `onnx-model` embedding service return?
2. Should the column be tightened from flexible `vector` to the exact model dimension before adding an index?
3. Do you need vector indexes next?

### APEX And Security

1. Which Oracle Database/APEX versions should this support?
2. Is this intended to call external HTTP APIs directly from the database using `APEX_WEB_SERVICE`, `UTL_HTTP`, or both?
3. How should network ACLs, wallets, and HTTPS certificates be handled in the install process?
4. Should debug logs ever include model names, endpoint URLs, or provider names in production?

### Packaging And Deployment

1. Should object files stay grouped by object type, or would you prefer one folder per database object with spec/body together?
2. When testing stabilizes, should this be packaged for SQLcl, Liquibase, APEX export support, or plain SQL Workshop install?

### Naming And Cleanliness

1. Do you want quoted uppercase DDL preserved, or normalized unquoted lowercase object names in scripts?
2. Should constraints and indexes follow a stricter naming convention?
3. Should public facade names use `BOT_` or a more app-specific prefix like `CB_`?
