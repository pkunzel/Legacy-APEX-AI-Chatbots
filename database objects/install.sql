set define off
set echo on
set feedback on
set serveroutput on size unlimited
set timing on

prompt Installing AI chatbot database objects

@@drop_legacy_bot_objects.sql

@@tables/cb_chatbots.sql
@@tables/cb_chatbot_images.sql
@@tables/cb_ai_models.sql
@@tables/cb_chatbot_conversations.sql
@@tables/cb_tools.sql
@@tables/cb_logs.sql

@@types/cb_provider_t.sql
@@types/cb_openai_provider_t.sql
@@types/cb_claude_provider_t.sql

@@packages/cb_agent_util.sql
@@packages/cb_adapter_openai.sql
@@packages/cb_adapter_claude.sql
@@packages/cb_memory.sql
@@packages/cb_tool_runner.sql
@@packages/cb_agent.sql

@@"type bodies/cb_openai_provider_t.plb"
@@"type bodies/cb_claude_provider_t.plb"

@@"package bodies/cb_agent_util.plb"
@@"package bodies/cb_adapter_openai.plb"
@@"package bodies/cb_adapter_claude.plb"
@@"package bodies/cb_memory.plb"
@@"package bodies/cb_tool_runner.plb"
@@"package bodies/cb_agent.plb"

@@triggers/cb_chatbot_conversations_biu.sql
@@triggers/cb_chatbot_images_biu.sql

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
       'CB_CHATBOT_IMAGES',
       'CB_AI_MODELS',
       'CB_CHATBOT_CONVERSATIONS',
       'CB_TOOLS',
       'CB_LOGS',
       'CB_PROVIDER_T',
       'CB_OPENAI_PROVIDER_T',
       'CB_CLAUDE_PROVIDER_T',
       'CB_AGENT_UTIL',
       'CB_ADAPTER_OPENAI',
       'CB_ADAPTER_CLAUDE',
       'CB_MEMORY',
       'CB_TOOL_RUNNER',
       'CB_AGENT',
       'CB_CHATBOT_CONVERSATIONS_BIU',
       'CB_CHATBOT_IMAGES_BIU')
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
       'CB_PROVIDER_T',
       'CB_OPENAI_PROVIDER_T',
       'CB_CLAUDE_PROVIDER_T',
       'CB_AGENT_UTIL',
       'CB_ADAPTER_OPENAI',
       'CB_ADAPTER_CLAUDE',
       'CB_MEMORY',
       'CB_TOOL_RUNNER',
       'CB_AGENT',
       'CB_CHATBOT_CONVERSATIONS_BIU',
       'CB_CHATBOT_IMAGES_BIU')
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
           'CB_CHATBOT_IMAGES',
           'CB_AI_MODELS',
           'CB_CHATBOT_CONVERSATIONS',
           'CB_TOOLS',
           'CB_LOGS',
           'CB_PROVIDER_T',
           'CB_OPENAI_PROVIDER_T',
           'CB_CLAUDE_PROVIDER_T',
           'CB_AGENT_UTIL',
           'CB_ADAPTER_OPENAI',
           'CB_ADAPTER_CLAUDE',
           'CB_MEMORY',
           'CB_TOOL_RUNNER',
           'CB_AGENT',
           'CB_CHATBOT_CONVERSATIONS_BIU',
           'CB_CHATBOT_IMAGES_BIU')
       and status <> 'VALID';

    if l_invalid_count > 0 then
        raise_application_error(-20000, l_invalid_count || ' installed object(s) are invalid. Review USER_ERRORS output above.');
    end if;
end;
/

prompt Database object install completed
