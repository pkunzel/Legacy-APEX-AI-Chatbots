/**
 * @file bot_agent_util.plb
 * @description Shared internal helpers for bot provider adapter packages.
 * @module bot_agent_util
 * @dependencies APEX_WEB_SERVICE, APEX_DEBUG, DBMS_LOB, DBMS_UTILITY,
 *               JSON_OBJECT_T, JSON_ARRAY_T
 * @notes Centralizes repeated validation, JSON message handling, and HTTP POST logic.
 */
create or replace package body bot_agent_util as

   gc_content_type constant varchar2(50) := 'application/json';

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
            'Error in bot_agent_util.make_api_request for '
            || p_provider_name
            || ': '
            || dbms_utility.format_error_stack
         );
         raise;
   end make_api_request;

end bot_agent_util;
/
