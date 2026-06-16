/**
 * @file rename_rag_to_memory_before_compile.sql
 * @description Run before compiling the renamed conversation-memory objects.
 */

-- Drop the trigger before renaming the embedding column it references.
begin
   execute immediate 'drop trigger cb_chatbot_conversations_biu';
exception
   when others then
      if sqlcode != -4080 then
         raise;
      end if;
end;
/

declare
   l_column_count number;
begin
   select count(*)
     into l_column_count
     from user_tab_columns
    where table_name = 'CB_CHATBOT_CONVERSATIONS'
      and column_name = 'MESSAGE_VECTOR';

   if l_column_count > 0 then
      execute immediate
         'alter table cb_chatbot_conversations rename column message_vector to message_embedding';
   end if;
end;
/

alter table cb_tools
   modify (tool_type default on null 'CONVERSATION_MEMORY');

update cb_tools
   set tool_type = 'CONVERSATION_MEMORY'
 where upper(tool_type) = 'CONTEXTUAL_MEMORY';

commit;

-- After this script, compile these repository files in dependency order:
-- 1. database objects/packages/bot_memory.sql
-- 2. database objects/package bodies/bot_memory.plb
-- 3. database objects/packages/bot_agent.sql
-- 4. database objects/package bodies/bot_agent.plb
-- 5. database objects/packages/bot_tool_runner.sql
-- 6. database objects/package bodies/bot_tool_runner.plb
-- 7. database objects/triggers/cb_chatbot_conversations_biu.sql
