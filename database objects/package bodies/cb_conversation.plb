/**
 * @file cb_conversation.plb
 * @description Conversation lifecycle implementation for submitting chat turns,
 *              archiving, and clearing actions.
 * @module cb_conversation
 * @dependencies cb_agent, cb_chatbots, cb_chatbot_conversations,
 *               cb_chatbot_archives, cb_chatbot_images, cb_logs, cb_memory,
 *               APEX_DEBUG, DBMS_LOB,
 *               DBMS_UTILITY
 * @notes The package does not commit. The caller controls transaction boundaries.
 */
create or replace package body cb_conversation as

   /**
    * @procedure validate_chatbot
    * @description Validates that a non-null chatbot identifier exists.
    */
   procedure validate_chatbot (
      p_chatbot_id in number
   ) is
      l_chatbot_id cb_chatbots.id%type;
   begin
      if p_chatbot_id is null then
         raise_application_error(-20001, 'Chatbot ID cannot be null');
      end if;

      select id
        into l_chatbot_id
        from cb_chatbots
       where id = p_chatbot_id;
   exception
      when no_data_found then
         raise_application_error(-20001, 'Chatbot not found: ' || p_chatbot_id);
   end validate_chatbot;

   /**
    * @procedure clear_live_conversation
    * @description Deletes live conversation rows and clears the running summary.
    */
   procedure clear_live_conversation (
      p_chatbot_id in number
   ) is
   begin
      delete from cb_chatbot_conversations
       where chatbot_id = p_chatbot_id;

      update cb_chatbots
         set current_summary = null
       where id = p_chatbot_id;
   end clear_live_conversation;

   /**
    * @function is_nonblank
    * @description Returns whether text contains at least one non-whitespace character.
    */
   function is_nonblank (
      p_message in varchar2
   ) return boolean is
   begin
      return p_message is not null
         and regexp_like(p_message, '[^[:space:]]');
   end is_nonblank;

   /**
    * @function get_chatbot_image
    * @description Returns the chatbot display image when it exists.
    */
   function get_chatbot_image (
      p_chatbot_id in cb_chatbots.id%type
   ) return cb_chatbots.image%type is
      l_image cb_chatbots.image%type;
   begin
      select image
        into l_image
        from cb_chatbots
       where id = p_chatbot_id;

      return l_image;
   exception
      when no_data_found then
         return null;
   end get_chatbot_image;

   /**
    * @function get_latest_user_message_id
    * @description Returns the newest live user-message identifier for a chatbot.
    */
   function get_latest_user_message_id (
      p_chatbot_id in number
   ) return cb_chatbot_conversations.id%type is
      l_user_message_id cb_chatbot_conversations.id%type;
   begin
      select id
        into l_user_message_id
        from (
           select id
             from cb_chatbot_conversations
            where chatbot_id = p_chatbot_id
              and lower(role) = 'user'
            order by id desc
       )
       where rownum = 1;

      return l_user_message_id;
   exception
      when no_data_found then
         raise_application_error(
            -20001,
            'A user message is required before requesting a response.'
         );
   end get_latest_user_message_id;

   /**
    * @procedure generate_and_store_reply
    * @description Generates an assistant reply through CB_AGENT and stores it as
    *              the next live conversation row.
    */
   procedure generate_and_store_reply (
      p_model_id             in cb_ai_models.id%type,
      p_chatbot_id           in cb_chatbots.id%type,
      p_user_message_id      in cb_chatbot_conversations.id%type,
      p_recall_message_count in number,
      p_max_tokens           in number
   ) is
      l_reply             clob;
      l_assistant_message cb_chatbot_conversations.message%type;
      l_image_search_term cb_chatbot_conversations.image_search_term%type;
   begin
      l_reply := cb_agent.get_text_response(
         p_model_id             => p_model_id,
         p_bot_id               => p_chatbot_id,
         p_current_message_id   => p_user_message_id,
         p_recall_message_count => p_recall_message_count,
         p_max_tokens           => p_max_tokens
      );

      l_assistant_message := dbms_lob.substr(l_reply, 8000, 1);
      l_image_search_term := cb_agent.get_image_definition(
         p_bot_id             => p_chatbot_id,
         p_assistant_response => l_assistant_message
      );

      insert into cb_chatbot_conversations (
         chatbot_id,
         role,
         message,
         image_search_term,
         image_search_term_embedding
      ) values (
         p_chatbot_id,
         'assistant',
         l_assistant_message,
         l_image_search_term,
         cb_memory.embed_message(
            p_message    => l_image_search_term,
            p_chatbot_id => p_chatbot_id
         )
      );
   end generate_and_store_reply;

   procedure submit_turn (
      p_model_id             in cb_ai_models.id%type,
      p_chatbot_id           in cb_chatbots.id%type,
      p_user_message         in cb_chatbot_conversations.message%type default null,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null
   ) is
      l_user_message_id cb_chatbot_conversations.id%type;
   begin
      validate_chatbot(p_chatbot_id);

      if is_nonblank(p_user_message) then
         insert into cb_chatbot_conversations (
            chatbot_id,
            role,
            message
         ) values (
            p_chatbot_id,
            'user',
            p_user_message
         )
         returning id into l_user_message_id;
      else
         l_user_message_id := get_latest_user_message_id(p_chatbot_id);
      end if;

      generate_and_store_reply(
         p_model_id             => p_model_id,
         p_chatbot_id           => p_chatbot_id,
         p_user_message_id      => l_user_message_id,
         p_recall_message_count => p_recall_message_count,
         p_max_tokens           => p_max_tokens
      );
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_conversation.submit_turn: '
            || dbms_utility.format_error_stack
         );
         raise;
   end submit_turn;

   /**
    * @function get_current_image_blob
    * @description Selects the image nearest to the latest assistant image-search
    *              term embedding.
    */
   function get_current_image_blob (
      p_chatbot_id in cb_chatbots.id%type
   ) return cb_chatbots.image%type is
      l_image cb_chatbots.image%type;
   begin
      select image
        into l_image
        from (
           select i.image
             from cb_chatbot_images i
             cross join (
                select image_search_term_embedding
                  from (
                     select image_search_term_embedding
                       from cb_chatbot_conversations
                      where chatbot_id = p_chatbot_id
                        and lower(role) = 'assistant'
                        and image_search_term_embedding is not null
                      order by id desc
                  )
                 where rownum = 1
             ) r
            where i.chatbot_id = p_chatbot_id
              and i.image_definition_embedding is not null
            order by i.image_definition_embedding <=> r.image_search_term_embedding
        )
       where rownum = 1;

      return l_image;
   exception
      when no_data_found then
         return null;
      when others then
         apex_debug.error(
            'Unexpected error in cb_conversation.get_current_image_blob: '
            || dbms_utility.format_error_stack
         );

         begin
            insert into cb_logs (
               chatbot_id,
               error,
               location
            ) values (
               p_chatbot_id,
               dbms_utility.format_error_stack
               || dbms_utility.format_error_backtrace,
               'cb_conversation.get_current_image_blob'
            );
         exception
            when others then
               apex_debug.error(
                  'Unexpected error while logging image-selection failure: '
                  || dbms_utility.format_error_stack
               );
         end;

         return null;
   end get_current_image_blob;

   /**
    * @procedure archive_chat
    * @description Captures the live conversation and chatbot metadata in one archive row.
    */
   procedure archive_chat (
      p_id_chat_bot in number
   ) is
      l_messages      clob;
      l_system_prompt cb_chatbots.prompt%type;
      l_bot_name      cb_chatbots.name%type;
   begin
      if p_id_chat_bot is null then
         raise_application_error(-20001, 'Chatbot ID cannot be null');
      end if;

      select prompt,
             name
        into l_system_prompt,
             l_bot_name
        from cb_chatbots
       where id = p_id_chat_bot;

      select json_arrayagg(
                 json_object(
                    'chat_id' value id,
                    'role'    value role,
                    'message' value message,
                    'created' value to_char(created, 'yyyy-mm-dd"T"hh24:mi:ss')
                    returning clob
                 )
                 order by created,
                          id
                 returning clob
             )
        into l_messages
        from cb_chatbot_conversations
       where chatbot_id = p_id_chat_bot;

      if l_messages is null then
         return;
      end if;

      insert into cb_chatbot_archives (
         chatbot_id,
         messages,
         system_prompt,
         bot_name
      ) values (
         p_id_chat_bot,
         l_messages,
         l_system_prompt,
         l_bot_name
      );
   exception
      when no_data_found then
         raise_application_error(-20001, 'Chatbot not found: ' || p_id_chat_bot);
      when others then
         apex_debug.error(
            'Unexpected error in cb_conversation.archive_chat: '
            || dbms_utility.format_error_stack
         );
         raise;
   end archive_chat;

   /**
    * @procedure clear_conversation
    * @description Validates the chatbot and clears its live conversation state.
    */
   procedure clear_conversation (
      p_chatbot_id in number
   ) is
   begin
      validate_chatbot(p_chatbot_id);
      clear_live_conversation(p_chatbot_id);
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_conversation.clear_conversation: '
            || dbms_utility.format_error_stack
         );
         raise;
   end clear_conversation;

end cb_conversation;
/
