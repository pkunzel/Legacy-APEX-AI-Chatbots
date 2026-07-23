/**
 * @file cb_agent_util.sql
 * @description Shared internal helpers for bot provider adapter packages.
 * @module cb_agent_util
 * @dependencies APEX_WEB_SERVICE, APEX_DEBUG, DBMS_LOB, DBMS_UTILITY,
 *               JSON_OBJECT_T, JSON_ARRAY_T
 * @notes Utility package for provider adapters. Not intended as an app-facing API.
 */
create or replace package cb_agent_util as

   /**
    * @constant gc_context_instructions
    * @description JSON key for stable chatbot instructions.
    */
   gc_context_instructions constant varchar2(30) := 'instructions';

   /**
    * @constant gc_context_global_context
    * @description JSON key for chatbot-level stable context.
    */
   gc_context_global_context constant varchar2(30) := 'global_context';

   /**
    * @constant gc_context_conversation_summary
    * @description JSON key for the running conversation summary.
    */
   gc_context_conversation_summary constant varchar2(30) := 'conversation_summary';

   /**
    * @constant gc_context_retrieved_context
    * @description JSON key for per-request retrieved conversation memory.
    */
   gc_context_retrieved_context constant varchar2(30) := 'retrieved_context';

    /**
    * @procedure validate_provider_inputs
    * @description Validates common provider connection inputs.
    * @param p_url Provider endpoint URL.
    * @param p_api_key Provider credential or header value.
    * @param p_model Provider model identifier.
    */
   procedure validate_provider_inputs (
      p_url          in varchar2,
      p_api_key      in varchar2,
      p_model        in varchar2
   );

    /**
    * @procedure append_message
    * @description Appends a role/content JSON object to a message array.
    * @param p_messages JSON message array to extend.
    * @param p_role Conversation role for the appended message.
    * @param p_message Message content for the appended object.
    */
   procedure append_message (
      p_messages in out nocopy json_array_t,
      p_role     in varchar2,
      p_message  in clob
   );

    /**
    * @procedure append_array
    * @description Appends all objects from one JSON array to another.
    * @param p_target JSON array to extend.
    * @param p_source JSON array whose objects are appended.
    */
   procedure append_array (
      p_target in out nocopy json_array_t,
      p_source in json_array_t
   );

    /**
    * @function parse_message_array
    * @description Parses a JSON array CLOB, returning an empty array for null input.
    * @param p_messages JSON array text to parse.
    * @param p_context Context included in validation errors.
    * @param p_package_name Package name included in validation errors.
    * @returns Parsed JSON array, or an empty array when p_messages is null.
    */
   function parse_message_array (
      p_messages     in clob,
      p_context      in varchar2,
      p_package_name in varchar2
   ) return json_array_t;

   /**
    * @function build_system_context
    * @description Builds provider-neutral system context as one JSON object.
    * @param p_instructions Stable chatbot or task instructions.
    * @param p_global_context Optional chatbot-level stable context.
    * @param p_conversation_summary Optional running conversation summary.
    * @param p_retrieved_context Optional per-request retrieved memory.
    * @returns CLOB JSON object containing named system-context sections.
    */
   function build_system_context (
      p_instructions         in clob,
      p_global_context       in clob default null,
      p_conversation_summary in clob default null,
      p_retrieved_context    in clob default null
   ) return clob;

   /**
    * @function parse_system_context
    * @description Parses provider-neutral system-context JSON.
    * @param p_system_context JSON object CLOB to parse.
    * @param p_package_name Package name included in validation errors.
    * @returns Parsed JSON object, or an empty object when input is null.
    */
   function parse_system_context (
      p_system_context in clob,
      p_package_name   in varchar2
   ) return json_object_t;

   /**
    * @function flatten_system_context
    * @description Formats structured system context as one labeled text prompt.
    * @param p_system_context Provider-neutral system-context JSON.
    * @returns CLOB containing populated sections in their defined order.
    */
   function flatten_system_context (
      p_system_context in clob
   ) return clob;

    /**
    * @function make_api_request
    * @description Sends a JSON POST request with provider-specific API key header
    *              and up to two optional extra headers.
    * @param p_url Provider endpoint URL.
    * @param p_api_key Provider credential/header value.
    * @param p_clob_request JSON request payload.
    * @param p_provider_name Provider name used in diagnostics.
    * @param p_api_key_header_name HTTP header name for p_api_key.
    * @param p_extra_header_01_name Optional first extra HTTP header name.
    * @param p_extra_header_01_value Optional first extra HTTP header value.
    * @param p_extra_header_02_name Optional second extra HTTP header name.
    * @param p_extra_header_02_value Optional second extra HTTP header value.
    * @returns CLOB containing the HTTP response body or provider error diagnostics.
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
   ) return clob;

end cb_agent_util;
/
