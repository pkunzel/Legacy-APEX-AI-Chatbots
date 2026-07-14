create or replace trigger cb_chatbot_conversations_biu
before insert or update of message
on cb_chatbot_conversations
for each row
begin
   if :new.message is not null then
      :new.message_embedding := cb_memory.embed_message(
         p_message    => :new.message,
         p_chatbot_id => :new.chatbot_id
      );
   else
      :new.message_embedding := null;
   end if;
end;
/
