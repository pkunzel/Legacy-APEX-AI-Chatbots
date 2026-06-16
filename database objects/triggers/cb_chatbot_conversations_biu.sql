/**
 * @file cb_chatbot_conversations_biu.sql
 * @description Maintains message embeddings for chatbot conversation rows.
 * @module cb_chatbot_conversations_biu
 * @dependencies cb_chatbot_conversations, bot_rag
 */
create or replace trigger cb_chatbot_conversations_biu
before insert or update of message
on cb_chatbot_conversations
for each row
begin
   if :new.message is not null then
      :new.message_vector := bot_rag.embed_message(:new.message);
   else
      :new.message_vector := null;
   end if;
end;
/
