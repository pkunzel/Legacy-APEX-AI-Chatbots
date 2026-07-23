/**
 * @file cb_agent_util.plb
 * @description Shared internal helpers for bot provider adapter packages.
 * @module cb_agent_util
 * @dependencies APEX_WEB_SERVICE, APEX_DEBUG, DBMS_LOB, DBMS_UTILITY,
 *               JSON_OBJECT_T, JSON_ARRAY_T
 * @notes Centralizes repeated validation, JSON message handling, and HTTP POST logic.
 */
create or replace package body cb_agent_util as

   gc_content_type constant varchar2(50) := 'application/json';

   /**
    * @function has_text
    * @description Returns whether a CLOB contains at least one non-whitespace character.
    */
   function has_text (
      p_value in clob
   ) return boolean is
   begin
      return p_value is not null
         and regexp_like(dbms_lob.substr(p_value, 32767, 1), '[^[:space:]]');
   end has_text;

   /**
    * @function get_context_section
    * @description Returns one CLOB-safe system-context JSON value when present.
    */
   function get_context_section (
      p_system_context in json_object_t,
      p_key            in varchar2
   ) return clob is
   begin
      if p_system_context is null
      or not p_system_context.has(p_key)
      or p_system_context.get(p_key).is_null then
         return null;
      end if;

      return p_system_context.get_clob(p_key);
   end get_context_section;

   /**
    * @function append_context_section
    * @description Appends one populated named section to flat system-context text.
    */
   function append_context_section (
      p_context in clob,
      p_title   in varchar2,
      p_value   in clob
   ) return clob is
   begin
      if not has_text(p_value) then
         return p_context;
      elsif p_context is null then
         if p_title is null then
            return p_value;
         end if;

         return p_title || ':' || chr(10) || p_value;
      end if;

      if p_title is null then
         return p_context || chr(10) || chr(10) || p_value;
      end if;

      return p_context || chr(10) || chr(10) || p_title || ':' || chr(10) || p_value;
   end append_context_section;

   /**
    * @procedure validate_provider_inputs
    * @description Validates common provider connection inputs.
    */
   procedure validate_provider_inputs (
      p_url          in varchar2,
      p_api_key      in varchar2,
      p_model        in varchar2
   ) is
   begin
      if p_url is null then
         raise_application_error(-20001, 'Provider URL cannot be null');
      elsif p_api_key is null then
         raise_application_error(-20001, 'Provider API key cannot be null');
      elsif p_model is null then
         raise_application_error(-20001, 'Provider model cannot be null');
      end if;
   end validate_provider_inputs;

   /**
    * @procedure append_message
    * @description Appends a role/content JSON object to a message array.
    */
   procedure append_message (
      p_messages in out nocopy json_array_t,
      p_role     in varchar2,
      p_message  in clob
   ) is
      l_message_json clob;
   begin
      select json_object(
                'role' value p_role,
                'content' value p_message
                returning clob
             )
        into l_message_json
        from dual;

      p_messages.append(json_object_t(l_message_json));
   end append_message;

   /**
    * @procedure append_array
    * @description Appends all objects from one JSON array to another.
    */
   procedure append_array (
      p_target in out nocopy json_array_t,
      p_source in json_array_t
   ) is
   begin
      if p_source is not null
      and p_source.get_size > 0 then
         for i in 0 .. p_source.get_size - 1 loop
            p_target.append(json_object_t(p_source.get(i)));
         end loop;
      end if;
   end append_array;

   /**
    * @function parse_message_array
    * @description Parses a JSON array CLOB, returning an empty array for null input.
    */
   function parse_message_array (
      p_messages     in clob,
      p_context      in varchar2,
      p_package_name in varchar2
   ) return json_array_t is
      l_messages json_array_t;
   begin
      if p_messages is null then
         return json_array_t();
      end if;

      l_messages := json_array_t.parse(p_messages);
      return l_messages;
   exception
      when others then
         apex_debug.error(
            'Invalid JSON in p_messages for '
            || p_package_name
            || '.'
            || p_context
            || '. Request payload was not created: '
            || dbms_utility.format_error_stack
         );
         raise_application_error(
            -20003,
            'Invalid conversation JSON passed to '
            || p_package_name
            || '.'
            || p_context
            || ': '
            || sqlerrm
         );
   end parse_message_array;

   /**
    * @function build_system_context
    * @description Builds provider-neutral system context as one JSON object.
    */
   function build_system_context (
      p_instructions         in clob,
      p_global_context       in clob default null,
      p_conversation_summary in clob default null,
      p_retrieved_context    in clob default null
   ) return clob is
      l_system_context json_object_t;
   begin
      l_system_context := json_object_t();
      l_system_context.put(gc_context_instructions, p_instructions);
      l_system_context.put(gc_context_global_context, p_global_context);
      l_system_context.put(gc_context_conversation_summary, p_conversation_summary);
      l_system_context.put(gc_context_retrieved_context, p_retrieved_context);

      return l_system_context.to_clob();
   end build_system_context;

   /**
    * @function parse_system_context
    * @description Parses provider-neutral system-context JSON.
    */
   function parse_system_context (
      p_system_context in clob,
      p_package_name   in varchar2
   ) return json_object_t is
      l_system_context json_object_t;
   begin
      if p_system_context is null then
         return json_object_t();
      end if;

      l_system_context := json_object_t.parse(p_system_context);
      return l_system_context;
   exception
      when others then
         apex_debug.error(
            'Invalid system-context JSON for '
            || p_package_name
            || '. Request payload was not created: '
            || dbms_utility.format_error_stack
         );
         raise_application_error(
            -20003,
            'Invalid system-context JSON passed to '
            || p_package_name
            || ': '
            || sqlerrm
         );
   end parse_system_context;

   /**
    * @function flatten_system_context
    * @description Formats structured system context as one labeled text prompt.
    */
   function flatten_system_context (
      p_system_context in clob
   ) return clob is
      l_context_json json_object_t;
      l_context      clob;
   begin
      l_context_json := parse_system_context(
         p_system_context => p_system_context,
         p_package_name   => 'cb_agent_util'
      );

      l_context := append_context_section(
         p_context => l_context,
         p_title   => null,
         p_value   => get_context_section(l_context_json, gc_context_instructions)
      );
      l_context := append_context_section(
         p_context => l_context,
         p_title   => 'Global context',
         p_value   => get_context_section(l_context_json, gc_context_global_context)
      );
      l_context := append_context_section(
         p_context => l_context,
         p_title   => 'Conversation summary',
         p_value   => get_context_section(l_context_json, gc_context_conversation_summary)
      );
      l_context := append_context_section(
         p_context => l_context,
         p_title   => 'Recalled conversation memory',
         p_value   => get_context_section(l_context_json, gc_context_retrieved_context)
      );

      return l_context;
   end flatten_system_context;

   /**
    * @function make_api_request
    * @description Sends a JSON POST request with provider-specific headers.
    */
   function make_api_request (
      p_url                  in varchar2,
      p_api_key              in varchar2,
      p_clob_request         in clob,
      p_provider_name        in varchar2,
      p_api_key_header_name  in varchar2,
      p_extra_header_01_name in varchar2 default null,
      p_extra_header_01_value in varchar2 default null,
      p_extra_header_02_name in varchar2 default null,
      p_extra_header_02_value in varchar2 default null
   ) return clob is
      l_clob_response clob;
      l_status_code   number;
   begin
      if p_clob_request is null then
         raise_application_error(-20001, 'Request body cannot be null');
      elsif p_api_key_header_name is null then
         raise_application_error(-20001, 'API key header name cannot be null');
      end if;

      apex_web_service.clear_request_headers;

      if p_extra_header_02_name is not null then
         apex_web_service.set_request_headers(
            p_name_01  => 'Content-Type',
            p_value_01 => gc_content_type,
            p_name_02  => p_api_key_header_name,
            p_value_02 => p_api_key,
            p_name_03  => p_extra_header_01_name,
            p_value_03 => p_extra_header_01_value,
            p_name_04  => p_extra_header_02_name,
            p_value_04 => p_extra_header_02_value
         );
      elsif p_extra_header_01_name is not null then
         apex_web_service.set_request_headers(
            p_name_01  => 'Content-Type',
            p_value_01 => gc_content_type,
            p_name_02  => p_api_key_header_name,
            p_value_02 => p_api_key,
            p_name_03  => p_extra_header_01_name,
            p_value_03 => p_extra_header_01_value
         );
      else
         apex_web_service.set_request_headers(
            p_name_01  => 'Content-Type',
            p_value_01 => gc_content_type,
            p_name_02  => p_api_key_header_name,
            p_value_02 => p_api_key
         );
      end if;

      l_clob_response := apex_web_service.make_rest_request(
         p_url         => p_url,
         p_http_method => 'POST',
         p_body        => p_clob_request
      );

      l_status_code := apex_web_service.g_status_code;

      if l_status_code >= 400 then
         raise_application_error(
            -20002,
            p_provider_name
            || ' API request failed with status '
            || l_status_code
            || ': '
            || dbms_lob.substr(l_clob_response, 4000, 1)
         );
      end if;

      return l_clob_response;
   exception
      when others then
         apex_debug.error(
            'Error in cb_agent_util.make_api_request for '
            || p_provider_name
            || ': '
            || dbms_utility.format_error_stack
         );
         raise;
   end make_api_request;

end cb_agent_util;
/
