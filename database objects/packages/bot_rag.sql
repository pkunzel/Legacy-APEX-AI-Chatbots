/**
 * @file bot_rag.sql
 * @description Retrieval/vector helpers for chatbot messages.
 * @module bot_rag
 * @dependencies APEX_AI, APEX_DEBUG, DBMS_UTILITY
 * @notes Keeps embedding generation outside table triggers and outside the
 *        provider adapters. The current implementation uses an APEX AI service
 *        static ID that points at an Oracle-native ONNX embedding model.
 */
create or replace package bot_rag as
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
    * @function get_relevant_messages
    * @description Returns plain-text relevant summarized messages for the query vector.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_query_vector Current user-message embedding vector.
    * @param p_max_messages Maximum number of relevant messages to return.
    * @returns CLOB with one message per line, or null when no relevant messages exist.
    */
   function get_relevant_messages (
      p_bot_id        in number,
      p_query_vector  in vector,
      p_max_messages  in number default 10
   ) return clob;

end bot_rag;
/
