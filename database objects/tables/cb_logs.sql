create table "CB_LOGS" (
   "CHATBOT_ID" number
      annotations ( "DESCRIPTION" 'Chatbot related to this log entry, when available.',"DISPLAY" 'Chatbot ID' ),
   "ERROR"      clob
      annotations ( "DESCRIPTION" 'Error text captured for later inspection.',"DISPLAY" 'Error' ),
   "LOCATION"   varchar2(4000 char)
      annotations ( "DESCRIPTION" 'Code location that wrote this log entry.',"DISPLAY" 'Location' ),
   "CREATED"    date default on null sysdate not null
      annotations ( "DESCRIPTION" 'Date when the log entry was created.',"DISPLAY" 'Created' )
) annotations ( "DESCRIPTION" 'Lightweight proof-of-concept error dump table.',"DISPLAY" 'Logs' );
