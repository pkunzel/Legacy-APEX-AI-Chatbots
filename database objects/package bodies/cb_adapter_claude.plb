/**
 * @file cb_adapter_claude.plb
 * @description Anthropic/Claude-compatible provider adapter package body.
 * @module cb_adapter_claude
 * @dependencies APEX_DEBUG, DBMS_UTILITY, UTL_HTTP, JSON_OBJECT_T, JSON_ARRAY_T,
 *               cb_agent_util
 * @notes Provider-specific algorithm:
 *        1. Convert generic prompt/history/user inputs into Anthropic messages.
 *        2. POST the request through shared utility HTTP handling.
 *        3. Extract content[0].text from the response.
 *        The package is called by cb_claude_provider_t, not directly by the facade.
 */
create or replace package body cb_adapter_claude as

   gc_anthropic_version constant varchar2(20) := '2023-06-01';
   gc_anthropic_beta    constant varchar2(50) := 'prompt-caching-2024-07-31';

   /**
    * @function build_payload
    * @description Builds an Anthropic-compatible Messages API payload.
    */
   function build_payload (
      p_model            in varchar2,
      p_system_prompt    in clob,
      p_history_messages in clob,
      p_user_message     in clob,
      p_max_tokens       in number
   ) return clob is
      l_json_obj      json_object_t;
      l_system_array  json_array_t;
      l_system_block  clob;
      l_messages      json_array_t;
      l_history       json_array_t;
      l_system_prompt clob;
      l_system_sample varchar2(32767);
   begin
      l_system_prompt := p_system_prompt;
      if l_system_prompt is not null then
         l_system_sample := dbms_lob.substr(l_system_prompt, 32767, 1);

         if regexp_like(l_system_sample, '[^[:space:]]') then
            select json_object(
                      'type' value 'text',
                      'text' value l_system_prompt,
                      'cache_control' value json_object('type' value 'ephemeral')
                      returning clob
                   )
              into l_system_block
              from dual;

            l_system_array := json_array_t();
            l_system_array.append(json_object_t(l_system_block));
         end if;
      end if;

      l_messages := json_array_t();
      l_history := cb_agent_util.parse_message_array(
         p_messages     => p_history_messages,
         p_context      => 'build_payload history',
         p_package_name => 'cb_adapter_claude'
      );

      cb_agent_util.append_array(
         p_target => l_messages,
         p_source => l_history
      );

      if p_user_message is not null
      and regexp_like(dbms_lob.substr(p_user_message, 32767, 1), '[^[:space:]]') then
         cb_agent_util.append_message(
            p_messages => l_messages,
            p_role     => 'user',
            p_message  => p_user_message
         );
      end if;

      if l_messages.get_size = 0 then
         raise_application_error(-20001, 'At least one message is required');
      end if;

      l_json_obj := json_object_t();
      l_json_obj.put('model', p_model);

      if p_max_tokens is not null then
         l_json_obj.put('max_tokens', p_max_tokens);
      end if;

      if l_system_array is not null then
         l_json_obj.put('system', l_system_array);
      end if;

      l_json_obj.put('messages', l_messages);

      return l_json_obj.to_clob();
   end build_payload;

   /**
    * @function parse_response
    * @description Extracts content[0].text from an Anthropic-compatible response.
    */
   function parse_response (
      p_api_response_raw in clob
   ) return clob is
      l_response_json_obj json_object_t;
      l_content_array     json_array_t;
      l_message_json_obj  json_object_t;
      l_assistant_text    clob;
   begin
      if p_api_response_raw is null then
         return 'No response received.';
      end if;

      begin
         l_response_json_obj := json_object_t.parse(p_api_response_raw);
         l_content_array := l_response_json_obj.get_array('content');

         if l_content_array is not null
         and l_content_array.get_size > 0 then
            l_message_json_obj := json_object_t(l_content_array.get(0));
            l_assistant_text := l_message_json_obj.get_string('text');

            if l_assistant_text is null then
               return 'Error: No assistant text found in the response.';
            end if;

            return l_assistant_text;
         end if;

         return 'Error: No content found in the response.';
      exception
         when others then
            apex_debug.message(
               'cb_adapter_claude.parse_response: Error parsing JSON response: '
               || sqlerrm
            );
            return 'Error parsing JSON response: ' || sqlerrm || ': ' || p_api_response_raw;
      end;
   end parse_response;

   /**
    * @function get_text_response
    * @description Adapter algorithm entry point used by cb_claude_provider_t.
    */
   function get_text_response (
      p_url              in varchar2,
      p_api_key          in varchar2,
      p_model            in varchar2,
      p_system_prompt    in clob,
      p_history_messages in clob,
      p_user_message     in clob,
      p_max_tokens       in number
   ) return clob is
      l_payload  clob;
      l_response clob;
   begin
      cb_agent_util.validate_provider_inputs(
         p_url          => p_url,
         p_api_key      => p_api_key,
         p_model        => p_model
      );

      l_payload := build_payload(
         p_model            => p_model,
         p_system_prompt    => p_system_prompt,
         p_history_messages => p_history_messages,
         p_user_message     => p_user_message,
         p_max_tokens       => p_max_tokens
      );

      apex_debug.message('cb_adapter_claude.get_text_response: Making API request...');
      l_response := cb_agent_util.make_api_request(
         p_url                   => p_url,
         p_api_key               => p_api_key,
         p_clob_request          => l_payload,
         p_provider_name         => 'Anthropic-compatible',
         p_api_key_header_name   => 'x-api-key',
         p_extra_header_01_name  => 'anthropic-version',
         p_extra_header_01_value => gc_anthropic_version,
         p_extra_header_02_name  => 'anthropic-beta',
         p_extra_header_02_value => gc_anthropic_beta
      );

      return parse_response(l_response);
   exception
      when utl_http.request_failed then
         apex_debug.message('cb_adapter_claude.get_text_response: HTTP request failed.');
         return 'HTTP request failed.';
      when others then
         apex_debug.error(
            'Unexpected error in cb_adapter_claude.get_text_response: '
            || dbms_utility.format_error_stack
         );
         raise;
   end get_text_response;

end cb_adapter_claude;
/
