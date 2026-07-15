# Current State

## Goal

This project is an Oracle Database / APEX-oriented chatbot proof of concept for
token-efficient agents that can hold longer conversations while maintaining
context through summarization and vector recall.

Phase 1 focuses on database objects and business rules. The code should allow a
caller to create multiple chatbots, talk to each bot, store user and assistant
messages, summarize conversation rows into memory, and recall summarized memory
when generating future replies.

## Phase 1 Scope

- Raw provider credentials may be stored in `CB_AI_MODELS`.
- APEX application exports are not kept here yet because the target OCI
  environment is limited to APEX 24.2.
- The application layer owns screen flow, page items, button behavior, and
  model selection. `CB_CONVERSATION.submit_turn` owns the multi-step user
  message, response-generation, and assistant-message persistence workflow.
- Vector embeddings are saved in `MESSAGE_EMBEDDING` as `vector(384, float32)`
  and used for memory recall, but no vector index is required yet.
- Chatbot-owned images have text-definition embeddings in
  `IMAGE_DEFINITION_EMBEDDING`. When configured, a dedicated image-selection
  model extracts the primary product for a turn, and that concise phrase selects
  the closest image through cosine vector distance.
- Multiple end users and multiple conversation threads per bot are out of scope.
  `CHATBOT_ID` represents one conversation thread per bot for this POC.
- System instructions live only in `CB_CHATBOTS.PROMPT`; system messages are not
  stored in `CB_CHATBOT_CONVERSATIONS` for this POC.

## Confirmed Capabilities

- DML works for the core tables.
- A caller can create multiple chatbot definitions in `CB_CHATBOTS`.
- A caller can create model configurations in `CB_AI_MODELS`.
- A caller can insert, edit, and delete conversation records in
  `CB_CHATBOT_CONVERSATIONS`.
- A caller can save a user message, call `CB_AGENT.get_text_response`, receive a
  response from at least two different LLM configurations, and save the response
  as an assistant message.
- A caller can use `CB_AGENT.create_summary` to summarize older unsummarized
  messages into `CB_CHATBOTS.CURRENT_SUMMARY` and mark included rows summarized.
- A caller can archive a complete live transcript into one
  `CB_CHATBOT_ARCHIVES` row without changing the live conversation.
- An APEX BLOB item can display the image selected from the latest assistant
  response's extracted primary-product phrase, with `CB_CHATBOTS.IMAGE` as its
  fallback.

## Runtime Chat Flow

1. The caller invokes `CB_CONVERSATION.submit_turn` with a new user message, or
   with a blank message to generate another response for the latest user message.
2. `CB_CONVERSATION` saves a nonblank user message or locates the latest live
   user message for regeneration.
3. The before-row trigger populates `MESSAGE_EMBEDDING` by calling
   `CB_MEMORY.embed_message`. If embedding fails, `CB_MEMORY` writes the error
   to `CB_LOGS`, returns null, and allows the message write to continue.
4. `CB_CONVERSATION` invokes `CB_AGENT.get_text_response` using the current
   user-message row and selected `CB_AI_MODELS.ID`.
5. `CB_AGENT` recalls summarized messages through `CB_MEMORY.get_recalled_messages`.
6. `CB_AGENT` builds context from the bot prompt, current summary, recalled
   memory, and unsummarized conversation rows.
7. `CB_AGENT` creates a provider subtype and returns the assistant text.
8. `CB_CONVERSATION` saves the assistant reply to `CB_CHATBOT_CONVERSATIONS`.
9. When `IMAGE_SELECTION_MODEL_ID` is configured, `CB_AGENT.get_image_search_term`
   uses `IMAGE_SELECTION_PROMPT` with only the current user message and assistant
   reply. `CB_CONVERSATION` embeds the extracted phrase, stores it in
   `IMAGE_SEARCH_TERM`, selects the closest `CB_CHATBOT_IMAGES` definition, and
   stores its ID in `SELECTED_IMAGE_ID`.
10. On page render, an APEX BLOB item can call
    `CB_CONVERSATION.get_current_image_blob(:PXX_CHATBOT_ID)`. The function
    returns the selected image from the latest assistant response. Missing
    configuration, extraction failures, no matching image, and lookup errors
    fall back to `CB_CHATBOTS.IMAGE`.

`CB_AGENT.get_text_response` does not insert the assistant reply. Neither it nor
`CB_CONVERSATION.submit_turn` commits; transaction boundaries belong to the caller.

Chat responses are expected to fit in `CB_CHATBOT_CONVERSATIONS.MESSAGE`, which
is `VARCHAR2(8000 CHAR)`. `CB_AGENT.get_text_response` logs and raises an error
when a chat response exceeds that limit. Summary text remains `CLOB`-based.

## Retrieval Design

`CB_AGENT.get_text_response` expects the current saved user-message ID instead
of raw user text. The current user message remains part of the unsummarized
transcript, and the ID is used to load its embedding for conversation memory
recall.

Provider context is assembled in this order:

1. Bot system prompt from `CB_CHATBOTS.PROMPT`.
2. Global context from `CB_CHATBOTS.GLOBAL_CONTEXT`, when present.
3. Current summary from `CB_CHATBOTS.CURRENT_SUMMARY`, when present.
4. Recalled summarized conversation messages, when present.
5. Unsummarized conversation rows from `CB_CHATBOT_CONVERSATIONS`, including the
   current user message.

Because the current message is already in the unsummarized transcript,
`CB_AGENT` passes `null` for the adapter-level `p_user_message`. The adapters
still support a non-null `p_user_message` for direct package tests.

Conversation memory recall candidates are summarized rows only:
`IS_SUMMARIZED = 'Y'`. This keeps the live transcript and recalled memory from
duplicating each other. Both user and assistant messages are eligible for
recall.

## Summary Design

`CB_AGENT.create_summary` summarizes older unsummarized rows while preserving the
latest `p_keep_latest_message_count` unsummarized rows in live history.
Eligibility is based on `ID` order, regardless of role.

The summary call uses the same provider abstraction as chat. It loads
`CB_CHATBOTS.SUMMARY_PROMPT`, falls back to a default summary prompt when blank,
sends the eligible transcript as a single user message, appends the raw model
response to `CB_CHATBOTS.CURRENT_SUMMARY` without separators or timestamps, and
sets `IS_SUMMARIZED = 'Y'` plus `SUMMARIZED_DATE = SYSDATE` for the included
rows.

The package does not commit, so APEX or the caller controls transaction
boundaries.

## Current Decisions

| Topic | Decision |
| --- | --- |
| Scope | Multiple chatbot proof of concept with one conversation thread per bot. |
| Caller | APEX or another caller invokes `CB_CONVERSATION.submit_turn` to save a user question and its response. |
| Chat persistence | `CB_AGENT.get_text_response` only returns the model response; `CB_CONVERSATION.submit_turn` inserts user and assistant messages. |
| Conversation ordering | `ID` order is good enough for the POC. |
| Users | Multiple users are out of scope for Phase 1. |
| Providers | Calls can route through Claude or OpenAI-compatible providers such as Novita. |
| Provider strategy | Novita remains OpenAI-compatible because the project maps web-service signatures, not individual providers. |
| Credentials | `CB_AI_MODELS.API_KEY` stores the raw provider secret for now. `CB_AGENT` formats provider-specific request headers at runtime. |
| Embeddings | Generated by `CB_MEMORY` through `APEX_AI.GET_VECTOR_EMBEDDINGS` using service static ID `db_onnx_model`, then stored as `vector(384, float32)`. |
| Message storage | Conversation `MESSAGE` is capped at `VARCHAR2(8000 CHAR)` for POC simplicity. Chat responses over this limit are logged and rejected. |
| Message vectorization | Every message role is vectorized, including user and assistant rows. |
| Embedding failures | Embedding failures are logged to `CB_LOGS` and do not block conversation message DML. |
| Update behavior | Updating a message updates its vector through the trigger. It does not call the LLM or create another assistant response. |
| Assistant persistence | `CB_CONVERSATION.submit_turn` inserts the assistant message after `CB_AGENT.get_text_response`. |
| Archive behavior | `CB_CONVERSATION.archive_chat` snapshots the whole transcript as JSON in `CB_CHATBOT_ARCHIVES`; it does not delete messages or clear the running summary. |
| Clear behavior | `CB_CONVERSATION.clear_conversation` separately deletes live messages and clears `CURRENT_SUMMARY`; it does not archive first. |
| Chatbot image display | `CB_CONVERSATION` embeds the extracted primary-product phrase, selects and stores the closest same-chatbot image, and `get_current_image_blob` returns that stored image. It returns `CB_CHATBOTS.IMAGE` when no selected image can be returned. |
| Conversation memory input | Memory recall uses the saved/current message embedding provided through `p_current_message_id`. |
| Conversation memory source | Memory recall retrieves only summarized rows, while all unsummarized rows stay in live history. |
| Summary ownership | `CB_AGENT.create_summary` owns summary creation because it is not an ordinary page DML process. |
| Summary append | Summary creation appends the raw LLM summary text to `CURRENT_SUMMARY`; no timestamp header or structured separator is added. |
| Summary cutoff | Summary creation takes `p_keep_latest_message_count` and summarizes older unsummarized rows by `ID`, regardless of role. |
| Summary model | Summary creation accepts either direct provider/model parameters or a `CB_AI_MODELS` row ID. |
| Summary flags | Summary creation summarizes both user and assistant rows, then marks all included rows as summarized. |
| Delete prevention | Delete prevention is not needed for the POC. |
| Role constraint | A database role check constraint is not needed for the POC. |
| Thread model | `CHATBOT_ID` alone identifies the single conversation thread per bot. |
| System instructions | System instructions live only in `CB_CHATBOTS.PROMPT`. |
| Model configuration | Callable model configurations live in `CB_AI_MODELS`. |
| Provider signature validation | `CB_AI_MODELS.SIGNATURE_TYPE` is intentionally unconstrained; `CB_AGENT` validates signatures it can route. |
| Model selection | Model choice remains runtime/page-level. Chatbots do not store a default model ID yet. |
| Facade API | `CB_AGENT` keeps direct provider-parameter functions and adds `p_model_id` overloads for chat and summary. |
| Install target | Plain SQL Workshop install is the target for this POC. |
| File organization | Keep files grouped as they are today. |
| Script naming style | Future cleanup should normalize scripts toward unquoted lowercase DDL. |
