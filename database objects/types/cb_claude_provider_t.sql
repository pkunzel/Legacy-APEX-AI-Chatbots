/**
 * @file cb_claude_provider_t.sql
 * @description Concrete Anthropic/Claude provider subtype.
 * @module cb_claude_provider_t
 * @dependencies cb_provider_t
 * @notes Handles Anthropic Messages API endpoints. The caller supplies endpoint
 *        URL, API key, model, and token limit.
 */
create or replace type cb_claude_provider_t under cb_provider_t (
   overriding member function get_signature_type return varchar2,

   overriding member function get_provider_name return varchar2,

   overriding member function get_text_response (
      p_system_prompt    in clob,
      p_history_messages in clob,
      p_user_message     in clob
   ) return clob
) final;
/
