# TODO And Risks

## Current TODO

- Verify the exact dimension returned by the `db_onnx_model` embedding service.
- Decide whether `MESSAGE_EMBEDDING` should stay as flexible `vector` through the full POC or be tightened before broader testing.
- Confirm whether the open IDE file `database objects/admin/setup_local_embedding_model.sql`
  should exist in the repository; it was not found on disk during the docs split.
- Test `CB_AGENT.create_summary` end to end after the chat flow has enough rows to summarize.
- Add a minimal smoke-test script for the current Phase 1 flow when the package APIs settle.

## Known Risks

- `CB_AI_MODELS.API_KEY` stores raw provider secrets. This is accepted for Phase 1 but is not production-ready.
- Conversation `MESSAGE` is `VARCHAR2(8000 CHAR)`. Chat responses over this limit are logged and rejected; summaries remain `CLOB`.
- Every message insert or update calls the embedding service through a row-level trigger. Bulk message repair or imports may be slow.
- No vector index exists yet, so summarized-memory recall is acceptable only for POC-scale data.
- Tool scaffolding exists, but it is not part of the current tested Phase 1 path.

## Documentation Watchlist

- Keep `current-state.md` aligned with tested behavior, not intended behavior.
- Keep `object-map.md` aligned with the actual DDL, especially column types.
- Move future ideas to `target-state.md` instead of mixing them into current design notes.
- Move bugs, conflicts, and unresolved questions to this file.

## Open Decisions

- Should constraints and indexes follow a stricter naming convention?
