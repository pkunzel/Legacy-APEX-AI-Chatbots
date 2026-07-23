/**
 * @file cb_adapter_claude.plb
 * @description Anthropic/Claude-compatible provider adapter package body.
 * @module cb_adapter_claude
 * @dependencies APEX_DEBUG, DBMS_UTILITY, UTL_HTTP, JSON_OBJECT_T, JSON_ARRAY_T,
 *               cb_agent_util
 * @notes Provider-specific algorithm:
 *        1. Convert generic system context, history, and user inputs into Anthropic messages.
 *        2. POST the request through shared utility HTTP handling.
 *        3. Extract content[0].text from the response.
 *        The package is called by cb_claude_provider_t, not directly by the facade.
 */
create or replace package body cb_adapter_claude as

   gc_anthropic_version constant varchar2(20) := '2023-06-01';
   gc_anthropic_beta    constant varchar2(50) := 'prompt-caching-2024-07-31';

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
    * @function get_system_block_text
    * @description Adds an optional section title to Anthropic system-block text.
    */
   function get_system_block_text (
      p_title in varchar2,
      p_value in clob
   ) return clob is
   begin
      if p_title is null then
         return p_value;
      end if;

      return p_title || ':' || chr(10) || p_value;
   end get_system_block_text;

   /**
    * @procedure append_system_block
    * @description Appends one nonblank Anthropic text system block.
    */
   procedure append_system_block (
      p_system_blocks in out nocopy json_array_t,
      p_text          in clob,
      p_cache_yn      in boolean
   ) is
      l_system_block clob;
   begin
      if not has_text(p_text) then
         return;
      end if;

      if p_cache_yn then
         select json_object(
                   'type' value 'text',
                   'text' value p_text,
                   'cache_control' value json_object('type' value 'ephemeral')
                   returning clob
                )
           into l_system_block
           from dual;
      else
         select json_object(
                   'type' value 'text',
                   'text' value p_text
                   returning clob
                )
           into l_system_block
           from dual;
      end if;

      p_system_blocks.append(json_object_t(l_system_block));
   end append_system_block;

   /**
    * @function build_system_blocks
    * @description Builds Anthropic system blocks and explicit stable-prefix cache boundaries.
    */
   function build_system_blocks (
      p_system_context in clob
   ) return json_array_t is
      l_context_json          json_object_t;
      l_system_blocks         json_array_t;
      l_instructions          clob;
      l_global_context        clob;
      l_conversation_summary  clob;
      l_retrieved_context     clob;
      l_cache_instructions_yn boolean;
      l_cache_global_yn       boolean;
   begin
      l_context_json := cb_agent_util.parse_system_context(
         p_system_context => p_system_context,
         p_package_name   => 'cb_adapter_claude'
      );
      l_system_blocks := json_array_t();

      l_instructions := get_context_section(
         l_context_json,
         cb_agent_util.gc_context_instructions
      );
      l_global_context := get_context_section(
         l_context_json,
         cb_agent_util.gc_context_global_context
      );
      l_conversation_summary := get_context_section(
         l_context_json,
         cb_agent_util.gc_context_conversation_summary
      );
      l_retrieved_context := get_context_section(
         l_context_json,
         cb_agent_util.gc_context_retrieved_context
      );

      l_cache_instructions_yn := has_text(l_instructions)
         and not has_text(l_global_context);
      l_cache_global_yn := has_text(l_global_context);

      append_system_block(
         p_system_blocks => l_system_blocks,
         p_text          => get_system_block_text(null, l_instructions),
         p_cache_yn      => l_cache_instructions_yn
      );
      append_system_block(
         p_system_blocks => l_system_blocks,
         p_text          => get_system_block_text('Global context', l_global_context),
         p_cache_yn      => l_cache_global_yn
      );
      append_system_block(
         p_system_blocks => l_system_blocks,
         p_text          => get_system_block_text(
                              'Conversation summary',
                              l_conversation_summary
                           ),
         p_cache_yn      => has_text(l_conversation_summary)
      );
      append_system_block(
         p_system_blocks => l_system_blocks,
         p_text          => get_system_block_text(
                              'Recalled conversation memory',
                              l_retrieved_context
                           ),
         p_cache_yn      => false
      );

      return l_system_blocks;
   end build_system_blocks;

   /**
    * @procedure log_cache_usage
    * @description Logs available Claude cache token counts without exposing prompt content.
    */
   procedure log_cache_usage (
      p_api_response_raw in clob
   ) is
      l_response_json json_object_t;
      l_usage_json    json_object_t;
      l_input_tokens  number;
      l_cache_created number;
      l_cache_read    number;
   begin
      if p_api_response_raw is null then
         return;
      end if;

      l_response_json := json_object_t.parse(p_api_response_raw);
      if not l_response_json.has('usage') then
         return;
      end if;

      l_usage_json := l_response_json.get_object('usage');
      if l_usage_json is null then
         return;
      end if;

      if l_usage_json.has('input_tokens') then
         l_input_tokens := l_usage_json.get_number('input_tokens');
      end if;
      if l_usage_json.has('cache_creation_input_tokens') then
         l_cache_created := l_usage_json.get_number('cache_creation_input_tokens');
      end if;
      if l_usage_json.has('cache_read_input_tokens') then
         l_cache_read := l_usage_json.get_number('cache_read_input_tokens');
      end if;

      apex_debug.message(
         'cb_adapter_claude cache usage: input_tokens='
         || nvl(to_char(l_input_tokens), '<not supplied>')
         || ', cache_creation_input_tokens='
         || nvl(to_char(l_cache_created), '<not supplied>')
         || ', cache_read_input_tokens='
         || nvl(to_char(l_cache_read), '<not supplied>')
      );
   exception
      when others then
         apex_debug.message(
            'cb_adapter_claude.log_cache_usage: Unable to read usage metadata: '
            || sqlerrm
         );
   end log_cache_usage;

   /**
    * @function build_payload
    * @description Builds an Anthropic-compatible Messages API payload.
    */
   function build_payload (
      p_model            in varchar2,
      p_system_context   in clob,
      p_history_messages in clob,
      p_user_message     in clob,
      p_max_tokens       in number
   ) return clob is
      l_json_obj      json_object_t;
      l_system_array json_array_t;
      l_messages     json_array_t;
      l_history      json_array_t;
   begin
      l_system_array := build_system_blocks(p_system_context);

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

      if l_system_array.get_size > 0 then
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

            -- Starting in Claude 5 we're getting the thinking object often
            -- in the position 1 of the content array
            if l_message_json_obj.get_string('type') = 'thinking' then
               l_message_json_obj := json_object_t(l_content_array.get(1));
            end if;

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
      p_system_context   in clob,
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
         p_system_context   => p_system_context,
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

      log_cache_usage(l_response);

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
