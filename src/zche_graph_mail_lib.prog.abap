*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_MAIL_LIB: e-mail through Microsoft Graph (INCLUDE)
*& abap-graph 0.7.1, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_MAIL_LIB with type "Include
*& program", paste this source, save. It needs ZCHE_GRAPH_CORE:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_mail_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Sending (as one mailbox, for example sap@contoso.com):
*&   - text or HTML, To/Cc/Bcc, reply-to, importance, inline pictures
*&   - attachments of any kind, also a spool request as PDF
*&   - small mails in one call; larger ones as a draft that gets its
*&     attachments one by one (big ones in pieces) and is then sent
*& Reading:
*&   - messages of a folder (only unread if wanted), body, attachments
*&   - mark as read, move to another folder
*&
*& Application permissions (Microsoft Entra ID, with admin consent):
*&   Mail.Send for sending, Mail.ReadWrite for drafts, reading, marking
*&   and moving. Restrict them to the mailboxes SAP may use (Exchange
*&   Online: RBAC for Applications or an application access policy);
*&   otherwise the application can send as anybody in the company.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types and limits
*----------------------------------------------------------------------*
INTERFACE lif_graph_mail.
  TYPES:
    BEGIN OF ty_address,
      address TYPE string,
      name    TYPE string,
    END OF ty_address,
    ty_addresses TYPE STANDARD TABLE OF ty_address WITH DEFAULT KEY.

  " CONTENT_ID and INLINE: for pictures shown in an HTML body (<img src="cid:logo">)
  TYPES:
    BEGIN OF ty_attachment,
      name         TYPE string,
      content_type TYPE string,
      content      TYPE xstring,
      inline       TYPE abap_bool,
      content_id   TYPE string,
    END OF ty_attachment,
    ty_attachments TYPE STANDARD TABLE OF ty_attachment WITH DEFAULT KEY.

  " IMPORTANCE: low, normal or high (empty = normal).
  " NO_SENT_COPY: X = do not keep a copy in Sent Items (only for small mails)
  TYPES:
    BEGIN OF ty_mail,
      subject      TYPE string,
      body         TYPE string,
      html         TYPE abap_bool,
      to           TYPE ty_addresses,
      cc           TYPE ty_addresses,
      bcc          TYPE ty_addresses,
      reply_to     TYPE ty_addresses,
      importance   TYPE string,
      attachments  TYPE ty_attachments,
      no_sent_copy TYPE abap_bool,
    END OF ty_mail.

  TYPES:
    BEGIN OF ty_message,
      id              TYPE string,
      received        TYPE string,
      from_address    TYPE string,
      from_name       TYPE string,
      subject         TYPE string,
      preview         TYPE string,
      is_read         TYPE abap_bool,
      has_attachments TYPE abap_bool,
      importance      TYPE string,
    END OF ty_message,
    ty_messages TYPE STANDARD TABLE OF ty_message WITH DEFAULT KEY.

  " KIND: file, item (an attached mail) or reference (a link to a file)
  TYPES:
    BEGIN OF ty_attachment_info,
      id           TYPE string,
      name         TYPE string,
      content_type TYPE string,
      size         TYPE i,
      inline       TYPE abap_bool,
      kind         TYPE string,
    END OF ty_attachment_info,
    ty_attachment_infos TYPE STANDARD TABLE OF ty_attachment_info WITH DEFAULT KEY.

  " Microsoft accepts at most 4 MB per request; Base64 makes attachments a third
  " larger. Up to this sum of attachments the mail goes in one request.
  CONSTANTS max_direct_bytes TYPE i VALUE 2900000.
  " A larger mail becomes a draft. Its attachments under 3 MB are added one
  " request each; from 3 MB on through an upload session, as Microsoft
  " describes it (3 to 150 MB)
  CONSTANTS upload_min_bytes TYPE i VALUE 3145728.
  " Pieces of a large attachment must be multiples of 320 KiB: 10 x 320 KiB
  CONSTANTS upload_chunk_bytes TYPE i VALUE 3276800.
  " Exchange Online accepts attachments up to 150 MB
  CONSTANTS max_attachment_bytes TYPE i VALUE 157286400.
ENDINTERFACE.


*----------------------------------------------------------------------*
* E-mail as one mailbox
*----------------------------------------------------------------------*
CLASS lcl_graph_mail DEFINITION FINAL.
  PUBLIC SECTION.
    "! IV_MAILBOX: the mailbox SAP sends as and reads, for example sap@contoso.com
    METHODS constructor
      IMPORTING
        io_client  TYPE REF TO lcl_graph_client
        iv_mailbox TYPE string.

    " Text like  a@b.com; Derya Kaya <derya@b.com>, c@d.com  -> addresses (separators ; and ,)
    CLASS-METHODS addresses
      IMPORTING
        iv_text             TYPE string
      RETURNING
        value(rt_addresses) TYPE lif_graph_mail=>ty_addresses.

    "! A spool request (ABAP list or SAPscript/Smart Forms) as a PDF attachment
    CLASS-METHODS attachment_from_spool
      IMPORTING
        iv_spool             TYPE rspoid
        iv_name              TYPE string OPTIONAL
      RETURNING
        value(rs_attachment) TYPE lif_graph_mail=>ty_attachment
      RAISING
        lcx_graph.

    METHODS send
      IMPORTING
        is_mail TYPE lif_graph_mail=>ty_mail
      RAISING
        lcx_graph.

    "! IV_FOLDER: inbox, archive, deleteditems, drafts, sentitems, junkemail or a folder ID
    METHODS list
      IMPORTING
        iv_folder          TYPE string DEFAULT `inbox`
        iv_unread_only     TYPE abap_bool DEFAULT abap_false
        iv_max             TYPE i DEFAULT 50
      RETURNING
        value(rt_messages) TYPE lif_graph_mail=>ty_messages
      RAISING
        lcx_graph.

    METHODS body
      IMPORTING
        iv_message_id  TYPE string
      EXPORTING
        ev_body        TYPE string
        ev_html        TYPE abap_bool
      RAISING
        lcx_graph.

    METHODS attachments
      IMPORTING
        iv_message_id         TYPE string
      RETURNING
        value(rt_attachments) TYPE lif_graph_mail=>ty_attachment_infos
      RAISING
        lcx_graph.

    "! The bytes of a file attachment
    METHODS attachment_content
      IMPORTING
        iv_message_id     TYPE string
        iv_attachment_id  TYPE string
      RETURNING
        value(rv_content) TYPE xstring
      RAISING
        lcx_graph.

    METHODS mark_read
      IMPORTING
        iv_message_id TYPE string
        iv_read       TYPE abap_bool DEFAULT abap_true
      RAISING
        lcx_graph.

    "! Returns the message ID in the new folder (moving changes it)
    METHODS move_to
      IMPORTING
        iv_message_id    TYPE string
        iv_folder        TYPE string
      RETURNING
        value(rv_new_id) TYPE string
      RAISING
        lcx_graph.

    "! Folder ID by display name, at the top level or below the inbox;
    "! well-known names (inbox, archive, ...) are returned as they are
    METHODS folder_id
      IMPORTING
        iv_name      TYPE string
      RETURNING
        value(rv_id) TYPE string
      RAISING
        lcx_graph.

    "! For tests only: smaller limits, so tests need no megabytes
    METHODS set_limits
      IMPORTING
        iv_max_direct_bytes   TYPE i
        iv_upload_chunk_bytes TYPE i
        iv_upload_min_bytes   TYPE i.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mv_mailbox TYPE string.
    DATA mv_max_direct_bytes TYPE i.
    DATA mv_upload_chunk_bytes TYPE i.
    DATA mv_upload_min_bytes TYPE i.

    METHODS path
      IMPORTING
        iv_rest        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    METHODS message_path
      IMPORTING
        iv_message_id  TYPE string
        iv_rest        TYPE string OPTIONAL
      RETURNING
        value(rv_path) TYPE string.

    METHODS validate
      IMPORTING
        is_mail TYPE lif_graph_mail=>ty_mail
      RAISING
        lcx_graph.

    METHODS write_message
      IMPORTING
        io_writer      TYPE REF TO lcl_graph_json_writer
        is_mail        TYPE lif_graph_mail=>ty_mail
        iv_attachments TYPE abap_bool.

    METHODS write_addresses
      IMPORTING
        io_writer    TYPE REF TO lcl_graph_json_writer
        iv_name      TYPE string
        it_addresses TYPE lif_graph_mail=>ty_addresses.

    METHODS write_attachment
      IMPORTING
        io_writer     TYPE REF TO lcl_graph_json_writer
        is_attachment TYPE lif_graph_mail=>ty_attachment.

    METHODS send_as_draft
      IMPORTING
        is_mail TYPE lif_graph_mail=>ty_mail
      RAISING
        lcx_graph.

    METHODS upload
      IMPORTING
        iv_message_id TYPE string
        is_attachment TYPE lif_graph_mail=>ty_attachment
      RAISING
        lcx_graph.

    CLASS-METHODS content_type_of
      IMPORTING
        is_attachment   TYPE lif_graph_mail=>ty_attachment
      RETURNING
        value(rv_type) TYPE string.
ENDCLASS.


CLASS lcl_graph_mail IMPLEMENTATION.

  METHOD constructor.
    mo_client = io_client.
    mv_mailbox = iv_mailbox.
    CONDENSE mv_mailbox.
    mv_max_direct_bytes = lif_graph_mail=>max_direct_bytes.
    mv_upload_chunk_bytes = lif_graph_mail=>upload_chunk_bytes.
    mv_upload_min_bytes = lif_graph_mail=>upload_min_bytes.
  ENDMETHOD.


  METHOD set_limits.
    mv_max_direct_bytes = iv_max_direct_bytes.
    mv_upload_chunk_bytes = iv_upload_chunk_bytes.
    mv_upload_min_bytes = iv_upload_min_bytes.
  ENDMETHOD.


  METHOD path.
    CONCATENATE `/users/` mv_mailbox iv_rest INTO rv_path.
  ENDMETHOD.


  METHOD message_path.
    DATA lv_id TYPE string.
    lv_id = lcl_graph_conv=>url_encode( iv_message_id ).
    CONCATENATE `/users/` mv_mailbox `/messages/` lv_id iv_rest INTO rv_path.
  ENDMETHOD.


  METHOD addresses.
    DATA lt_parts TYPE lcl_graph_json=>ty_names.
    DATA lv_part TYPE string.
    DATA ls_address TYPE lif_graph_mail=>ty_address.
    DATA lv_name TYPE string.
    DATA lv_address TYPE string.
    DATA lv_length TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_start TYPE i.
    DATA lv_count TYPE i.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_quoted TYPE abap_bool.
    DATA lv_angle TYPE abap_bool.

    " ; and , separate addresses, but not inside "..." or <...>:
    " "Kaya, Derya" <derya@b.com> is one address, as Outlook writes it
    lv_length = strlen( iv_text ).
    DO lv_length TIMES.
      lv_offset = sy-index - 1.
      lv_char = iv_text+lv_offset(1).
      IF lv_char = '"'.
        IF lv_quoted = abap_true.
          lv_quoted = abap_false.
        ELSE.
          lv_quoted = abap_true.
        ENDIF.
      ELSEIF lv_quoted = abap_false AND lv_char = '<'.
        lv_angle = abap_true.
      ELSEIF lv_quoted = abap_false AND lv_char = '>'.
        lv_angle = abap_false.
      ELSEIF lv_quoted = abap_false AND lv_angle = abap_false AND ( lv_char = ',' OR lv_char = ';' ).
        lv_count = lv_offset - lv_start.
        lv_part = iv_text+lv_start(lv_count).
        APPEND lv_part TO lt_parts.
        lv_start = lv_offset + 1.
      ENDIF.
    ENDDO.
    lv_count = lv_length - lv_start.
    IF lv_count > 0.
      lv_part = iv_text+lv_start(lv_count).
      APPEND lv_part TO lt_parts.
    ENDIF.
    LOOP AT lt_parts INTO lv_part.
      CONDENSE lv_part.
      IF lv_part IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_address.
      IF lv_part CS '<'.
        " Derya Kaya <derya@b.com>
        SPLIT lv_part AT '<' INTO lv_name lv_address.
        REPLACE ALL OCCURRENCES OF '>' IN lv_address WITH ''.
        REPLACE ALL OCCURRENCES OF '"' IN lv_name WITH ''.
        CONDENSE: lv_name, lv_address.
        ls_address-name = lv_name.
        ls_address-address = lv_address.
      ELSE.
        ls_address-address = lv_part.
      ENDIF.
      APPEND ls_address TO rt_addresses.
    ENDLOOP.
  ENDMETHOD.


  METHOD attachment_from_spool.
    DATA lt_pdf TYPE STANDARD TABLE OF tline WITH DEFAULT KEY.
    DATA ls_pdf TYPE tline.
    DATA lv_bytes TYPE i.
    DATA lv_number TYPE string.
    DATA lv_text TYPE string.
    DATA lv_rc TYPE i.
    FIELD-SYMBOLS <lv_raw> TYPE x.

    " An ABAP list first; if it is not one, SAPscript or Smart Forms (OTF)
    CALL FUNCTION 'CONVERT_ABAPSPOOLJOB_2_PDF'
      EXPORTING
        src_spoolid   = iv_spool
        no_dialog     = abap_true
      IMPORTING
        pdf_bytecount = lv_bytes
      TABLES
        pdf           = lt_pdf
      EXCEPTIONS
        err_no_abap_spooljob = 1
        OTHERS               = 2.
    lv_rc = sy-subrc.
    IF lv_rc = 1.
      CALL FUNCTION 'CONVERT_OTFSPOOLJOB_2_PDF'
        EXPORTING
          src_spoolid   = iv_spool
          no_dialog     = abap_true
        IMPORTING
          pdf_bytecount = lv_bytes
        TABLES
          pdf           = lt_pdf
        EXCEPTIONS
          OTHERS        = 1.
      lv_rc = sy-subrc.
    ENDIF.
    lv_number = iv_spool.
    CONDENSE lv_number.
    IF lv_rc <> 0 OR lv_bytes = 0.
      CONCATENATE `Spool request ` lv_number ` could not be converted to PDF.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = `Check in SP01 that the spool request exists and that you may display it.`.
    ENDIF.

    " The PDF bytes are stored in the text lines; take them as bytes
    LOOP AT lt_pdf INTO ls_pdf.
      ASSIGN ls_pdf TO <lv_raw> CASTING.
      CONCATENATE rs_attachment-content <lv_raw> INTO rs_attachment-content IN BYTE MODE.
    ENDLOOP.
    rs_attachment-content = rs_attachment-content(lv_bytes).
    rs_attachment-content_type = `application/pdf`.
    IF iv_name IS INITIAL.
      CONCATENATE `spool_` lv_number `.pdf` INTO rs_attachment-name.
    ELSE.
      rs_attachment-name = iv_name.
    ENDIF.
  ENDMETHOD.


  METHOD content_type_of.
    DATA lv_name TYPE string.
    rv_type = is_attachment-content_type.
    IF rv_type IS NOT INITIAL.
      RETURN.
    ENDIF.
    lv_name = is_attachment-name.
    TRANSLATE lv_name TO LOWER CASE.
    IF lv_name CP '*.pdf'.
      rv_type = `application/pdf`.
    ELSEIF lv_name CP '*.xlsx'.
      rv_type = `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.
    ELSEIF lv_name CP '*.docx'.
      rv_type = `application/vnd.openxmlformats-officedocument.wordprocessingml.document`.
    ELSEIF lv_name CP '*.csv'.
      rv_type = `text/csv`.
    ELSEIF lv_name CP '*.txt'.
      rv_type = `text/plain`.
    ELSEIF lv_name CP '*.xml'.
      rv_type = `application/xml`.
    ELSEIF lv_name CP '*.png'.
      rv_type = `image/png`.
    ELSEIF lv_name CP '*.jpg' OR lv_name CP '*.jpeg'.
      rv_type = `image/jpeg`.
    ELSEIF lv_name CP '*.zip'.
      rv_type = `application/zip`.
    ELSE.
      rv_type = `application/octet-stream`.
    ENDIF.
  ENDMETHOD.


  METHOD validate.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA lv_size TYPE i.
    DATA lv_text TYPE string.

    IF mv_mailbox IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `No mailbox given to send from.`
          hint = `Enter the mailbox SAP sends as, for example sap@contoso.com.`.
    ENDIF.
    IF is_mail-to IS INITIAL AND is_mail-cc IS INITIAL AND is_mail-bcc IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `The mail has no recipient.`.
    ENDIF.
    IF is_mail-importance IS NOT INITIAL AND is_mail-importance <> `low`
        AND is_mail-importance <> `normal` AND is_mail-importance <> `high`.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `Importance must be low, normal or high.`.
    ENDIF.
    LOOP AT is_mail-attachments INTO ls_attachment.
      lv_size = xstrlen( ls_attachment-content ).
      IF lv_size > lif_graph_mail=>max_attachment_bytes.
        CONCATENATE `Attachment ` ls_attachment-name ` is larger than 150 MB, the limit of Exchange Online.` INTO lv_text.
        RAISE EXCEPTION TYPE lcx_graph
          EXPORTING
            text = lv_text.
      ENDIF.
      IF ls_attachment-name IS INITIAL.
        RAISE EXCEPTION TYPE lcx_graph
          EXPORTING
            text = `An attachment has no file name.`.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD write_addresses.
    DATA ls_address TYPE lif_graph_mail=>ty_address.
    IF it_addresses IS INITIAL.
      RETURN.
    ENDIF.
    io_writer->begin_array( iv_name ).
    LOOP AT it_addresses INTO ls_address.
      io_writer->begin_object( ).
      io_writer->begin_object( `emailAddress` ).
      io_writer->add_string( iv_name = `address` iv_value = ls_address-address ).
      IF ls_address-name IS NOT INITIAL.
        io_writer->add_string( iv_name = `name` iv_value = ls_address-name ).
      ENDIF.
      io_writer->end_object( ).
      io_writer->end_object( ).
    ENDLOOP.
    io_writer->end_array( ).
  ENDMETHOD.


  METHOD write_attachment.
    DATA lv_base64 TYPE string.
    DATA lv_type TYPE string.
    lv_base64 = lcl_graph_conv=>to_base64( is_attachment-content ).
    lv_type = content_type_of( is_attachment ).
    io_writer->begin_object( ).
    io_writer->add_string( iv_name = `@odata.type` iv_value = `#microsoft.graph.fileAttachment` ).
    io_writer->add_string( iv_name = `name` iv_value = is_attachment-name ).
    io_writer->add_string( iv_name = `contentType` iv_value = lv_type ).
    io_writer->add_string( iv_name = `contentBytes` iv_value = lv_base64 ).
    IF is_attachment-inline = abap_true.
      io_writer->add_boolean( iv_name = `isInline` iv_value = abap_true ).
      io_writer->add_string( iv_name = `contentId` iv_value = is_attachment-content_id ).
    ENDIF.
    io_writer->end_object( ).
  ENDMETHOD.


  METHOD write_message.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    io_writer->add_string( iv_name = `subject` iv_value = is_mail-subject ).
    IF is_mail-importance IS NOT INITIAL.
      io_writer->add_string( iv_name = `importance` iv_value = is_mail-importance ).
    ENDIF.
    io_writer->begin_object( `body` ).
    IF is_mail-html = abap_true.
      io_writer->add_string( iv_name = `contentType` iv_value = `HTML` ).
    ELSE.
      io_writer->add_string( iv_name = `contentType` iv_value = `Text` ).
    ENDIF.
    io_writer->add_string( iv_name = `content` iv_value = is_mail-body ).
    io_writer->end_object( ).
    write_addresses( io_writer = io_writer iv_name = `toRecipients` it_addresses = is_mail-to ).
    write_addresses( io_writer = io_writer iv_name = `ccRecipients` it_addresses = is_mail-cc ).
    write_addresses( io_writer = io_writer iv_name = `bccRecipients` it_addresses = is_mail-bcc ).
    write_addresses( io_writer = io_writer iv_name = `replyTo` it_addresses = is_mail-reply_to ).
    IF iv_attachments = abap_true AND is_mail-attachments IS NOT INITIAL.
      io_writer->begin_array( `attachments` ).
      LOOP AT is_mail-attachments INTO ls_attachment.
        write_attachment( io_writer = io_writer is_attachment = ls_attachment ).
      ENDLOOP.
      io_writer->end_array( ).
    ENDIF.
  ENDMETHOD.


  METHOD send.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA lv_total TYPE i.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_save TYPE abap_bool.

    validate( is_mail ).
    LOOP AT is_mail-attachments INTO ls_attachment.
      lv_total = lv_total + xstrlen( ls_attachment-content ).
    ENDLOOP.
    IF lv_total > mv_max_direct_bytes.
      send_as_draft( is_mail ).
      RETURN.
    ENDIF.

    " Everything fits into one request
    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->begin_object( `message` ).
    write_message( io_writer = lo_writer is_mail = is_mail iv_attachments = abap_true ).
    lo_writer->end_object( ).
    IF is_mail-no_sent_copy = abap_true.
      lv_save = abap_false.
    ELSE.
      lv_save = abap_true.
    ENDIF.
    lo_writer->add_boolean( iv_name = `saveToSentItems` iv_value = lv_save ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = path( `/sendMail` ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
  ENDMETHOD.


  METHOD send_as_draft.
    " Too large for one request: a draft, then the attachments one by one, then send.
    " A sent draft always stays in Sent Items.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_id TYPE string.
    DATA lv_size TYPE i.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    write_message( io_writer = lo_writer is_mail = is_mail iv_attachments = abap_false ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = path( `/messages` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    lv_id = lo_json->get( `id` ).
    IF lv_id IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `Microsoft Graph created the draft but returned no ID.`.
    ENDIF.

    LOOP AT is_mail-attachments INTO ls_attachment.
      lv_size = xstrlen( ls_attachment-content ).
      IF lv_size < mv_upload_min_bytes.
        CREATE OBJECT lo_writer.
        write_attachment( io_writer = lo_writer is_attachment = ls_attachment ).
        lv_json = lo_writer->result( ).
        lv_path = message_path( iv_message_id = lv_id iv_rest = `/attachments` ).
        mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
      ELSE.
        upload( iv_message_id = lv_id is_attachment = ls_attachment ).
      ENDIF.
    ENDLOOP.

    lv_path = message_path( iv_message_id = lv_id iv_rest = `/send` ).
    mo_client->request( iv_method = 'POST' iv_path = lv_path ).
  ENDMETHOD.


  METHOD upload.
    " Large attachment: an upload session, then the bytes in pieces to the URL Microsoft gives
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_url TYPE string.
    DATA lv_type TYPE string.
    DATA lv_size TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_length TYPE i.
    DATA lv_last TYPE i.
    DATA lv_chunk TYPE xstring.
    DATA lt_headers TYPE tihttpnvp.
    DATA ls_header TYPE ihttpnvp.
    DATA lv_from TYPE string.
    DATA lv_to TYPE string.
    DATA lv_total TYPE string.

    lv_size = xstrlen( is_attachment-content ).
    lv_type = content_type_of( is_attachment ).
    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->begin_object( `AttachmentItem` ).
    lo_writer->add_string( iv_name = `attachmentType` iv_value = `file` ).
    lo_writer->add_string( iv_name = `name` iv_value = is_attachment-name ).
    lo_writer->add_number( iv_name = `size` iv_value = lv_size ).
    lo_writer->add_string( iv_name = `contentType` iv_value = lv_type ).
    IF is_attachment-inline = abap_true.
      lo_writer->add_boolean( iv_name = `isInline` iv_value = abap_true ).
      lo_writer->add_string( iv_name = `contentId` iv_value = is_attachment-content_id ).
    ENDIF.
    lo_writer->end_object( ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = message_path( iv_message_id = iv_message_id iv_rest = `/attachments/createUploadSession` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    lv_url = lo_json->get( `uploadUrl` ).
    IF lv_url IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `Microsoft Graph opened no upload session for the attachment.`.
    ENDIF.

    lv_total = lcl_graph_conv=>num( lv_size ).
    WHILE lv_offset < lv_size.
      lv_length = lv_size - lv_offset.
      IF lv_length > mv_upload_chunk_bytes.
        lv_length = mv_upload_chunk_bytes.
      ENDIF.
      lv_chunk = is_attachment-content+lv_offset(lv_length).
      lv_last = lv_offset + lv_length - 1.
      lv_from = lcl_graph_conv=>num( lv_offset ).
      lv_to = lcl_graph_conv=>num( lv_last ).
      CLEAR lt_headers.
      ls_header-name = 'Content-Type'.
      ls_header-value = 'application/octet-stream'.
      APPEND ls_header TO lt_headers.
      ls_header-name = 'Content-Range'.
      CONCATENATE `bytes ` lv_from '-' lv_to '/' lv_total INTO ls_header-value.
      APPEND ls_header TO lt_headers.
      mo_client->request_url( iv_method = 'PUT' iv_url = lv_url iv_body = lv_chunk it_headers = lt_headers ).
      lv_offset = lv_offset + lv_length.
    ENDWHILE.
  ENDMETHOD.


  METHOD list.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_message TYPE lif_graph_mail=>ty_message.
    DATA lv_path TYPE string.
    DATA lv_folder TYPE string.
    DATA lv_top TYPE i.
    DATA lv_top_text TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_prefix TYPE string.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_value TYPE string.
    DATA lv_lines TYPE i.

    IF iv_max <= 0.
      RETURN.
    ENDIF.
    lv_top = iv_max.
    IF lv_top > 100.
      lv_top = 100.
    ENDIF.
    lv_top_text = lcl_graph_conv=>num( lv_top ).
    lv_folder = lcl_graph_conv=>url_encode( iv_folder ).
    CONCATENATE `/mailFolders/` lv_folder `/messages`
                `?$select=id,receivedDateTime,from,subject,bodyPreview,isRead,hasAttachments,importance`
                `&$top=` lv_top_text INTO lv_path.
    IF iv_unread_only = abap_true.
      CONCATENATE lv_path `&$filter=isRead%20eq%20false` INTO lv_path.
    ENDIF.
    lv_path = path( lv_path ).
    lt_pages = mo_client->get_pages( iv_path = lv_path iv_max_items = iv_max ).

    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        CLEAR ls_message.
        CONCATENATE lv_prefix `id` INTO lv_field.
        ls_message-id = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `receivedDateTime` INTO lv_field.
        ls_message-received = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `from/emailAddress/address` INTO lv_field.
        ls_message-from_address = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `from/emailAddress/name` INTO lv_field.
        ls_message-from_name = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `subject` INTO lv_field.
        ls_message-subject = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `bodyPreview` INTO lv_field.
        ls_message-preview = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `importance` INTO lv_field.
        ls_message-importance = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `isRead` INTO lv_field.
        lv_value = lo_page->get( lv_field ).
        IF lv_value = `true`.
          ls_message-is_read = abap_true.
        ENDIF.
        CONCATENATE lv_prefix `hasAttachments` INTO lv_field.
        lv_value = lo_page->get( lv_field ).
        IF lv_value = `true`.
          ls_message-has_attachments = abap_true.
        ENDIF.
        APPEND ls_message TO rt_messages.
        lv_lines = lines( rt_messages ).
        IF lv_lines >= iv_max.
          RETURN.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD body.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_type TYPE string.

    CLEAR: ev_body, ev_html.
    lv_path = message_path( iv_message_id = iv_message_id iv_rest = `?$select=body` ).
    lo_json = mo_client->get_json( lv_path ).
    ev_body = lo_json->get( `body/content` ).
    lv_type = lo_json->get( `body/contentType` ).
    TRANSLATE lv_type TO LOWER CASE.
    IF lv_type = `html`.
      ev_html = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD attachments.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA ls_info TYPE lif_graph_mail=>ty_attachment_info.
    DATA lv_path TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_field TYPE string.
    DATA lv_value TYPE string.

    lv_path = message_path( iv_message_id = iv_message_id
                            iv_rest       = `/attachments?$select=id,name,contentType,size,isInline` ).
    lo_json = mo_client->get_json( lv_path ).
    lv_count = lo_json->count( `value` ).
    DO lv_count TIMES.
      lv_index = sy-index - 1.
      lv_number = lcl_graph_conv=>num( lv_index ).
      CONCATENATE `value/` lv_number `/` INTO lv_prefix.
      CLEAR ls_info.
      CONCATENATE lv_prefix `id` INTO lv_field.
      ls_info-id = lo_json->get( lv_field ).
      CONCATENATE lv_prefix `name` INTO lv_field.
      ls_info-name = lo_json->get( lv_field ).
      CONCATENATE lv_prefix `contentType` INTO lv_field.
      ls_info-content_type = lo_json->get( lv_field ).
      CONCATENATE lv_prefix `size` INTO lv_field.
      ls_info-size = lo_json->get( lv_field ).
      CONCATENATE lv_prefix `isInline` INTO lv_field.
      lv_value = lo_json->get( lv_field ).
      IF lv_value = `true`.
        ls_info-inline = abap_true.
      ENDIF.
      CONCATENATE lv_prefix `@odata.type` INTO lv_field.
      lv_value = lo_json->get( lv_field ).
      IF lv_value CS 'itemAttachment'.
        ls_info-kind = `item`.
      ELSEIF lv_value CS 'referenceAttachment'.
        ls_info-kind = `reference`.
      ELSE.
        ls_info-kind = `file`.
      ENDIF.
      APPEND ls_info TO rt_attachments.
    ENDDO.
  ENDMETHOD.


  METHOD attachment_content.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_id TYPE string.

    lv_id = lcl_graph_conv=>url_encode( iv_attachment_id ).
    CONCATENATE `/attachments/` lv_id `/$value` INTO lv_rest.
    lv_path = message_path( iv_message_id = iv_message_id iv_rest = lv_rest ).
    ls_response = mo_client->request( iv_method = 'GET' iv_path = lv_path ).
    rv_content = ls_response-body.
  ENDMETHOD.


  METHOD mark_read.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_boolean( iv_name = `isRead` iv_value = iv_read ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = message_path( iv_message_id = iv_message_id ).
    mo_client->send_json( iv_method = 'PATCH' iv_path = lv_path iv_json = lv_json ).
  ENDMETHOD.


  METHOD move_to.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `destinationId` iv_value = iv_folder ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = message_path( iv_message_id = iv_message_id iv_rest = `/move` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    rv_new_id = lo_json->get( `id` ).
  ENDMETHOD.


  METHOD folder_id.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_name TYPE string.
    DATA lv_lower TYPE string.
    DATA lv_filter TYPE string.
    DATA lv_path TYPE string.
    DATA lv_text TYPE string.

    lv_lower = iv_name.
    TRANSLATE lv_lower TO LOWER CASE.
    IF lv_lower = `inbox` OR lv_lower = `archive` OR lv_lower = `deleteditems` OR lv_lower = `drafts`
        OR lv_lower = `sentitems` OR lv_lower = `junkemail` OR lv_lower = `outbox`.
      rv_id = lv_lower.
      RETURN.
    ENDIF.

    " OData quotes a single quote by doubling it
    lv_name = iv_name.
    REPLACE ALL OCCURRENCES OF `'` IN lv_name WITH `''`.
    CONCATENATE `displayName eq '` lv_name `'` INTO lv_filter.
    lv_filter = lcl_graph_conv=>url_encode( lv_filter ).
    CONCATENATE `/mailFolders?$select=id&$filter=` lv_filter INTO lv_path.
    lv_path = path( lv_path ).
    lo_json = mo_client->get_json( lv_path ).
    rv_id = lo_json->get( `value/0/id` ).
    IF rv_id IS NOT INITIAL.
      RETURN.
    ENDIF.
    CONCATENATE `/mailFolders/inbox/childFolders?$select=id&$filter=` lv_filter INTO lv_path.
    lv_path = path( lv_path ).
    lo_json = mo_client->get_json( lv_path ).
    rv_id = lo_json->get( `value/0/id` ).
    IF rv_id IS INITIAL.
      CONCATENATE `Mail folder "` iv_name `" was not found at the top level or below the inbox of ` mv_mailbox `.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for e-mail. A test double from ZCHE_GRAPH_CORE answers
*& instead of Microsoft; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_mail DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_cut TYPE REF TO lcl_graph_mail.

    METHODS setup.
    METHODS address_text FOR TESTING.
    METHODS send_small FOR TESTING RAISING lcx_graph.
    METHODS send_large FOR TESTING RAISING lcx_graph.
    METHODS attachment_under_3mb FOR TESTING RAISING lcx_graph.
    METHODS no_recipient FOR TESTING.
    METHODS list_unread FOR TESTING RAISING lcx_graph.
    METHODS attachment_bytes FOR TESTING RAISING lcx_graph.
    METHODS mark_and_move FOR TESTING RAISING lcx_graph.
    METHODS folder_by_name FOR TESTING RAISING lcx_graph.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.

    METHODS bytes
      IMPORTING
        iv_text         TYPE string
      RETURNING
        value(rv_bytes) TYPE xstring.
ENDCLASS.


CLASS ltc_graph_mail IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lo_client TYPE REF TO lcl_graph_client.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `mail` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    CREATE OBJECT lo_client
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
    CREATE OBJECT mo_cut
      EXPORTING
        io_client  = lo_client
        iv_mailbox = `sap@contoso.com`.
    mo_http->token_answer( ).
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD bytes.
    rv_bytes = lcl_graph_conv=>to_utf8( iv_text ).
  ENDMETHOD.


  METHOD address_text.
    DATA lt_addresses TYPE lif_graph_mail=>ty_addresses.
    DATA ls_address TYPE lif_graph_mail=>ty_address.
    DATA lv_count TYPE i.

    lt_addresses = lcl_graph_mail=>addresses( `a@b.com; "Derya Kaya" <derya@b.com>, ,c@d.com` ).
    lv_count = lines( lt_addresses ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
    READ TABLE lt_addresses INDEX 2 INTO ls_address.
    cl_aunit_assert=>assert_equals( act = ls_address-address exp = `derya@b.com` ).
    cl_aunit_assert=>assert_equals( act = ls_address-name exp = `Derya Kaya` ).
    " A comma inside the quoted name, as Outlook copies it, does not split
    lt_addresses = lcl_graph_mail=>addresses( `"Kaya, Derya" <derya@b.com>; ap@x.com, b@y.com` ).
    lv_count = lines( lt_addresses ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
    READ TABLE lt_addresses INDEX 1 INTO ls_address.
    cl_aunit_assert=>assert_equals( act = ls_address-name exp = `Kaya, Derya` ).
    cl_aunit_assert=>assert_equals( act = ls_address-address exp = `derya@b.com` ).
  ENDMETHOD.


  METHOD send_small.
    DATA ls_mail TYPE lif_graph_mail=>ty_mail.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_expected TYPE string.

    ls_mail-subject = `Fatura 4711`.
    ls_mail-body = `<p>Merhaba</p>`.
    ls_mail-html = abap_true.
    ls_mail-to = lcl_graph_mail=>addresses( `Derya <derya@b.com>` ).
    ls_mail-importance = `high`.
    ls_attachment-name = `a.txt`.
    ls_attachment-content = bytes( `hello` ).
    APPEND ls_attachment TO ls_mail-attachments.
    mo_http->answer( iv_status = 202 ).
    mo_cut->send( ls_mail ).

    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `POST` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/sendMail` ).
    CONCATENATE `{"message":{"subject":"Fatura 4711","importance":"high","body":{"contentType":"HTML","content":"<p>Merhaba</p>"},`
                `"toRecipients":[{"emailAddress":{"address":"derya@b.com","name":"Derya"}}],`
                `"attachments":[{"@odata.type":"#microsoft.graph.fileAttachment","name":"a.txt","contentType":"text/plain",`
                `"contentBytes":"aGVsbG8="}]},"saveToSentItems":true}` INTO lv_expected.
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = lv_expected ).
  ENDMETHOD.


  METHOD attachment_under_3mb.
    " Too large for one request in total, but under 3 MB itself: the draft
    " gets it in one request, without an upload session
    DATA ls_mail TYPE lif_graph_mail=>ty_mail.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_count TYPE i.

    mo_cut->set_limits( iv_max_direct_bytes = 10 iv_upload_chunk_bytes = 4 iv_upload_min_bytes = 20 ).
    ls_mail-subject = `2.95 MB`.
    ls_mail-to = lcl_graph_mail=>addresses( `derya@b.com` ).
    ls_attachment-name = `report.pdf`.
    ls_attachment-content = bytes( `ABCDEFGHIJKL` ).
    APPEND ls_attachment TO ls_mail-attachments.
    mo_http->answer( iv_status = 201 iv_body = `{"id":"M1"}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"A1"}` ).
    mo_http->answer( iv_status = 202 ).
    mo_cut->send( ls_mail ).
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 4 ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/messages/M1/attachments` ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/messages/M1/send` ).
  ENDMETHOD.


  METHOD send_large.
    " Limits of 10, 11 and 4 bytes stand for 2.9 MB, 3 MB and pieces of 3.2 MB
    DATA ls_mail TYPE lif_graph_mail=>ty_mail.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_range TYPE string.
    DATA lv_count TYPE i.
    DATA lv_more TYPE xstring.

    mo_cut->set_limits( iv_max_direct_bytes = 10 iv_upload_chunk_bytes = 4 iv_upload_min_bytes = 11 ).
    ls_mail-subject = `Big`.
    ls_mail-to = lcl_graph_mail=>addresses( `derya@b.com` ).
    ls_attachment-name = `small.txt`.
    ls_attachment-content = bytes( `123456` ).
    APPEND ls_attachment TO ls_mail-attachments.
    ls_attachment-name = `big.pdf`.
    ls_attachment-content = bytes( `ABCDEFGHIJ` ).
    lv_more = bytes( `KL` ).
    CONCATENATE ls_attachment-content lv_more INTO ls_attachment-content IN BYTE MODE.
    APPEND ls_attachment TO ls_mail-attachments.

    mo_http->answer( iv_status = 201 iv_body = `{"id":"M1"}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"A1"}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"uploadUrl":"https://outlook.office.com/up?key=1"}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_http->answer( iv_status = 201 ).
    mo_http->answer( iv_status = 202 ).
    mo_cut->send( ls_mail ).

    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 8 ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/messages` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/messages/M1/attachments` ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri
                                    exp = `/v1.0/users/sap@contoso.com/messages/M1/attachments/createUploadSession` ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-body exp = '*"size":12*' ).
    ls_request = request_at( 5 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `https://outlook.office.com/up?key=1` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `ABCD` ).
    lv_range = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Content-Range` ).
    cl_aunit_assert=>assert_equals( act = lv_range exp = `bytes 0-3/12` ).
    " The upload URL carries its own key: no token may go there
    lv_range = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Authorization` ).
    cl_aunit_assert=>assert_initial( lv_range ).
    ls_request = request_at( 7 ).
    lv_range = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Content-Range` ).
    cl_aunit_assert=>assert_equals( act = lv_range exp = `bytes 8-11/12` ).
    ls_request = request_at( 8 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/messages/M1/send` ).
  ENDMETHOD.


  METHOD no_recipient.
    DATA ls_mail TYPE lif_graph_mail=>ty_mail.
    DATA lv_failed TYPE abap_bool.
    ls_mail-subject = `x`.
    TRY.
        mo_cut->send( ls_mail ).
      CATCH lcx_graph.
        lv_failed = abap_true.
    ENDTRY.
    cl_aunit_assert=>assert_equals( act = lv_failed exp = abap_true ).
  ENDMETHOD.


  METHOD list_unread.
    DATA lt_messages TYPE lif_graph_mail=>ty_messages.
    DATA ls_message TYPE lif_graph_mail=>ty_message.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_count TYPE i.
    DATA lv_json TYPE string.

    CONCATENATE `{"value":[{"id":"M1","receivedDateTime":"2026-11-02T08:00:00Z","subject":"Fatura",`
                `"from":{"emailAddress":{"address":"satis@derya.com","name":"Derya"}},`
                `"isRead":false,"hasAttachments":true,"importance":"normal","bodyPreview":"Ekte"},`
                `{"id":"M2","subject":"Two","isRead":false}]}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    lt_messages = mo_cut->list( iv_unread_only = abap_true iv_max = 10 ).
    lv_count = lines( lt_messages ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    READ TABLE lt_messages INDEX 1 INTO ls_message.
    cl_aunit_assert=>assert_equals( act = ls_message-from_address exp = `satis@derya.com` ).
    cl_aunit_assert=>assert_equals( act = ls_message-has_attachments exp = abap_true ).
    cl_aunit_assert=>assert_equals( act = ls_message-is_read exp = abap_false ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri
                                     exp = '/v1.0/users/sap@contoso.com/mailFolders/inbox/messages?$select=*&$top=10&$filter=isRead%20eq%20false' ).
  ENDMETHOD.


  METHOD attachment_bytes.
    DATA lv_content TYPE xstring.
    DATA lv_expected TYPE xstring.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 200 iv_body = `%PDF-1.4` ).
    lv_content = mo_cut->attachment_content( iv_message_id = `M1` iv_attachment_id = `A1` ).
    lv_expected = bytes( `%PDF-1.4` ).
    cl_aunit_assert=>assert_equals( act = lv_content exp = lv_expected ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/messages/M1/attachments/A1/$value` ).
  ENDMETHOD.


  METHOD mark_and_move.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"M1","isRead":true}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"M1-NEW"}` ).
    mo_cut->mark_read( `M1` ).
    lv_id = mo_cut->move_to( iv_message_id = `M1` iv_folder = `archive` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `PATCH` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"isRead":true}` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"destinationId":"archive"}` ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `M1-NEW` ).
  ENDMETHOD.


  METHOD folder_by_name.
    DATA lv_id TYPE string.
    lv_id = mo_cut->folder_id( `Archive` ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `archive` ).
    " Not at the top level, found below the inbox
    mo_http->answer( iv_status = 200 iv_body = `{"value":[]}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"F9"}]}` ).
    lv_id = mo_cut->folder_id( `SAP Faturalar` ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `F9` ).
  ENDMETHOD.

ENDCLASS.
