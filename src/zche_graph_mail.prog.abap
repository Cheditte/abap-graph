*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_MAIL: send and read e-mail through Microsoft Graph
*& abap-graph 0.7.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE and ZCHE_GRAPH_MAIL_LIB first,
*& then SE38, create executable program ZCHE_GRAPH_MAIL, paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Two things you can do from the screen:
*&   Send:  a mail as the given mailbox, optionally with a spool
*&          request as PDF (also as a background job, for example after
*&          a report: enter the spool number)
*&   Read:  list the messages of a folder, optionally with attachments
*& Your own programs call LCL_GRAPH_MAIL directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_mail LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_mail_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_conn WITH FRAME TITLE t_conn.
PARAMETERS p_tenant TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
PARAMETERS p_box TYPE c LENGTH 120 LOWER CASE OBLIGATORY.
PARAMETERS p_login TYPE rfcdest DEFAULT 'ZCHE_GRAPH_LOGIN'.
PARAMETERS p_api TYPE rfcdest DEFAULT 'ZCHE_GRAPH_API'.
SELECTION-SCREEN END OF BLOCK b_conn.

SELECTION-SCREEN BEGIN OF BLOCK b_mode WITH FRAME TITLE t_mode.
PARAMETERS r_send RADIOBUTTON GROUP mode DEFAULT 'X'.
PARAMETERS r_read RADIOBUTTON GROUP mode.
SELECTION-SCREEN END OF BLOCK b_mode.

SELECTION-SCREEN BEGIN OF BLOCK b_send WITH FRAME TITLE t_send.
PARAMETERS p_to TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_cc TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_subj TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_body TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_html AS CHECKBOX.
PARAMETERS p_imp TYPE c LENGTH 6 LOWER CASE DEFAULT 'normal'.
PARAMETERS p_spool TYPE rspoid.
PARAMETERS p_nosent AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b_send.

SELECTION-SCREEN BEGIN OF BLOCK b_read WITH FRAME TITLE t_read.
PARAMETERS p_folder TYPE c LENGTH 120 LOWER CASE DEFAULT 'inbox'.
PARAMETERS p_unread AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_max TYPE i DEFAULT 20.
PARAMETERS p_atts AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b_read.


*----------------------------------------------------------------------*
* Texts: Turkish when the user is logged on in Turkish, English otherwise
*----------------------------------------------------------------------*
CLASS lcl_text DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS get
      IMPORTING
        iv_en          TYPE csequence
        iv_tr          TYPE csequence
      RETURNING
        value(rv_text) TYPE string.

    CLASS-METHODS set_selection_texts.

  PRIVATE SECTION.
    CLASS-METHODS add
      IMPORTING
        iv_name  TYPE csequence
        iv_en    TYPE csequence
        iv_tr    TYPE csequence
      CHANGING
        ct_texts TYPE STANDARD TABLE.
ENDCLASS.


CLASS lcl_text IMPLEMENTATION.

  METHOD get.
    IF sy-langu = 'T'.
      rv_text = iv_tr.
    ELSE.
      rv_text = iv_en.
    ENDIF.
  ENDMETHOD.


  METHOD add.
    DATA ls_text TYPE rsseltexts.
    ls_text-name = iv_name.
    ls_text-kind = 'P'.
    ls_text-text = get( iv_en = iv_en iv_tr = iv_tr ).
    APPEND ls_text TO ct_texts.
  ENDMETHOD.


  METHOD set_selection_texts.
    " The function module needs exactly this table type (default key)
    DATA lt_texts TYPE STANDARD TABLE OF rsseltexts WITH DEFAULT KEY.

    t_conn = get( iv_en = 'Connection' iv_tr = 'Bağlantı' ).
    t_mode = get( iv_en = 'What to do' iv_tr = 'Ne yapılacak' ).
    t_send = get( iv_en = 'Mail to send' iv_tr = 'Gönderilecek e-posta' ).
    t_read = get( iv_en = 'Folder to read' iv_tr = 'Okunacak klasör' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_BOX' iv_en = 'Mailbox (sender)' iv_tr = 'Posta kutusu (gönderen)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_SEND' iv_en = 'Send a mail' iv_tr = 'E-posta gönder' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TO' iv_en = 'To (; between addresses)' iv_tr = 'Kime (adresler arası ;)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_CC' iv_en = 'Cc' iv_tr = 'Bilgi (Cc)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SUBJ' iv_en = 'Subject' iv_tr = 'Konu' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_BODY' iv_en = 'Text' iv_tr = 'Metin' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_HTML' iv_en = 'Text is HTML' iv_tr = 'Metin HTML' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_IMP' iv_en = 'Importance (low/normal/high)' iv_tr = 'Önem (low/normal/high)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SPOOL' iv_en = 'Spool request as PDF' iv_tr = 'PDF olarak spool talebi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_NOSENT' iv_en = 'No copy in Sent Items' iv_tr = 'Gönderilenlere kopya yok' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_READ' iv_en = 'Read a folder' iv_tr = 'Klasör oku' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FOLDER' iv_en = 'Folder (inbox or name)' iv_tr = 'Klasör (inbox ya da adı)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_UNREAD' iv_en = 'Only unread' iv_tr = 'Yalnızca okunmamışlar' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_MAX' iv_en = 'At most (messages)' iv_tr = 'En çok (mesaj)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_ATTS' iv_en = 'Also list attachments' iv_tr = 'Ekleri de listele' CHANGING ct_texts = lt_texts ).

    CALL FUNCTION 'SELECTION_TEXTS_MODIFY'
      EXPORTING
        program                     = sy-repid
      TABLES
        seltexts                    = lt_texts
      EXCEPTIONS
        program_not_found           = 1
        program_cannot_be_generated = 2
        OTHERS                      = 3.
    IF sy-subrc <> 0.                                       "#EC NEEDED
      " Without texts the screen still works; it shows the field names
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* The two actions, written as a list (also works as a background job)
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS send
      IMPORTING
        io_mail TYPE REF TO lcl_graph_mail
        is_mail TYPE lif_graph_mail=>ty_mail
        iv_spool TYPE rspoid.

    CLASS-METHODS read
      IMPORTING
        io_mail        TYPE REF TO lcl_graph_mail
        iv_folder      TYPE string
        iv_unread_only TYPE abap_bool
        iv_max         TYPE i
        iv_attachments TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-METHODS error
      IMPORTING
        ix_graph TYPE REF TO lcx_graph.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD error.
    DATA lv_text TYPE string.
    lv_text = ix_graph->get_text( ).
    CONCATENATE `ERROR ` lv_text INTO lv_text.
    WRITE: / lv_text.
    IF ix_graph->hint IS NOT INITIAL.
      CONCATENATE `      ` ix_graph->hint INTO lv_text.
      WRITE: / lv_text.
    ENDIF.
    IF ix_graph->request_id IS NOT INITIAL.
      CONCATENATE `      request-id: ` ix_graph->request_id INTO lv_text.
      WRITE: / lv_text.
    ENDIF.
    " In the background an E message ends the job as "Cancelled"
    IF sy-batch = abap_true.
      MESSAGE lv_text TYPE 'E'.
    ENDIF.
  ENDMETHOD.


  METHOD send.
    DATA ls_mail TYPE lif_graph_mail=>ty_mail.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_text TYPE string.
    DATA lv_size TYPE string.
    DATA lv_bytes TYPE i.

    ls_mail = is_mail.
    TRY.
        IF iv_spool IS NOT INITIAL.
          ls_attachment = lcl_graph_mail=>attachment_from_spool( iv_spool ).
          APPEND ls_attachment TO ls_mail-attachments.
          lv_bytes = xstrlen( ls_attachment-content ).
          lv_size = lcl_graph_conv=>num( lv_bytes ).
          lv_text = lcl_text=>get( iv_en = `Spool request converted to PDF: ` iv_tr = `Spool talebi PDF'e çevrildi: ` ).
          CONCATENATE lv_text ls_attachment-name ` (` lv_size ` bytes)` INTO lv_text.
          WRITE: / lv_text.
        ENDIF.
        io_mail->send( ls_mail ).
      CATCH lcx_graph INTO lx_graph.
        error( lx_graph ).
        RETURN.
    ENDTRY.
    lv_text = lcl_text=>get( iv_en = 'Sent. Microsoft accepted the mail; delivery follows in Exchange Online.'
                             iv_tr = 'Gönderildi. Microsoft e-postayı kabul etti; teslimat Exchange Online''da sürüyor.' ).
    CONCATENATE `OK ` lv_text INTO lv_text.
    WRITE: / lv_text.
    MESSAGE lv_text TYPE 'S'.
  ENDMETHOD.


  METHOD read.
    DATA lt_messages TYPE lif_graph_mail=>ty_messages.
    DATA ls_message TYPE lif_graph_mail=>ty_message.
    DATA lt_attachments TYPE lif_graph_mail=>ty_attachment_infos.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment_info.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_folder TYPE string.
    DATA lv_text TYPE string.
    DATA lv_flags TYPE string.
    DATA lv_size TYPE string.
    DATA lv_count TYPE string.
    DATA lv_lines TYPE i.

    TRY.
        lv_folder = io_mail->folder_id( iv_folder ).
        lt_messages = io_mail->list( iv_folder      = lv_folder
                                     iv_unread_only = iv_unread_only
                                     iv_max         = iv_max ).
        lv_lines = lines( lt_messages ).
        lv_count = lcl_graph_conv=>num( lv_lines ).
        lv_text = lcl_text=>get( iv_en = `Messages: ` iv_tr = `Mesajlar: ` ).
        CONCATENATE lv_text lv_count INTO lv_text.
        WRITE: / lv_text COLOR COL_HEADING.
        ULINE.
        LOOP AT lt_messages INTO ls_message.
          CLEAR lv_flags.
          IF ls_message-is_read = abap_false.
            CONCATENATE lv_flags `*` INTO lv_flags.
          ENDIF.
          IF ls_message-has_attachments = abap_true.
            CONCATENATE lv_flags `@` INTO lv_flags.
          ENDIF.
          CONCATENATE ls_message-received ls_message-from_address lv_flags ls_message-subject
            INTO lv_text SEPARATED BY ` | `.
          WRITE: / lv_text.
          IF iv_attachments = abap_true AND ls_message-has_attachments = abap_true.
            lt_attachments = io_mail->attachments( ls_message-id ).
            LOOP AT lt_attachments INTO ls_attachment.
              lv_size = lcl_graph_conv=>num( ls_attachment-size ).
              CONCATENATE `      ` ls_attachment-name ` (` ls_attachment-content_type `, ` lv_size ` bytes, `
                          ls_attachment-kind `)` INTO lv_text.
              WRITE: / lv_text.
            ENDLOOP.
          ENDIF.
        ENDLOOP.
      CATCH lcx_graph INTO lx_graph.
        error( lx_graph ).
        RETURN.
    ENDTRY.
    lv_text = lcl_text=>get( iv_en = '* unread, @ with attachments' iv_tr = '* okunmamış, @ ekli' ).
    ULINE.
    WRITE: / lv_text.
  ENDMETHOD.

ENDCLASS.


DATA gs_config TYPE lif_graph=>ty_config.
DATA go_client TYPE REF TO lcl_graph_client.
DATA go_mail TYPE REF TO lcl_graph_mail.
DATA gs_mail TYPE lif_graph_mail=>ty_mail.
DATA gv_text TYPE string.
DATA gv_folder TYPE string.

INITIALIZATION.
  lcl_text=>set_selection_texts( ).

START-OF-SELECTION.
  gv_text = p_tenant.
  CONDENSE gv_text.
  gs_config = lcl_graph_client=>default_config( gv_text ).
  gs_config-login_destination = p_login.
  gs_config-api_destination = p_api.
  CREATE OBJECT go_client
    EXPORTING
      is_config = gs_config.
  gv_text = p_box.
  CREATE OBJECT go_mail
    EXPORTING
      io_client  = go_client
      iv_mailbox = gv_text.

  IF r_send = abap_true.
    gv_text = p_to.
    gs_mail-to = lcl_graph_mail=>addresses( gv_text ).
    gv_text = p_cc.
    gs_mail-cc = lcl_graph_mail=>addresses( gv_text ).
    gs_mail-subject = p_subj.
    gs_mail-body = p_body.
    gs_mail-html = p_html.
    gs_mail-importance = p_imp.
    CONDENSE gs_mail-importance.
    gs_mail-no_sent_copy = p_nosent.
    lcl_app=>send( io_mail = go_mail is_mail = gs_mail iv_spool = p_spool ).
  ELSE.
    gv_folder = p_folder.
    gv_folder = lcl_graph_conv=>trim( gv_folder ).
    lcl_app=>read( io_mail        = go_mail
                   iv_folder      = gv_folder
                   iv_unread_only = p_unread
                   iv_max         = p_max
                   iv_attachments = p_atts ).
  ENDIF.
