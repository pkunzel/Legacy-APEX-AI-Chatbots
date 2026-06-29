set define off
set echo on
set feedback on
set serveroutput on size unlimited
set timing on

prompt Installing AI chatbot database objects

@@tables/cb_chatbots.sql
@@tables/cb_ai_models.sql
@@tables/cb_chatbot_conversations.sql
@@tables/cb_tools.sql

@@types/bot_provider_t.sql
@@types/bot_openai_provider_t.sql
@@types/bot_claude_provider_t.sql

@@packages/bot_agent_util.sql
@@packages/bot_adapter_openai.sql
@@packages/bot_adapter_claude.sql
@@packages/bot_memory.sql
@@packages/bot_tool_runner.sql
@@packages/bot_agent.sql

@@type bodies/bot_openai_provider_t.plb
@@type bodies/bot_claude_provider_t.plb

@@package bodies/bot_agent_util.plb
@@package bodies/bot_adapter_openai.plb
@@package bodies/bot_adapter_claude.plb
@@package bodies/bot_memory.plb
@@package bodies/bot_tool_runner.plb
@@package bodies/bot_agent.plb

@@triggers/cb_chatbot_conversations_biu.sql

prompt Checking installed object status

column object_type format a20
column object_name format a40
column status format a10

select object_type,
       object_name,
       status
  from user_objects
 where object_name in (
       'CB_CHATBOTS',
       'CB_AI_MODELS',
       'CB_CHATBOT_CONVERSATIONS',
       'CB_TOOLS',
       'BOT_PROVIDER_T',
       'BOT_OPENAI_PROVIDER_T',
       'BOT_CLAUDE_PROVIDER_T',
       'BOT_AGENT_UTIL',
       'BOT_ADAPTER_OPENAI',
       'BOT_ADAPTER_CLAUDE',
       'BOT_MEMORY',
       'BOT_TOOL_RUNNER',
       'BOT_AGENT',
       'CB_CHATBOT_CONVERSATIONS_BIU')
 order by object_type,
          object_name;

column name format a40
column type format a20
column line format 99999
column position format 99999
column text format a100

select name,
       type,
       line,
       position,
       text
  from user_errors
 where name in (
       'BOT_PROVIDER_T',
       'BOT_OPENAI_PROVIDER_T',
       'BOT_CLAUDE_PROVIDER_T',
       'BOT_AGENT_UTIL',
       'BOT_ADAPTER_OPENAI',
       'BOT_ADAPTER_CLAUDE',
       'BOT_MEMORY',
       'BOT_TOOL_RUNNER',
       'BOT_AGENT',
       'CB_CHATBOT_CONVERSATIONS_BIU')
 order by name,
          sequence;

declare
    l_invalid_count number;
begin
    select count(*)
      into l_invalid_count
      from user_objects
     where object_name in (
           'CB_CHATBOTS',
           'CB_AI_MODELS',
           'CB_CHATBOT_CONVERSATIONS',
           'CB_TOOLS',
           'BOT_PROVIDER_T',
           'BOT_OPENAI_PROVIDER_T',
           'BOT_CLAUDE_PROVIDER_T',
           'BOT_AGENT_UTIL',
           'BOT_ADAPTER_OPENAI',
           'BOT_ADAPTER_CLAUDE',
           'BOT_MEMORY',
           'BOT_TOOL_RUNNER',
           'BOT_AGENT',
           'CB_CHATBOT_CONVERSATIONS_BIU')
       and status <> 'VALID';

    if l_invalid_count > 0 then
        raise_application_error(-20000, l_invalid_count || ' installed object(s) are invalid. Review USER_ERRORS output above.');
    end if;
end;
/

prompt Database object install completed
