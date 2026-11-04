*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_CALENDAR: Outlook calendar through Microsoft Graph
*& abap-graph 0.6.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE and ZCHE_GRAPH_CALENDAR_LIB
*& first, then SE38, create executable program ZCHE_GRAPH_CALENDAR,
*& paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& What you can do from the screen (also as a background job):
*&   - list the events of a mailbox's calendar for a period
*&   - create an event; attendees get an invitation
*&   - cancel an event (attendees are told) or delete it
*& Dates and times are in the SAP time zone on the screen.
*& Your own programs call LCL_GRAPH_CALENDAR directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_calendar LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_calendar_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_conn WITH FRAME TITLE t_conn.
PARAMETERS p_tenant TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
PARAMETERS p_box TYPE c LENGTH 120 LOWER CASE OBLIGATORY.
PARAMETERS p_login TYPE rfcdest DEFAULT 'ZCHE_GRAPH_LOGIN'.
PARAMETERS p_api TYPE rfcdest DEFAULT 'ZCHE_GRAPH_API'.
SELECTION-SCREEN END OF BLOCK b_conn.

SELECTION-SCREEN BEGIN OF BLOCK b_do WITH FRAME TITLE t_do.
PARAMETERS r_list RADIOBUTTON GROUP do DEFAULT 'X'.
PARAMETERS r_create RADIOBUTTON GROUP do.
PARAMETERS r_cancel RADIOBUTTON GROUP do.
PARAMETERS r_delete RADIOBUTTON GROUP do.
SELECTION-SCREEN END OF BLOCK b_do.

SELECTION-SCREEN BEGIN OF BLOCK b_when WITH FRAME TITLE t_when.
PARAMETERS p_from TYPE d DEFAULT sy-datum.
PARAMETERS p_to TYPE d.
PARAMETERS p_tstart TYPE t DEFAULT '090000'.
PARAMETERS p_tend TYPE t DEFAULT '100000'.
PARAMETERS p_allday AS CHECKBOX.
PARAMETERS p_tz TYPE timezone.
SELECTION-SCREEN END OF BLOCK b_when.

SELECTION-SCREEN BEGIN OF BLOCK b_what WITH FRAME TITLE t_what.
PARAMETERS p_subj TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_loc TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_att TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_body TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_remind TYPE i DEFAULT 15.
PARAMETERS p_key TYPE c LENGTH 60 LOWER CASE.
PARAMETERS p_id TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_comm TYPE c LENGTH 255 LOWER CASE.
SELECTION-SCREEN END OF BLOCK b_what.


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

    t_conn = get( iv_en = 'Connection and mailbox' iv_tr = 'Bağlantı ve posta kutusu' ).
    t_do = get( iv_en = 'What to do' iv_tr = 'Ne yapılacak' ).
    t_when = get( iv_en = 'When' iv_tr = 'Ne zaman' ).
    t_what = get( iv_en = 'Event' iv_tr = 'Etkinlik' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_BOX' iv_en = 'Mailbox (calendar)' iv_tr = 'Posta kutusu (takvim)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_LIST' iv_en = 'List events' iv_tr = 'Etkinlikleri listele' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_CREATE' iv_en = 'Create an event' iv_tr = 'Etkinlik oluştur' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_CANCEL' iv_en = 'Cancel (attendees are told)' iv_tr = 'İptal et (katılımcılara gider)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_DELETE' iv_en = 'Delete from this calendar' iv_tr = 'Bu takvimden sil' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FROM' iv_en = 'Date (from)' iv_tr = 'Tarih (başlangıç)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TO' iv_en = 'Date to (empty = same day)' iv_tr = 'Bitiş tarihi (boş = aynı gün)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TSTART' iv_en = 'Start time' iv_tr = 'Başlangıç saati' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TEND' iv_en = 'End time' iv_tr = 'Bitiş saati' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_ALLDAY' iv_en = 'All day' iv_tr = 'Tüm gün' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TZ' iv_en = 'SAP time zone (empty = yours)' iv_tr = 'SAP saat dilimi (boş: sizin)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SUBJ' iv_en = 'Subject' iv_tr = 'Konu' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOC' iv_en = 'Location' iv_tr = 'Yer' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_ATT' iv_en = 'Attendees (a@x.com; b@x.com)' iv_tr = 'Katılımcılar (a@x.com;b@x.com)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_BODY' iv_en = 'Text' iv_tr = 'Metin' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_REMIND' iv_en = 'Reminder (minutes, -1 = off)' iv_tr = 'Hatırlatma (dk, -1 = kapalı)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_KEY' iv_en = 'Your key (once per key)' iv_tr = 'Anahtarınız (bir kez)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_ID' iv_en = 'Event ID (from the list)' iv_tr = 'Etkinlik ID (listeden)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_COMM' iv_en = 'Comment with the cancel' iv_tr = 'İptal açıklaması' CHANGING ct_texts = lt_texts ).

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
* The actions, written as a list (also works as a background job)
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run
      IMPORTING
        io_client TYPE REF TO lcl_graph_client
      RAISING
        lcx_graph.

    CLASS-METHODS error
      IMPORTING
        ix_graph TYPE REF TO lcx_graph.

  PRIVATE SECTION.
    CLASS-METHODS when
      IMPORTING
        is_event       TYPE lif_graph_calendar=>ty_event
      RETURNING
        value(rv_text) TYPE string.
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


  METHOD when.
    " 2026-11-10 09:00-10:30, or 2026-12-31 (all day)
    DATA lv_date TYPE c LENGTH 10.
    DATA lv_end_date TYPE c LENGTH 10.
    DATA lv_start TYPE c LENGTH 5.
    DATA lv_end TYPE c LENGTH 5.
    DATA lv_all_day TYPE string.

    CONCATENATE is_event-start_date(4) `-` is_event-start_date+4(2) `-` is_event-start_date+6(2) INTO lv_date.
    CONCATENATE is_event-end_date(4) `-` is_event-end_date+4(2) `-` is_event-end_date+6(2) INTO lv_end_date.
    IF is_event-all_day = abap_true.
      rv_text = lv_date.
      IF is_event-end_date <> is_event-start_date.
        CONCATENATE rv_text ` - ` lv_end_date INTO rv_text.
      ENDIF.
      lv_all_day = lcl_text=>get( iv_en = `(all day)` iv_tr = `(tüm gün)` ).
      CONCATENATE rv_text lv_all_day INTO rv_text SEPARATED BY space.
      RETURN.
    ENDIF.
    CONCATENATE is_event-start_time(2) `:` is_event-start_time+2(2) INTO lv_start.
    CONCATENATE is_event-end_time(2) `:` is_event-end_time+2(2) INTO lv_end.
    IF is_event-end_date = is_event-start_date.
      CONCATENATE lv_date ` ` lv_start `-` lv_end INTO rv_text.
    ELSE.
      CONCATENATE lv_date ` ` lv_start ` - ` lv_end_date ` ` lv_end INTO rv_text.
    ENDIF.
  ENDMETHOD.


  METHOD run.
    DATA lo_calendar TYPE REF TO lcl_graph_calendar.
    DATA lt_events TYPE lif_graph_calendar=>ty_events.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.
    DATA lv_mailbox TYPE string.
    DATA lv_text TYPE string.
    DATA lv_when TYPE string.
    DATA lv_value TYPE string.
    DATA lv_to TYPE d.
    DATA lv_count TYPE i.
    DATA lv_number TYPE string.

    lv_mailbox = p_box.
    CONDENSE lv_mailbox.
    CREATE OBJECT lo_calendar
      EXPORTING
        io_client    = io_client
        iv_mailbox   = lv_mailbox
        iv_time_zone = p_tz.
    lv_to = p_to.
    IF lv_to IS INITIAL.
      lv_to = p_from.
    ENDIF.

    IF r_list = abap_true.
      lt_events = lo_calendar->events( iv_from = p_from iv_to = lv_to ).
      lv_count = lines( lt_events ).
      lv_number = lcl_graph_conv=>num( lv_count ).
      lv_text = lcl_text=>get( iv_en = `Events: ` iv_tr = `Etkinlikler: ` ).
      CONCATENATE lv_text lv_number INTO lv_text.
      WRITE: / lv_text COLOR COL_HEADING.
      ULINE.
      LOOP AT lt_events INTO ls_event.
        lv_when = when( ls_event ).
        CONCATENATE lv_when ls_event-subject ls_event-location ls_event-organizer INTO lv_text SEPARATED BY ` | `.
        IF ls_event-cancelled = abap_true.
          lv_value = lcl_text=>get( iv_en = `cancelled` iv_tr = `iptal` ).
          CONCATENATE lv_text lv_value INTO lv_text SEPARATED BY ` | `.
        ENDIF.
        WRITE: / lv_text.
        CONCATENATE `      ID: ` ls_event-id INTO lv_text.
        WRITE: / lv_text.
      ENDLOOP.

    ELSEIF r_create = abap_true.
      ls_event-subject = p_subj.
      ls_event-body = p_body.
      ls_event-location = p_loc.
      ls_event-start_date = p_from.
      ls_event-end_date = lv_to.
      ls_event-start_time = p_tstart.
      ls_event-end_time = p_tend.
      ls_event-all_day = p_allday.
      ls_event-reminder = p_remind.
      ls_event-transaction_id = p_key.
      lv_value = p_att.
      TRANSLATE lv_value USING ',;'.
      SPLIT lv_value AT ';' INTO TABLE ls_event-attendees.
      ls_event = lo_calendar->create( ls_event ).
      lv_when = when( ls_event ).
      lv_text = lcl_text=>get( iv_en = `Created: ` iv_tr = `Oluşturuldu: ` ).
      CONCATENATE `OK ` lv_text ls_event-subject `, ` lv_when INTO lv_text.
      WRITE: / lv_text.
      CONCATENATE `      ID: ` ls_event-id INTO lv_text.
      WRITE: / lv_text.
      IF ls_event-web_link IS NOT INITIAL.
        CONCATENATE `      ` ls_event-web_link INTO lv_text.
        WRITE: / lv_text.
      ENDIF.

    ELSE.
      lv_value = p_id.
      CONDENSE lv_value.
      IF r_cancel = abap_true.
        lv_text = p_comm.
        lo_calendar->cancel( iv_id = lv_value iv_comment = lv_text ).
        lv_text = lcl_text=>get( iv_en = `OK Cancelled; the attendees get a message.` iv_tr = `OK İptal edildi; katılımcılara bildirim gider.` ).
      ELSE.
        lo_calendar->delete( lv_value ).
        lv_text = lcl_text=>get( iv_en = `OK Deleted from this calendar.` iv_tr = `OK Bu takvimden silindi.` ).
      ENDIF.
      WRITE: / lv_text.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


DATA gs_config TYPE lif_graph=>ty_config.
DATA go_client TYPE REF TO lcl_graph_client.
DATA gx_graph TYPE REF TO lcx_graph.
DATA gv_text TYPE string.

INITIALIZATION.
  lcl_text=>set_selection_texts( ).
  p_tz = sy-zonlo.

START-OF-SELECTION.
  gv_text = p_tenant.
  CONDENSE gv_text.
  gs_config = lcl_graph_client=>default_config( gv_text ).
  gs_config-login_destination = p_login.
  gs_config-api_destination = p_api.
  CREATE OBJECT go_client
    EXPORTING
      is_config = gs_config.
  TRY.
      lcl_app=>run( go_client ).
    CATCH lcx_graph INTO gx_graph.
      lcl_app=>error( gx_graph ).
  ENDTRY.
