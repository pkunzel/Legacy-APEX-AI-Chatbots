/**
 * @file cb_conversation.sql
 * @description Conversation lifecycle API for submitting chat turns, archiving,
 *              or clearing a chatbot's live transcript.
 * @module cb_conversation
 * @dependencies cb_agent, cb_chatbots, cb_chatbot_conversations,
 *               cb_chatbot_archives, APEX_DEBUG
 * @notes The package does not commit. The APEX caller owns the transaction.
 */
create or replace package cb_conversation as

   /**
    * @procedure submit_turn
    * @description Submits a new user message and stores its assistant response.
    *              When p_user_message is null or blank, creates a replacement
    *              response for the latest live user message instead.
    * @param p_model_id AI model configuration ID from cb_ai_models.
    * @param p_chatbot_id Chatbot identifier from cb_chatbots.
    * @param p_user_message New user message, or null/blank to regenerate.
    * @param p_recall_message_count Number of summarized messages to recall.
    * @param p_max_tokens Optional provider response token limit.
    * @param p_max_tool_steps Optional maximum agent tool calls.
    */
   procedure submit_turn (
      p_model_id             in cb_ai_models.id%type,
      p_chatbot_id           in cb_chatbots.id%type,
      p_user_message         in cb_chatbot_conversations.message%type default null,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null,
      p_max_tool_steps       in number default null
   );

   /**
    * @procedure archive_chat
    * @description Saves the complete live conversation as one archive row.
    *              It does not change live messages or the running summary.
    * @param p_id_chat_bot Chatbot identifier from cb_chatbots.
    */
   procedure archive_chat (
      p_id_chat_bot in number
   );

   /**
    * @procedure clear_conversation
    * @description Removes live conversation messages and clears the chatbot's
    *              running summary without creating an archive row.
    * @param p_chatbot_id Chatbot identifier from cb_chatbots.
    */
   procedure clear_conversation (
      p_chatbot_id in number
   );

end cb_conversation;
/
