/*
 * @file cb_config.sql
 * @description Creates the application-wide chatbot configuration table.
 * @module Chatbot configuration
 * @dependencies None
 * @notes SHOW_IMAGES uses Y/N instead of SQL BOOLEAN for Oracle compatibility.
 */
create table "CB_CONFIG" (
   "SHOW_IMAGES"              varchar2(1 char) default 'N' not null enable annotations ( "DESCRIPTION" 'Whether chatbot images are displayed (Y/N).'
   ,"DISPLAY" 'Show Images' ),
   "DEFAULT_AVATAR"           blob annotations ( "DESCRIPTION" 'Default avatar image used when a chatbot does not provide one.'
   ,"DISPLAY" 'Default Avatar' ),
   "DEFAULT_AVATAR_FILENAME"  varchar2(255 char) annotations ( "DESCRIPTION" 'Original filename for the default avatar image.'
   ,"DISPLAY" 'Default Avatar Filename' ),
   "DEFAULT_AVATAR_MIME_TYPE" varchar2(100 char) annotations ( "DESCRIPTION" 'MIME type for the default avatar image.'
   ,"DISPLAY" 'Default Avatar MIME Type' ),
   constraint "CB_CONFIG_SHOW_IMAGES_CK"
      check ( show_images in ( 'Y', 'N' ) ) enable
) annotations ( "DESCRIPTION" 'Stores application-wide chatbot display configuration and the default avatar.',"DISPLAY" 'Configuration' );
