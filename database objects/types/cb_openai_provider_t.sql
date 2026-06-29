/**
 * @file cb_openai_provider_t.sql
 * @description Concrete OpenAI-compatible provider subtype.
 * @module cb_openai_provider_t
 * @dependencies cb_provider_t
 * @notes Handles OpenAI and OpenAI-compatible endpoints. The caller supplies
 *        endpoint URL, API key/header value, model, and token limit.
 */
create or replace type cb_openai_provider_t under cb_provider_t (
   overriding member function get_signature_type return varchar2,

   overriding member function get_provider_name return varchar2,

   overriding member function get_text_response (
      p_system_prompt    in clob,
      p_history_messages in clob,
      p_user_message     in clob
   ) return clob
) final;
/
