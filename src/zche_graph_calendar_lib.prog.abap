*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_CALENDAR_LIB: Outlook calendar through Microsoft Graph
*& (INCLUDE)
*& abap-graph 0.6.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_CALENDAR_LIB with type
*& "Include program", paste this source, save. It needs ZCHE_GRAPH_CORE:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_calendar_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& The calendar of one mailbox (a user or a shared mailbox):
*&   - create an event, with attendees who get an invitation
*&   - list the events of a period
*&   - change an event, cancel it (attendees are told) or delete it
*& Dates and times are SAP dates and times in an SAP time zone (by
*& default the user's, SY-ZONLO); they travel to Microsoft as UTC.
*&
*& Application permissions (Microsoft Entra ID, with admin consent):
*& Calendars.ReadWrite. Restrict it to the SAP mailboxes, as for e-mail.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
INTERFACE lif_graph_calendar.
  TYPES ty_addresses TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

  " SHOW_AS: free, tentative, busy, oof or workingElsewhere.
  " An all-day event takes START_DATE to END_DATE (both included); times are
  " ignored. REMINDER: minutes before the start; -1 = no reminder.
  " TRANSACTION_ID: your own key, for example the SAP document number.
  " Microsoft creates an event only once per key, so a repeated call
  " does not make a second event.
  TYPES:
    BEGIN OF ty_event,
      id             TYPE string,
      subject        TYPE string,
      body           TYPE string,
      html           TYPE abap_bool,
      start_date     TYPE d,
      start_time     TYPE t,
      end_date       TYPE d,
      end_time       TYPE t,
      all_day        TYPE abap_bool,
      location       TYPE string,
      attendees      TYPE ty_addresses,
      optional       TYPE ty_addresses,
      show_as        TYPE string,
      reminder       TYPE i,
      categories     TYPE ty_addresses,
      transaction_id TYPE string,
      organizer      TYPE string,
      cancelled      TYPE abap_bool,
      web_link       TYPE string,
    END OF ty_event,
    ty_events TYPE STANDARD TABLE OF ty_event WITH DEFAULT KEY.
ENDINTERFACE.


*----------------------------------------------------------------------*
* The calendar of one mailbox
*----------------------------------------------------------------------*
CLASS lcl_graph_calendar DEFINITION FINAL.
  PUBLIC SECTION.
    "! IV_MAILBOX: the address of a user or a shared mailbox.
    "! IV_TIME_ZONE: the SAP time zone of the dates and times (empty: SY-ZONLO)
    METHODS constructor
      IMPORTING
        io_client    TYPE REF TO lcl_graph_client
        iv_mailbox   TYPE string
        iv_time_zone TYPE timezone OPTIONAL.

    "! Returns the event as Microsoft stored it, with its ID
    METHODS create
      IMPORTING
        is_event        TYPE lif_graph_calendar=>ty_event
      RETURNING
        value(rs_event) TYPE lif_graph_calendar=>ty_event
      RAISING
        lcx_graph.

    "! Events that touch the days IV_FROM to IV_TO (both included), the
    "! occurrences of series one by one
    METHODS events
      IMPORTING
        iv_from          TYPE d
        iv_to            TYPE d
        iv_max           TYPE i DEFAULT 1000
      RETURNING
        value(rt_events) TYPE lif_graph_calendar=>ty_events
      RAISING
        lcx_graph.

    METHODS event
      IMPORTING
        iv_id           TYPE string
      RETURNING
        value(rs_event) TYPE lif_graph_calendar=>ty_event
      RAISING
        lcx_graph.

    "! Sends subject, body, time, location, attendees and the rest again;
    "! attendees get an updated invitation
    METHODS update
      IMPORTING
        iv_id    TYPE string
        is_event TYPE lif_graph_calendar=>ty_event
      RAISING
        lcx_graph.

    "! Only the organizer can cancel; attendees get IV_COMMENT with the cancellation
    METHODS cancel
      IMPORTING
        iv_id      TYPE string
        iv_comment TYPE string OPTIONAL
      RAISING
        lcx_graph.

    "! Removes the event from this calendar only; attendees are not told
    METHODS delete
      IMPORTING
        iv_id TYPE string
      RAISING
        lcx_graph.

    "! "2026-11-10T09:00:00" (UTC) for an SAP date and time in IV_TIME_ZONE
    CLASS-METHODS to_utc
      IMPORTING
        iv_date        TYPE d
        iv_time        TYPE t
        iv_time_zone   TYPE timezone
      RETURNING
        value(rv_text) TYPE string.

    "! "2026-11-10T09:00:00.0000000" (UTC) -> SAP date and time in IV_TIME_ZONE
    CLASS-METHODS from_utc
      IMPORTING
        iv_text      TYPE string
        iv_time_zone TYPE timezone
      EXPORTING
        ev_date      TYPE d
        ev_time      TYPE t.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mv_mailbox TYPE string.
    DATA mv_time_zone TYPE timezone.

    METHODS path
      IMPORTING
        iv_rest        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    METHODS event_json
      IMPORTING
        is_event       TYPE lif_graph_calendar=>ty_event
      RETURNING
        value(rv_json) TYPE string
      RAISING
        lcx_graph.

    METHODS event_from_json
      IMPORTING
        io_json         TYPE REF TO lcl_graph_json
        iv_prefix       TYPE string
      RETURNING
        value(rs_event) TYPE lif_graph_calendar=>ty_event.

    CLASS-METHODS add_attendees
      IMPORTING
        io_writer    TYPE REF TO lcl_graph_json_writer
        it_addresses TYPE lif_graph_calendar=>ty_addresses
        iv_type      TYPE string.

    CLASS-METHODS add_time
      IMPORTING
        io_writer TYPE REF TO lcl_graph_json_writer
        iv_name   TYPE string
        iv_text   TYPE string.

    CLASS-METHODS utc_headers
      RETURNING
        value(rt_headers) TYPE tihttpnvp.
ENDCLASS.


CLASS lcl_graph_calendar IMPLEMENTATION.

  METHOD constructor.
    mo_client = io_client.
    mv_mailbox = iv_mailbox.
    CONDENSE mv_mailbox.
    mv_time_zone = iv_time_zone.
    IF mv_time_zone IS INITIAL.
      mv_time_zone = sy-zonlo.
    ENDIF.
  ENDMETHOD.


  METHOD path.
    CONCATENATE `/users/` mv_mailbox iv_rest INTO rv_path.
  ENDMETHOD.


  METHOD utc_headers.
    " Times in answers in UTC; they are turned into SAP time here
    DATA ls_header TYPE ihttpnvp.
    ls_header-name = 'Prefer'.
    ls_header-value = 'outlook.timezone="UTC"'.
    APPEND ls_header TO rt_headers.
  ENDMETHOD.


  METHOD to_utc.
    DATA lv_stamp TYPE timestamp.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.
    DATA lv_utc TYPE timezone VALUE 'UTC'.

    CONVERT DATE iv_date TIME iv_time INTO TIME STAMP lv_stamp TIME ZONE iv_time_zone.
    CONVERT TIME STAMP lv_stamp TIME ZONE lv_utc INTO DATE lv_date TIME lv_time.
    CONCATENATE lv_date(4) `-` lv_date+4(2) `-` lv_date+6(2) `T`
                lv_time(2) `:` lv_time+2(2) `:` lv_time+4(2) INTO rv_text.
  ENDMETHOD.


  METHOD from_utc.
    DATA lv_stamp TYPE timestamp.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.
    DATA lv_utc TYPE timezone VALUE 'UTC'.

    CLEAR: ev_date, ev_time.
    IF strlen( iv_text ) < 19.
      RETURN.
    ENDIF.
    CONCATENATE iv_text(4) iv_text+5(2) iv_text+8(2) INTO lv_date.
    CONCATENATE iv_text+11(2) iv_text+14(2) iv_text+17(2) INTO lv_time.
    CONVERT DATE lv_date TIME lv_time INTO TIME STAMP lv_stamp TIME ZONE lv_utc.
    CONVERT TIME STAMP lv_stamp TIME ZONE iv_time_zone INTO DATE ev_date TIME ev_time.
  ENDMETHOD.


  METHOD add_time.
    io_writer->begin_object( iv_name ).
    io_writer->add_string( iv_name = `dateTime` iv_value = iv_text ).
    io_writer->add_string( iv_name = `timeZone` iv_value = `UTC` ).
    io_writer->end_object( ).
  ENDMETHOD.


  METHOD add_attendees.
    DATA lv_address TYPE string.
    LOOP AT it_addresses INTO lv_address.
      CONDENSE lv_address.
      IF lv_address IS INITIAL.
        CONTINUE.
      ENDIF.
      io_writer->begin_object( ).
      io_writer->add_string( iv_name = `type` iv_value = iv_type ).
      io_writer->begin_object( `emailAddress` ).
      io_writer->add_string( iv_name = `address` iv_value = lv_address ).
      io_writer->end_object( ).
      io_writer->end_object( ).
    ENDLOOP.
  ENDMETHOD.


  METHOD event_json.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lv_start TYPE string.
    DATA lv_end TYPE string.
    DATA lv_text TYPE string.
    DATA lv_category TYPE string.
    DATA lv_end_date TYPE d.

    IF is_event-all_day = abap_true.
      " Whole days: midnight to midnight; the end day is the day after
      lv_end_date = is_event-end_date.
      IF lv_end_date IS INITIAL.
        lv_end_date = is_event-start_date.
      ENDIF.
      lv_end_date = lv_end_date + 1.
      CONCATENATE is_event-start_date(4) `-` is_event-start_date+4(2) `-` is_event-start_date+6(2) `T00:00:00` INTO lv_start.
      CONCATENATE lv_end_date(4) `-` lv_end_date+4(2) `-` lv_end_date+6(2) `T00:00:00` INTO lv_end.
    ELSE.
      lv_start = to_utc( iv_date = is_event-start_date iv_time = is_event-start_time iv_time_zone = mv_time_zone ).
      lv_end_date = is_event-end_date.
      IF lv_end_date IS INITIAL.
        lv_end_date = is_event-start_date.
      ENDIF.
      lv_end = to_utc( iv_date = lv_end_date iv_time = is_event-end_time iv_time_zone = mv_time_zone ).
      IF lv_end <= lv_start.
        CONCATENATE `The event "` is_event-subject `" ends before it starts.` INTO lv_text.
        RAISE EXCEPTION TYPE lcx_graph
          EXPORTING
            text = lv_text.
      ENDIF.
    ENDIF.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `subject` iv_value = is_event-subject ).
    IF is_event-body IS NOT INITIAL.
      lo_writer->begin_object( `body` ).
      IF is_event-html = abap_true.
        lo_writer->add_string( iv_name = `contentType` iv_value = `HTML` ).
      ELSE.
        lo_writer->add_string( iv_name = `contentType` iv_value = `Text` ).
      ENDIF.
      lo_writer->add_string( iv_name = `content` iv_value = is_event-body ).
      lo_writer->end_object( ).
    ENDIF.
    add_time( io_writer = lo_writer iv_name = `start` iv_text = lv_start ).
    add_time( io_writer = lo_writer iv_name = `end` iv_text = lv_end ).
    lo_writer->add_boolean( iv_name = `isAllDay` iv_value = is_event-all_day ).
    IF is_event-location IS NOT INITIAL.
      lo_writer->begin_object( `location` ).
      lo_writer->add_string( iv_name = `displayName` iv_value = is_event-location ).
      lo_writer->end_object( ).
    ENDIF.
    IF is_event-attendees IS NOT INITIAL OR is_event-optional IS NOT INITIAL.
      lo_writer->begin_array( `attendees` ).
      add_attendees( io_writer = lo_writer it_addresses = is_event-attendees iv_type = `required` ).
      add_attendees( io_writer = lo_writer it_addresses = is_event-optional iv_type = `optional` ).
      lo_writer->end_array( ).
    ENDIF.
    IF is_event-show_as IS NOT INITIAL.
      lo_writer->add_string( iv_name = `showAs` iv_value = is_event-show_as ).
    ENDIF.
    IF is_event-reminder < 0.
      lo_writer->add_boolean( iv_name = `isReminderOn` iv_value = abap_false ).
    ELSEIF is_event-reminder > 0.
      lo_writer->add_boolean( iv_name = `isReminderOn` iv_value = abap_true ).
      lo_writer->add_number( iv_name = `reminderMinutesBeforeStart` iv_value = is_event-reminder ).
    ENDIF.
    IF is_event-categories IS NOT INITIAL.
      lo_writer->begin_array( `categories` ).
      LOOP AT is_event-categories INTO lv_category.
        lo_writer->add_string( iv_value = lv_category ).
      ENDLOOP.
      lo_writer->end_array( ).
    ENDIF.
    IF is_event-transaction_id IS NOT INITIAL.
      lo_writer->add_string( iv_name = `transactionId` iv_value = is_event-transaction_id ).
    ENDIF.
    lo_writer->end_object( ).
    rv_json = lo_writer->result( ).
  ENDMETHOD.


  METHOD event_from_json.
    DATA lv_field TYPE string.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_type TYPE string.
    DATA lv_address TYPE string.

    CONCATENATE iv_prefix `id` INTO lv_field.
    rs_event-id = io_json->get( lv_field ).
    CONCATENATE iv_prefix `subject` INTO lv_field.
    rs_event-subject = io_json->get( lv_field ).
    CONCATENATE iv_prefix `bodyPreview` INTO lv_field.
    rs_event-body = io_json->get( lv_field ).
    CONCATENATE iv_prefix `isAllDay` INTO lv_field.
    lv_value = io_json->get( lv_field ).
    IF lv_value = `true`.
      rs_event-all_day = abap_true.
    ENDIF.
    CONCATENATE iv_prefix `isCancelled` INTO lv_field.
    lv_value = io_json->get( lv_field ).
    IF lv_value = `true`.
      rs_event-cancelled = abap_true.
    ENDIF.
    CONCATENATE iv_prefix `start/dateTime` INTO lv_field.
    lv_value = io_json->get( lv_field ).
    CONCATENATE iv_prefix `end/dateTime` INTO lv_field.
    IF rs_event-all_day = abap_true AND strlen( lv_value ) >= 10.
      " Whole days stay days; the end day Microsoft gives is the day after
      CONCATENATE lv_value(4) lv_value+5(2) lv_value+8(2) INTO rs_event-start_date.
      lv_value = io_json->get( lv_field ).
      IF strlen( lv_value ) >= 10.
        CONCATENATE lv_value(4) lv_value+5(2) lv_value+8(2) INTO rs_event-end_date.
        rs_event-end_date = rs_event-end_date - 1.
      ENDIF.
    ELSE.
      from_utc( EXPORTING iv_text = lv_value iv_time_zone = mv_time_zone
                IMPORTING ev_date = rs_event-start_date ev_time = rs_event-start_time ).
      lv_value = io_json->get( lv_field ).
      from_utc( EXPORTING iv_text = lv_value iv_time_zone = mv_time_zone
                IMPORTING ev_date = rs_event-end_date ev_time = rs_event-end_time ).
    ENDIF.
    CONCATENATE iv_prefix `location/displayName` INTO lv_field.
    rs_event-location = io_json->get( lv_field ).
    CONCATENATE iv_prefix `showAs` INTO lv_field.
    rs_event-show_as = io_json->get( lv_field ).
    CONCATENATE iv_prefix `organizer/emailAddress/address` INTO lv_field.
    rs_event-organizer = io_json->get( lv_field ).
    CONCATENATE iv_prefix `webLink` INTO lv_field.
    rs_event-web_link = io_json->get( lv_field ).
    CONCATENATE iv_prefix `transactionId` INTO lv_field.
    rs_event-transaction_id = io_json->get( lv_field ).

    CONCATENATE iv_prefix `attendees` INTO lv_field.
    lv_count = io_json->count( lv_field ).
    DO lv_count TIMES.
      lv_index = sy-index - 1.
      lv_number = lcl_graph_conv=>num( lv_index ).
      CONCATENATE iv_prefix `attendees/` lv_number `/` INTO lv_prefix.
      CONCATENATE lv_prefix `emailAddress/address` INTO lv_field.
      lv_address = io_json->get( lv_field ).
      CONCATENATE lv_prefix `type` INTO lv_field.
      lv_type = io_json->get( lv_field ).
      IF lv_type = `optional`.
        APPEND lv_address TO rs_event-optional.
      ELSE.
        APPEND lv_address TO rs_event-attendees.
      ENDIF.
    ENDDO.
    CONCATENATE iv_prefix `categories` INTO lv_field.
    lv_count = io_json->count( lv_field ).
    DO lv_count TIMES.
      lv_index = sy-index - 1.
      lv_number = lcl_graph_conv=>num( lv_index ).
      CONCATENATE iv_prefix `categories/` lv_number INTO lv_field.
      lv_value = io_json->get( lv_field ).
      APPEND lv_value TO rs_event-categories.
    ENDDO.
  ENDMETHOD.


  METHOD create.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lt_headers TYPE tihttpnvp.

    lv_json = event_json( is_event ).
    lv_path = path( `/events` ).
    lt_headers = utc_headers( ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json it_headers = lt_headers ).
    rs_event = event_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD events.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_from TYPE string.
    DATA lv_to TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.
    DATA lv_day_after TYPE d.
    DATA lv_midnight TYPE t.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_lines TYPE i.
    DATA lv_max_pages TYPE i.

    IF iv_max <= 0.
      RETURN.
    ENDIF.
    CLEAR lv_midnight.
    lv_from = to_utc( iv_date = iv_from iv_time = lv_midnight iv_time_zone = mv_time_zone ).
    lv_day_after = iv_to + 1.
    lv_to = to_utc( iv_date = lv_day_after iv_time = lv_midnight iv_time_zone = mv_time_zone ).
    CONCATENATE `/calendarView?startDateTime=` lv_from `Z&endDateTime=` lv_to `Z`
                `&$top=100&$orderby=start/dateTime`
                `&$select=id,subject,bodyPreview,start,end,isAllDay,isCancelled,location,attendees,showAs,organizer,webLink,categories,transactionId`
      INTO lv_rest.
    lv_path = path( lv_rest ).
    lt_headers = utc_headers( ).
    lv_max_pages = iv_max DIV 100 + 1.
    lt_pages = mo_client->get_pages( iv_path = lv_path iv_max_pages = lv_max_pages it_headers = lt_headers ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        ls_event = event_from_json( io_json = lo_page iv_prefix = lv_prefix ).
        APPEND ls_event TO rt_events.
        lv_lines = lines( rt_events ).
        IF lv_lines >= iv_max.
          RETURN.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD event.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_id TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.

    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/events/` lv_id INTO lv_rest.
    lv_path = path( lv_rest ).
    lt_headers = utc_headers( ).
    lo_json = mo_client->get_json( iv_path = lv_path it_headers = lt_headers ).
    rs_event = event_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD update.
    DATA lv_json TYPE string.
    DATA lv_id TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.

    " The key only counts when an event is created
    ls_event = is_event.
    CLEAR ls_event-transaction_id.
    lv_json = event_json( ls_event ).
    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/events/` lv_id INTO lv_rest.
    lv_path = path( lv_rest ).
    mo_client->send_json( iv_method = 'PATCH' iv_path = lv_path iv_json = lv_json ).
  ENDMETHOD.


  METHOD cancel.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lv_json TYPE string.
    DATA lv_id TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    IF iv_comment IS NOT INITIAL.
      lo_writer->add_string( iv_name = `comment` iv_value = iv_comment ).
    ENDIF.
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/events/` lv_id `/cancel` INTO lv_rest.
    lv_path = path( lv_rest ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
  ENDMETHOD.


  METHOD delete.
    DATA lv_id TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.

    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/events/` lv_id INTO lv_rest.
    lv_path = path( lv_rest ).
    mo_client->delete_path( lv_path ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for the calendar. A test double from ZCHE_GRAPH_CORE
*& answers instead of Microsoft; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_calendar DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_cut TYPE REF TO lcl_graph_calendar.

    METHODS setup.
    METHODS utc_both_ways FOR TESTING.
    METHODS create_event FOR TESTING RAISING lcx_graph.
    METHODS create_all_day FOR TESTING RAISING lcx_graph.
    METHODS end_before_start FOR TESTING.
    METHODS list_period FOR TESTING RAISING lcx_graph.
    METHODS cancel_event FOR TESTING RAISING lcx_graph.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.
ENDCLASS.


CLASS ltc_graph_calendar IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lo_client TYPE REF TO lcl_graph_client.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `calendar` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    CREATE OBJECT lo_client
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
    " UTC+3 all year, so the tests do not depend on summer time
    CREATE OBJECT mo_cut
      EXPORTING
        io_client    = lo_client
        iv_mailbox   = `sap@contoso.com`
        iv_time_zone = 'TURKEY'.
    mo_http->token_answer( ).
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD utc_both_ways.
    DATA lv_text TYPE string.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.

    lv_text = lcl_graph_calendar=>to_utc( iv_date = '20261110' iv_time = '013000' iv_time_zone = 'TURKEY' ).
    cl_aunit_assert=>assert_equals( act = lv_text exp = `2026-11-09T22:30:00` ).
    lcl_graph_calendar=>from_utc( EXPORTING iv_text = `2026-11-09T22:30:00.0000000` iv_time_zone = 'TURKEY'
                                  IMPORTING ev_date = lv_date ev_time = lv_time ).
    cl_aunit_assert=>assert_equals( act = lv_date exp = '20261110' ).
    cl_aunit_assert=>assert_equals( act = lv_time exp = '013000' ).
  ENDMETHOD.


  METHOD create_event.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.
    DATA ls_created TYPE lif_graph_calendar=>ty_event.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_expected TYPE string.
    DATA lv_prefer TYPE string.
    DATA lv_answer TYPE string.

    ls_event-subject = `Bakım: Pres 3`.
    ls_event-body = `Bakım emri 4711`.
    ls_event-start_date = '20261110'.
    ls_event-start_time = '090000'.
    ls_event-end_time = '103000'.
    ls_event-location = `Hol B`.
    APPEND `derya@contoso.com` TO ls_event-attendees.
    APPEND `ayse@contoso.com` TO ls_event-optional.
    ls_event-reminder = 15.
    ls_event-transaction_id = `PM-4711`.
    CONCATENATE `{"id":"E1","subject":"Bakım: Pres 3","isAllDay":false,`
                `"start":{"dateTime":"2026-11-10T06:00:00.0000000","timeZone":"UTC"},`
                `"end":{"dateTime":"2026-11-10T07:30:00.0000000","timeZone":"UTC"},`
                `"attendees":[{"type":"required","emailAddress":{"address":"derya@contoso.com"}}],`
                `"webLink":"https://outlook.office365.com/owa/?itemid=E1"}` INTO lv_answer.
    mo_http->answer( iv_status = 201 iv_body = lv_answer ).
    ls_created = mo_cut->create( ls_event ).
    cl_aunit_assert=>assert_equals( act = ls_created-id exp = `E1` ).
    cl_aunit_assert=>assert_equals( act = ls_created-start_time exp = '090000' ).
    cl_aunit_assert=>assert_equals( act = ls_created-end_time exp = '103000' ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/events` ).
    CONCATENATE `{"subject":"Bakım: Pres 3","body":{"contentType":"Text","content":"Bakım emri 4711"},`
                `"start":{"dateTime":"2026-11-10T06:00:00","timeZone":"UTC"},`
                `"end":{"dateTime":"2026-11-10T07:30:00","timeZone":"UTC"},"isAllDay":false,`
                `"location":{"displayName":"Hol B"},`
                `"attendees":[{"type":"required","emailAddress":{"address":"derya@contoso.com"}},`
                `{"type":"optional","emailAddress":{"address":"ayse@contoso.com"}}],`
                `"isReminderOn":true,"reminderMinutesBeforeStart":15,"transactionId":"PM-4711"}` INTO lv_expected.
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = lv_expected ).
    lv_prefer = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Prefer` ).
    cl_aunit_assert=>assert_equals( act = lv_prefer exp = `outlook.timezone="UTC"` ).
  ENDMETHOD.


  METHOD create_all_day.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    ls_event-subject = `Envanter sayımı`.
    ls_event-start_date = '20261231'.
    ls_event-end_date = '20261231'.
    ls_event-all_day = abap_true.
    ls_event-show_as = `free`.
    ls_event-reminder = -1.
    mo_http->answer( iv_status = 201 iv_body = `{"id":"E2"}` ).
    mo_cut->create( ls_event ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp(
      act = ls_request-body
      exp = '*"start":{"dateTime":"2026-12-31T00:00:00"*"end":{"dateTime":"2027-01-01T00:00:00"*"isAllDay":true*"showAs":"free","isReminderOn":false}' ).
  ENDMETHOD.


  METHOD end_before_start.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.
    DATA lx_graph TYPE REF TO lcx_graph.

    ls_event-subject = `Ters`.
    ls_event-start_date = '20261110'.
    ls_event-start_time = '100000'.
    ls_event-end_time = '090000'.
    TRY.
        mo_cut->create( ls_event ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*ends before it starts*' ).
  ENDMETHOD.


  METHOD list_period.
    DATA lt_events TYPE lif_graph_calendar=>ty_events.
    DATA ls_event TYPE lif_graph_calendar=>ty_event.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_answer TYPE string.
    DATA lv_count TYPE i.

    CONCATENATE `{"value":[{"id":"E1","subject":"Bakım","isAllDay":false,`
                `"start":{"dateTime":"2026-11-10T06:00:00.0000000"},"end":{"dateTime":"2026-11-10T07:30:00.0000000"},`
                `"organizer":{"emailAddress":{"address":"sap@contoso.com"}},"categories":["SAP"]},`
                `{"id":"E2","subject":"Sayım","isAllDay":true,"isCancelled":true,`
                `"start":{"dateTime":"2026-12-31T00:00:00.0000000"},"end":{"dateTime":"2027-01-02T00:00:00.0000000"}}]}` INTO lv_answer.
    mo_http->answer( iv_status = 200 iv_body = lv_answer ).
    lt_events = mo_cut->events( iv_from = '20261101' iv_to = '20261231' ).
    lv_count = lines( lt_events ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    READ TABLE lt_events INDEX 1 INTO ls_event.
    cl_aunit_assert=>assert_equals( act = ls_event-start_time exp = '090000' ).
    cl_aunit_assert=>assert_equals( act = ls_event-organizer exp = `sap@contoso.com` ).
    lv_count = lines( ls_event-categories ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    READ TABLE lt_events INDEX 2 INTO ls_event.
    cl_aunit_assert=>assert_equals( act = ls_event-end_date exp = '20270101' ).
    cl_aunit_assert=>assert_equals( act = ls_event-cancelled exp = abap_true ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp(
      act = ls_request-uri
      exp = '/v1.0/users/sap@contoso.com/calendarView?startDateTime=2026-10-31T21:00:00Z&endDateTime=2026-12-31T21:00:00Z&$top=100*' ).
  ENDMETHOD.


  METHOD cancel_event.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 202 ).
    mo_cut->cancel( iv_id = `E1` iv_comment = `Bakım ertelendi` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `POST` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users/sap@contoso.com/events/E1/cancel` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"comment":"Bakım ertelendi"}` ).
  ENDMETHOD.

ENDCLASS.
