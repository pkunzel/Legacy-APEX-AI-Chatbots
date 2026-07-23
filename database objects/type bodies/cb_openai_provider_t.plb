/**
 * @file cb_openai_provider_t.plb
 * @description Concrete OpenAI-compatible provider subtype body.
 * @module cb_openai_provider_t
 * @dependencies cb_agent, cb_adapter_openai
 * @notes Overrides the abstract provider contract and delegates the provider
 *        payload/response algorithm to cb_adapter_openai.
 */
create or replace type body cb_openai_provider_t as

   overriding member function get_signature_type return varchar2 is
   begin
      return cb_agent.gc_signature_openai;
   end get_signature_type;

   overriding member function get_provider_name return varchar2 is
   begin
      return 'OpenAI-compatible';
   end get_provider_name;

   overriding member function get_text_response (
      p_system_context   in clob,
      p_history_messages in clob,
      p_user_message     in clob
   ) return clob is
   begin
      return cb_adapter_openai.get_text_response(
         p_url              => self.url,
         p_api_key          => self.api_key,
         p_model            => self.model,
         p_system_context   => p_system_context,
         p_history_messages => p_history_messages,
         p_user_message     => p_user_message,
         p_max_tokens       => self.max_tokens
      );
   end get_text_response;

end;
/
