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
    * @procedure validate_provider_inputs
    * @description Validates common provider connection inputs.
    */
   procedure validate_provider_inputs (
      p_url          in varchar2,
      p_api_key      in varchar2,
      p_model        in varchar2
   );

   /**
    * @procedure append_message
    * @description Appends a role/content JSON object to a message array.
    */
   procedure append_message (
      p_messages in out nocopy json_array_t,
      p_role     in varchar2,
      p_message  in clob
   );

   /**
    * @procedure append_array
    * @description Appends all objects from one JSON array to another.
    */
   procedure append_array (
      p_target in out nocopy json_array_t,
      p_source in json_array_t
   );

   /**
    * @function parse_message_array
    * @description Parses a JSON array CLOB, returning an empty array for null input.
    */
   function parse_message_array (
      p_messages     in clob,
      p_context      in varchar2,
      p_package_name in varchar2
   ) return json_array_t;

   /**
    * @function make_api_request
    * @description Sends a JSON POST request with provider-specific API key header
    *              and up to two optional extra headers.
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
