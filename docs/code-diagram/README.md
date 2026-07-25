# Project code diagram

This folder contains a dependency-free, current-state view of the Oracle Database / APEX chatbot proof of concept.

## Open it

Open [`index.html`](index.html) directly in a browser. No server, Oracle connection, package installation, or network access is required.

The page has three views:

- **System architecture** — runtime boundaries, provider abstraction, memory, and persistence.
- **Object dependencies** — repository tables, packages, types, and triggers grouped by responsibility.
- **Chat request sequence** — the `CB_CONVERSATION.submit_turn` flow, including embeddings, recall, provider dispatch, assistant persistence, image lookup, and error behavior.

Selecting a node highlights its immediate relationships and shows links to the source SQL or PL/SQL files. `architecture.svg` is a static export of the first view for use in Markdown or presentations.

## Updating the diagram

1. Update `diagram-data.js` from the authoritative project documentation and SQL/PLB dependency declarations.
2. Keep node IDs unique within each view and make every edge endpoint refer to an existing node.
3. Keep source links relative to this folder. Encode spaces as `%20` in links.
4. Update `architecture.svg` if the default system view changes.
5. Run the validation checks below and open `index.html` at desktop and narrow widths.

## Validation checklist

- Every source link resolves to an existing repository file.
- `diagram-data.js` and the inline page script pass JavaScript syntax checks.
- All three views render with no browser console errors.
- Node selection, edge highlighting, source links, and keyboard activation work.
- The layout remains readable at approximately 1440px, 736px, and 320px widths.
- Light and dark system themes retain readable contrast.
- No credentials, endpoint secrets, or invented runtime configuration are included.

The map is based on `docs/current-state.md`, `docs/object-map.md`, and the dependency annotations in the database object files. It describes Phase 1 as implemented; future APEX screens and hardening work are not presented as current objects.
