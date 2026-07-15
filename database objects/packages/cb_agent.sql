/**
 * @file cb_agent.sql
 * @description Public facade package for routing chatbot requests through a
 *              polymorphic provider object hierarchy.
 * @module cb_agent
 * @dependencies cb_ai_models, cb_chatbots, cb_chatbot_conversations, cb_logs, APEX_DEBUG,
 *               cb_agent_util, cb_memory, cb_provider_t,
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
    * @returns CLOB containing assistant text or provider response parse diagnostics.
    *          Chat responses longer than CB_CHATBOT_CONVERSATIONS.MESSAGE are
    *          logged and rejected; summaries remain CLOB-based.
    */
   function get_text_response (
      p_signature_type       in varchar2,
      p_url                  in varchar2,
      p_api_key              in varchar2,
      p_model                in varchar2,
      p_bot_id               in number,
      p_current_message_id   in number,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null
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
    * @returns CLOB containing assistant text or provider response parse diagnostics.
    *          Chat responses longer than CB_CHATBOT_CONVERSATIONS.MESSAGE are
    *          logged and rejected; summaries remain CLOB-based.
    */
   function get_text_response (
      p_model_id             in number,
      p_bot_id               in number,
      p_current_message_id   in number,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null
   ) return clob;

   /**
    * @function get_image_definition
    * @description Uses the chatbot image-definition prompt and configured image
    *              model to derive a concise image-search term from an assistant
    *              response. Failures are logged and returned as null.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_assistant_response Assistant response from which to derive the term.
    * @returns Image-search term, or null when the input is blank or generation fails.
    */
   function get_image_definition (
      p_bot_id             in cb_chatbots.id%type,
      p_assistant_response in cb_chatbot_conversations.message%type
   ) return cb_chatbot_conversations.image_search_term%type;

   /**
    * @procedure create_summary
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
    */
   procedure create_summary (
      p_signature_type             in varchar2,
      p_url                        in varchar2,
      p_api_key                    in varchar2,
      p_model                      in varchar2,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   );

   /**
    * @procedure create_summary
    * @description Loads provider details from cb_ai_models, summarizes older
    *              conversation rows, appends the raw model summary, and marks
    *              summarized rows as summarized.
    * @param p_model_id AI model configuration ID from cb_ai_models.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_keep_latest_message_count Number of latest unsummarized rows to keep live.
    * @param p_max_tokens Optional maximum response tokens. Overrides cb_ai_models.max_tokens when provided.
    */
   procedure create_summary (
      p_model_id                   in number,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   );

end cb_agent;
/
