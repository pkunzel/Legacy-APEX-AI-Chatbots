---
name: sql-plsql-standards
description: Apply this project's SQL and PL/SQL API, documentation, and approval standards. Use whenever writing, reviewing, modifying, debugging, or planning SQL or PL/SQL, including DDL, DML, packages, package bodies, types, triggers, and APEX PL/SQL processes.
---

# SQL and PL/SQL Standards

Follow these rules for every SQL or PL/SQL task in this project.

## API design

- Do not use procedures with `OUT` or `IN OUT` parameters to return values.
- Return one value with a function.
- Return multiple values with one JSON object. Use `JSON_OBJECT_T` for PL/SQL-only callers; return JSON as a `CLOB` when the caller boundary requires a SQL/APEX-compatible scalar value.
- Keep procedures for commands that have no return value.
- Do not add parameters, return values, or behaviors that the caller did not request.

## Documentation and structure

- Follow the documentation style in `database objects/package bodies/cb_agent.plb`.
- Start database source files with a block containing `@file`, `@description`, `@module`, `@dependencies`, and relevant `@notes`.
- Document public package members with Javadoc-style blocks using `@procedure` or `@function`, `@description`, `@param`, and `@returns` where applicable.
- Keep implementation helpers private unless another package genuinely needs them.

## Table design

- Every table must define a primary key. Use the project's standard identity `ID` column and a named primary-key constraint unless the user explicitly requires a different key design.

## Approval gates

- If analysis, review, diagnosis, or planning indicates that a database object must be updated or deleted, stop and ask for explicit user approval before modifying any database object or its source file.
- Treat tables, views, packages, package bodies, types, triggers, indexes, constraints, and other schema objects as database objects.
- If a requested design conflicts with these standards, stop and explain the conflict. Ask whether the user wants to override the standard; do not silently implement the exception.
- Once approved, implement only the requested, approved scope and preserve the caller's transaction ownership unless explicitly told otherwise.
