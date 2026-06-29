/**
 * @file cb_provider_t.sql
 * @description Abstract provider contract for chatbot provider implementations.
 * @module cb_provider_t
 * @dependencies Oracle SQL object type support
 * @notes This object type is intentionally not instantiable. Concrete provider
 *        subtypes override get_text_response so cb_agent can use true
 *        polymorphic method dispatch through a cb_provider_t variable.
 */
create or replace type cb_provider_t force as object (
   url        varchar2(4000),
   api_key    varchar2(4000),
   model      varchar2(150),
   max_tokens number,

   /**
    * @function get_signature_type
    * @description Returns the normalized signature family implemented by the subtype.
    */
   not instantiable member function get_signature_type return varchar2,

   /**
    * @function get_provider_name
    * @description Returns a human-readable provider name for debug and diagnostics.
    */
   not instantiable member function get_provider_name return varchar2,

   /**
    * @function get_text_response
    * @description Provider-specific request execution contract. p_user_message
    *              is optional when p_history_messages already contains the full transcript.
    */
   not instantiable member function get_text_response (
      p_system_prompt    in clob,
      p_history_messages in clob,
      p_user_message     in clob
   ) return clob
) not instantiable not final;
/
