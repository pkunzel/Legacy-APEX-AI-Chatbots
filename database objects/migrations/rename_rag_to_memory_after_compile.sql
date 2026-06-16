/**
 * @file rename_rag_to_memory_after_compile.sql
 * @description Run after BOT_MEMORY, BOT_AGENT, BOT_TOOL_RUNNER, and
 *              CB_CHATBOT_CONVERSATIONS_BIU compile cleanly.
 */

begin
   execute immediate 'drop package bot_rag';
exception
   when others then
      if sqlcode != -4043 then
         raise;
      end if;
end;
/
