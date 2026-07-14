/**
 * @file cb_tool_runner.sql
 * @description Tool registry and execution facade for optional agent behavior.
 * @module cb_tool_runner
 * @dependencies cb_tools, cb_memory, APEX_DEBUG
 * @notes Tool definitions belong directly to one chatbot through CB_TOOLS.CHATBOT_ID.
 *        Create a separate tool row when another chatbot needs similar behavior.
 *        The first POC executor supports agent-invoked conversation memory
 *        lookup over summarized conversation rows.
 */
create or replace package cb_tool_runner as
   gc_tool_type_conversation_memory constant varchar2(50) := 'CONVERSATION_MEMORY';

    /**
    * @function has_enabled_tools_yn
    * @description Returns Y when the chatbot has at least one enabled tool.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @returns VARCHAR2 value Y when an enabled tool exists; otherwise N.
    */
   function has_enabled_tools_yn (
      p_bot_id in number
   ) return varchar2;

    /**
    * @function has_enabled_tools
    * @description Boolean PL/SQL helper for package callers.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @returns TRUE when an enabled tool exists; otherwise FALSE.
    */
   function has_enabled_tools (
      p_bot_id in number
   ) return boolean;

    /**
    * @function get_tool_instructions
    * @description Returns LLM-facing descriptions for enabled tools.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @returns CLOB containing formatted enabled-tool instructions, or null when none exist.
    */
   function get_tool_instructions (
      p_bot_id in number
   ) return clob;

    /**
    * @function execute_tool
    * @description Executes one enabled read-only tool for the chatbot.
    * @param p_bot_id Chatbot identifier from cb_chatbots.
    * @param p_tool_name Enabled tool name requested by the agent.
    * @param p_arguments JSON arguments supplied with the tool request.
    * @param p_default_query Fallback query when the tool request has no usable query.
    * @returns CLOB containing the tool result, or null when the requested tool is not enabled.
    */
   function execute_tool (
      p_bot_id        in number,
      p_tool_name     in varchar2,
      p_arguments     in clob,
      p_default_query in varchar2 default null
   ) return clob;

end cb_tool_runner;
/
