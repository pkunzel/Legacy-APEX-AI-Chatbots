# TODO And Risks

## Current TODO

- Confirm whether the open IDE file `database objects/admin/setup_local_embedding_model.sql`
  should exist in the repository; it was not found on disk during the docs split.
- Re-run the SQL Workshop install or object compile in the cloud schema after the
  latest `CB_LOGS`, `CB_MEMORY`, and trigger changes.
- Test that a simulated embedding failure writes to `CB_LOGS`, leaves
  `MESSAGE_EMBEDDING` null, and does not block conversation message DML.
- Test `CB_AGENT.create_summary` end to end after the chat flow has enough rows to summarize.
- Test `CB_CONVERSATION.archive_chat` and `CB_CONVERSATION.clear_conversation`
  rollback behavior and summary reset. Archive must remain non-destructive.
- Test `CB_CONVERSATION.submit_turn` for new-message, blank-message response,
  and provider-error rollback behavior.
- Test semantic image selection with a missing assistant embedding, no image
  definitions, and a missing chatbot display image; each case should yield the
  defined fallback or null without breaking page rendering.
- Add a minimal smoke-test script for the current Phase 1 flow when the package APIs settle.

## Known Risks

- `CB_AI_MODELS.API_KEY` stores raw provider secrets. This is accepted for Phase 1 but is not production-ready.
- Conversation `MESSAGE` is `VARCHAR2(8000 CHAR)`. Chat responses over this limit are logged and rejected; summaries remain `CLOB`.
- Every message insert or update calls the embedding service through a row-level trigger. Bulk message repair or imports may be slow.
- No vector index exists yet, so summarized-memory recall is acceptable only for POC-scale data.
- No image-definition vector index exists yet. The semantic image lookup filters
  by chatbot first, which is suitable for the small demonstration image set.
- `CB_LOGS` writes are part of the caller transaction. A full caller rollback also rolls back the log entry.
- Tool scaffolding exists, but it is not part of the current tested Phase 1 path.

## Next Chat Restart Notes

- Start from `PROJECT_MAP.md`, then read `docs/current-state.md` and this file.
- Treat `docs/current-state.md` as the current source of truth for Phase 1 behavior.
- The latest embedding design is: `CB_CHATBOT_CONVERSATIONS.MESSAGE_EMBEDDING`
  is `vector(384, float32)`, the APEX AI service static ID is `db_onnx_model`,
  and `CB_MEMORY.embed_message` owns embedding failure logging.
- The latest non-blocking log design is: `CB_LOGS` has no FK, indexes, or PK and
  currently stores embedding failures only.
- The next likely validation step is to compile/install in the cloud schema and
  inspect `USER_ERRORS` for `CB_MEMORY`, `CB_TOOL_RUNNER`, and
  `CB_CHATBOT_CONVERSATIONS_BIU`.

## Documentation Watchlist

- Keep `current-state.md` aligned with tested behavior, not intended behavior.
- Keep `object-map.md` aligned with the actual DDL, especially column types.
- Move future ideas to `target-state.md` instead of mixing them into current design notes.
- Move bugs, conflicts, and unresolved questions to this file.

## Open Decisions

- Should constraints and indexes follow a stricter naming convention?
