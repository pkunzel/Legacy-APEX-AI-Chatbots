/**
 * @file cb_claude_provider_t.sql
 * @description Concrete Anthropic/Claude provider subtype.
 * @module cb_claude_provider_t
 * @dependencies cb_provider_t
 * @notes Handles Anthropic Messages API endpoints. The caller supplies endpoint
 *        URL, API key, model, and token limit.
 */
create or replace type cb_claude_provider_t under cb_provider_t (

   /**
    * @function get_signature_type
    * @description Returns the Anthropic provider signature family.
    * @returns VARCHAR2 provider signature family.
    */
   overriding member function get_signature_type return varchar2,

   /**
    * @function get_provider_name
    * @description Returns the Anthropic-compatible provider display name.
    * @returns VARCHAR2 provider display name.
    */
   overriding member function get_provider_name return varchar2,

   /**
    * @function get_text_response
    * @description Sends a request through the Anthropic Messages API adapter.
    * @param p_system_context Provider-neutral system-context JSON.
    * @param p_history_messages Conversation history encoded for the provider.
    * @param p_user_message Current user message when not already in history.
    * @returns CLOB containing provider response text or response diagnostics.
    */
   overriding member function get_text_response (
      p_system_context   in clob,
      p_history_messages in clob,
      p_user_message     in clob
   ) return clob
) final;
/
