/**
 * @file bot_agent.plb
 * @description Facade package body for provider-neutral chatbot calls. It keeps
 *              one app-facing API while delegating provider selection to a true
 *              SQL object type hierarchy.
 * @module bot_agent
 * @dependencies cb_chatbots, cb_chatbot_conversations, APEX_DEBUG,
 *               DBMS_LOB, DBMS_UTILITY, bot_agent_util, bot_memory,
 *               bot_tool_runner, bot_provider_t, bot_openai_provider_t,
 *               bot_claude_provider_t, JSON_OBJECT_T, JSON_ARRAY_T
 * @notes Migration-safe database object. Does not depend on legacy helper objects.
 *        Model, endpoint URL, and API key are caller-supplied by design; do not
 *        query a model registry table here so credentials can later move behind
 *        a secure provider.
 */
create or replace package body bot_agent as

   /**
    * @function normalize_signature_type
    * @description Normalizes caller-provided provider signature aliases.
    */
   function normalize_signature_type (
      p_signature_type in varchar2
   ) return varchar2 is
      l_signature_type varchar2(30);
   begin
      l_signature_type := upper(trim(p_signature_type));

      if l_signature_type in (
         gc_signature_openai,
         gc_signature_openai_compatible,
         'OPENAI_COMPAT'
      ) then
         return gc_signature_openai;
      elsif l_signature_type in ('ANTHROPIC', 'CLAUDE') then
         return gc_signature_anthropic;
      end if;

      raise_application_error(
         -20001,
         'Unsupported bot provider signature type: ' || p_signature_type
      );
   end normalize_signature_type;

   /**
    * @function default_max_tokens
    * @description Returns the signature-specific token default when the caller does not provide one.
    */
   function default_max_tokens (
      p_signature_type in varchar2
   ) return number is
   begin
      if p_signature_type = gc_signature_anthropic then
         return gc_claude_max_tokens;
      end if;

      return gc_openai_max_tokens;
   end default_max_tokens;

   /**
    * @function create_provider
    * @description Creates the concrete provider subtype behind a bot_provider_t reference.
    */
   function create_provider (
      p_signature_type in varchar2,
      p_url            in varchar2,
      p_api_key        in varchar2,
      p_model          in varchar2,
      p_max_tokens     in number
   ) return bot_provider_t is
      l_provider bot_provider_t;
   begin
      if p_signature_type = gc_signature_anthropic then
         l_provider := bot_claude_provider_t(
            p_url,
            p_api_key,
            p_model,
            p_max_tokens
         );
      else
         l_provider := bot_openai_provider_t(
            p_url,
            p_api_key,
            p_model,
            p_max_tokens
         );
      end if;

      return l_provider;
   end create_provider;

   /**
    * @procedure append_context_section
    * @description Appends named context text to the system prompt.
    */
   procedure append_context_section (
      p_context in out nocopy clob,
      p_title   in varchar2,
      p_value   in clob
   ) is
   begin
      if p_value is null
      or not regexp_like(dbms_lob.substr(p_value, 32767, 1), '[^[:space:]]') then
         return;
      end if;

      if p_context is null then
         p_context := p_title || ':' || chr(10) || p_value;
      else
         p_context := p_context || chr(10) || chr(10) || p_title || ':' || chr(10) || p_value;
      end if;
   end append_context_section;

   /**
    * @function get_system_context
    * @description Combines the bot prompt, current summary, and recalled older messages.
    */
   function get_system_context (
      p_bot_id            in number,
      p_recalled_messages in clob
   ) return clob is
      l_prompt          cb_chatbots.prompt%type;
      l_current_summary cb_chatbots.current_summary%type;
      l_system_context  clob;
   begin
      select prompt,
             current_summary
        into l_prompt,
             l_current_summary
        from cb_chatbots
       where id = p_bot_id;

      l_system_context := l_prompt;

      append_context_section(
         p_context => l_system_context,
         p_title   => 'Conversation summary',
         p_value   => l_current_summary
      );

      append_context_section(
         p_context => l_system_context,
         p_title   => 'Recalled conversation memory',
         p_value   => p_recalled_messages
      );

      return l_system_context;
   exception
      when no_data_found then
         raise_application_error(
            -20001,
            'Chatbot not found: ' || p_bot_id
         );
   end get_system_context;

   /**
    * @function get_current_message_embedding
    * @description Loads the already-saved current user message embedding for memory recall.
    */
   function get_current_message_embedding (
      p_bot_id             in number,
      p_current_message_id in number
   ) return cb_chatbot_conversations.message_embedding%type is
      l_user_message      cb_chatbot_conversations.message%type;
      l_message_embedding cb_chatbot_conversations.message_embedding%type;
   begin
      select message,
             message_embedding
        into l_user_message,
             l_message_embedding
        from cb_chatbot_conversations
       where id = p_current_message_id
         and chatbot_id = p_bot_id;

      if l_user_message is null then
         raise_application_error(
            -20001,
            'Current message cannot be null: ' || p_current_message_id
         );
      end if;

      return l_message_embedding;
   exception
      when no_data_found then
         raise_application_error(
            -20001,
            'Current chatbot message not found: ' || p_current_message_id
         );
   end get_current_message_embedding;

   /**
    * @function get_current_message_text
    * @description Loads the current saved message text for tool fallback queries.
    */
   function get_current_message_text (
      p_bot_id             in number,
      p_current_message_id in number
   ) return cb_chatbot_conversations.message%type is
      l_message cb_chatbot_conversations.message%type;
   begin
      select message
        into l_message
        from cb_chatbot_conversations
       where id = p_current_message_id
         and chatbot_id = p_bot_id;

      return l_message;
   exception
      when no_data_found then
         raise_application_error(
            -20001,
            'Current chatbot message not found: ' || p_current_message_id
         );
   end get_current_message_text;

   /**
    * @function get_conversation_messages
    * @description Loads unsummarized conversation rows as role/content JSON.
   */
   function get_conversation_messages (
      p_bot_id            in number,
      p_include_system_yn in varchar2
   ) return clob is
      l_messages json_array_t;
   begin
      l_messages := json_array_t();

      for rec in (
         select role,
                message
           from cb_chatbot_conversations
          where chatbot_id = p_bot_id
            and is_summarized = 'N'
            and (p_include_system_yn = 'Y' or role <> 'system')
          order by id
      )
      loop
         bot_agent_util.append_message(
            p_messages => l_messages,
            p_role     => rec.role,
            p_message  => rec.message
         );
      end loop;

      return l_messages.to_clob();
   end get_conversation_messages;

   /**
    * @function get_summary_prompt
    * @description Returns the bot summary prompt or a POC-safe default.
    */
   function get_summary_prompt (
      p_bot_id in number
   ) return clob is
      l_summary_prompt cb_chatbots.summary_prompt%type;
   begin
      select summary_prompt
        into l_summary_prompt
        from cb_chatbots
       where id = p_bot_id;

      if l_summary_prompt is null
      or not regexp_like(dbms_lob.substr(l_summary_prompt, 32767, 1), '[^[:space:]]') then
         l_summary_prompt :=
            'Summarize the conversation transcript for future chatbot context. '
            || 'Preserve durable facts, user preferences, decisions, constraints, '
            || 'open tasks, and details that may help the bot reply consistently. '
            || 'Ignore filler and transient wording.';
      end if;

      return l_summary_prompt;
   exception
      when no_data_found then
         raise_application_error(
            -20001,
            'Chatbot not found: ' || p_bot_id
         );
   end get_summary_prompt;

   /**
    * @function get_summary_max_message_id
    * @description Finds the highest row ID eligible for summarization while
    *              preserving the latest N unsummarized rows.
    */
   function get_summary_max_message_id (
      p_bot_id                    in number,
      p_keep_latest_message_count in number
   ) return number is
      l_max_message_id cb_chatbot_conversations.id%type;
   begin
      select max(id)
        into l_max_message_id
        from (
           select id,
                  row_number() over (order by id desc) rn
             from cb_chatbot_conversations
            where chatbot_id = p_bot_id
              and is_summarized = 'N'
        )
       where rn > p_keep_latest_message_count;

      return l_max_message_id;
   end get_summary_max_message_id;

   /**
    * @function get_summary_transcript
    * @description Formats eligible conversation rows as one transcript CLOB.
    */
   function get_summary_transcript (
      p_bot_id         in number,
      p_max_message_id in number
   ) return clob is
      l_transcript clob;
   begin
      if p_max_message_id is null then
         return null;
      end if;

      for rec in (
         select role,
                message
           from cb_chatbot_conversations
          where chatbot_id = p_bot_id
            and is_summarized = 'N'
            and id <= p_max_message_id
          order by id
      )
      loop
         if l_transcript is null then
            l_transcript := 'Conversation transcript:' || chr(10);
         end if;

         l_transcript :=
            l_transcript
            || '['
            || rec.role
            || '] '
            || rec.message
            || chr(10);
      end loop;

      return l_transcript;
   end get_summary_transcript;

   /**
    * @procedure append_current_summary
    * @description Appends raw summary text to the bot running summary.
    */
   procedure append_current_summary (
      p_bot_id      in number,
      p_new_summary in clob
   ) is
   begin
      update cb_chatbots
         set current_summary =
                case
                   when current_summary is null then p_new_summary
                   else current_summary || p_new_summary
                end
       where id = p_bot_id;
   end append_current_summary;

   /**
    * @procedure mark_messages_summarized
    * @description Marks the exact eligible row range as summarized.
    */
   procedure mark_messages_summarized (
      p_bot_id         in number,
      p_max_message_id in number
   ) is
   begin
      update cb_chatbot_conversations
         set is_summarized = 'Y',
             summarized_date = sysdate
       where chatbot_id = p_bot_id
         and is_summarized = 'N'
         and id <= p_max_message_id;
   end mark_messages_summarized;

   /**
    * @function get_agent_system_prompt
    * @description Adds the tool-use JSON contract to the normal system prompt.
    */
   function get_agent_system_prompt (
      p_system_prompt     in clob,
      p_tool_instructions in clob
   ) return clob is
      l_agent_instructions clob;
      l_agent_prompt       clob;
   begin
      l_agent_instructions :=
         'Agent tool instructions:' || chr(10)
         || 'Tools are optional. Use a tool only when the current answer needs information not already present in the conversation context. '
         || 'Only request tools listed below. Respond with exactly one JSON object and no markdown.' || chr(10)
         || 'To answer directly: {"type":"final","message":"your user-facing answer"}' || chr(10)
         || 'To call a tool: {"type":"tool_call","tool_name":"tool_name","arguments":{"query":"short focused search question"}}'
         || chr(10) || chr(10)
         || 'Available tools:' || chr(10)
         || p_tool_instructions;

      l_agent_prompt := p_system_prompt;
      append_context_section(
         p_context => l_agent_prompt,
         p_title   => 'Agent instructions',
         p_value   => l_agent_instructions
      );

      return l_agent_prompt;
   end get_agent_system_prompt;

   /**
    * @function parse_agent_response
    * @description Parses the model's JSON decision. Returns null for normal text.
    */
   function parse_agent_response (
      p_response in clob
   ) return json_object_t is
      l_response_text varchar2(32767);
      l_response_json json_object_t;
   begin
      if p_response is null then
         return null;
      end if;

      l_response_text := dbms_lob.substr(p_response, 32767, 1);
      l_response_text := regexp_replace(
         l_response_text,
         '^[[:space:]]*```json[[:space:]]*',
         '',
         1,
         1,
         'i'
      );
      l_response_text := regexp_replace(
         l_response_text,
         '^[[:space:]]*```[[:space:]]*',
         ''
      );
      l_response_text := regexp_replace(
         l_response_text,
         '[[:space:]]*```[[:space:]]*$',
         ''
      );

      l_response_json := json_object_t.parse(l_response_text);
      return l_response_json;
   exception
      when others then
         apex_debug.message(
            'bot_agent.parse_agent_response: model returned non-JSON final text: '
            || sqlerrm
         );
         return null;
   end parse_agent_response;

   /**
    * @procedure append_agent_message
    * @description Appends one role/content message to the loop history CLOB.
    */
   procedure append_agent_message (
      p_messages in out nocopy clob,
      p_role     in varchar2,
      p_message  in clob
   ) is
      l_messages json_array_t;
   begin
      l_messages := bot_agent_util.parse_message_array(
         p_messages     => p_messages,
         p_context      => 'append_agent_message',
         p_package_name => 'bot_agent'
      );

      bot_agent_util.append_message(
         p_messages => l_messages,
         p_role     => p_role,
         p_message  => p_message
      );

      p_messages := l_messages.to_clob();
   end append_agent_message;

   /**
    * @function get_tool_arguments
    * @description Returns the JSON object arguments from an agent tool-call response.
    */
   function get_tool_arguments (
      p_response_json in json_object_t
   ) return clob is
      l_arguments_json json_object_t;
   begin
      l_arguments_json := p_response_json.get_object('arguments');

      if l_arguments_json is null then
         return '{}';
      end if;

      return l_arguments_json.to_clob();
   exception
      when others then
         raise_application_error(
            -20003,
            'Invalid agent tool arguments: ' || sqlerrm
         );
   end get_tool_arguments;

   /**
    * @function get_agent_response
    * @description Runs the bounded agent loop for bots with enabled tools.
    */
   function get_agent_response (
      p_provider             in bot_provider_t,
      p_bot_id               in number,
      p_system_prompt        in clob,
      p_history_messages     in clob,
      p_current_message_text in varchar2,
      p_max_tool_steps       in number
   ) return clob is
      l_tool_instructions clob;
      l_agent_prompt      clob;
      l_loop_messages     clob;
      l_model_response    clob;
      l_response_json     json_object_t;
      l_response_type     varchar2(30);
      l_final_message     clob;
      l_tool_name         varchar2(150);
      l_tool_arguments    clob;
      l_tool_result       clob;
      l_max_tool_steps    number;
   begin
      l_tool_instructions := bot_tool_runner.get_tool_instructions(p_bot_id);

      if l_tool_instructions is null then
         return p_provider.get_text_response(
            p_system_prompt    => p_system_prompt,
            p_history_messages => p_history_messages,
            p_user_message     => null
         );
      end if;

      l_max_tool_steps := trunc(nvl(p_max_tool_steps, gc_max_tool_steps));

      if l_max_tool_steps < 0 then
         raise_application_error(-20001, 'Max tool steps cannot be negative');
      end if;

      l_agent_prompt := get_agent_system_prompt(
         p_system_prompt     => p_system_prompt,
         p_tool_instructions => l_tool_instructions
      );
      l_loop_messages := p_history_messages;

      for i in 0 .. l_max_tool_steps loop
         l_model_response := p_provider.get_text_response(
            p_system_prompt    => l_agent_prompt,
            p_history_messages => l_loop_messages,
            p_user_message     => null
         );

         l_response_json := parse_agent_response(l_model_response);

         if l_response_json is null then
            return l_model_response;
         end if;

         l_response_type := lower(trim(l_response_json.get_string('type')));

         if l_response_type = 'final' then
            l_final_message := l_response_json.get_string('message');

            if l_final_message is null
            or not regexp_like(dbms_lob.substr(l_final_message, 32767, 1), '[^[:space:]]') then
               return l_model_response;
            end if;

            return l_final_message;
         elsif l_response_type = 'tool_call' then
            if i >= l_max_tool_steps then
               raise_application_error(-20004, 'Maximum agent tool steps reached');
            end if;

            l_tool_name := l_response_json.get_string('tool_name');
            l_tool_arguments := get_tool_arguments(l_response_json);

            append_agent_message(
               p_messages => l_loop_messages,
               p_role     => 'assistant',
               p_message  => l_model_response
            );

            l_tool_result := bot_tool_runner.execute_tool(
               p_bot_id        => p_bot_id,
               p_tool_name     => l_tool_name,
               p_arguments     => l_tool_arguments,
               p_default_query => p_current_message_text
            );

            if l_tool_result is null then
               append_agent_message(
                  p_messages => l_loop_messages,
                  p_role     => 'user',
                  p_message  => 'The requested tool is not available for this bot. '
                                || 'Return a normal final answer using the existing conversation context. '
                                || 'Respond only as {"type":"final","message":"..."}'
               );
            else
               append_agent_message(
                  p_messages => l_loop_messages,
                  p_role     => 'user',
                  p_message  => 'Tool result for '
                                || l_tool_name
                                || ':'
                                || chr(10)
                                || l_tool_result
                                || chr(10)
                                || 'Use the tool result to continue. Return final JSON, '
                                || 'or request another enabled tool only if still necessary.'
               );
            end if;
         else
            apex_debug.error(
               'Unsupported agent response type: '
               || nvl(l_response_type, '<null>')
            );
            return l_model_response;
         end if;
      end loop;

      raise_application_error(-20004, 'Maximum agent tool steps reached');
   end get_agent_response;

   /**
    * @function get_text_response
    * @description Builds app context, dispatches through a provider object, and returns text.
    */
   function get_text_response (
      p_signature_type       in varchar2,
      p_url                  in varchar2,
      p_api_key              in varchar2,
      p_model                in varchar2,
      p_bot_id               in number,
      p_current_message_id   in number,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null,
      p_max_tool_steps       in number default gc_max_tool_steps
   ) return clob is
      l_signature_type    varchar2(30);
      l_max_tokens        number;
      l_system_prompt     clob;
      l_history_messages  clob;
      l_recalled_messages clob;
      l_message_embedding cb_chatbot_conversations.message_embedding%type;
      l_current_message   cb_chatbot_conversations.message%type;
      l_provider          bot_provider_t;
   begin
      l_signature_type := normalize_signature_type(p_signature_type);
      l_max_tokens := nvl(p_max_tokens, default_max_tokens(l_signature_type));

      apex_debug.message('bot_agent.get_text_response signature: ' || l_signature_type);
      apex_debug.message('bot_agent.get_text_response model: ' || p_model);
      apex_debug.message('bot_agent.get_text_response bot: ' || p_bot_id);

      l_message_embedding := get_current_message_embedding(
         p_bot_id             => p_bot_id,
         p_current_message_id => p_current_message_id
      );

      l_recalled_messages := bot_memory.get_recalled_messages(
         p_bot_id          => p_bot_id,
         p_query_embedding => l_message_embedding,
         p_max_messages    => p_recall_message_count
      );

      l_system_prompt := get_system_context(
         p_bot_id            => p_bot_id,
         p_recalled_messages => l_recalled_messages
      );

      l_history_messages := get_conversation_messages(
         p_bot_id            => p_bot_id,
         p_include_system_yn => 'N'
      );

      l_provider := create_provider(
         p_signature_type => l_signature_type,
         p_url            => p_url,
         p_api_key        => p_api_key,
         p_model          => p_model,
         p_max_tokens     => l_max_tokens
      );

      apex_debug.message(
         'bot_agent.get_text_response provider: '
         || l_provider.get_provider_name
      );

      if bot_tool_runner.has_enabled_tools(p_bot_id) then
         l_current_message := get_current_message_text(
            p_bot_id             => p_bot_id,
            p_current_message_id => p_current_message_id
         );

         return get_agent_response(
            p_provider             => l_provider,
            p_bot_id               => p_bot_id,
            p_system_prompt        => l_system_prompt,
            p_history_messages     => l_history_messages,
            p_current_message_text => l_current_message,
            p_max_tool_steps       => p_max_tool_steps
         );
      end if;

      return l_provider.get_text_response(
         p_system_prompt    => l_system_prompt,
         p_history_messages => l_history_messages,
         p_user_message     => null
      );
   exception
      when others then
         apex_debug.error(
            'Unexpected error in bot_agent.get_text_response: '
            || dbms_utility.format_error_stack
         );
         raise;
   end get_text_response;

   /**
    * @function create_summary
    * @description Calls an LLM to summarize older unsummarized messages, then
    *              appends the raw summary and flags included rows.
    */
   function create_summary (
      p_signature_type             in varchar2,
      p_url                        in varchar2,
      p_api_key                    in varchar2,
      p_model                      in varchar2,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   ) return clob is
      l_signature_type            varchar2(30);
      l_max_tokens                number;
      l_keep_latest_message_count number;
      l_summary_prompt            clob;
      l_summary_transcript        clob;
      l_new_summary               clob;
      l_new_summary_sample        varchar2(4000);
      l_max_message_id            cb_chatbot_conversations.id%type;
      l_provider                  bot_provider_t;
   begin
      l_signature_type := normalize_signature_type(p_signature_type);
      l_max_tokens := nvl(p_max_tokens, default_max_tokens(l_signature_type));
      l_keep_latest_message_count := nvl(p_keep_latest_message_count, 10);

      if p_bot_id is null then
         raise_application_error(-20001, 'Chatbot ID cannot be null');
      elsif l_keep_latest_message_count < 0 then
         raise_application_error(-20001, 'Latest message count cannot be negative');
      end if;

      apex_debug.message('bot_agent.create_summary signature: ' || l_signature_type);
      apex_debug.message('bot_agent.create_summary model: ' || p_model);
      apex_debug.message('bot_agent.create_summary bot: ' || p_bot_id);

      l_max_message_id := get_summary_max_message_id(
         p_bot_id                    => p_bot_id,
         p_keep_latest_message_count => l_keep_latest_message_count
      );

      if l_max_message_id is null then
         return null;
      end if;

      l_summary_prompt := get_summary_prompt(p_bot_id);
      l_summary_transcript := get_summary_transcript(
         p_bot_id         => p_bot_id,
         p_max_message_id => l_max_message_id
      );

      if l_summary_transcript is null then
         return null;
      end if;

      l_provider := create_provider(
         p_signature_type => l_signature_type,
         p_url            => p_url,
         p_api_key        => p_api_key,
         p_model          => p_model,
         p_max_tokens     => l_max_tokens
      );

      l_new_summary := l_provider.get_text_response(
         p_system_prompt    => l_summary_prompt,
         p_history_messages => null,
         p_user_message     => l_summary_transcript
      );

      l_new_summary_sample := dbms_lob.substr(l_new_summary, 4000, 1);

      if l_new_summary is null
      or not regexp_like(l_new_summary_sample, '[^[:space:]]') then
         raise_application_error(-20001, 'Summary response cannot be blank');
      elsif regexp_like(
         l_new_summary_sample,
         '^(Error:|No response received\.|HTTP request failed\.)'
      ) then
         raise_application_error(
            -20002,
            'Summary provider did not return usable text: ' || l_new_summary_sample
         );
      end if;

      append_current_summary(
         p_bot_id      => p_bot_id,
         p_new_summary => l_new_summary
      );

      mark_messages_summarized(
         p_bot_id         => p_bot_id,
         p_max_message_id => l_max_message_id
      );

      return l_new_summary;
   exception
      when others then
         apex_debug.error(
            'Unexpected error in bot_agent.create_summary: '
            || dbms_utility.format_error_stack
         );
         raise;
   end create_summary;

end bot_agent;
/
