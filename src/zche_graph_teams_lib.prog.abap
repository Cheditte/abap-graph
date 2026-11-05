*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_TEAMS_LIB: messages to a Microsoft Teams channel through
*& a Workflows webhook (INCLUDE)
*& abap-graph 0.7.4, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_TEAMS_LIB with type "Include
*& program", paste this source, save. It needs ZCHE_GRAPH_CORE:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_teams_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Microsoft Graph does not let an application post to a channel. Teams
*& offers a webhook instead: in the channel, Workflows, template "Send
*& webhook alerts to a channel". The workflow gives a long URL; whoever
*& has it can post to the channel, so it is kept like a password:
*&   SM59, type G: target host = the host of the URL, port 443, SSL
*&   active (ANONYM), path prefix = the rest of the URL, from the first /
*&   after the host to the end, with ?...&sig=... ; no logon data.
*& This code only knows the name of the SM59 destination, never the URL.
*& No token and no Microsoft Entra permission is needed.
*&
*& A message is an Adaptive Card: a title in the colour of its level
*& (info, good, warning, error), a text, name/value lines and a button
*& that opens a link.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
INTERFACE lif_graph_teams.
  TYPES:
    BEGIN OF ty_fact,
      name  TYPE string,
      value TYPE string,
    END OF ty_fact,
    ty_facts TYPE STANDARD TABLE OF ty_fact WITH DEFAULT KEY.

  " LEVEL: info (default), good, warning or error
  TYPES:
    BEGIN OF ty_card,
      title      TYPE string,
      text       TYPE string,
      level      TYPE string,
      facts      TYPE ty_facts,
      link_url   TYPE string,
      link_title TYPE string,
    END OF ty_card.
ENDINTERFACE.


*----------------------------------------------------------------------*
* A Teams channel behind a Workflows webhook
*----------------------------------------------------------------------*
CLASS lcl_graph_teams DEFINITION FINAL.
  PUBLIC SECTION.
    "! IV_DESTINATION: the SM59 destination that holds the webhook URL.
    "! IO_HTTP only for tests; normally empty
    METHODS constructor
      IMPORTING
        iv_destination TYPE rfcdest
        io_http        TYPE REF TO lif_graph_http OPTIONAL.

    "! Posts the card. Not repeated after an error: the message may have
    "! arrived already, and a second one would confuse more than a missing one.
    METHODS send
      IMPORTING
        is_card TYPE lif_graph_teams=>ty_card
      RAISING
        lcx_graph.

    "! A short message: title and text, level info
    METHODS send_text
      IMPORTING
        iv_title TYPE string
        iv_text  TYPE string OPTIONAL
        iv_level TYPE string DEFAULT `info`
      RAISING
        lcx_graph.

    "! The body the webhook gets
    CLASS-METHODS card_json
      IMPORTING
        is_card        TYPE lif_graph_teams=>ty_card
      RETURNING
        value(rv_json) TYPE string
      RAISING
        lcx_graph.

    "! "Order=4711 | Plant=1000" -> name/value lines; only the first = separates
    CLASS-METHODS facts_from_text
      IMPORTING
        iv_text         TYPE string
      RETURNING
        value(rt_facts) TYPE lif_graph_teams=>ty_facts.

  PRIVATE SECTION.
    DATA mv_destination TYPE rfcdest.
    DATA mo_http TYPE REF TO lif_graph_http.
ENDCLASS.


CLASS lcl_graph_teams IMPLEMENTATION.

  METHOD constructor.
    mv_destination = iv_destination.
    IF io_http IS BOUND.
      mo_http = io_http.
    ELSE.
      CREATE OBJECT mo_http TYPE lcl_graph_http.
    ENDIF.
  ENDMETHOD.


  METHOD facts_from_text.
    DATA lt_parts TYPE lcl_graph_json=>ty_names.
    DATA lv_part TYPE string.
    DATA ls_fact TYPE lif_graph_teams=>ty_fact.

    SPLIT iv_text AT '|' INTO TABLE lt_parts.
    LOOP AT lt_parts INTO lv_part.
      IF lv_part NA '='.
        CONTINUE.
      ENDIF.
      CLEAR ls_fact.
      SPLIT lv_part AT '=' INTO ls_fact-name ls_fact-value IN CHARACTER MODE.
      ls_fact-name = lcl_graph_conv=>trim( ls_fact-name ).
      ls_fact-value = lcl_graph_conv=>trim( ls_fact-value ).
      IF ls_fact-name IS NOT INITIAL.
        APPEND ls_fact TO rt_facts.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD card_json.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA ls_fact TYPE lif_graph_teams=>ty_fact.
    DATA lv_level TYPE string.
    DATA lv_color TYPE string.
    DATA lv_text TYPE string.
    DATA lv_link_title TYPE string.

    lv_level = is_card-level.
    TRANSLATE lv_level TO LOWER CASE.
    CONDENSE lv_level NO-GAPS.
    CASE lv_level.
      WHEN `` OR `info`.
        lv_color = `Accent`.
      WHEN `good`.
        lv_color = `Good`.
      WHEN `warning`.
        lv_color = `Warning`.
      WHEN `error`.
        lv_color = `Attention`.
      WHEN OTHERS.
        CONCATENATE `Unknown level "` is_card-level `"; use info, good, warning or error.` INTO lv_text.
        RAISE EXCEPTION TYPE lcx_graph
          EXPORTING
            text = lv_text.
    ENDCASE.
    IF is_card-title IS INITIAL AND is_card-text IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `The message has neither a title nor a text.`.
    ENDIF.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `type` iv_value = `message` ).
    lo_writer->begin_array( `attachments` ).
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `contentType` iv_value = `application/vnd.microsoft.card.adaptive` ).
    lo_writer->begin_object( `content` ).
    lo_writer->add_string( iv_name = `$schema` iv_value = `http://adaptivecards.io/schemas/adaptive-card.json` ).
    lo_writer->add_string( iv_name = `type` iv_value = `AdaptiveCard` ).
    lo_writer->add_string( iv_name = `version` iv_value = `1.4` ).
    lo_writer->begin_array( `body` ).
    IF is_card-title IS NOT INITIAL.
      lo_writer->begin_object( ).
      lo_writer->add_string( iv_name = `type` iv_value = `TextBlock` ).
      lo_writer->add_string( iv_name = `text` iv_value = is_card-title ).
      lo_writer->add_string( iv_name = `weight` iv_value = `Bolder` ).
      lo_writer->add_string( iv_name = `size` iv_value = `Medium` ).
      lo_writer->add_string( iv_name = `color` iv_value = lv_color ).
      lo_writer->add_boolean( iv_name = `wrap` iv_value = abap_true ).
      lo_writer->end_object( ).
    ENDIF.
    IF is_card-text IS NOT INITIAL.
      lo_writer->begin_object( ).
      lo_writer->add_string( iv_name = `type` iv_value = `TextBlock` ).
      lo_writer->add_string( iv_name = `text` iv_value = is_card-text ).
      lo_writer->add_boolean( iv_name = `wrap` iv_value = abap_true ).
      lo_writer->end_object( ).
    ENDIF.
    IF is_card-facts IS NOT INITIAL.
      lo_writer->begin_object( ).
      lo_writer->add_string( iv_name = `type` iv_value = `FactSet` ).
      lo_writer->begin_array( `facts` ).
      LOOP AT is_card-facts INTO ls_fact.
        lo_writer->begin_object( ).
        lo_writer->add_string( iv_name = `title` iv_value = ls_fact-name ).
        lo_writer->add_string( iv_name = `value` iv_value = ls_fact-value ).
        lo_writer->end_object( ).
      ENDLOOP.
      lo_writer->end_array( ).
      lo_writer->end_object( ).
    ENDIF.
    lo_writer->end_array( ).
    IF is_card-link_url IS NOT INITIAL.
      lv_link_title = is_card-link_title.
      IF lv_link_title IS INITIAL.
        lv_link_title = `Open`.
      ENDIF.
      lo_writer->begin_array( `actions` ).
      lo_writer->begin_object( ).
      lo_writer->add_string( iv_name = `type` iv_value = `Action.OpenUrl` ).
      lo_writer->add_string( iv_name = `title` iv_value = lv_link_title ).
      lo_writer->add_string( iv_name = `url` iv_value = is_card-link_url ).
      lo_writer->end_object( ).
      lo_writer->end_array( ).
    ENDIF.
    lo_writer->end_object( ).
    lo_writer->end_object( ).
    lo_writer->end_array( ).
    lo_writer->end_object( ).
    rv_json = lo_writer->result( ).
  ENDMETHOD.


  METHOD send.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lt_headers TYPE tihttpnvp.
    DATA ls_header TYPE ihttpnvp.
    DATA lv_json TYPE string.
    DATA lv_body TYPE xstring.
    DATA lv_status TYPE string.
    DATA lv_text TYPE string.
    DATA lv_hint TYPE string.
    DATA lv_answer TYPE string.

    lv_json = card_json( is_card ).
    lv_body = lcl_graph_conv=>to_utf8( lv_json ).
    ls_header-name = 'Content-Type'.
    ls_header-value = 'application/json'.
    APPEND ls_header TO lt_headers.
    " The URI stays empty: the whole address is in the SM59 destination
    ls_response = mo_http->send( iv_destination = mv_destination
                                 iv_method      = 'POST'
                                 iv_uri         = ``
                                 it_headers     = lt_headers
                                 iv_body        = lv_body ).
    " Only 2xx means the channel took it; a redirect (3xx) did not deliver it
    IF ls_response-status >= 200 AND ls_response-status < 300.
      RETURN.
    ENDIF.

    lv_status = lcl_graph_conv=>num( ls_response-status ).
    CONCATENATE `The Teams webhook in SM59 destination ` mv_destination ` answered HTTP ` lv_status `.` INTO lv_text.
    " The answer may say what is wrong with the card; it never holds the URL
    lv_answer = lcl_graph_conv=>from_utf8( ls_response-body ).
    IF strlen( lv_answer ) > 300.
      lv_answer = lv_answer(300).
    ENDIF.
    " A proxy's error page might repeat the address and its key: then not shown
    IF lv_answer CS 'sig='.
      CLEAR lv_answer.
    ENDIF.
    IF lv_answer IS NOT INITIAL.
      CONCATENATE lv_text lv_answer INTO lv_text SEPARATED BY space.
    ENDIF.
    CASE ls_response-status.
      WHEN 400.
        lv_hint = `The workflow did not accept the card. Check that the workflow uses the template "Send webhook alerts to a channel".`.
      WHEN 401 OR 403 OR 404.
        lv_hint = `The address was not accepted. Check that the workflow is on, and that the path prefix in SM59 holds the whole rest of the URL, ?...&sig=... included.`.
      WHEN 429.
        lv_hint = `Too many messages in a short time; send fewer, or later.`.
      WHEN 301 OR 302 OR 303 OR 307 OR 308.
        lv_hint = `The address sent the card elsewhere, so it did not arrive. Check the host and path prefix in SM59, and the proxy.`.
      WHEN OTHERS.
        lv_hint = `Look at the run history of the workflow in Teams (Workflows, the workflow, 28-day run history).`.
    ENDCASE.
    RAISE EXCEPTION TYPE lcx_graph
      EXPORTING
        text        = lv_text
        hint        = lv_hint
        http_status = ls_response-status.
  ENDMETHOD.


  METHOD send_text.
    DATA ls_card TYPE lif_graph_teams=>ty_card.
    ls_card-title = iv_title.
    ls_card-text = iv_text.
    ls_card-level = iv_level.
    send( ls_card ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for Teams. A test double from ZCHE_GRAPH_CORE answers
*& instead of the webhook; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_teams DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_cut TYPE REF TO lcl_graph_teams.

    METHODS setup.
    METHODS card_body FOR TESTING RAISING lcx_graph.
    METHODS send_card FOR TESTING RAISING lcx_graph.
    METHODS refused FOR TESTING.
    METHODS redirected FOR TESTING.
    METHODS wrong_level FOR TESTING.
    METHODS text_to_facts FOR TESTING.
ENDCLASS.


CLASS ltc_graph_teams IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT mo_http.
    CREATE OBJECT mo_cut
      EXPORTING
        iv_destination = 'ZCHE_TEAMS_TEST'
        io_http        = mo_http.
  ENDMETHOD.


  METHOD card_body.
    DATA ls_card TYPE lif_graph_teams=>ty_card.
    DATA lv_json TYPE string.
    DATA lv_expected TYPE string.

    ls_card-title = `Job ZFI_CLOSE ended with an error`.
    ls_card-text = `Period 11/2026, "company code" 1000`.
    ls_card-level = `Error`.
    ls_card-facts = lcl_graph_teams=>facts_from_text( `System=A4H/001 | Spool=4711` ).
    ls_card-link_url = `https://sap.contoso.com/sm37`.
    ls_card-link_title = `Open SM37`.
    lv_json = lcl_graph_teams=>card_json( ls_card ).
    CONCATENATE `{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{`
                `"$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.4","body":[`
                `{"type":"TextBlock","text":"Job ZFI_CLOSE ended with an error","weight":"Bolder","size":"Medium","color":"Attention","wrap":true},`
                `{"type":"TextBlock","text":"Period 11/2026, \"company code\" 1000","wrap":true},`
                `{"type":"FactSet","facts":[{"title":"System","value":"A4H/001"},{"title":"Spool","value":"4711"}]}],`
                `"actions":[{"type":"Action.OpenUrl","title":"Open SM37","url":"https://sap.contoso.com/sm37"}]}}]}` INTO lv_expected.
    cl_aunit_assert=>assert_equals( act = lv_json exp = lv_expected ).
  ENDMETHOD.


  METHOD send_card.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_type TYPE string.
    DATA lv_count TYPE i.

    mo_http->answer( iv_status = 202 ).
    mo_cut->send_text( iv_title = `Gece işi bitti` iv_text = `3 belge` iv_level = `good` ).
    READ TABLE mo_http->mt_requests INDEX 1 INTO ls_request.
    cl_aunit_assert=>assert_equals( act = ls_request-destination exp = 'ZCHE_TEAMS_TEST' ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `POST` ).
    cl_aunit_assert=>assert_initial( act = ls_request-uri ).
    lv_type = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Content-Type` ).
    cl_aunit_assert=>assert_equals( act = lv_type exp = `application/json` ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-body exp = '*"text":"Gece işi bitti"*"color":"Good"*"text":"3 belge"*' ).
    " No token request: a webhook needs none
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
  ENDMETHOD.


  METHOD refused.
    DATA lx_graph TYPE REF TO lcx_graph.

    mo_http->answer( iv_status = 404 ).
    TRY.
        mo_cut->send_text( iv_title = `Test` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*SM59 destination ZCHE_TEAMS_TEST answered HTTP 404*' ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->hint exp = '*path prefix*' ).
  ENDMETHOD.


  METHOD redirected.
    " A redirect did not deliver the card: an error, for 302 and for 307
    DATA lx_graph TYPE REF TO lcx_graph.

    mo_http->answer( iv_status = 302 ).
    TRY.
        mo_cut->send_text( iv_title = `Test` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `302 counted as sent` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->hint exp = '*did not arrive*' ).
    CLEAR lx_graph.
    mo_http->answer( iv_status = 307 ).
    TRY.
        mo_cut->send_text( iv_title = `Test` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `307 counted as sent` ).
  ENDMETHOD.


  METHOD wrong_level.
    DATA lx_graph TYPE REF TO lcx_graph.

    TRY.
        mo_cut->send_text( iv_title = `Test` iv_level = `red` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*Unknown level*' ).
    " Nothing was sent
    cl_aunit_assert=>assert_initial( act = mo_http->mt_requests ).
  ENDMETHOD.


  METHOD text_to_facts.
    DATA lt_facts TYPE lif_graph_teams=>ty_facts.
    DATA ls_fact TYPE lif_graph_teams=>ty_fact.
    DATA lv_count TYPE i.

    lt_facts = lcl_graph_teams=>facts_from_text( ` Sipariş = 4711 | Not=a=b | boş ` ).
    lv_count = lines( lt_facts ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    READ TABLE lt_facts INDEX 1 INTO ls_fact.
    cl_aunit_assert=>assert_equals( act = ls_fact-name exp = `Sipariş` ).
    cl_aunit_assert=>assert_equals( act = ls_fact-value exp = `4711` ).
    READ TABLE lt_facts INDEX 2 INTO ls_fact.
    cl_aunit_assert=>assert_equals( act = ls_fact-value exp = `a=b` ).
  ENDMETHOD.

ENDCLASS.
