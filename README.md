# Legacy AI Chatbots

Oracle Database and APEX-oriented chatbot proof of concept for a single APEX application for applications unable to run APEX 26.1

The project stores:

- chatbot definitions and prompts
- AI model connection settings
- conversation messages and embeddings
- optional chatbot-specific tools

It exposes one main facade package, `CB_AGENT`, which routes a request to either an OpenAI-compatible adapter or an Anthropic/Claude-compatible adapter.

## What This Project Does

The current design is intentionally provider-neutral:

1. The APEX app saves the user message to `CB_CHATBOT_CONVERSATIONS`.
2. The app calls `CB_AGENT` with either a model configuration row or direct provider details.
3. `CB_AGENT` loads the bot prompt, current summary, unsummarized history, and recalled summarized messages.
4. If tools are enabled for the bot, `CB_AGENT` can enter a bounded tool loop through `CB_TOOL_RUNNER`.
5. The provider subtype delegates request construction and HTTP execution to `CB_ADAPTER_OPENAI` or `CB_ADAPTER_CLAUDE`.
6. `CB_AGENT.get_text_response` returns assistant text only.
7. The APEX app inserts the assistant message after the call.
8. `CB_AGENT.create_summary` summarizes older conversation rows and appends the raw summary to `CB_CHATBOTS.CURRENT_SUMMARY`.

## Repository Layout

The scripts are grouped by object type:

- `database objects/tables/`
- `database objects/types/`
- `database objects/type bodies/`
- `database objects/packages/`
- `database objects/package bodies/`
- `database objects/triggers/`

Key objects:

| Object | Purpose |
| --- | --- |
| `CB_CHATBOTS` | Stores chatbot definitions, prompts, welcome text, and running summary text. |
| `CB_AI_MODELS` | Stores provider URL, API key, model name, signature type, and optional default token limit. |
| `CB_CHATBOT_CONVERSATIONS` | Stores conversation messages, role, embedding, summary flag, and timestamps. |
| `CB_TOOLS` | Stores chatbot-owned tool definitions exposed to the LLM. |
| `CB_PROVIDER_T` | Abstract provider contract used for polymorphic dispatch. |
| `CB_OPENAI_PROVIDER_T` | Concrete OpenAI-compatible provider subtype. |
| `CB_CLAUDE_PROVIDER_T` | Concrete Anthropic/Claude provider subtype. |
| `CB_AGENT` | Public facade for chat responses and summaries. |
| `CB_AGENT_UTIL` | Shared validation, JSON, and HTTP helper package. |
| `CB_MEMORY` | Embedding and semantic recall helpers. |
| `CB_TOOL_RUNNER` | Tool registry and execution facade. |
| `CB_CHATBOT_CONVERSATIONS_BIU` | Trigger that maintains message embeddings. |

## Runtime Flow

### Chat

`CB_AGENT.get_text_response` expects the current saved user-message row ID, not just raw text. It uses that row to load the current embedding for memory recall, then assembles the request context in this order:

1. `CB_CHATBOTS.PROMPT`
2. `CB_CHATBOTS.CURRENT_SUMMARY`
3. recalled summarized messages
4. live unsummarized conversation rows

### Summary

`CB_AGENT.create_summary` summarizes older unsummarized rows, appends the model output to `CB_CHATBOTS.CURRENT_SUMMARY`, and marks the included rows as summarized.

### Tools

When tools are enabled for a bot, `CB_AGENT` adds a simple JSON contract to the prompt. The first implemented tool is `CONVERSATION_MEMORY`, which searches summarized conversation rows and returns relevant text to the model.

## Usage

The usual APEX flow is:

1. Insert the user message into `CB_CHATBOT_CONVERSATIONS`.
2. Call `CB_AGENT.get_text_response`.
3. Insert the assistant message returned by the function.
4. Refresh the chat region.

Typical calls use either a saved model row or direct provider details:

```sql
CB_AGENT.get_text_response(
   p_model_id           => :PXX_MODEL_ID,
   p_bot_id             => :PXX_BOT_ID,
   p_current_message_id => :PXX_MESSAGE_ID
);
```

```sql
CB_AGENT.get_text_response(
   p_signature_type     => 'OPENAI_COMPATIBLE',
   p_url                => :PXX_URL,
   p_api_key            => :PXX_API_KEY,
   p_model              => :PXX_MODEL,
   p_bot_id             => :PXX_BOT_ID,
   p_current_message_id => :PXX_MESSAGE_ID
);
```

## Install Order

There is no install driver script yet, so the objects are expected to be loaded in dependency order:

1. `tables/cb_chatbots.sql`
2. `tables/cb_ai_models.sql`
3. `tables/cb_chatbot_conversations.sql`
4. `tables/cb_tools.sql`
5. `types/cb_provider_t.sql`
6. `types/cb_openai_provider_t.sql`
7. `types/cb_claude_provider_t.sql`
8. `packages/cb_agent_util.sql`
9. `packages/cb_adapter_openai.sql`
10. `packages/cb_adapter_claude.sql`
11. `packages/cb_memory.sql`
12. `packages/cb_tool_runner.sql`
13. `packages/cb_agent.sql`
14. `type bodies/cb_openai_provider_t.plb`
15. `type bodies/cb_claude_provider_t.plb`
16. `package bodies/cb_agent_util.plb`
17. `package bodies/cb_adapter_openai.plb`
18. `package bodies/cb_adapter_claude.plb`
19. `package bodies/cb_memory.plb`
20. `package bodies/cb_tool_runner.plb`
21. `package bodies/cb_agent.plb`
22. `triggers/cb_chatbot_conversations_biu.sql`

## Dependencies

This project expects an Oracle Database and APEX environment with support for:

- `APEX_AI`
- `APEX_WEB_SERVICE`
- `APEX_DEBUG`
- `UTL_HTTP`
- object types and polymorphic methods
- the `VECTOR` datatype used for embeddings

The embedding helper uses the APEX AI service static ID `db_onnx_model`.

## Notes

- The project is scoped to one chatbot proof of concept for one APEX application.
- `CB_AGENT` does not insert assistant messages; the caller owns that step.
- Conversation memory is based on summarized rows only.
- Message embeddings are maintained by trigger, not by the provider adapters.
- `CB_AI_MODELS.API_KEY` stores the raw secret, and the packages format provider-specific headers at runtime.
- Tool execution is read-only in this POC.

## Known Gaps

- There is no install wrapper script yet.
- Vector dimensions are still flexible in `CB_CHATBOT_CONVERSATIONS.MESSAGE_EMBEDDING`.
- Network ACL, wallet, and certificate setup are not documented here yet.
- SQL export packaging and Liquibase support are not part of this repository snapshot.

## Project Map

For a deeper object-by-object breakdown, see [database objects/PROJECT_MAP.md](database%20objects/PROJECT_MAP.md).
