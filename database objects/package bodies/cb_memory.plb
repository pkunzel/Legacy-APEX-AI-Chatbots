/**
 * @file cb_memory.plb
 * @description Conversation memory package body for semantic recall of summarized messages.
 * @module cb_memory
 * @dependencies APEX_AI, APEX_DEBUG, DBMS_UTILITY
 */
create or replace package body cb_memory as

   /**
    * @function get_embedding_text
    * @description Normalizes message text accepted by APEX_AI.
    */
   function get_embedding_text (
      p_message in varchar2
   ) return varchar2 is
      l_message varchar2(4000);
   begin
      if p_message is null then
         return null;
      end if;

      l_message := p_message;

      if not regexp_like(l_message, '[^[:space:]]') then
         return null;
      end if;

      return l_message;
   end get_embedding_text;

   /**
    * @function embed_message
    * @description Generates an embedding using the configured APEX AI service.
    */
   function embed_message (
      p_message           in varchar2,
      p_service_static_id in varchar2 default gc_embedding_service_static_id
   ) return vector is
      l_message   varchar2(4000);
      l_embedding vector;
   begin
      if p_service_static_id is null then
         raise_application_error(-20001, 'Embedding service static ID cannot be null');
      end if;

      l_message := get_embedding_text(p_message);

      if l_message is null then
         return null;
      end if;

      l_embedding := apex_ai.get_vector_embeddings(
         p_value             => l_message,
         p_service_static_id => p_service_static_id
      );

      return l_embedding;
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_memory.embed_message: '
            || dbms_utility.format_error_stack
         );
         raise;
   end embed_message;

   /**
    * @procedure append_recalled_message
    * @description Appends one plain-text recalled message to the returned memory context.
    */
   procedure append_recalled_message (
      p_context in out nocopy clob,
      p_message in varchar2
   ) is
   begin
      if p_message is null then
         return;
      end if;

      if p_context is null then
         p_context := p_message;
      else
         p_context := p_context || chr(10) || p_message;
      end if;
   end append_recalled_message;

   /**
    * @function get_recalled_messages
    * @description Returns summarized conversation messages relevant to the query embedding.
    */
   function get_recalled_messages (
      p_bot_id          in number,
      p_query_embedding in vector,
      p_max_messages    in number default 10
   ) return clob is
      l_context clob;
   begin
      if p_bot_id is null then
         raise_application_error(-20001, 'Chatbot ID cannot be null');
      elsif p_query_embedding is null then
         return null;
      elsif nvl(p_max_messages, 0) <= 0 then
         return null;
      end if;

      for rec in (
         select message
           from (
              select id,
                     message,
                     vector_distance(message_embedding, p_query_embedding, cosine) distance
                from cb_chatbot_conversations
               where chatbot_id = p_bot_id
                 and is_summarized = 'Y'
                 and message is not null
                 and message_embedding is not null
               order by distance, id desc
           )
          where rownum <= p_max_messages
      )
      loop
         append_recalled_message(
            p_context => l_context,
            p_message => rec.message
         );
      end loop;

      return l_context;
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_memory.get_recalled_messages: '
            || dbms_utility.format_error_stack
         );
         raise;
   end get_recalled_messages;

end cb_memory;
/
