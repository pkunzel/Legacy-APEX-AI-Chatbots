set define off
set echo on
set feedback on
set serveroutput on size unlimited

prompt Dropping legacy BOT_* database objects

declare
   procedure drop_object (
      p_object_type in varchar2,
      p_object_name in varchar2
   ) is
      l_sql varchar2(200);
   begin
      l_sql := 'drop ' || p_object_type || ' ' || p_object_name;

      if p_object_type = 'type' then
         l_sql := l_sql || ' force';
      end if;

      execute immediate l_sql;
      dbms_output.put_line('Dropped legacy object ' || upper(p_object_type) || ' ' || upper(p_object_name));
   exception
      when others then
         if sqlcode = -4043 then
            dbms_output.put_line('Legacy object not found: ' || upper(p_object_type) || ' ' || upper(p_object_name));
         else
            raise;
         end if;
   end drop_object;
begin
   drop_object('package', 'bot_agent');
   drop_object('package', 'bot_tool_runner');
   drop_object('package', 'bot_memory');
   drop_object('package', 'bot_adapter_claude');
   drop_object('package', 'bot_adapter_openai');
   drop_object('package', 'bot_agent_util');

   drop_object('type', 'bot_claude_provider_t');
   drop_object('type', 'bot_openai_provider_t');
   drop_object('type', 'bot_provider_t');
end;
/

prompt Legacy BOT_* cleanup completed
