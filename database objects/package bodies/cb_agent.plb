/**
 * @file cb_agent.plb
 * @description Facade package body for provider-neutral chatbot calls. It keeps
 *              one app-facing API while delegating provider selection to a true
 *              SQL object type hierarchy.
 * @module cb_agent
 * @dependencies cb_ai_models, cb_chatbots, cb_chatbot_conversations, cb_logs, APEX_DEBUG,
 *               DBMS_LOB, DBMS_UTILITY, cb_agent_util, cb_memory,
 *               cb_provider_t, cb_openai_provider_t,
 *               cb_claude_provider_t, JSON_OBJECT_T, JSON_ARRAY_T
 * @notes Migration-safe database object. Supports caller-supplied provider
 *        parameters and model-table lookup through CB_AI_MODELS.
 */
create or replace package body cb_agent as

   type t_ai_model_config is record (
      signature_type cb_ai_models.signature_type%type,
      url            cb_ai_models.url%type,
      api_key        cb_ai_models.api_key%type,
      model          cb_ai_models.model%type,
      max_tokens     cb_ai_models.max_tokens%type
   );

   gc_message_max_chars constant number := 8000;

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
    * @function get_header_api_key
    * @description Converts a stored raw secret into the header value expected by the adapter.
    */
   function get_header_api_key (
      p_signature_type in varchar2,
      p_api_key        in varchar2
   ) return varchar2 is
      l_api_key varchar2(4000);
   begin
      l_api_key := trim(p_api_key);

      if p_signature_type = gc_signature_openai then
         if regexp_like(l_api_key, '^Bearer[[:space:]]+', 'i') then
            return l_api_key;
         end if;

         return 'Bearer ' || l_api_key;
      end if;

      return l_api_key;
   end get_header_api_key;

   /**
    * @function get_ai_model_config
    * @description Loads one model connection configuration from cb_ai_models.
    */
   function get_ai_model_config (
      p_model_id in number
   ) return t_ai_model_config is
      l_config t_ai_model_config;
   begin
      if p_model_id is null then
         raise_application_error(-20001, 'AI model ID cannot be null');
      end if;

      select signature_type,
             url,
             api_key,
             model,
             max_tokens
        into l_config.signature_type,
             l_config.url,
             l_config.api_key,
             l_config.model,
             l_config.max_tokens
        from cb_ai_models
       where id = p_model_id;

      return l_config;
   exception
      when no_data_found then
         raise_application_error(-20001, 'AI model configuration not found: ' || p_model_id);
   end get_ai_model_config;

   /**
    * @function create_provider
    * @description Creates the concrete provider subtype behind a cb_provider_t reference.
    */
   function create_provider (
      p_signature_type in varchar2,
      p_url            in varchar2,
      p_api_key        in varchar2,
      p_model          in varchar2,
      p_max_tokens     in number
   ) return cb_provider_t is
      l_provider cb_provider_t;
   begin
      if p_signature_type = gc_signature_anthropic then
         l_provider := cb_claude_provider_t(
            p_url,
            p_api_key,
            p_model,
            p_max_tokens
         );
      else
         l_provider := cb_openai_provider_t(
            p_url,
            p_api_key,
            p_model,
            p_max_tokens
         );
      end if;

      return l_provider;
   end create_provider;

   /**
    * @function validate_chat_response
    * @description Enforces the conversation message storage limit for chat replies.
    */
   function validate_chat_response (
      p_response in clob,
      p_bot_id   in number,
      p_model    in varchar2
   ) return clob is
      l_length number;
   begin
      if p_response is null then
         return null;
      end if;

      l_length := dbms_lob.getlength(p_response);

      if l_length > gc_message_max_chars then
         apex_debug.error(
            'cb_agent.get_text_response returned '
            || l_length
            || ' characters for chatbot '
            || p_bot_id
            || ', model '
            || p_model
            || '. Maximum conversation message length is '
            || gc_message_max_chars
            || ' characters.'
         );

         raise_application_error(
            -20005,
            'Assistant response exceeds the maximum conversation message length of '
            || gc_message_max_chars
            || ' characters.'
         );
      end if;

      return p_response;
   end validate_chat_response;

   /**
    * @function get_system_context
    * @description Builds provider-neutral context from bot instructions, stable
    *              context, running summary, and recalled older messages.
    */
   function get_system_context (
      p_bot_id            in number,
      p_recalled_messages in clob
   ) return clob is
      l_prompt          cb_chatbots.prompt%type;
      l_global_context  cb_chatbots.global_context%type;
      l_current_summary cb_chatbots.current_summary%type;
      l_system_context  clob;
   begin
      select prompt,
             global_context,
             current_summary
        into l_prompt,
             l_global_context,
             l_current_summary
        from cb_chatbots
       where id = p_bot_id;

      l_system_context := cb_agent_util.build_system_context(
         p_instructions         => l_prompt,
         p_global_context       => l_global_context,
         p_conversation_summary => l_current_summary,
         p_retrieved_context    => p_recalled_messages
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
         cb_agent_util.append_message(
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
         raise_application_error(
            -20001,
            'Create a summary prompt to use the summary feature'
         );
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
      p_max_tokens           in number default null
   ) return clob is
      l_signature_type    varchar2(30);
      l_max_tokens        number;
      l_system_context    clob;
      l_history_messages  clob;
      l_recalled_messages clob;
      l_message_embedding cb_chatbot_conversations.message_embedding%type;
      l_provider          cb_provider_t;
      l_response          clob;
   begin
      l_signature_type := normalize_signature_type(p_signature_type);
      l_max_tokens := nvl(p_max_tokens, default_max_tokens(l_signature_type));

      apex_debug.message('cb_agent.get_text_response signature: ' || l_signature_type);
      apex_debug.message('cb_agent.get_text_response model: ' || p_model);
      apex_debug.message('cb_agent.get_text_response bot: ' || p_bot_id);

      l_message_embedding := get_current_message_embedding(
         p_bot_id             => p_bot_id,
         p_current_message_id => p_current_message_id
      );

      l_recalled_messages := cb_memory.get_recalled_messages(
         p_bot_id          => p_bot_id,
         p_query_embedding => l_message_embedding,
         p_max_messages    => p_recall_message_count
      );

      l_system_context := get_system_context(
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
         'cb_agent.get_text_response provider: '
         || l_provider.get_provider_name
      );

      l_response := l_provider.get_text_response(
         p_system_context   => l_system_context,
         p_history_messages => l_history_messages,
         p_user_message     => null
      );

      return validate_chat_response(
         p_response => l_response,
         p_bot_id   => p_bot_id,
         p_model    => p_model
      );
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_agent.get_text_response: '
            || dbms_utility.format_error_stack
         );
         raise;
   end get_text_response;

   /**
    * @function get_text_response
    * @description Loads model provider details from cb_ai_models, then returns text.
    */
   function get_text_response (
      p_model_id             in number,
      p_bot_id               in number,
      p_current_message_id   in number,
      p_recall_message_count in number default 10,
      p_max_tokens           in number default null
   ) return clob is
      l_config         t_ai_model_config;
      l_signature_type varchar2(30);
   begin
      l_config := get_ai_model_config(p_model_id);
      l_signature_type := normalize_signature_type(l_config.signature_type);

      return get_text_response(
         p_signature_type       => l_signature_type,
         p_url                  => l_config.url,
         p_api_key              => get_header_api_key(
                                      p_signature_type => l_signature_type,
                                      p_api_key        => l_config.api_key
                                   ),
         p_model                => l_config.model,
         p_bot_id               => p_bot_id,
         p_current_message_id   => p_current_message_id,
         p_recall_message_count => p_recall_message_count,
         p_max_tokens           => nvl(p_max_tokens, l_config.max_tokens)
      );
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_agent.get_text_response by model ID: '
            || dbms_utility.format_error_stack
         );
         raise;
   end get_text_response;

   /**
    * @function get_image_definition
    * @description Uses the chatbot image-definition prompt and configured image
    *              model to derive a concise image-search term from an assistant response.
    */
   function get_image_definition (
      p_bot_id             in cb_chatbots.id%type,
      p_assistant_response in cb_chatbot_conversations.message%type
   ) return cb_chatbot_conversations.image_search_term%type is
      l_image_model_id         cb_chatbots.image_llm_model_id%type;
      l_image_definition_prompt cb_chatbots.image_definition_prompt%type;
      l_config                 t_ai_model_config;
      l_signature_type         varchar2(30);
      l_provider               cb_provider_t;
      l_response               clob;
      l_response_sample        varchar2(32767);
      l_response_length        number;
      l_effective_max_tokens   number;
      l_failure_reason         varchar2(100);
      l_error_details          clob;
   begin
      if p_assistant_response is null
      or not regexp_like(p_assistant_response, '[^[:space:]]') then
         return null;
      end if;

      select image_llm_model_id,
             image_definition_prompt
        into l_image_model_id,
             l_image_definition_prompt
        from cb_chatbots
       where id = p_bot_id;

      if l_image_definition_prompt is null
      or not regexp_like(
         dbms_lob.substr(l_image_definition_prompt, 32767, 1),
         '[^[:space:]]'
      ) then
         raise_application_error(-20001, 'Image definition prompt cannot be null');
      end if;

      l_config := get_ai_model_config(l_image_model_id);
      l_signature_type := normalize_signature_type(l_config.signature_type);
      l_effective_max_tokens := nvl(
         l_config.max_tokens,
         default_max_tokens(l_signature_type)
      );

      l_provider := create_provider(
         p_signature_type => l_signature_type,
         p_url            => l_config.url,
         p_api_key        => get_header_api_key(
                               p_signature_type => l_signature_type,
                               p_api_key        => l_config.api_key
                            ),
         p_model          => l_config.model,
         p_max_tokens     => l_effective_max_tokens
      );

      l_response := l_provider.get_text_response(
         p_system_context   => cb_agent_util.build_system_context(
                                  p_instructions => l_image_definition_prompt
                               ),
         p_history_messages => null,
         p_user_message     => p_assistant_response
      );

      l_response_sample := lower(dbms_lob.substr(l_response, 32767, 1));
      l_response_length := dbms_lob.getlength(l_response);

      if l_response_sample is null
      or not regexp_like(l_response_sample, '[^[:space:]]') then
         l_failure_reason := 'blank provider response';
      elsif l_response_sample like 'error%' then
         l_failure_reason := 'provider response begins with "error"';
      elsif l_response_sample like 'http request failed%' then
         l_failure_reason := 'provider HTTP request failed';
      elsif l_response_sample like 'no response received%' then
         l_failure_reason := 'provider returned no response';
      end if;

      if l_failure_reason is not null then
         raise_application_error(
            -20001,
            'Image definition generation failed: ' || l_failure_reason
         );
      end if;

      return dbms_lob.substr(l_response, 300, 1);
   exception
      when others then
         l_error_details :=
            'Image-definition diagnostics:'
            || chr(10) || 'bot_id=' || nvl(to_char(p_bot_id), '<null>')
            || chr(10) || 'image_model_id=' || nvl(to_char(l_image_model_id), '<null>')
            || chr(10) || 'signature_type=' || nvl(l_signature_type, '<null>')
            || chr(10) || 'model=' || nvl(l_config.model, '<null>')
            || chr(10) || 'max_tokens=' || nvl(to_char(l_effective_max_tokens), '<null>')
            || chr(10) || 'assistant_response_length=' || nvl(to_char(length(p_assistant_response)), '<null>')
            || chr(10) || 'response_length=' || nvl(to_char(l_response_length), '<null>')
            || chr(10) || 'response_sample=' || nvl(
               replace(
                  replace(dbms_lob.substr(l_response, 4000, 1), chr(13), ' '),
                  chr(10),
                  ' '
               ),
               '<null>'
            )
            || chr(10) || 'error_stack=' || dbms_utility.format_error_stack
            || chr(10) || 'error_backtrace=' || dbms_utility.format_error_backtrace;

         apex_debug.error(
            'Unexpected error in cb_agent.get_image_definition: '
            || dbms_lob.substr(l_error_details, 32767, 1)
         );

         begin
            insert into cb_logs (
               chatbot_id,
               error,
               location
            ) values (
               p_bot_id,
               l_error_details,
               'cb_agent.get_image_definition'
            );
         exception
            when others then
               apex_debug.error(
                  'Unexpected error while logging image-definition failure: '
                  || dbms_utility.format_error_stack
               );
         end;

         return null;
   end get_image_definition;

   /**
    * @procedure create_summary
    * @description Calls an LLM to summarize older unsummarized messages, then
    *              appends the raw summary and flags included rows.
    */
   procedure create_summary (
      p_signature_type             in varchar2,
      p_url                        in varchar2,
      p_api_key                    in varchar2,
      p_model                      in varchar2,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   ) is
      l_signature_type            varchar2(30);
      l_max_tokens                number;
      l_keep_latest_message_count number;
      l_summary_prompt            clob;
      l_current_summary           cb_chatbots.current_summary%type;
      l_summary_transcript        clob;
      l_new_summary               clob;
      l_new_summary_sample        varchar2(4000);
      l_max_message_id            cb_chatbot_conversations.id%type;
      l_provider                  cb_provider_t;
   begin
      l_signature_type := normalize_signature_type(p_signature_type);
      l_max_tokens := nvl(p_max_tokens, default_max_tokens(l_signature_type));
      l_keep_latest_message_count := nvl(p_keep_latest_message_count, 10);

      if p_bot_id is null then
         raise_application_error(-20001, 'Chatbot ID cannot be null');
      elsif l_keep_latest_message_count < 0 then
         raise_application_error(-20001, 'Latest message count cannot be negative');
      end if;

      apex_debug.message('cb_agent.create_summary signature: ' || l_signature_type);
      apex_debug.message('cb_agent.create_summary model: ' || p_model);
      apex_debug.message('cb_agent.create_summary bot: ' || p_bot_id);

      l_max_message_id := get_summary_max_message_id(
         p_bot_id                    => p_bot_id,
         p_keep_latest_message_count => l_keep_latest_message_count
      );

      if l_max_message_id is null then
         return;
      end if;

      l_summary_prompt := get_summary_prompt(p_bot_id);

      select current_summary
        into l_current_summary
        from cb_chatbots
       where id = p_bot_id;

      l_summary_transcript := get_summary_transcript(
         p_bot_id         => p_bot_id,
         p_max_message_id => l_max_message_id
      );

      if l_summary_transcript is null then
         return;
      end if;

      if l_current_summary is not null
      and regexp_like(dbms_lob.substr(l_current_summary, 32767, 1), '[^[:space:]]') then
         l_summary_transcript :=
            '<existing_running_summary>'
            || chr(10)
            || l_current_summary
            || chr(10)
            || '</existing_running_summary>'
            || chr(10)
            || chr(10)
            || '<new_conversation_transcript>'
            || chr(10)
            || l_summary_transcript
            || chr(10)
            || '</new_conversation_transcript>';
      else
         l_summary_transcript :=
            'New conversation transcript:'
            || chr(10)
            || l_summary_transcript;
      end if;

      l_provider := create_provider(
         p_signature_type => l_signature_type,
         p_url            => p_url,
         p_api_key        => p_api_key,
         p_model          => p_model,
         p_max_tokens     => l_max_tokens
      );

      l_new_summary := l_provider.get_text_response(
         p_system_context   => cb_agent_util.build_system_context(
                                  p_instructions => l_summary_prompt
                               ),
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

   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_agent.create_summary: '
            || dbms_utility.format_error_stack
         );
         raise;
   end create_summary;

   /**
    * @procedure create_summary
    * @description Loads model provider details from cb_ai_models, then creates a summary.
    */
   procedure create_summary (
      p_model_id                   in number,
      p_bot_id                     in number,
      p_keep_latest_message_count  in number default 10,
      p_max_tokens                 in number default null
   ) is
      l_config         t_ai_model_config;
      l_signature_type varchar2(30);
   begin
      l_config := get_ai_model_config(p_model_id);
      l_signature_type := normalize_signature_type(l_config.signature_type);

      create_summary(
         p_signature_type            => l_signature_type,
         p_url                       => l_config.url,
         p_api_key                   => get_header_api_key(
                                           p_signature_type => l_signature_type,
                                           p_api_key        => l_config.api_key
                                        ),
         p_model                     => l_config.model,
         p_bot_id                    => p_bot_id,
         p_keep_latest_message_count => p_keep_latest_message_count,
         p_max_tokens                => nvl(p_max_tokens, l_config.max_tokens)
      );
   exception
      when others then
         apex_debug.error(
            'Unexpected error in cb_agent.create_summary by model ID: '
            || dbms_utility.format_error_stack
         );
         raise;
   end create_summary;

end cb_agent;
/
