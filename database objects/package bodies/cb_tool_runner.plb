/**
 * @file cb_tool_runner.plb
 * @description Tool registry and execution facade for optional agent behavior.
 * @module cb_tool_runner
 * @dependencies cb_tools, cb_memory, APEX_DEBUG,
 *               DBMS_LOB, DBMS_UTILITY, JSON_OBJECT_T
 * @notes The current executor exposes read-only conversation-memory lookup.
 */
create or replace package body cb_tool_runner as

   /**
    * @procedure append_text
    * @description Appends text to a CLOB.
    */
   procedure append_text (
      p_target in out nocopy clob,
      p_value  in varchar2
   ) is
   begin
      if p_value is null then
         return;
      end if;

      if p_target is null then
         p_target := p_value;
      else
         p_target := p_target || p_value;
      end if;
   end append_text;

   /**
    * @function normalize_tool_name
    * @description Normalizes an LLM/tool-table tool name for comparison.
    */
   function normalize_tool_name (
      p_tool_name in varchar2
   ) return varchar2 is
   begin
      return lower(trim(p_tool_name));
   end normalize_tool_name;

   /**
    * @function get_argument_value
    * @description Reads a string argument from a JSON object.
    */
   function get_argument_value (
      p_arguments in clob,
      p_name      in varchar2
   ) return varchar2 is
      l_arguments_json json_object_t;
      l_value          varchar2(4000);
   begin
      if p_arguments is null then
         return null;
      end if;

      l_arguments_json := json_object_t.parse(p_arguments);
      l_value := l_arguments_json.get_string(p_name);

      if l_value is null
      or not regexp_like(l_value, '[^[:space:]]') then
         return null;
      end if;

      return l_value;
   exception
      when others then
         apex_debug.error(
            'Invalid tool arguments JSON: ' || dbms_utility.format_error_stack
         );
         raise_application_error(
            -20003,
            'Invalid tool arguments JSON for ' || p_name || ': ' || sqlerrm
         );
   end get_argument_value;

   /**
    * @function limit_result
    * @description Clips large CLOB results to a configured character limit.
    */
   function limit_result (
      p_value     in clob,
      p_max_chars in number
   ) return clob is
      l_result    clob;
      l_marker    varchar2(100) := chr(10) || '[tool result truncated]';
      l_max_chars number := greatest(nvl(p_max_chars, 100000), 1);
   begin
      if p_value is null then
         return null;
      elsif dbms_lob.getlength(p_value) <= l_max_chars then
         return p_value;
      end if;

      dbms_lob.createtemporary(l_result, true);
      dbms_lob.copy(
         dest_lob    => l_result,
         src_lob     => p_value,
         amount      => l_max_chars,
         dest_offset => 1,
         src_offset  => 1
      );
      dbms_lob.writeappend(l_result, length(l_marker), l_marker);

      return l_result;
   end limit_result;

   /**
    * @function execute_conversation_memory
    * @description Searches summarized conversation rows with a tool-selected query.
    */
   function execute_conversation_memory (
      p_bot_id           in number,
      p_arguments        in clob,
      p_default_query    in varchar2,
      p_max_messages     in number,
      p_max_result_chars in number
   ) return clob is
      l_query           varchar2(4000);
      l_query_embedding vector;
      l_result          clob;
   begin
      l_query := get_argument_value(
         p_arguments => p_arguments,
         p_name      => 'query'
      );

      if l_query is null then
         l_query := get_argument_value(
            p_arguments => p_arguments,
            p_name      => 'question'
         );
      end if;

      if l_query is null then
         l_query := p_default_query;
      end if;

      if l_query is null
      or not regexp_like(l_query, '[^[:space:]]') then
         raise_application_error(-20001, 'Conversation memory query cannot be blank');
      end if;

      l_query_embedding := cb_memory.embed_message(
         p_message    => l_query,
         p_chatbot_id => p_bot_id
      );
      l_result := cb_memory.get_recalled_messages(
         p_bot_id          => p_bot_id,
         p_query_embedding => l_query_embedding,
         p_max_messages    => p_max_messages
      );

      if l_result is null then
         return 'No conversation memories were found for the requested query.';
      end if;

      return limit_result(
         p_value     => l_result,
         p_max_chars => p_max_result_chars
      );
   end execute_conversation_memory;

   /**
    * @function has_enabled_tools_yn
    * @description Returns Y when the chatbot has at least one enabled tool.
    */
   function has_enabled_tools_yn (
      p_bot_id in number
   ) return varchar2 is
      l_count number;
   begin
      if p_bot_id is null then
         return 'N';
      end if;

      select count(*)
        into l_count
        from cb_tools t
       where t.chatbot_id = p_bot_id
         and t.enabled_yn = 'Y';

      if l_count > 0 then
         return 'Y';
      end if;

      return 'N';
   end has_enabled_tools_yn;

   /**
    * @function has_enabled_tools
    * @description Boolean PL/SQL helper for package callers.
    */
   function has_enabled_tools (
      p_bot_id in number
   ) return boolean is
   begin
      return has_enabled_tools_yn(p_bot_id) = 'Y';
   end has_enabled_tools;

   /**
    * @function get_tool_instructions
    * @description Returns LLM-facing descriptions for enabled tools.
    */
   function get_tool_instructions (
      p_bot_id in number
   ) return clob is
      l_instructions clob;
   begin
      for rec in (
         select t.tool_name,
                t.description
           from cb_tools t
          where t.chatbot_id = p_bot_id
            and t.enabled_yn = 'Y'
          order by t.tool_name
      )
      loop
         append_text(
            p_target => l_instructions,
            p_value  => '- '
                        || rec.tool_name
                        || ': '
                        || dbms_lob.substr(rec.description, 4000, 1)
                        || chr(10)
                        || '  Arguments JSON: {"query":"short focused search question"}'
                        || chr(10)
         );
      end loop;

      return l_instructions;
   end get_tool_instructions;

   /**
    * @function execute_tool
    * @description Executes one enabled read-only tool for the chatbot.
    */
   function execute_tool (
      p_bot_id        in number,
      p_tool_name     in varchar2,
      p_arguments     in clob,
      p_default_query in varchar2 default null
   ) return clob is
      l_tool_type        cb_tools.tool_type%type;
      l_max_rows         cb_tools.max_rows%type;
      l_max_result_chars cb_tools.max_result_chars%type;
      l_tool_name        cb_tools.tool_name%type;
   begin
      if p_bot_id is null then
         raise_application_error(-20001, 'Chatbot ID cannot be null');
      elsif p_tool_name is null then
         raise_application_error(-20001, 'Tool name cannot be null');
      end if;

      l_tool_name := normalize_tool_name(p_tool_name);

      begin
         select t.tool_type,
                t.max_rows,
                t.max_result_chars
           into l_tool_type,
                l_max_rows,
                l_max_result_chars
           from cb_tools t
          where t.chatbot_id = p_bot_id
            and t.enabled_yn = 'Y'
            and lower(trim(t.tool_name)) = l_tool_name;
      exception
         when no_data_found then
            apex_debug.error(
               'LLM requested a tool that is not enabled for chatbot '
               || p_bot_id
               || ': '
               || p_tool_name
            );
            return null;
      end;

      apex_debug.message(
         'cb_tool_runner.execute_tool tool: '
         || p_tool_name
         || ', type: '
         || l_tool_type
      );

      if upper(l_tool_type) = gc_tool_type_conversation_memory then
         return execute_conversation_memory(
            p_bot_id           => p_bot_id,
            p_arguments        => p_arguments,
            p_default_query    => p_default_query,
            p_max_messages     => l_max_rows,
            p_max_result_chars => l_max_result_chars
         );
      end if;

      raise_application_error(-20001, 'Unsupported tool type: ' || l_tool_type);
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_tool_runner.execute_tool: '
            || dbms_utility.format_error_stack
         );
         raise;
   end execute_tool;

end cb_tool_runner;
/
