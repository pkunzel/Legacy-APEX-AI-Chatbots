/**
 * @file bot_adapter_openai.sql
 * @description OpenAI-compatible provider adapter package.
 * @module bot_adapter_openai
 * @dependencies bot_agent_util, APEX_DEBUG, DBMS_LOB, DBMS_UTILITY,
 *               UTL_HTTP, JSON_OBJECT_T, JSON_ARRAY_T
 * @notes Adapter-only package. It receives model, endpoint, API key, prompt,
 *        history, and user input from bot_openai_provider_t; it does not query
 *        app tables or credential stores.
 */
create or replace package bot_adapter_openai as

   /**
    * @function get_text_response
    * @description Builds an OpenAI-compatible payload, sends the request, and
    *              extracts assistant text from the provider response.
    * @param p_url Provider endpoint URL.
    * @param p_api_key Authorization header value, usually Bearer plus token.
    * @param p_model Provider model identifier.
    * @param p_system_prompt System prompt to prepend to messages.
    * @param p_history_messages JSON array CLOB containing prior role/content messages.
    * @param p_user_message Optional latest user message, appended when not already present in history.
    * @param p_max_tokens Maximum response tokens.
    * @returns CLOB containing assistant text or provider response parse diagnostics.
    */
   function get_text_response (
      p_url              in varchar2,
      p_api_key          in varchar2,
      p_model            in varchar2,
      p_system_prompt    in clob,
      p_history_messages in clob,
      p_user_message     in clob,
      p_max_tokens       in number
   ) return clob;

end bot_adapter_openai;
/
