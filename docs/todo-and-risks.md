# TODO And Risks

## Current TODO

- Verify the exact dimension returned by the `onnx-model` embedding service.
- Decide whether `MESSAGE_EMBEDDING` should stay as flexible `vector` through the
  full POC or be tightened before broader testing.
- Confirm whether the open IDE file `database objects/admin/setup_local_embedding_model.sql`
  should exist in the repository; it was not found on disk during the docs split.
- Test `CB_AGENT.create_summary` end to end after the chat flow has enough rows
  to summarize.
- Decide whether `CURRENT_SUMMARY` needs separators or timestamps between
  appended summaries.
- Add a minimal smoke-test script for the current Phase 1 flow when the package
  APIs settle.

## Known Risks

- `CB_AI_MODELS.API_KEY` stores raw provider secrets. This is accepted for Phase
  1 but is not production-ready.
- Conversation `MESSAGE` is `VARCHAR2(8000 CHAR)`. Long assistant responses may
  require truncation before insert unless the column changes to `CLOB`.
- Every message insert or update calls the embedding service through a row-level
  trigger. Bulk message repair or imports may be slow.
- No vector index exists yet, so summarized-memory recall is acceptable only for
  POC-scale data.
- `CHATBOT_ID` alone identifies a conversation thread. Real multi-user use will
  need a separate conversation/session model.
- Tool scaffolding exists, but it is not part of the current tested Phase 1 path.
- Provider calls depend on database network configuration, ACLs, wallets, and
  remote API availability.

## Documentation Watchlist

- Keep `current-state.md` aligned with tested behavior, not intended behavior.
- Keep `object-map.md` aligned with the actual DDL, especially column types.
- Move future ideas to `target-state.md` instead of mixing them into current
  design notes.
- Move bugs, conflicts, and unresolved questions to this file.

## Open Decisions

- Should system messages ever be stored in `CB_CHATBOT_CONVERSATIONS`, or should
  system instructions live only in `CB_CHATBOTS.PROMPT`?
- Should Novita remain purely OpenAI-compatible or get its own named provider
  adapter later?
- Should the first packaged deployment target be SQLcl, Liquibase, or plain SQL
  Workshop install?
- Should object files stay grouped by object type, or move toward one folder per
  database object with spec/body together?
- Should quoted uppercase DDL be preserved or normalized to unquoted lowercase
  scripts?
- Should constraints and indexes follow a stricter naming convention?
