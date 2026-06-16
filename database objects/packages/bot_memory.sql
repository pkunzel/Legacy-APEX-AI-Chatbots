/**
 * @file bot_memory.sql
 * @description Conversation memory helpers for semantic recall of summarized messages.
 * @module bot_memory
 * @dependencies APEX_AI, APEX_DEBUG, DBMS_UTILITY
 * @notes Keeps embedding generation outside table triggers and outside the
 *        provider adapters. This package repairs summary degradation by
 *        recalling older summarized conversation messages when they are
 *        semantically relevant to the current turn.
 */
create or replace package bot_memory as
   gc_embedding_service_static_id constant varchar2(255) := 'onnx-model';

   /**
    * @function embed_message
    * @description Returns a vector embedding for nonblank message text.
    * @param p_message Message text to embed.
    * @param p_service_static_id APEX AI service static ID for the embedding model.
    * @returns VECTOR embedding, or null when p_message is null/blank.
    */
   function embed_message (
      p_message           in varchar2,
      p_service_static_id in varchar2 default gc_embedding_service_static_id
   ) return vector;

   /**
    * @function get_recalled_messages
    * @description Returns summarized conversation messages relevant to the query embedding.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_query_embedding Current user-message embedding.
    * @param p_max_messages Maximum number of recalled messages to return.
    * @returns CLOB with one message per line, or null when no recalled messages exist.
    */
   function get_recalled_messages (
      p_bot_id          in number,
      p_query_embedding in vector,
      p_max_messages    in number default 10
   ) return clob;

end bot_memory;
/
