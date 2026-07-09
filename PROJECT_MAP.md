# AI Chatbots Database Project Map

This is the entry point for the database-object documentation. The details are
split by purpose so it is easier to tell current behavior from future plans and
open work.

## Start Here

- [Current State](docs/current-state.md): what the Phase 1 database code is
  expected to do now.
- [Object Map](docs/object-map.md): tables, packages, types, triggers, and
  install order.
- [Target State](docs/target-state.md): where the proof of concept is intended
  to go after the current phase.
- [TODO And Risks](docs/todo-and-risks.md): missing work, known conflicts,
  bugs, and open decisions.

## Current Phase

Phase 1 is focused on database objects and business rules for an Oracle
Database / APEX-oriented chatbot proof of concept.

The current goal is to allow a caller to create multiple chatbots, talk to each
bot, persist user and assistant messages, summarize older conversation rows into
memory, and recall summarized memory through vectors. The APEX application layer
is intentionally not stored here yet.

For the current implementation, tools and raw database-stored credentials are
accepted proof-of-concept scaffolding rather than production-ready security or
agent orchestration.
