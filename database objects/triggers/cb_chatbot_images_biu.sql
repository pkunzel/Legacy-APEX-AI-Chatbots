create or replace trigger cb_chatbot_images_biu
before insert or update of image_definition
on cb_chatbot_images
for each row
begin
   if :new.image_definition is not null then
      :new.image_definition_embedding := cb_memory.embed_message(
         p_message    => :new.image_definition,
         p_chatbot_id => :new.chatbot_id
      );
   else
      :new.image_definition_embedding := null;
   end if;
end;
/
