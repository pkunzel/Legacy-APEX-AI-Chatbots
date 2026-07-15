# Target State

## Product Direction

The proof of concept should demonstrate how Oracle Database and APEX can support
token-efficient chatbot agents that maintain useful long-running context.

The mature version should support:

- Multiple configurable chatbots.
- Runtime model selection or bot-level model defaults.
- Long conversations through summary plus vector recall to improve quality of data based on the user's question.
- Stronger semantic image-selection rules, such as relevance thresholds or
  user-message/product-aware selection. The current latest-assistant-reply
  matching is implemented for the demonstration.
- APEX screens for chatbot CRUD, model configuration, conversations, summary
  actions, and chat interaction.
- Plain SQL Workshop installation for the proof of concept.

## Future Application Layer

APEX is expected to own:

- Chatbot CRUD.
- AI model CRUD.
- Conversation message CRUD.
- Chat page model selection.
- Chat page call to `CB_CONVERSATION.submit_turn` for a new user message or an
  additional response for the latest user message.
- BLOB image item query using `CB_CONVERSATION.get_current_image_blob` after a
  chat response is saved.
- Summary button or process calling `CB_AGENT.create_summary`.
- Screen refresh and error display.

APEX exports are intentionally not stored in this repo during Phase 1.

## Future Security And Operations

Future hardening should revisit:

- Moving provider secrets out of raw `CB_AI_MODELS.API_KEY` storage or encrypting
  them.
- Network ACL and HTTPS wallet setup.
- Logging policies so production debug logs do not expose sensitive endpoint or
  credential-adjacent details.
- Normalizing scripts toward unquoted lowercase DDL.

## Future Memory And Retrieval

Future memory improvements may include:

- Adding a vector index when recall volume requires it.
- Adding a cosine vector index for image-definition search when a chatbot owns
  enough images for the current filtered scan to become slow.
- Separating summary memory from raw recalled message memory if summary quality
  becomes noisy.

## Future Provider Strategy

Provider strategy can evolve by:

- Keeping Novita and similar services under the OpenAI-compatible adapter when
  their web-service signature matches.
- Adding provider-specific adapters only when options, request shape, or response
  parsing materially diverge.
- Adding model options such as temperature, top-p, response format, or provider
  thinking settings if the application needs them.
