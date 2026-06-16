/**
 * @file bot_tool_runner.sql
 * @description Tool registry and execution facade for optional agent behavior.
 * @module bot_tool_runner
 * @dependencies cb_tools, cb_chatbot_tools, bot_rag, APEX_DEBUG
 * @notes Tools are reusable definitions. Chatbots opt into tools through
 *        CB_CHATBOT_TOOLS. The first POC executor supports contextual memory
 *        lookup over summarized conversation rows.
 */
create or replace package bot_tool_runner as
   gc_tool_type_contextual_memory constant varchar2(50) := 'CONTEXTUAL_MEMORY';

   /**
    * @function has_enabled_tools_yn
    * @description Returns Y when the chatbot has at least one enabled tool.
    */
   function has_enabled_tools_yn (
      p_bot_id in number
   ) return varchar2;

   /**
    * @function has_enabled_tools
    * @description Boolean PL/SQL helper for package callers.
    */
   function has_enabled_tools (
      p_bot_id in number
   ) return boolean;

   /**
    * @function get_tool_instructions
    * @description Returns LLM-facing descriptions for enabled tools.
    */
   function get_tool_instructions (
      p_bot_id in number
   ) return clob;

   /**
    * @function execute_tool
    * @description Executes one enabled read-only tool for the chatbot.
    */
   function execute_tool (
      p_bot_id        in number,
      p_tool_name     in varchar2,
      p_arguments     in clob,
      p_default_query in varchar2 default null
   ) return clob;

end bot_tool_runner;
/

