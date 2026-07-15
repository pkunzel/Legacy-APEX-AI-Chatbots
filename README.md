# Legacy AI Chatbots

Oracle Database and APEX-oriented chatbot proof of concept for a single APEX application for applications unable to run APEX 26.1

The project stores:

- chatbot definitions and prompts
- chatbot display images and searchable product images
- AI model connection settings
- conversation messages and embeddings

It exposes `CB_AGENT` for provider-backed responses and `CB_CONVERSATION` for
conversation lifecycle actions such as submitting a turn, archiving, clearing,
and selecting a contextual display image.

## What This Project Does

The current design is intentionally provider-neutral:

1. The APEX app calls `CB_CONVERSATION.submit_turn` with a message, or a blank
   message to regenerate a response for the latest user message.
2. `CB_CONVERSATION` saves a supplied user message and calls `CB_AGENT` with a
   model configuration row.
3. `CB_AGENT` loads the bot prompt, current summary, unsummarized history, and recalled summarized messages.
4. The provider subtype delegates request construction and HTTP execution to `CB_ADAPTER_OPENAI` or `CB_ADAPTER_CLAUDE`.
5. `CB_AGENT.get_text_response` returns assistant text only.
6. `CB_CONVERSATION` saves the assistant message after the call.
7. When configured, a dedicated image-selection model extracts the primary
   product from the current user message and assistant reply. The application
   vector-matches that concise phrase to image definitions, persists the chosen
   image, and an APEX BLOB item retrieves it through
   `CB_CONVERSATION.get_current_image_blob`. It falls back to the chatbot
   display image.
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
| `CB_CHATBOTS` | Stores chatbot definitions, display image metadata, prompts, welcome text, running summary text, and optional image-selection configuration. |
| `CB_CHATBOT_IMAGES` | Stores chatbot-owned images, image definitions, and definition embeddings for searchable product context. |
| `CB_AI_MODELS` | Stores provider URL, API key, model name, signature type, and optional default token limit. |
| `CB_CHATBOT_CONVERSATIONS` | Stores conversation messages, role, embedding, selected image metadata, summary flag, and timestamps. |
| `CB_CHATBOT_ARCHIVES` | Stores complete transcript snapshots as JSON, with chatbot prompt and name snapshots. |
| `CB_PROVIDER_T` | Abstract provider contract used for polymorphic dispatch. |
| `CB_OPENAI_PROVIDER_T` | Concrete OpenAI-compatible provider subtype. |
| `CB_CLAUDE_PROVIDER_T` | Concrete Anthropic/Claude provider subtype. |
| `CB_AGENT` | Public facade for chat responses and summaries. |
| `CB_CONVERSATION` | Conversation lifecycle facade for submit/regenerate, archive, clear, and contextual BLOB image retrieval. |
| `CB_AGENT_UTIL` | Shared validation, JSON, and HTTP helper package. |
| `CB_MEMORY` | Embedding and semantic recall helpers. |
| `CB_CHATBOT_CONVERSATIONS_BIU` | Trigger that maintains message embeddings. |
| `CB_CHATBOT_IMAGES_BIU` | Trigger that maintains image definition embeddings. |

## Runtime Flow

### Chat

`CB_CONVERSATION.submit_turn` saves or locates the current user-message row, then
calls `CB_AGENT.get_text_response`. The agent uses that row's embedding for
memory recall and assembles the request context in this order:

1. `CB_CHATBOTS.PROMPT`
2. `CB_CHATBOTS.GLOBAL_CONTEXT`, when present
3. `CB_CHATBOTS.CURRENT_SUMMARY`, when present
4. recalled summarized messages
5. live unsummarized conversation rows

### Image Selection

When `CB_CHATBOTS.IMAGE_SELECTION_MODEL_ID` is configured,
`CB_AGENT.get_image_search_term` calls that model with only the current user
message and generated assistant reply. It uses `IMAGE_SELECTION_PROMPT` to
extract a concise primary-product phrase. `CB_CONVERSATION` embeds that phrase,
stores it in `IMAGE_SEARCH_TERM`, selects the nearest chatbot-owned image, and
stores its ID in `SELECTED_IMAGE_ID`. An absent configuration or an image
selection failure leaves the image unset so the default chatbot image is used.

Example configuration:

```sql
update cb_chatbots
   set image_selection_model_id = :PXX_IMAGE_SELECTION_MODEL_ID,
       image_selection_prompt = q'~
Extract the primary product discussed, recommended, or presented in the chat
turn. Return only a short, specific noun phrase suitable for semantic image
search. Prefer the central product over side dishes, ingredients, sauces,
drinks, preparation methods, and serving suggestions. Word frequency does not
determine the primary product. When no exact product is stated, infer the most
likely primary product from the user message and assistant reply.
~'
 where id = :PXX_CHATBOT_ID;
```

### Summary

`CB_AGENT.create_summary` summarizes older unsummarized rows, appends the model output to `CB_CHATBOTS.CURRENT_SUMMARY`, and marks the included rows as summarized.

## Usage

The usual APEX flow is:

1. Call `CB_CONVERSATION.submit_turn`.
2. Refresh the chat and image regions.

Typical calls use either a saved model row or direct provider details:

```sql
CB_CONVERSATION.submit_turn(
   p_model_id   => :PXX_MODEL_ID,
   p_chatbot_id => :PXX_CHATBOT_ID,
   p_user_message => :PXX_MESSAGE
);
```

```sql
select cb_conversation.get_current_image_blob(:PXX_CHATBOT_ID) as image
from dual;
```

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
- `CB_AGENT` does not insert assistant messages directly; `CB_CONVERSATION.submit_turn` owns chat-turn persistence.
- Archive and clear are intentionally separate operations: archiving is non-destructive.
- When configured, semantic image selection embeds the extracted primary-product phrase rather than the full assistant reply, then selects the nearest image definition. It falls back to `CB_CHATBOTS.IMAGE`.
- Conversation memory is based on summarized rows only.
- Message embeddings are maintained by trigger, not by the provider adapters.
- `CB_AI_MODELS.API_KEY` stores the raw secret, and the packages format provider-specific headers at runtime.

## Known Gaps

- The fixed `vector(384, float32)` embedding columns require the configured
  embedding service to continue returning compatible vectors.
- Network ACL, wallet, and certificate setup are not documented here yet.
- SQL export packaging and Liquibase support are not part of this repository snapshot.

## Project Map

For a deeper object-by-object breakdown, see [database objects/PROJECT_MAP.md](database%20objects/PROJECT_MAP.md).
