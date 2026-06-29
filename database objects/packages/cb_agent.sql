/**
 * @file cb_agent.sql
 * @description Public facade package for routing chatbot requests through a
 *              polymorphic provider object hierarchy.
 * @module cb_agent
 * @dependencies cb_ai_models, cb_chatbots, cb_chatbot_conversations, APEX_DEBUG,
 *               cb_agent_util, cb_memory, cb_tool_runner, cb_provider_t,
 *               cb_openai_provider_t, cb_claude_provider_t
 * @notes Migration-safe database object. Supports caller-supplied provider
 *        parameters and model-table lookup through CB_AI_MODELS.
 */
create or replace package cb_agent as
   -- Signature families and caller-friendly aliases supported by the gateway.
   gc_signature_openai            constant varchar2(30) := 'OPENAI';
   gc_signature_openai_compatible constant varchar2(30) := 'OPENAI_COMPATIBLE';
   gc_signature_anthropic         constant varchar2(30) := 'ANTHROPIC';

   -- Provider-specific token defaults used when p_max_tokens is omitted.
   gc_openai_max_tokens constant number := 8000;
   gc_claude_max_tokens constant number := 4000;
   gc_max_tool_steps    constant number := 5;

   /**
    * @function get_text_response
    * @description Builds conversation context, creates the requested provider subtype,
    *              dispatches through cb_provider_t, and returns assistant text.
    * @param p_signature_type Signature family: OPENAI or ANTHROPIC.
    * @param p_url Provider endpoint URL.
    * @param p_api_key Provider credential/header value.
    * @param p_model Provider model identifier.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_current_message_id Current saved user-message row from cb_chatbot_conversations.
    * @param p_recall_message_count Number of older summarized messages to recall through conversation memory.
    * @param p_max_tokens Optional maximum response tokens. Defaults by signature type.
    * @param p_max_tool_steps Maximum tool calls allowed when the bot has tools.
    * @returns CLOB containing assistant text or provider response parse diagnostics.
    */
   function get_text_response (
      p_signature_type       in varchar2,
      p_url                  in varchar2,
      p_api_key              in varchar2,
      p_model                in varchar2,
      p_bot_id               in number,
      p_current_message_id   in number,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null,
      p_max_tool_steps       in number default gc_max_tool_steps
   ) return clob;

   /**
    * @function get_text_response
    * @description Loads provider details from cb_ai_models, then delegates to
    *              the provider-neutral text response flow.
    * @param p_model_id AI model configuration ID from cb_ai_models.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_current_message_id Current saved user-message row from cb_chatbot_conversations.
    * @param p_recall_message_count Number of older summarized messages to recall through conversation memory.
    * @param p_max_tokens Optional maximum response tokens. Overrides cb_ai_models.max_tokens when provided.
    * @param p_max_tool_steps Maximum tool calls allowed when the bot has tools.
    * @returns CLOB containing assistant text or provider response parse diagnostics.
    */
   function get_text_response (
      p_model_id             in number,
      p_bot_id               in number,
      p_current_message_id   in number,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null,
      p_max_tool_steps       in number default gc_max_tool_steps
   ) return clob;

   /**
    * @function create_summary
    * @description Summarizes older unsummarized conversation rows, appends the
    *              raw model summary to cb_chatbots.current_summary, and marks
    *              summarized rows as summarized.
    * @param p_signature_type Signature family: OPENAI or ANTHROPIC.
    * @param p_url Provider endpoint URL.
    * @param p_api_key Provider credential/header value.
    * @param p_model Provider model identifier for the summary call.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_keep_latest_message_count Number of latest unsummarized rows to keep live.
    * @param p_max_tokens Optional maximum response tokens. Defaults by signature type.
    * @returns CLOB containing the new raw summary text, or null when nothing is eligible.
    */
   function create_summary (
      p_signature_type             in varchar2,
      p_url                        in varchar2,
      p_api_key                    in varchar2,
      p_model                      in varchar2,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   ) return clob;

   /**
    * @function create_summary
    * @description Loads provider details from cb_ai_models, summarizes older
    *              conversation rows, appends the raw model summary, and marks
    *              summarized rows as summarized.
    * @param p_model_id AI model configuration ID from cb_ai_models.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_keep_latest_message_count Number of latest unsummarized rows to keep live.
    * @param p_max_tokens Optional maximum response tokens. Overrides cb_ai_models.max_tokens when provided.
    * @returns CLOB containing the new raw summary text, or null when nothing is eligible.
    */
   function create_summary (
      p_model_id                   in number,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   ) return clob;

end cb_agent;
/
