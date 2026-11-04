*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_CORE: Microsoft Graph from ABAP, shared core (INCLUDE)
*& abap-graph 0.7.1, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_CORE with type "Include
*& program", paste this source, save. Programs that talk to Microsoft
*& Graph start with INCLUDE zche_graph_core.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& What is inside:
*&   LIF_GRAPH          types and constants
*&   LCX_GRAPH          error with HTTP status, Graph error code, hint
*&   LCL_GRAPH_CONV     UTF-8, Base64, URL encoding
*&   LCL_GRAPH_JSON     reads JSON (Graph responses)
*&   LCL_GRAPH_JSON_WRITER  writes JSON (request bodies)
*&   LIF_GRAPH_HTTP, LCL_GRAPH_HTTP  HTTP through an SM59 destination
*&   LCL_GRAPH_TOKEN    OAuth2 client credentials token, cached
*&   LCL_GRAPH_CLIENT   Graph calls: retries, paging, errors
*&
*& Two SM59 destinations (type G, SSL active) are needed:
*&   ZCHE_GRAPH_LOGIN  host login.microsoftonline.com, port 443, basic
*&                     authentication: user = application (client) ID,
*&                     password = client secret
*&   ZCHE_GRAPH_API    host graph.microsoft.com, port 443, no logon data
*& The secret stays in SM59; this code never sees it.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types and constants
*----------------------------------------------------------------------*
INTERFACE lif_graph.
  CONSTANTS version TYPE string VALUE `0.7.1`.
  CONSTANTS default_login_destination TYPE rfcdest VALUE 'ZCHE_GRAPH_LOGIN'.
  CONSTANTS default_api_destination TYPE rfcdest VALUE 'ZCHE_GRAPH_API'.
  CONSTANTS default_api_version TYPE string VALUE `v1.0`.
  CONSTANTS default_max_retries TYPE i VALUE 3.
  CONSTANTS default_ssl_id TYPE ssfapplssl VALUE 'ANONYM'.

  TYPES:
    BEGIN OF ty_config,
      tenant            TYPE string,
      login_destination TYPE rfcdest,
      api_destination   TYPE rfcdest,
      api_version       TYPE string,
      max_retries       TYPE i,
      " SSL client PSE for URLs Microsoft hands out (large uploads)
      ssl_id            TYPE ssfapplssl,
    END OF ty_config.

  TYPES:
    BEGIN OF ty_response,
      status  TYPE i,
      reason  TYPE string,
      headers TYPE tihttpnvp,
      body    TYPE xstring,
    END OF ty_response.
ENDINTERFACE.


*----------------------------------------------------------------------*
* Error: what went wrong, and a hint who can fix it
*----------------------------------------------------------------------*
CLASS lcx_graph DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA text TYPE string READ-ONLY.
    DATA hint TYPE string READ-ONLY.
    DATA http_status TYPE i READ-ONLY.
    DATA error_code TYPE string READ-ONLY.
    DATA request_id TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        text        TYPE string OPTIONAL
        hint        TYPE string OPTIONAL
        http_status TYPE i OPTIONAL
        error_code  TYPE string OPTIONAL
        request_id  TYPE string OPTIONAL
        previous    TYPE REF TO cx_root OPTIONAL.

    METHODS if_message~get_text REDEFINITION.
    METHODS if_message~get_longtext REDEFINITION.
ENDCLASS.


CLASS lcx_graph IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    me->text = text.
    me->hint = hint.
    me->http_status = http_status.
    me->error_code = error_code.
    me->request_id = request_id.
  ENDMETHOD.


  METHOD if_message~get_text.
    result = text.
    IF result IS INITIAL.
      result = super->if_message~get_text( ).
    ENDIF.
  ENDMETHOD.


  METHOD if_message~get_longtext.
    " Text, hint and the request ID Microsoft support asks for
    result = text.
    IF hint IS NOT INITIAL.
      CONCATENATE result ` ` hint INTO result.
    ENDIF.
    IF request_id IS NOT INITIAL.
      CONCATENATE result ` (request-id ` request_id `)` INTO result.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Conversions: UTF-8, Base64, URL encoding, numbers as text
*----------------------------------------------------------------------*
CLASS lcl_graph_conv DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS to_utf8
      IMPORTING
        iv_text         TYPE string
      RETURNING
        value(rv_bytes) TYPE xstring.

    CLASS-METHODS from_utf8
      IMPORTING
        iv_bytes       TYPE xstring
      RETURNING
        value(rv_text) TYPE string.

    CLASS-METHODS to_base64
      IMPORTING
        iv_bytes        TYPE xstring
      RETURNING
        value(rv_base64) TYPE string.

    "! Base64 or Base64url (as in tokens), with or without padding
    CLASS-METHODS from_base64
      IMPORTING
        iv_base64       TYPE string
      RETURNING
        value(rv_bytes) TYPE xstring.

    "! Encodes one value for a URL query or a form body
    CLASS-METHODS url_encode
      IMPORTING
        iv_text        TYPE string
      RETURNING
        value(rv_text) TYPE string.

    "! A number as text, without blanks or thousands separators
    CLASS-METHODS num
      IMPORTING
        iv_number      TYPE i
      RETURNING
        value(rv_text) TYPE string.

    "! A number as JSON writes it (RFC 8259): -12.5, 0, 1e-3, 2E+6.
    "! Not: 00123, +5, 1., .5, 1e, 1..2, 1 2, 1.234,50
    CLASS-METHODS is_json_number
      IMPORTING
        iv_text          TYPE string
      RETURNING
        value(rv_number) TYPE abap_bool.

    "! Blanks at the start and the end go; blanks inside stay as they are
    "! (CONDENSE would turn "a  b" into "a b", another file or value)
    CLASS-METHODS trim
      IMPORTING
        iv_text        TYPE string
      RETURNING
        value(rv_text) TYPE string.

    "! "/Reports\2026/" -> "Reports/2026": backslashes become slashes, no slash at either end
    CLASS-METHODS clean_path
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    "! "/Reports/2026/a b.pdf" -> "Reports/2026/a%20b.pdf"; each part is encoded, slashes stay
    CLASS-METHODS encode_path
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rv_path) TYPE string.
ENDCLASS.


CLASS lcl_graph_conv IMPLEMENTATION.

  METHOD to_utf8.
    DATA lo_conv TYPE REF TO cl_abap_conv_out_ce.
    lo_conv = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
    lo_conv->convert( EXPORTING data = iv_text IMPORTING buffer = rv_bytes ).
  ENDMETHOD.


  METHOD from_utf8.
    DATA lo_conv TYPE REF TO cl_abap_conv_in_ce.
    IF iv_bytes IS INITIAL.
      RETURN.
    ENDIF.
    " A byte that is no UTF-8 (a proxy's error page in Windows-1252), or a
    " character this system cannot hold, becomes # instead of a short dump
    lo_conv = cl_abap_conv_in_ce=>create( encoding    = 'UTF-8'
                                          input       = iv_bytes
                                          replacement = '#'
                                          ignore_cerr = abap_true ).
    lo_conv->read( IMPORTING data = rv_text ).
  ENDMETHOD.


  METHOD to_base64.
    rv_base64 = cl_http_utility=>encode_x_base64( iv_bytes ).
  ENDMETHOD.


  METHOD from_base64.
    DATA lv_text TYPE string.
    DATA lv_rest TYPE i.

    lv_text = iv_base64.
    TRANSLATE lv_text USING '-+_/'.
    lv_rest = strlen( lv_text ) MOD 4.
    IF lv_rest = 2.
      CONCATENATE lv_text '==' INTO lv_text.
    ELSEIF lv_rest = 3.
      CONCATENATE lv_text '=' INTO lv_text.
    ENDIF.
    rv_bytes = cl_http_utility=>decode_x_base64( lv_text ).
  ENDMETHOD.


  METHOD url_encode.
    rv_text = cl_http_utility=>escape_url( iv_text ).
  ENDMETHOD.


  METHOD num.
    " WRITE puts the minus sign behind the number (5-); JSON wants it in front
    DATA lv_text TYPE c LENGTH 12.
    DATA lv_number TYPE i.
    lv_number = abs( iv_number ).
    WRITE lv_number TO lv_text LEFT-JUSTIFIED NO-GROUPING.
    rv_text = lv_text.
    IF iv_number < 0.
      CONCATENATE '-' rv_text INTO rv_text.
    ENDIF.
  ENDMETHOD.


  METHOD is_json_number.
    " States: 0 start, 1 after -, 2 after a leading 0, 3 in the integer digits,
    " 4 after the dot, 5 in the fraction, 6 after e, 7 after the sign of e,
    " 8 in the exponent. The number is complete in 2, 3, 5 and 8.
    DATA lv_length TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_state TYPE i.
    DATA lv_digit TYPE abap_bool.

    rv_number = abap_false.
    lv_length = strlen( iv_text ).
    IF lv_length = 0.
      RETURN.
    ENDIF.
    DO lv_length TIMES.
      lv_offset = sy-index - 1.
      lv_char = iv_text+lv_offset(1).
      IF lv_char CA '0123456789' AND lv_char <> space.
        lv_digit = abap_true.
      ELSE.
        lv_digit = abap_false.
      ENDIF.
      CASE lv_state.
        WHEN 0 OR 1.
          IF lv_char = '-' AND lv_state = 0.
            lv_state = 1.
          ELSEIF lv_char = '0'.
            lv_state = 2.
          ELSEIF lv_digit = abap_true.
            lv_state = 3.
          ELSE.
            RETURN.
          ENDIF.
        WHEN 2 OR 3.
          IF lv_digit = abap_true AND lv_state = 3.
            lv_state = 3.
          ELSEIF lv_char = '.'.
            lv_state = 4.
          ELSEIF lv_char = 'e' OR lv_char = 'E'.
            lv_state = 6.
          ELSE.
            RETURN.
          ENDIF.
        WHEN 4 OR 5.
          IF lv_digit = abap_true.
            lv_state = 5.
          ELSEIF lv_state = 5 AND ( lv_char = 'e' OR lv_char = 'E' ).
            lv_state = 6.
          ELSE.
            RETURN.
          ENDIF.
        WHEN 6.
          IF lv_char = '+' OR lv_char = '-'.
            lv_state = 7.
          ELSEIF lv_digit = abap_true.
            lv_state = 8.
          ELSE.
            RETURN.
          ENDIF.
        WHEN 7 OR 8.
          IF lv_digit = abap_true.
            lv_state = 8.
          ELSE.
            RETURN.
          ENDIF.
      ENDCASE.
    ENDDO.
    IF lv_state = 2 OR lv_state = 3 OR lv_state = 5 OR lv_state = 8.
      rv_number = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD trim.
    DATA lv_length TYPE i.
    DATA lv_last TYPE i.

    rv_text = iv_text.
    SHIFT rv_text LEFT DELETING LEADING space.
    DO.
      lv_length = strlen( rv_text ).
      IF lv_length = 0.
        EXIT.
      ENDIF.
      lv_last = lv_length - 1.
      " A string literal: the character constant SPACE would count as empty here
      IF rv_text+lv_last(1) <> ` `.
        EXIT.
      ENDIF.
      rv_text = rv_text(lv_last).
    ENDDO.
  ENDMETHOD.


  METHOD clean_path.
    DATA lv_length TYPE i.
    DATA lv_last TYPE i.

    rv_path = iv_path.
    TRANSLATE rv_path USING '\/'.
    rv_path = trim( rv_path ).
    WHILE rv_path IS NOT INITIAL AND rv_path(1) = '/'.
      SHIFT rv_path LEFT BY 1 PLACES.
    ENDWHILE.
    DO.
      lv_length = strlen( rv_path ).
      IF lv_length = 0.
        EXIT.
      ENDIF.
      lv_last = lv_length - 1.
      IF rv_path+lv_last(1) <> '/'.
        EXIT.
      ENDIF.
      rv_path = rv_path(lv_last).
    ENDDO.
  ENDMETHOD.


  METHOD encode_path.
    DATA lt_parts TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
    DATA lv_part TYPE string.
    DATA lv_path TYPE string.

    lv_path = clean_path( iv_path ).
    SPLIT lv_path AT '/' INTO TABLE lt_parts.
    LOOP AT lt_parts INTO lv_part.
      lv_part = url_encode( lv_part ).
      IF rv_path IS INITIAL.
        rv_path = lv_part.
      ELSE.
        CONCATENATE rv_path '/' lv_part INTO rv_path.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Reads JSON. Values are reached with a path of member names and array
* positions separated by "/", positions counted from 0:
*   error/code          value/0/id          value/0/from/emailAddress/name
* Numbers, true, false and null come back as their text.
*----------------------------------------------------------------------*
CLASS lcl_graph_json DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF kind,
        object  TYPE c LENGTH 1 VALUE 'O',
        array   TYPE c LENGTH 1 VALUE 'A',
        string  TYPE c LENGTH 1 VALUE 'S',
        number  TYPE c LENGTH 1 VALUE 'N',
        boolean TYPE c LENGTH 1 VALUE 'B',
        null    TYPE c LENGTH 1 VALUE 'Z',
      END OF kind.

    TYPES ty_names TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    CLASS-METHODS parse
      IMPORTING
        iv_json        TYPE string
      RETURNING
        value(ro_json) TYPE REF TO lcl_graph_json
      RAISING
        lcx_graph.

    "! Text of a value; empty if the path does not exist or is not a value
    METHODS get
      IMPORTING
        iv_path         TYPE string
      RETURNING
        value(rv_value) TYPE string.

    METHODS exists
      IMPORTING
        iv_path          TYPE string
      RETURNING
        value(rv_exists) TYPE abap_bool.

    "! Kind of the value at the path (see constants KIND); empty if missing
    METHODS kind_of
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rv_kind) TYPE char1.

    "! Number of members of an object or elements of an array
    METHODS count
      IMPORTING
        iv_path         TYPE string
      RETURNING
        value(rv_count) TYPE i.

    "! Member names of an object, in their order
    METHODS names
      IMPORTING
        iv_path         TYPE string
      RETURNING
        value(rt_names) TYPE ty_names.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_node,
        id     TYPE i,
        parent TYPE i,
        name   TYPE string,
        kind   TYPE c LENGTH 1,
        value  TYPE string,
      END OF ty_node,
      ty_nodes TYPE STANDARD TABLE OF ty_node WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_child,
        parent   TYPE i,
        position TYPE i,
        id       TYPE i,
      END OF ty_child,
      ty_children TYPE SORTED TABLE OF ty_child WITH UNIQUE KEY parent position.

    DATA mv_text TYPE string.
    DATA mv_length TYPE i.
    DATA mv_position TYPE i.
    DATA mt_nodes TYPE ty_nodes.
    DATA mt_children TYPE ty_children.

    METHODS parse_value
      IMPORTING
        iv_parent TYPE i
        iv_name   TYPE string
      RAISING
        lcx_graph.

    METHODS parse_string
      RETURNING
        value(rv_text) TYPE string
      RAISING
        lcx_graph.

    METHODS skip_blanks.

    METHODS add_node
      IMPORTING
        iv_parent    TYPE i
        iv_name      TYPE string
        iv_kind      TYPE c
        iv_value     TYPE string OPTIONAL
      RETURNING
        value(rv_id) TYPE i.

    METHODS expect
      IMPORTING
        iv_char TYPE c
      RAISING
        lcx_graph.

    METHODS syntax_error
      IMPORTING
        iv_what TYPE string
      RAISING
        lcx_graph.

    METHODS find
      IMPORTING
        iv_path      TYPE string
      RETURNING
        value(rv_id) TYPE i.

    METHODS unicode_char
      IMPORTING
        iv_hex         TYPE string
      RETURNING
        value(rv_char) TYPE string.
ENDCLASS.


CLASS lcl_graph_json IMPLEMENTATION.

  METHOD parse.
    CREATE OBJECT ro_json.
    ro_json->mv_text = iv_json.
    ro_json->mv_length = strlen( iv_json ).
    ro_json->mv_position = 0.
    ro_json->skip_blanks( ).
    IF ro_json->mv_position >= ro_json->mv_length.
      ro_json->syntax_error( `empty text` ).
    ENDIF.
    ro_json->parse_value( iv_parent = 0 iv_name = `` ).
    ro_json->skip_blanks( ).
    IF ro_json->mv_position < ro_json->mv_length.
      ro_json->syntax_error( `text after the end` ).
    ENDIF.
  ENDMETHOD.


  METHOD skip_blanks.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_cr TYPE c LENGTH 1.
    DATA lv_crlf TYPE c LENGTH 2.
    " Carriage return: the first character of CR/LF
    lv_crlf = cl_abap_char_utilities=>cr_lf.
    lv_cr = lv_crlf(1).
    WHILE mv_position < mv_length.
      lv_char = mv_text+mv_position(1).
      IF lv_char = ' ' OR lv_char = cl_abap_char_utilities=>horizontal_tab
          OR lv_char = cl_abap_char_utilities=>newline OR lv_char = lv_cr.
        mv_position = mv_position + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.


  METHOD add_node.
    DATA ls_node TYPE ty_node.
    DATA ls_child TYPE ty_child.
    DATA lv_position TYPE i.

    rv_id = lines( mt_nodes ) + 1.
    ls_node-id = rv_id.
    ls_node-parent = iv_parent.
    ls_node-name = iv_name.
    ls_node-kind = iv_kind.
    ls_node-value = iv_value.
    APPEND ls_node TO mt_nodes.
    IF iv_parent > 0.
      LOOP AT mt_children TRANSPORTING NO FIELDS WHERE parent = iv_parent.
        lv_position = lv_position + 1.
      ENDLOOP.
      ls_child-parent = iv_parent.
      ls_child-position = lv_position.
      ls_child-id = rv_id.
      INSERT ls_child INTO TABLE mt_children.
    ENDIF.
  ENDMETHOD.


  METHOD syntax_error.
    DATA lv_text TYPE string.
    DATA lv_position TYPE string.
    lv_position = lcl_graph_conv=>num( mv_position ).
    CONCATENATE `The response is not valid JSON (` iv_what ` at character ` lv_position `).` INTO lv_text.
    RAISE EXCEPTION TYPE lcx_graph
      EXPORTING
        text = lv_text.
  ENDMETHOD.


  METHOD expect.
    DATA lv_what TYPE string.
    skip_blanks( ).
    IF mv_position >= mv_length OR mv_text+mv_position(1) <> iv_char.
      CONCATENATE `expected ` iv_char INTO lv_what.
      syntax_error( lv_what ).
    ENDIF.
    mv_position = mv_position + 1.
  ENDMETHOD.


  METHOD parse_value.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_id TYPE i.
    DATA lv_name TYPE string.
    DATA lv_value TYPE string.
    DATA lv_start TYPE i.
    DATA lv_length TYPE i.
    DATA lv_index TYPE i.
    DATA lv_index_text TYPE string.
    DATA lv_cr TYPE c LENGTH 1.
    DATA lv_crlf TYPE c LENGTH 2.

    " Carriage return: the first character of CR/LF
    lv_crlf = cl_abap_char_utilities=>cr_lf.
    lv_cr = lv_crlf(1).
    skip_blanks( ).
    IF mv_position >= mv_length.
      syntax_error( `unexpected end` ).
    ENDIF.
    lv_char = mv_text+mv_position(1).

    CASE lv_char.
      WHEN '{'.
        lv_id = add_node( iv_parent = iv_parent iv_name = iv_name iv_kind = kind-object ).
        mv_position = mv_position + 1.
        skip_blanks( ).
        IF mv_position < mv_length AND mv_text+mv_position(1) = '}'.
          mv_position = mv_position + 1.
          RETURN.
        ENDIF.
        DO.
          skip_blanks( ).
          expect( '"' ).
          mv_position = mv_position - 1.
          lv_name = parse_string( ).
          expect( ':' ).
          parse_value( iv_parent = lv_id iv_name = lv_name ).
          skip_blanks( ).
          IF mv_position >= mv_length.
            syntax_error( `unexpected end in object` ).
          ENDIF.
          lv_char = mv_text+mv_position(1).
          mv_position = mv_position + 1.
          IF lv_char = '}'.
            EXIT.
          ELSEIF lv_char <> ','.
            syntax_error( `expected , or }` ).
          ENDIF.
        ENDDO.

      WHEN '['.
        lv_id = add_node( iv_parent = iv_parent iv_name = iv_name iv_kind = kind-array ).
        mv_position = mv_position + 1.
        skip_blanks( ).
        IF mv_position < mv_length AND mv_text+mv_position(1) = ']'.
          mv_position = mv_position + 1.
          RETURN.
        ENDIF.
        lv_index = 0.
        DO.
          " Array elements are named by their position, so paths work the same way
          lv_index_text = lcl_graph_conv=>num( lv_index ).
          parse_value( iv_parent = lv_id iv_name = lv_index_text ).
          lv_index = lv_index + 1.
          skip_blanks( ).
          IF mv_position >= mv_length.
            syntax_error( `unexpected end in array` ).
          ENDIF.
          lv_char = mv_text+mv_position(1).
          mv_position = mv_position + 1.
          IF lv_char = ']'.
            EXIT.
          ELSEIF lv_char <> ','.
            syntax_error( `expected , or ]` ).
          ENDIF.
        ENDDO.

      WHEN '"'.
        lv_value = parse_string( ).
        add_node( iv_parent = iv_parent iv_name = iv_name iv_kind = kind-string iv_value = lv_value ).

      WHEN OTHERS.
        " Number, true, false or null: everything up to the next delimiter
        lv_start = mv_position.
        WHILE mv_position < mv_length.
          lv_char = mv_text+mv_position(1).
          IF lv_char = ',' OR lv_char = '}' OR lv_char = ']' OR lv_char = ' '
              OR lv_char = cl_abap_char_utilities=>horizontal_tab
              OR lv_char = cl_abap_char_utilities=>newline
              OR lv_char = lv_cr.
            EXIT.
          ENDIF.
          mv_position = mv_position + 1.
        ENDWHILE.
        lv_length = mv_position - lv_start.
        IF lv_length = 0.
          syntax_error( `expected a value` ).
        ENDIF.
        lv_value = mv_text+lv_start(lv_length).
        IF lv_value = `true` OR lv_value = `false`.
          add_node( iv_parent = iv_parent iv_name = iv_name iv_kind = kind-boolean iv_value = lv_value ).
        ELSEIF lv_value = `null`.
          add_node( iv_parent = iv_parent iv_name = iv_name iv_kind = kind-null iv_value = lv_value ).
        ELSEIF lv_value CO '0123456789+-.eE'.
          add_node( iv_parent = iv_parent iv_name = iv_name iv_kind = kind-number iv_value = lv_value ).
        ELSE.
          syntax_error( `unknown value` ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.


  METHOD parse_string.
    " MV_POSITION is on the opening quote
    DATA lv_quote TYPE i.
    DATA lv_backslash TYPE i.
    DATA lv_next TYPE i.
    DATA lv_length TYPE i.
    DATA lv_piece TYPE string.
    DATA lv_escape TYPE c LENGTH 1.
    DATA lv_hex TYPE string.
    DATA lv_cr TYPE c LENGTH 1.
    DATA lv_crlf TYPE c LENGTH 2.

    " Carriage return: the first character of CR/LF
    lv_crlf = cl_abap_char_utilities=>cr_lf.
    lv_cr = lv_crlf(1).
    mv_position = mv_position + 1.
    DO.
      IF mv_position >= mv_length.
        syntax_error( `unterminated string` ).
      ENDIF.
      " Copy everything up to the next quote or backslash in one piece
      lv_quote = -1.
      lv_backslash = -1.
      FIND '"' IN SECTION OFFSET mv_position OF mv_text MATCH OFFSET lv_quote.
      IF sy-subrc <> 0.
        syntax_error( `unterminated string` ).
      ENDIF.
      " Only up to the quote: searching the whole rest of the text for every
      " string makes a large page slow, as most pages hold no backslash at all
      lv_length = lv_quote - mv_position.
      FIND '\' IN SECTION OFFSET mv_position LENGTH lv_length OF mv_text MATCH OFFSET lv_backslash.
      IF sy-subrc <> 0.
        lv_backslash = -1.
      ENDIF.
      IF lv_backslash >= 0 AND lv_backslash < lv_quote.
        lv_next = lv_backslash.
      ELSE.
        lv_next = lv_quote.
      ENDIF.
      lv_length = lv_next - mv_position.
      IF lv_length > 0.
        lv_piece = mv_text+mv_position(lv_length).
        CONCATENATE rv_text lv_piece INTO rv_text.
      ENDIF.
      mv_position = lv_next + 1.
      IF lv_next = lv_quote.
        RETURN.
      ENDIF.

      " Escape sequence
      IF mv_position >= mv_length.
        syntax_error( `unterminated string` ).
      ENDIF.
      lv_escape = mv_text+mv_position(1).
      mv_position = mv_position + 1.
      CASE lv_escape.
        WHEN '"' OR '\' OR '/'.
          lv_piece = lv_escape.
        WHEN 'n'.
          lv_piece = cl_abap_char_utilities=>newline.
        WHEN 'r'.
          lv_piece = lv_cr.
        WHEN 't'.
          lv_piece = cl_abap_char_utilities=>horizontal_tab.
        WHEN 'b'.
          lv_piece = unicode_char( `0008` ).
        WHEN 'f'.
          lv_piece = unicode_char( `000C` ).
        WHEN 'u'.
          IF mv_position + 4 > mv_length.
            syntax_error( `incomplete \u escape` ).
          ENDIF.
          lv_hex = mv_text+mv_position(4).
          mv_position = mv_position + 4.
          lv_piece = unicode_char( lv_hex ).
        WHEN OTHERS.
          syntax_error( `unknown escape` ).
      ENDCASE.
      CONCATENATE rv_text lv_piece INTO rv_text.
    ENDDO.
  ENDMETHOD.


  METHOD unicode_char.
    DATA lv_hex TYPE c LENGTH 4.
    DATA lv_char TYPE c LENGTH 1.

    lv_hex = iv_hex.
    TRANSLATE lv_hex TO UPPER CASE.
    " A space would be lost when a character field is moved to a string
    IF lv_hex = '0020'.
      rv_char = ` `.
      RETURN.
    ENDIF.
    TRY.
        lv_char = cl_abap_conv_in_ce=>uccp( lv_hex ).
        rv_char = lv_char.
      CATCH cx_root.                                     "#EC CATCH_ALL
        rv_char = '?'.
    ENDTRY.
  ENDMETHOD.


  METHOD find.
    DATA lt_parts TYPE ty_names.
    DATA lv_part TYPE string.
    DATA lv_found TYPE abap_bool.
    DATA ls_child TYPE ty_child.
    DATA ls_node TYPE ty_node.

    IF mt_nodes IS INITIAL.
      RETURN.
    ENDIF.
    rv_id = 1.
    IF iv_path IS INITIAL.
      RETURN.
    ENDIF.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    LOOP AT lt_parts INTO lv_part.
      IF lv_part IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_found = abap_false.
      LOOP AT mt_children INTO ls_child WHERE parent = rv_id.
        READ TABLE mt_nodes INDEX ls_child-id INTO ls_node.
        IF ls_node-name = lv_part.
          rv_id = ls_child-id.
          lv_found = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_found = abap_false.
        rv_id = 0.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD get.
    DATA lv_id TYPE i.
    DATA ls_node TYPE ty_node.
    lv_id = find( iv_path ).
    IF lv_id = 0.
      RETURN.
    ENDIF.
    READ TABLE mt_nodes INDEX lv_id INTO ls_node.
    IF ls_node-kind <> kind-object AND ls_node-kind <> kind-array AND ls_node-kind <> kind-null.
      rv_value = ls_node-value.
    ENDIF.
  ENDMETHOD.


  METHOD exists.
    rv_exists = abap_false.
    IF find( iv_path ) > 0.
      rv_exists = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD kind_of.
    DATA lv_id TYPE i.
    DATA ls_node TYPE ty_node.
    lv_id = find( iv_path ).
    IF lv_id = 0.
      RETURN.
    ENDIF.
    READ TABLE mt_nodes INDEX lv_id INTO ls_node.
    rv_kind = ls_node-kind.
  ENDMETHOD.


  METHOD count.
    DATA lv_id TYPE i.
    lv_id = find( iv_path ).
    IF lv_id = 0.
      RETURN.
    ENDIF.
    LOOP AT mt_children TRANSPORTING NO FIELDS WHERE parent = lv_id.
      rv_count = rv_count + 1.
    ENDLOOP.
  ENDMETHOD.


  METHOD names.
    DATA lv_id TYPE i.
    DATA ls_child TYPE ty_child.
    DATA ls_node TYPE ty_node.
    lv_id = find( iv_path ).
    IF lv_id = 0.
      RETURN.
    ENDIF.
    LOOP AT mt_children INTO ls_child WHERE parent = lv_id.
      READ TABLE mt_nodes INDEX ls_child-id INTO ls_node.
      APPEND ls_node-name TO rt_names.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Writes JSON for request bodies, for example:
*   CREATE OBJECT lo_writer.
*   lo_writer->begin_object( ).
*   lo_writer->begin_object( `message` ).
*   lo_writer->add_string( iv_name = `subject` iv_value = lv_subject ).
*   lo_writer->end_object( ).
*   lo_writer->add_boolean( iv_name = `saveToSentItems` iv_value = abap_true ).
*   lo_writer->end_object( ).
*   lv_json = lo_writer->result( ).
* Inside arrays, leave the names empty.
*----------------------------------------------------------------------*
CLASS lcl_graph_json_writer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS escape
      IMPORTING
        iv_text        TYPE string
      RETURNING
        value(rv_json) TYPE string.

    METHODS begin_object
      IMPORTING
        iv_name TYPE string OPTIONAL.

    METHODS end_object.

    METHODS begin_array
      IMPORTING
        iv_name TYPE string OPTIONAL.

    METHODS end_array.

    METHODS add_string
      IMPORTING
        iv_name  TYPE string OPTIONAL
        iv_value TYPE string.

    METHODS add_number
      IMPORTING
        iv_name  TYPE string OPTIONAL
        iv_value TYPE i.

    METHODS add_boolean
      IMPORTING
        iv_name  TYPE string OPTIONAL
        iv_value TYPE abap_bool.

    "! Inserts ready JSON text as the value
    METHODS add_raw
      IMPORTING
        iv_name TYPE string OPTIONAL
        iv_json TYPE string.

    METHODS result
      RETURNING
        value(rv_json) TYPE string.

  PRIVATE SECTION.
    " U+0000 to U+001F; JSON allows none of them as they are
    CLASS-DATA gv_controls TYPE string.

    DATA mv_json TYPE string.
    " One line per open object or array: X when it has no member yet
    DATA mt_first TYPE STANDARD TABLE OF abap_bool WITH DEFAULT KEY.

    METHODS member
      IMPORTING
        iv_name TYPE string.
ENDCLASS.


CLASS lcl_graph_json_writer IMPLEMENTATION.

  METHOD escape.
    CONSTANTS lc_hex TYPE c LENGTH 16 VALUE '0123456789abcdef'.
    DATA lv_length TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_piece TYPE string.
    DATA lv_cr TYPE c LENGTH 1.
    DATA lv_crlf TYPE c LENGTH 2.
    DATA lv_code TYPE c LENGTH 4.
    DATA lv_control TYPE c LENGTH 1.
    DATA lv_position TYPE i.
    DATA lv_high TYPE i.
    DATA lv_low TYPE i.

    IF gv_controls IS INITIAL.
      DO 32 TIMES.
        lv_position = sy-index - 1.
        lv_high = lv_position DIV 16.
        lv_low = lv_position MOD 16.
        CONCATENATE '00' lc_hex+lv_high(1) lc_hex+lv_low(1) INTO lv_code.
        " UCCP reads upper case hex only
        TRANSLATE lv_code TO UPPER CASE.
        lv_control = cl_abap_conv_in_ce=>uccp( lv_code ).
        CONCATENATE gv_controls lv_control INTO gv_controls.
      ENDDO.
    ENDIF.
    " Carriage return: the first character of CR/LF
    lv_crlf = cl_abap_char_utilities=>cr_lf.
    lv_cr = lv_crlf(1).
    lv_length = strlen( iv_text ).
    DO lv_length TIMES.
      lv_offset = sy-index - 1.
      lv_char = iv_text+lv_offset(1).
      CASE lv_char.
        WHEN '"'.
          lv_piece = `\"`.
        WHEN '\'.
          lv_piece = `\\`.
        WHEN cl_abap_char_utilities=>newline.
          lv_piece = `\n`.
        WHEN lv_cr.
          lv_piece = `\r`.
        WHEN cl_abap_char_utilities=>horizontal_tab.
          lv_piece = `\t`.
        WHEN ' '.
          lv_piece = ` `.
        WHEN OTHERS.
          lv_piece = lv_char.
          " Other control characters (backspace, form feed, U+0001 ...) as \u00XX
          FIND lv_char IN gv_controls MATCH OFFSET lv_position.
          IF sy-subrc = 0.
            lv_high = lv_position DIV 16.
            lv_low = lv_position MOD 16.
            CONCATENATE `\u00` lc_hex+lv_high(1) lc_hex+lv_low(1) INTO lv_piece.
          ENDIF.
      ENDCASE.
      CONCATENATE rv_json lv_piece INTO rv_json.
    ENDDO.
  ENDMETHOD.


  METHOD member.
    DATA lv_first TYPE abap_bool.
    DATA lv_lines TYPE i.
    DATA lv_name TYPE string.

    lv_lines = lines( mt_first ).
    IF lv_lines > 0.
      READ TABLE mt_first INDEX lv_lines INTO lv_first.
      IF lv_first = abap_true.
        MODIFY mt_first INDEX lv_lines FROM abap_false.
      ELSE.
        CONCATENATE mv_json ',' INTO mv_json.
      ENDIF.
    ENDIF.
    IF iv_name IS NOT INITIAL.
      lv_name = escape( iv_name ).
      CONCATENATE mv_json '"' lv_name '":' INTO mv_json.
    ENDIF.
  ENDMETHOD.


  METHOD begin_object.
    member( iv_name ).
    CONCATENATE mv_json '{' INTO mv_json.
    APPEND abap_true TO mt_first.
  ENDMETHOD.


  METHOD end_object.
    DATA lv_lines TYPE i.
    CONCATENATE mv_json '}' INTO mv_json.
    lv_lines = lines( mt_first ).
    DELETE mt_first INDEX lv_lines.
  ENDMETHOD.


  METHOD begin_array.
    member( iv_name ).
    CONCATENATE mv_json '[' INTO mv_json.
    APPEND abap_true TO mt_first.
  ENDMETHOD.


  METHOD end_array.
    DATA lv_lines TYPE i.
    CONCATENATE mv_json ']' INTO mv_json.
    lv_lines = lines( mt_first ).
    DELETE mt_first INDEX lv_lines.
  ENDMETHOD.


  METHOD add_string.
    DATA lv_value TYPE string.
    member( iv_name ).
    lv_value = escape( iv_value ).
    CONCATENATE mv_json '"' lv_value '"' INTO mv_json.
  ENDMETHOD.


  METHOD add_number.
    DATA lv_value TYPE string.
    member( iv_name ).
    lv_value = lcl_graph_conv=>num( iv_value ).
    CONCATENATE mv_json lv_value INTO mv_json.
  ENDMETHOD.


  METHOD add_boolean.
    member( iv_name ).
    IF iv_value = abap_true.
      CONCATENATE mv_json 'true' INTO mv_json.
    ELSE.
      CONCATENATE mv_json 'false' INTO mv_json.
    ENDIF.
  ENDMETHOD.


  METHOD add_raw.
    member( iv_name ).
    CONCATENATE mv_json iv_json INTO mv_json.
  ENDMETHOD.


  METHOD result.
    rv_json = mv_json.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* HTTP: one request through an SM59 destination. Behind an interface,
* so unit tests can answer instead of Microsoft.
*----------------------------------------------------------------------*
INTERFACE lif_graph_http.
  "! IV_URI: path and query, for example /v1.0/users?$top=5
  METHODS send
    IMPORTING
      iv_destination     TYPE rfcdest
      iv_method          TYPE string
      iv_uri             TYPE string
      it_headers         TYPE tihttpnvp
      iv_body            TYPE xstring
    RETURNING
      value(rs_response) TYPE lif_graph=>ty_response
    RAISING
      lcx_graph.

  "! To a full URL that Microsoft hands out with its own access key, for
  "! example the upload URL of a large attachment. No SM59 destination:
  "! the proxy comes from SICF (Client > Proxy Settings), the SSL client
  "! PSE is IV_SSL_ID.
  METHODS send_url
    IMPORTING
      iv_url             TYPE string
      iv_method          TYPE string
      it_headers         TYPE tihttpnvp
      iv_body            TYPE xstring
      iv_ssl_id          TYPE ssfapplssl
    RETURNING
      value(rs_response) TYPE lif_graph=>ty_response
    RAISING
      lcx_graph.
ENDINTERFACE.


CLASS lcl_graph_http DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES lif_graph_http.

  PRIVATE SECTION.
    "! Sends the request and reads the answer; IV_TARGET names the target in error texts
    METHODS execute
      IMPORTING
        io_client          TYPE REF TO if_http_client
        iv_method          TYPE string
        iv_uri             TYPE string
        it_headers         TYPE tihttpnvp
        iv_body            TYPE xstring
        iv_target          TYPE string
      RETURNING
        value(rs_response) TYPE lif_graph=>ty_response
      RAISING
        lcx_graph.
ENDCLASS.


CLASS lcl_graph_http IMPLEMENTATION.

  METHOD lif_graph_http~send.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_text TYPE string.
    DATA lv_hint TYPE string.
    DATA lv_target TYPE string.

    cl_http_client=>create_by_destination(
      EXPORTING
        destination              = iv_destination
      IMPORTING
        client                   = lo_client
      EXCEPTIONS
        argument_not_found       = 1
        destination_not_found    = 2
        destination_no_authority = 3
        plugin_not_active        = 4
        internal_error           = 5
        OTHERS                   = 6 ).
    IF sy-subrc <> 0.
      CASE sy-subrc.
        WHEN 2.
          CONCATENATE `SM59 destination ` iv_destination ` does not exist.` INTO lv_text.
          lv_hint = `Create it in SM59 as type G (HTTP connection to external server); see the installation guide.`.
        WHEN 3.
          CONCATENATE `You are not authorized to use SM59 destination ` iv_destination `.` INTO lv_text.
          lv_hint = `Ask Basis for authorization object S_ICF for this destination.`.
        WHEN 4.
          lv_text = `The HTTP client is not active on this SAP system.`.
          lv_hint = `Ask Basis to activate the HTTP/HTTPS ports (transaction SMICM).`.
        WHEN OTHERS.
          CONCATENATE `SM59 destination ` iv_destination ` cannot be used.` INTO lv_text.
      ENDCASE.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = lv_hint.
    ENDIF.

    CONCATENATE `SM59 destination ` iv_destination INTO lv_target.
    rs_response = execute( io_client  = lo_client
                           iv_method  = iv_method
                           iv_uri     = iv_uri
                           it_headers = it_headers
                           iv_body    = iv_body
                           iv_target  = lv_target ).
  ENDMETHOD.


  METHOD lif_graph_http~send_url.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_host TYPE string.
    DATA lv_text TYPE string.

    " Only the host goes into error texts: the rest of the URL is a secret key
    lv_host = iv_url.
    REPLACE FIRST OCCURRENCE OF 'https://' IN lv_host WITH ''.
    SPLIT lv_host AT '/' INTO lv_host lv_text.
    cl_http_client=>create_by_url(
      EXPORTING
        url                = iv_url
        ssl_id             = iv_ssl_id
      IMPORTING
        client             = lo_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4 ).
    IF sy-subrc <> 0.
      CONCATENATE `No HTTP client for ` lv_host `.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = `Ask Basis to check the HTTPS port (SMICM) and the SSL client PSE in STRUST.`.
    ENDIF.
    rs_response = execute( io_client  = lo_client
                           iv_method  = iv_method
                           iv_uri     = ``
                           it_headers = it_headers
                           iv_body    = iv_body
                           iv_target  = lv_host ).
  ENDMETHOD.


  METHOD execute.
    DATA lo_client TYPE REF TO if_http_client.
    DATA ls_header TYPE ihttpnvp.
    DATA lv_code TYPE i.
    DATA lv_reason TYPE string.
    DATA lv_message TYPE string.
    DATA lv_text TYPE string.
    DATA lv_hint TYPE string.

    lo_client = io_client.
    " Never show a logon popup or keep cookies; a background job has no one to answer
    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.
    lo_client->propertytype_accept_cookie = if_http_client=>co_disabled.
    lo_client->request->set_method( iv_method ).
    IF iv_uri IS NOT INITIAL.
      cl_http_utility=>set_request_uri( request = lo_client->request uri = iv_uri ).
    ENDIF.
    LOOP AT it_headers INTO ls_header.
      lo_client->request->set_header_field( name = ls_header-name value = ls_header-value ).
    ENDLOOP.
    IF iv_body IS NOT INITIAL.
      lo_client->request->set_data( iv_body ).
    ENDIF.

    lo_client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        http_invalid_timeout       = 4
        OTHERS                     = 5 ).
    IF sy-subrc = 0.
      lo_client->receive(
        EXCEPTIONS
          http_communication_failure = 1
          http_invalid_state         = 2
          http_processing_failed     = 3
          OTHERS                     = 4 ).
    ENDIF.
    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING message = lv_message ).
      lo_client->close( ).
      CONCATENATE `No connection to ` iv_target `: ` lv_message INTO lv_text.
      lv_hint = `Check in SM59 (Connection Test) the host, port 443 and "SSL active"; in STRUST that the SSL client PSE has the Microsoft root certificates; the proxy; and that the kernel supports TLS 1.2.`.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = lv_hint.
    ENDIF.

    lo_client->response->get_status( IMPORTING code = lv_code reason = lv_reason ).
    rs_response-status = lv_code.
    rs_response-reason = lv_reason.
    rs_response-body = lo_client->response->get_data( ).
    lo_client->response->get_header_fields( CHANGING fields = rs_response-headers ).
    lo_client->close( ).
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Access token for the application (OAuth2 client credentials). The
* client ID and secret are sent by the SM59 destination as basic
* authentication; Microsoft accepts that (client_secret_basic).
* Tokens are kept until five minutes before they expire.
*----------------------------------------------------------------------*
CLASS lcl_graph_token DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS scope TYPE string VALUE `https://graph.microsoft.com/.default`.

    METHODS constructor
      IMPORTING
        is_config TYPE lif_graph=>ty_config
        io_http   TYPE REF TO lif_graph_http.

    METHODS get
      RETURNING
        value(rv_token) TYPE string
      RAISING
        lcx_graph.

    "! Forgets the cached token, for example after HTTP 401
    METHODS invalidate.

    "! Application permissions in the token (claim "roles"), for checks
    CLASS-METHODS roles_of
      IMPORTING
        iv_token        TYPE string
      RETURNING
        value(rt_roles) TYPE lcl_graph_json=>ty_names.

    "! Turns a Microsoft sign-in error (AADSTS...) into a hint
    CLASS-METHODS hint_for
      IMPORTING
        iv_description TYPE string
      RETURNING
        value(rv_hint) TYPE string.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_cached,
        tenant      TYPE string,
        destination TYPE rfcdest,
        token       TYPE string,
        valid_until TYPE timestampl,
      END OF ty_cached.

    CLASS-DATA gt_cache TYPE SORTED TABLE OF ty_cached WITH UNIQUE KEY tenant destination.

    DATA ms_config TYPE lif_graph=>ty_config.
    DATA mo_http TYPE REF TO lif_graph_http.
ENDCLASS.


CLASS lcl_graph_token IMPLEMENTATION.

  METHOD constructor.
    ms_config = is_config.
    mo_http = io_http.
  ENDMETHOD.


  METHOD get.
    DATA ls_cached TYPE ty_cached.
    DATA lv_now TYPE timestampl.
    DATA lv_uri TYPE string.
    DATA lv_form TYPE string.
    DATA lv_scope TYPE string.
    DATA lv_body TYPE xstring.
    DATA lt_headers TYPE tihttpnvp.
    DATA ls_header TYPE ihttpnvp.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lv_text TYPE string.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_error TYPE string.
    DATA lv_description TYPE string.
    DATA lv_hint TYPE string.
    DATA lv_status TYPE string.
    DATA lv_seconds TYPE i.

    GET TIME STAMP FIELD lv_now.
    READ TABLE gt_cache INTO ls_cached
      WITH TABLE KEY tenant = ms_config-tenant destination = ms_config-login_destination.
    IF sy-subrc = 0 AND ls_cached-valid_until > lv_now.
      rv_token = ls_cached-token.
      RETURN.
    ENDIF.

    IF ms_config-tenant IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `No tenant given.`
          hint = `Enter the directory (tenant) ID or the tenant domain, for example contoso.onmicrosoft.com.`.
    ENDIF.

    CONCATENATE '/' ms_config-tenant '/oauth2/v2.0/token' INTO lv_uri.
    lv_scope = lcl_graph_conv=>url_encode( scope ).
    CONCATENATE 'grant_type=client_credentials&scope=' lv_scope INTO lv_form.
    lv_body = lcl_graph_conv=>to_utf8( lv_form ).
    ls_header-name = 'Content-Type'.
    ls_header-value = 'application/x-www-form-urlencoded'.
    APPEND ls_header TO lt_headers.
    ls_header-name = 'Accept'.
    ls_header-value = 'application/json'.
    APPEND ls_header TO lt_headers.

    ls_response = mo_http->send( iv_destination = ms_config-login_destination
                                 iv_method      = 'POST'
                                 iv_uri         = lv_uri
                                 it_headers     = lt_headers
                                 iv_body        = lv_body ).
    lv_text = lcl_graph_conv=>from_utf8( ls_response-body ).
    TRY.
        lo_json = lcl_graph_json=>parse( lv_text ).
      CATCH lcx_graph.
        lv_status = lcl_graph_conv=>num( ls_response-status ).
        CONCATENATE `Microsoft sign-in answered HTTP ` lv_status ` without JSON.` INTO lv_text.
        RAISE EXCEPTION TYPE lcx_graph
          EXPORTING
            text        = lv_text
            hint        = `Check that SM59 destination ZCHE_GRAPH_LOGIN points to login.microsoftonline.com without a path prefix.`
            http_status = ls_response-status.
    ENDTRY.

    IF ls_response-status <> 200.
      lv_error = lo_json->get( `error` ).
      lv_description = lo_json->get( `error_description` ).
      lv_hint = hint_for( lv_description ).
      CONCATENATE `Microsoft sign-in refused the token request: ` lv_error ` - ` lv_description INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text        = lv_text
          hint        = lv_hint
          http_status = ls_response-status
          error_code  = lv_error.
    ENDIF.

    rv_token = lo_json->get( `access_token` ).
    IF rv_token IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `Microsoft sign-in answered without an access token.`.
    ENDIF.
    lv_seconds = lo_json->get( `expires_in` ).
    lv_seconds = lv_seconds - 300.
    IF lv_seconds < 0.
      lv_seconds = 0.
    ENDIF.
    ls_cached-tenant = ms_config-tenant.
    ls_cached-destination = ms_config-login_destination.
    ls_cached-token = rv_token.
    ls_cached-valid_until = cl_abap_tstmp=>add( tstmp = lv_now secs = lv_seconds ).
    DELETE TABLE gt_cache WITH TABLE KEY tenant = ms_config-tenant destination = ms_config-login_destination.
    INSERT ls_cached INTO TABLE gt_cache.
  ENDMETHOD.


  METHOD invalidate.
    DELETE TABLE gt_cache WITH TABLE KEY tenant = ms_config-tenant destination = ms_config-login_destination.
  ENDMETHOD.


  METHOD roles_of.
    DATA lt_parts TYPE lcl_graph_json=>ty_names.
    DATA lv_payload TYPE string.
    DATA lv_bytes TYPE xstring.
    DATA lv_json TYPE string.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_path TYPE string.
    DATA lv_number TYPE string.
    DATA lv_role TYPE string.

    SPLIT iv_token AT '.' INTO TABLE lt_parts.
    READ TABLE lt_parts INDEX 2 INTO lv_payload.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    TRY.
        lv_bytes = lcl_graph_conv=>from_base64( lv_payload ).
        lv_json = lcl_graph_conv=>from_utf8( lv_bytes ).
        lo_json = lcl_graph_json=>parse( lv_json ).
      CATCH cx_root.                                     "#EC CATCH_ALL
        RETURN.
    ENDTRY.
    lv_count = lo_json->count( `roles` ).
    DO lv_count TIMES.
      lv_index = sy-index - 1.
      lv_number = lcl_graph_conv=>num( lv_index ).
      CONCATENATE `roles/` lv_number INTO lv_path.
      lv_role = lo_json->get( lv_path ).
      APPEND lv_role TO rt_roles.
    ENDDO.
  ENDMETHOD.


  METHOD hint_for.
    IF iv_description CS 'AADSTS7000215'.
      rv_hint = `The client secret is wrong. In SM59 destination ZCHE_GRAPH_LOGIN the password must be the secret's "Value", not its "Secret ID".`.
    ELSEIF iv_description CS 'AADSTS7000222'.
      rv_hint = `The client secret has expired. Create a new one in the app registration and enter it in SM59.`.
    ELSEIF iv_description CS 'AADSTS700038'.
      rv_hint = `The user in SM59 destination ZCHE_GRAPH_LOGIN is not an application ID. Enter the "Application (client) ID" from the app registration overview.`.
    ELSEIF iv_description CS 'AADSTS700016'.
      rv_hint = `The application (client) ID was not found in this tenant. Check the user in SM59 destination ZCHE_GRAPH_LOGIN and the tenant ID.`.
    ELSEIF iv_description CS 'AADSTS90002' OR iv_description CS 'AADSTS900023'.
      rv_hint = `The tenant was not found. Use the directory (tenant) ID from the app registration overview, or the tenant domain.`.
    ELSEIF iv_description CS 'AADSTS7000216' OR iv_description CS 'AADSTS7000218'
        OR iv_description CS 'AADSTS900144'.
      rv_hint = `The client ID or secret did not arrive. In SM59 destination ZCHE_GRAPH_LOGIN set "Basic authentication" with user = client ID and password = secret.`.
    ELSEIF iv_description CS 'AADSTS50126' OR iv_description CS 'AADSTS50034'.
      rv_hint = `Microsoft treated the request as a user sign-in. Check the SM59 logon data: only the client ID and secret belong there.`.
    ELSEIF iv_description CS 'AADSTS1002012'.
      rv_hint = `The scope is not accepted. This should not happen; please report it.`.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Microsoft Graph calls. Paths are relative to the API version, for
* example /users/someone@contoso.com/sendMail; a path that starts with
* /v1.0/ or /beta/ is used as it is.
* - HTTP 429 is retried after the time Microsoft asks for (header
*   Retry-After, at most 60 seconds), up to MAX_RETRIES times. HTTP 503
*   and 504 too, but only for GET, PUT and DELETE: a POST or PATCH may
*   have been carried out, so it is not sent a second time.
* - HTTP 401 gets one new token and one more try.
* - Other answers from 400 on raise LCX_GRAPH with Microsoft's error
*   code, message, request ID and a hint.
*----------------------------------------------------------------------*
CLASS lcl_graph_client DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES ty_pages TYPE STANDARD TABLE OF REF TO lcl_graph_json WITH DEFAULT KEY.

    "! IO_HTTP only for tests; normally empty
    METHODS constructor
      IMPORTING
        is_config TYPE lif_graph=>ty_config
        io_http   TYPE REF TO lif_graph_http OPTIONAL.

    "! Default destinations, API version and retries for a tenant
    CLASS-METHODS default_config
      IMPORTING
        iv_tenant        TYPE string
      RETURNING
        value(rs_config) TYPE lif_graph=>ty_config.

    "! Any call; the body is sent as it is. Raises LCX_GRAPH from HTTP 400 on.
    METHODS request
      IMPORTING
        iv_method          TYPE string
        iv_path            TYPE string
        iv_body            TYPE xstring OPTIONAL
        iv_content_type    TYPE string OPTIONAL
        it_headers         TYPE tihttpnvp OPTIONAL
      RETURNING
        value(rs_response) TYPE lif_graph=>ty_response
      RAISING
        lcx_graph.

    METHODS get_json
      IMPORTING
        iv_path        TYPE string
        it_headers     TYPE tihttpnvp OPTIONAL
      RETURNING
        value(ro_json) TYPE REF TO lcl_graph_json
      RAISING
        lcx_graph.

    "! GET and follow @odata.nextLink; one entry per page.
    "! IV_MAX_ITEMS: stop once the pages hold that many entries in "value"
    "! (0: no limit). IV_MAX_PAGES guards against endless paging: when
    "! Microsoft still has more after that many pages, LCX_GRAPH is raised
    "! rather than returning part of the result as if it were all.
    METHODS get_pages
      IMPORTING
        iv_path         TYPE string
        iv_max_pages    TYPE i DEFAULT 100
        iv_max_items    TYPE i DEFAULT 0
        it_headers      TYPE tihttpnvp OPTIONAL
      RETURNING
        value(rt_pages) TYPE ty_pages
      RAISING
        lcx_graph.

    "! POST, PATCH or PUT with a JSON body; returns the JSON answer (or an empty one)
    METHODS send_json
      IMPORTING
        iv_method      TYPE string
        iv_path        TYPE string
        iv_json        TYPE string
        it_headers     TYPE tihttpnvp OPTIONAL
      RETURNING
        value(ro_json) TYPE REF TO lcl_graph_json
      RAISING
        lcx_graph.

    METHODS delete_path
      IMPORTING
        iv_path    TYPE string
        it_headers TYPE tihttpnvp OPTIONAL
      RAISING
        lcx_graph.

    "! To a full URL Microsoft handed out with its own key (no token is sent),
    "! for example an upload URL. Raises LCX_GRAPH from HTTP 400 on.
    METHODS request_url
      IMPORTING
        iv_method          TYPE string
        iv_url             TYPE string
        iv_body            TYPE xstring OPTIONAL
        it_headers         TYPE tihttpnvp OPTIONAL
      RETURNING
        value(rs_response) TYPE lif_graph=>ty_response
      RAISING
        lcx_graph.

    "! The path part of an absolute Graph URL, for example of @odata.nextLink
    CLASS-METHODS path_of_url
      IMPORTING
        iv_url         TYPE string
      RETURNING
        value(rv_path) TYPE string.

    CLASS-METHODS header_value
      IMPORTING
        it_headers      TYPE tihttpnvp
        iv_name         TYPE string
      RETURNING
        value(rv_value) TYPE string.

  PRIVATE SECTION.
    DATA ms_config TYPE lif_graph=>ty_config.
    DATA mo_http TYPE REF TO lif_graph_http.
    DATA mo_token TYPE REF TO lcl_graph_token.

    METHODS full_path
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    METHODS raise_error
      IMPORTING
        is_response TYPE lif_graph=>ty_response
        iv_method   TYPE string
        iv_path     TYPE string
      RAISING
        lcx_graph.

    METHODS wait_seconds
      IMPORTING
        is_response       TYPE lif_graph=>ty_response
        iv_attempt        TYPE i
      RETURNING
        value(rv_seconds) TYPE i.
ENDCLASS.


CLASS lcl_graph_client IMPLEMENTATION.

  METHOD default_config.
    rs_config-tenant = iv_tenant.
    rs_config-login_destination = lif_graph=>default_login_destination.
    rs_config-api_destination = lif_graph=>default_api_destination.
    rs_config-api_version = lif_graph=>default_api_version.
    rs_config-max_retries = lif_graph=>default_max_retries.
    rs_config-ssl_id = lif_graph=>default_ssl_id.
  ENDMETHOD.


  METHOD constructor.
    ms_config = is_config.
    IF ms_config-login_destination IS INITIAL.
      ms_config-login_destination = lif_graph=>default_login_destination.
    ENDIF.
    IF ms_config-api_destination IS INITIAL.
      ms_config-api_destination = lif_graph=>default_api_destination.
    ENDIF.
    IF ms_config-api_version IS INITIAL.
      ms_config-api_version = lif_graph=>default_api_version.
    ENDIF.
    IF ms_config-ssl_id IS INITIAL.
      ms_config-ssl_id = lif_graph=>default_ssl_id.
    ENDIF.
    IF io_http IS BOUND.
      mo_http = io_http.
    ELSE.
      CREATE OBJECT mo_http TYPE lcl_graph_http.
    ENDIF.
    CREATE OBJECT mo_token
      EXPORTING
        is_config = ms_config
        io_http   = mo_http.
  ENDMETHOD.


  METHOD full_path.
    IF iv_path CP '/v1.0/*' OR iv_path CP '/beta/*'.
      rv_path = iv_path.
    ELSEIF iv_path IS NOT INITIAL AND iv_path(1) = '/'.
      CONCATENATE '/' ms_config-api_version iv_path INTO rv_path.
    ELSE.
      CONCATENATE '/' ms_config-api_version '/' iv_path INTO rv_path.
    ENDIF.
  ENDMETHOD.


  METHOD request.
    DATA lt_headers TYPE tihttpnvp.
    DATA ls_header TYPE ihttpnvp.
    DATA lv_token TYPE string.
    DATA lv_uri TYPE string.
    DATA lv_attempt TYPE i.
    DATA lv_renewed TYPE abap_bool.
    DATA lv_seconds TYPE i.

    lv_uri = full_path( iv_path ).
    DO.
      lv_token = mo_token->get( ).
      CLEAR lt_headers.
      ls_header-name = 'Authorization'.
      CONCATENATE 'Bearer' lv_token INTO ls_header-value SEPARATED BY space.
      APPEND ls_header TO lt_headers.
      ls_header-name = 'Accept'.
      ls_header-value = 'application/json'.
      APPEND ls_header TO lt_headers.
      IF iv_content_type IS NOT INITIAL.
        ls_header-name = 'Content-Type'.
        ls_header-value = iv_content_type.
        APPEND ls_header TO lt_headers.
      ENDIF.
      APPEND LINES OF it_headers TO lt_headers.

      rs_response = mo_http->send( iv_destination = ms_config-api_destination
                                   iv_method      = iv_method
                                   iv_uri         = lv_uri
                                   it_headers     = lt_headers
                                   iv_body        = iv_body ).

      IF rs_response-status = 401 AND lv_renewed = abap_false.
        " The token may have been revoked or be too old: one more try with a new one
        mo_token->invalidate( ).
        lv_renewed = abap_true.
        CONTINUE.
      ENDIF.
      " 429: Microsoft did not carry the request out, so any request may go again.
      " 503/504: it may have been carried out; only requests that do the same
      " when repeated go again, not POST or PATCH (a second mail, a second item)
      IF lv_attempt < ms_config-max_retries
         AND ( rs_response-status = 429
            OR ( ( rs_response-status = 503 OR rs_response-status = 504 )
             AND ( iv_method = 'GET' OR iv_method = 'PUT' OR iv_method = 'DELETE' ) ) ).
        lv_attempt = lv_attempt + 1.
        lv_seconds = wait_seconds( is_response = rs_response iv_attempt = lv_attempt ).
        IF lv_seconds > 0.
          WAIT UP TO lv_seconds SECONDS.
        ENDIF.
        CONTINUE.
      ENDIF.
      EXIT.
    ENDDO.

    IF rs_response-status >= 400.
      raise_error( is_response = rs_response iv_method = iv_method iv_path = lv_uri ).
    ENDIF.
  ENDMETHOD.


  METHOD wait_seconds.
    DATA lv_value TYPE string.
    lv_value = header_value( it_headers = is_response-headers iv_name = `retry-after` ).
    IF lv_value IS NOT INITIAL AND lv_value CO '0123456789'.
      rv_seconds = lv_value.
    ELSE.
      " No advice from Microsoft: 2, 4, 8 ... seconds
      rv_seconds = 1.
      DO iv_attempt TIMES.
        rv_seconds = rv_seconds * 2.
      ENDDO.
    ENDIF.
    IF rv_seconds > 60.
      rv_seconds = 60.
    ENDIF.
  ENDMETHOD.


  METHOD header_value.
    DATA ls_header TYPE ihttpnvp.
    DATA lv_name TYPE string.
    DATA lv_wanted TYPE string.

    lv_wanted = iv_name.
    TRANSLATE lv_wanted TO LOWER CASE.
    LOOP AT it_headers INTO ls_header.
      lv_name = ls_header-name.
      TRANSLATE lv_name TO LOWER CASE.
      IF lv_name = lv_wanted.
        rv_value = ls_header-value.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD raise_error.
    DATA lv_text TYPE string.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_code TYPE string.
    DATA lv_message TYPE string.
    DATA lv_request_id TYPE string.
    DATA lv_status TYPE string.
    DATA lv_hint TYPE string.

    lv_text = lcl_graph_conv=>from_utf8( is_response-body ).
    TRY.
        lo_json = lcl_graph_json=>parse( lv_text ).
        lv_code = lo_json->get( `error/code` ).
        lv_message = lo_json->get( `error/message` ).
        lv_request_id = lo_json->get( `error/innerError/request-id` ).
      CATCH lcx_graph.                                    "#EC NO_HANDLER
        " Not JSON: keep the status only
    ENDTRY.
    IF lv_request_id IS INITIAL.
      lv_request_id = header_value( it_headers = is_response-headers iv_name = `request-id` ).
    ENDIF.

    CASE is_response-status.
      WHEN 400.
        lv_hint = `The request was not accepted; the message above says which value is wrong.`.
      WHEN 401.
        lv_hint = `The token was not accepted. Check that SM59 destination ZCHE_GRAPH_API has no logon data of its own.`.
      WHEN 403.
        lv_hint = `The application lacks a permission for this call, admin consent is missing, or the mailbox or site is not in the allowed scope. Check the API permissions of the app registration.`.
      WHEN 404.
        lv_hint = `Not found: check the user, mailbox, site or item in the path.`.
      WHEN 429.
        lv_hint = `Microsoft is busy or limiting requests; the call was retried. Run it again later or with smaller amounts.`.
      WHEN 503 OR 504.
        IF iv_method = 'POST' OR iv_method = 'PATCH'.
          lv_hint = `The outcome is unknown: Microsoft may have carried the request out. Check (for a mail: Sent Items; for a list or table: its items) before you run it again.`.
        ELSE.
          lv_hint = `Microsoft is busy; the call was retried. Run it again later.`.
        ENDIF.
    ENDCASE.

    lv_status = lcl_graph_conv=>num( is_response-status ).
    CONCATENATE `Microsoft Graph answered HTTP ` lv_status ` to ` iv_method ` ` iv_path INTO lv_text.
    IF lv_code IS NOT INITIAL.
      CONCATENATE lv_text `: ` lv_code ` - ` lv_message INTO lv_text.
    ENDIF.
    RAISE EXCEPTION TYPE lcx_graph
      EXPORTING
        text        = lv_text
        hint        = lv_hint
        http_status = is_response-status
        error_code  = lv_code
        request_id  = lv_request_id.
  ENDMETHOD.


  METHOD get_json.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lv_text TYPE string.
    ls_response = request( iv_method = 'GET' iv_path = iv_path it_headers = it_headers ).
    lv_text = lcl_graph_conv=>from_utf8( ls_response-body ).
    ro_json = lcl_graph_json=>parse( lv_text ).
  ENDMETHOD.


  METHOD get_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_next TYPE string.
    DATA lv_items TYPE i.
    DATA lv_count TYPE i.
    DATA lv_number TYPE string.
    DATA lv_text TYPE string.

    lv_path = iv_path.
    DO iv_max_pages TIMES.
      lo_page = get_json( iv_path = lv_path it_headers = it_headers ).
      APPEND lo_page TO rt_pages.
      lv_next = lo_page->get( `@odata.nextLink` ).
      IF lv_next IS INITIAL.
        RETURN.
      ENDIF.
      " Enough entries: the next page is not asked for
      lv_count = lo_page->count( `value` ).
      lv_items = lv_items + lv_count.
      IF iv_max_items > 0 AND lv_items >= iv_max_items.
        RETURN.
      ENDIF.
      lv_path = path_of_url( lv_next ).
    ENDDO.
    lv_number = lcl_graph_conv=>num( iv_max_pages ).
    CONCATENATE `Microsoft Graph has more than ` lv_number ` pages for ` iv_path `; the result would not be complete.` INTO lv_text.
    RAISE EXCEPTION TYPE lcx_graph
      EXPORTING
        text = lv_text
        hint = `Narrow the request (a filter, a folder) or ask for fewer entries.`.
  ENDMETHOD.


  METHOD send_json.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lv_body TYPE xstring.
    DATA lv_text TYPE string.

    lv_body = lcl_graph_conv=>to_utf8( iv_json ).
    ls_response = request( iv_method       = iv_method
                           iv_path         = iv_path
                           iv_body         = lv_body
                           iv_content_type = `application/json`
                           it_headers      = it_headers ).
    lv_text = lcl_graph_conv=>from_utf8( ls_response-body ).
    IF lv_text IS INITIAL.
      lv_text = `{}`.
    ENDIF.
    ro_json = lcl_graph_json=>parse( lv_text ).
  ENDMETHOD.


  METHOD delete_path.
    request( iv_method = 'DELETE' iv_path = iv_path it_headers = it_headers ).
  ENDMETHOD.


  METHOD request_url.
    DATA lv_host TYPE string.
    DATA lv_rest TYPE string.

    rs_response = mo_http->send_url( iv_url     = iv_url
                                     iv_method  = iv_method
                                     it_headers = it_headers
                                     iv_body    = iv_body
                                     iv_ssl_id  = ms_config-ssl_id ).
    IF rs_response-status >= 400.
      " The URL carries a key: only its host goes into the error text
      lv_host = iv_url.
      REPLACE FIRST OCCURRENCE OF 'https://' IN lv_host WITH ''.
      SPLIT lv_host AT '/' INTO lv_host lv_rest.
      raise_error( is_response = rs_response iv_method = iv_method iv_path = lv_host ).
    ENDIF.
  ENDMETHOD.


  METHOD path_of_url.
    DATA lv_offset TYPE i.
    DATA lv_rest TYPE string.

    rv_path = iv_url.
    FIND '://' IN iv_url MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lv_offset = lv_offset + 3.
    lv_rest = iv_url+lv_offset.
    FIND '/' IN lv_rest MATCH OFFSET lv_offset.
    IF sy-subrc = 0.
      rv_path = lv_rest+lv_offset.
    ELSE.
      rv_path = '/'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* SharePoint sites, shared by the files and lists modules
*----------------------------------------------------------------------*
CLASS lcl_graph_site DEFINITION FINAL.
  PUBLIC SECTION.
    "! The site's ID. IV_HOST: contoso.sharepoint.com; IV_SITE: /sites/Finance
    "! (empty for the root site)
    CLASS-METHODS id
      IMPORTING
        io_client    TYPE REF TO lcl_graph_client
        iv_host      TYPE string
        iv_site      TYPE string OPTIONAL
      RETURNING
        value(rv_id) TYPE string
      RAISING
        lcx_graph.
ENDCLASS.


CLASS lcl_graph_site IMPLEMENTATION.

  METHOD id.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_site TYPE string.
    DATA lv_host TYPE string.

    lv_host = iv_host.
    CONDENSE lv_host.
    IF lv_host IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `No SharePoint host given.`
          hint = `Enter the host of your SharePoint, for example contoso.sharepoint.com.`.
    ENDIF.
    " /sites/{host}:/sites/Finance, or /sites/{host} for the root site
    lv_site = lcl_graph_conv=>encode_path( iv_site ).
    IF lv_site IS INITIAL.
      CONCATENATE `/sites/` lv_host `?$select=id` INTO lv_path.
    ELSE.
      CONCATENATE `/sites/` lv_host `:/` lv_site `?$select=id` INTO lv_path.
    ENDIF.
    lo_json = io_client->get_json( lv_path ).
    rv_id = lo_json->get( `id` ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests. They run with the program that includes this core (in
*& ADT: Ctrl+Shift+F10; in SE38: Program > Execute > Unit Tests). No
*& call leaves the system: a test double answers instead of Microsoft.
*& Written for ABAP 7.00: risk level and duration are pseudo comments,
*& and every result is put into a variable before it is checked.
*&---------------------------------------------------------------------*
CLASS ltd_graph_http DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PUBLIC SECTION.
    INTERFACES lif_graph_http.

    TYPES:
      BEGIN OF ty_request,
        destination TYPE rfcdest,
        method      TYPE string,
        uri         TYPE string,
        headers     TYPE tihttpnvp,
        body        TYPE string,
      END OF ty_request.

    DATA mt_requests TYPE STANDARD TABLE OF ty_request WITH DEFAULT KEY.

    "! Queues an answer; answers are given in the order they were queued
    METHODS answer
      IMPORTING
        iv_status      TYPE i
        iv_body        TYPE string OPTIONAL
        iv_retry_after TYPE string OPTIONAL.

    METHODS token_answer.

  PRIVATE SECTION.
    DATA mt_answers TYPE STANDARD TABLE OF lif_graph=>ty_response WITH DEFAULT KEY.
ENDCLASS.


CLASS ltd_graph_http IMPLEMENTATION.

  METHOD answer.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA ls_header TYPE ihttpnvp.
    ls_response-status = iv_status.
    ls_response-body = lcl_graph_conv=>to_utf8( iv_body ).
    IF iv_retry_after IS NOT INITIAL.
      ls_header-name = 'Retry-After'.
      ls_header-value = iv_retry_after.
      APPEND ls_header TO ls_response-headers.
    ENDIF.
    APPEND ls_response TO mt_answers.
  ENDMETHOD.


  METHOD token_answer.
    answer( iv_status = 200 iv_body = `{"token_type":"Bearer","expires_in":3599,"access_token":"TOKEN1"}` ).
  ENDMETHOD.


  METHOD lif_graph_http~send_url.
    rs_response = lif_graph_http~send( iv_destination = space
                                       iv_method      = iv_method
                                       iv_uri         = iv_url
                                       it_headers     = it_headers
                                       iv_body        = iv_body ).
  ENDMETHOD.


  METHOD lif_graph_http~send.
    DATA ls_request TYPE ty_request.
    ls_request-destination = iv_destination.
    ls_request-method = iv_method.
    ls_request-uri = iv_uri.
    ls_request-headers = it_headers.
    ls_request-body = lcl_graph_conv=>from_utf8( iv_body ).
    APPEND ls_request TO mt_requests.
    READ TABLE mt_answers INDEX 1 INTO rs_response.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `Test double: no answer queued`.
    ENDIF.
    DELETE mt_answers INDEX 1.
  ENDMETHOD.

ENDCLASS.


CLASS ltc_graph_json DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    METHODS objects_and_arrays FOR TESTING RAISING lcx_graph.
    METHODS escapes FOR TESTING RAISING lcx_graph.
    METHODS values FOR TESTING RAISING lcx_graph.
    METHODS empty_containers FOR TESTING RAISING lcx_graph.
    METHODS invalid_json FOR TESTING.
    METHODS writer FOR TESTING.
    METHODS writer_escapes FOR TESTING.
    METHODS control_characters FOR TESTING RAISING lcx_graph.
    METHODS json_numbers FOR TESTING.
    METHODS negative_number FOR TESTING.
    METHODS bytes_not_utf8 FOR TESTING.
    METHODS backslash_after_quote FOR TESTING RAISING lcx_graph.
ENDCLASS.


CLASS ltc_graph_json IMPLEMENTATION.

  METHOD objects_and_arrays.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA lv_names TYPE string.
    DATA lv_text TYPE string.

    CONCATENATE `{ "value": [ {"id":"A1","from":{"emailAddress":{"name":"Derya"}}}, {"id":"A2"} ],`
                ` "@odata.nextLink": "https://graph.microsoft.com/v1.0/x?$skiptoken=1" }` INTO lv_text.
    lo_json = lcl_graph_json=>parse( lv_text ).
    lv_value = lo_json->get( `value/0/id` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `A1` ).
    lv_value = lo_json->get( `value/1/id` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `A2` ).
    lv_value = lo_json->get( `value/0/from/emailAddress/name` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Derya` ).
    lv_value = lo_json->get( `@odata.nextLink` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `https://graph.microsoft.com/v1.0/x?$skiptoken=1` ).
    lv_count = lo_json->count( `value` ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    lt_names = lo_json->names( `value/0` ).
    CONCATENATE LINES OF lt_names INTO lv_names SEPARATED BY ','.
    cl_aunit_assert=>assert_equals( act = lv_names exp = `id,from` ).
    lv_value = lo_json->get( `value/5/id` ).
    cl_aunit_assert=>assert_initial( lv_value ).
  ENDMETHOD.


  METHOD escapes.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_value TYPE string.
    DATA lv_expected TYPE string.

    lo_json = lcl_graph_json=>parse( `{"a":"say \"hi\"\\ok\/","b":"G\u00fcney \u0130zmir","c":"x\u0020y","d":"two  spaces "}` ).
    lv_value = lo_json->get( `a` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `say "hi"\ok/` ).
    lv_value = lo_json->get( `b` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Güney İzmir` ).
    lv_value = lo_json->get( `c` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `x y` ).
    lv_value = lo_json->get( `d` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `two  spaces ` ).
    lo_json = lcl_graph_json=>parse( `{"n":"line1\nline2"}` ).
    lv_value = lo_json->get( `n` ).
    CONCATENATE `line1` cl_abap_char_utilities=>newline `line2` INTO lv_expected.
    cl_aunit_assert=>assert_equals( act = lv_value exp = lv_expected ).
  ENDMETHOD.


  METHOD values.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_value TYPE string.
    DATA lv_kind TYPE char1.
    DATA lv_exists TYPE abap_bool.

    lo_json = lcl_graph_json=>parse( `{"n":-12.5e3,"t":true,"f":false,"z":null}` ).
    lv_value = lo_json->get( `n` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `-12.5e3` ).
    lv_value = lo_json->get( `t` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `true` ).
    lv_kind = lo_json->kind_of( `f` ).
    cl_aunit_assert=>assert_equals( act = lv_kind exp = lcl_graph_json=>kind-boolean ).
    lv_value = lo_json->get( `z` ).
    cl_aunit_assert=>assert_initial( lv_value ).
    lv_exists = lo_json->exists( `z` ).
    cl_aunit_assert=>assert_equals( act = lv_exists exp = abap_true ).
    lv_exists = lo_json->exists( `nothing` ).
    cl_aunit_assert=>assert_equals( act = lv_exists exp = abap_false ).
  ENDMETHOD.


  METHOD empty_containers.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_count TYPE i.
    DATA lv_kind TYPE char1.

    lo_json = lcl_graph_json=>parse( `{"a":{},"b":[],"c":[1,[2,3]]}` ).
    lv_count = lo_json->count( `a` ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 0 ).
    lv_kind = lo_json->kind_of( `b` ).
    cl_aunit_assert=>assert_equals( act = lv_kind exp = lcl_graph_json=>kind-array ).
    lv_count = lo_json->count( `c/1` ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
  ENDMETHOD.


  METHOD invalid_json.
    DATA lv_failed TYPE abap_bool.
    TRY.
        lcl_graph_json=>parse( `{"a":1,}` ).
      CATCH lcx_graph.
        lv_failed = abap_true.
    ENDTRY.
    cl_aunit_assert=>assert_equals( act = lv_failed exp = abap_true msg = `trailing comma` ).
    CLEAR lv_failed.
    TRY.
        lcl_graph_json=>parse( `{"a":"open` ).
      CATCH lcx_graph.
        lv_failed = abap_true.
    ENDTRY.
    cl_aunit_assert=>assert_equals( act = lv_failed exp = abap_true msg = `open string` ).
    CLEAR lv_failed.
    TRY.
        lcl_graph_json=>parse( `<html>` ).
      CATCH lcx_graph.
        lv_failed = abap_true.
    ENDTRY.
    cl_aunit_assert=>assert_equals( act = lv_failed exp = abap_true msg = `HTML` ).
  ENDMETHOD.


  METHOD writer.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lv_json TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->begin_object( `message` ).
    lo_writer->add_string( iv_name = `subject` iv_value = `Fatura` ).
    lo_writer->begin_array( `toRecipients` ).
    lo_writer->begin_object( ).
    lo_writer->begin_object( `emailAddress` ).
    lo_writer->add_string( iv_name = `address` iv_value = `a@b.com` ).
    lo_writer->end_object( ).
    lo_writer->end_object( ).
    lo_writer->end_array( ).
    lo_writer->end_object( ).
    lo_writer->add_boolean( iv_name = `saveToSentItems` iv_value = abap_false ).
    lo_writer->add_number( iv_name = `n` iv_value = 42 ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    cl_aunit_assert=>assert_equals(
      act = lv_json
      exp = `{"message":{"subject":"Fatura","toRecipients":[{"emailAddress":{"address":"a@b.com"}}]},"saveToSentItems":false,"n":42}` ).
  ENDMETHOD.


  METHOD control_characters.
    " Written and read back unchanged; nothing raw below U+0020 in the JSON
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_text TYPE string.
    DATA lv_json TYPE string.
    DATA lv_value TYPE string.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_code TYPE c LENGTH 4.
    DATA lv_length TYPE i.

    lv_text = `Şirket "A" \ `.
    lv_code = '0008'.
    lv_char = cl_abap_conv_in_ce=>uccp( lv_code ).
    CONCATENATE lv_text lv_char INTO lv_text.
    lv_code = '000C'.
    lv_char = cl_abap_conv_in_ce=>uccp( lv_code ).
    CONCATENATE lv_text lv_char `x` INTO lv_text.
    lv_code = '0001'.
    lv_char = cl_abap_conv_in_ce=>uccp( lv_code ).
    CONCATENATE lv_text lv_char cl_abap_char_utilities=>horizontal_tab `ğ` INTO lv_text.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `v` iv_value = lv_text ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    cl_aunit_assert=>assert_equals( act = lv_json exp = `{"v":"Şirket \"A\" \\ \u0008\u000cx\u0001\tğ"}` ).
    lo_json = lcl_graph_json=>parse( lv_json ).
    lv_value = lo_json->get( `v` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = lv_text ).
    lo_json = lcl_graph_json=>parse( `{"v":"a\bb\fc"}` ).
    lv_value = lo_json->get( `v` ).
    lv_length = strlen( lv_value ).
    cl_aunit_assert=>assert_equals( act = lv_length exp = 5 ).
  ENDMETHOD.


  METHOD negative_number.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lv_json TYPE string.
    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_number( iv_name = `n` iv_value = -5 ).
    lo_writer->add_number( iv_name = `z` iv_value = 0 ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    cl_aunit_assert=>assert_equals( act = lv_json exp = `{"n":-5,"z":0}` ).
  ENDMETHOD.


  METHOD bytes_not_utf8.
    " "Erreur" with a Windows-1252 e acute (E9), as a proxy's error page may send it
    DATA lv_bytes TYPE xstring.
    DATA lv_text TYPE string.
    lv_bytes = '457272E975722035303220'.
    lv_text = lcl_graph_conv=>from_utf8( lv_bytes ).
    cl_aunit_assert=>assert_char_cp( act = lv_text exp = 'Err*502*' ).
  ENDMETHOD.


  METHOD backslash_after_quote.
    " The backslash of the second value must not be taken for one in the first
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_value TYPE string.
    lo_json = lcl_graph_json=>parse( `{"a":"x","b":"y\"z"}` ).
    lv_value = lo_json->get( `a` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `x` ).
    lv_value = lo_json->get( `b` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `y"z` ).
  ENDMETHOD.


  METHOD json_numbers.
    DATA lt_texts TYPE lcl_graph_json=>ty_names.
    DATA lv_text TYPE string.
    DATA lv_number TYPE abap_bool.

    SPLIT `0,-12.5,1e-3,2E+6,1234.50,-0.5` AT ',' INTO TABLE lt_texts.
    LOOP AT lt_texts INTO lv_text.
      lv_number = lcl_graph_conv=>is_json_number( lv_text ).
      cl_aunit_assert=>assert_equals( act = lv_number exp = abap_true msg = lv_text ).
    ENDLOOP.
    SPLIT `00123;+1;--1;1e;1..2;1e.2;1e2.3;1.;.5;-;1 2;1.234,50;2026-11-02;0x1` AT ';' INTO TABLE lt_texts.
    LOOP AT lt_texts INTO lv_text.
      lv_number = lcl_graph_conv=>is_json_number( lv_text ).
      cl_aunit_assert=>assert_equals( act = lv_number exp = abap_false msg = lv_text ).
    ENDLOOP.
  ENDMETHOD.


  METHOD writer_escapes.
    DATA lv_text TYPE string.
    DATA lv_json TYPE string.
    CONCATENATE `a "b" \ c` cl_abap_char_utilities=>newline `d  ` INTO lv_text.
    lv_json = lcl_graph_json_writer=>escape( lv_text ).
    cl_aunit_assert=>assert_equals( act = lv_json exp = `a \"b\" \\ c\nd  ` ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_graph_client DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_cut TYPE REF TO lcl_graph_client.

    METHODS setup.
    METHODS token_request FOR TESTING RAISING lcx_graph.
    METHODS token_cached FOR TESTING RAISING lcx_graph.
    METHODS token_error_hint FOR TESTING.
    METHODS graph_error FOR TESTING.
    METHODS retry_after_429 FOR TESTING RAISING lcx_graph.
    METHODS retry_get_after_503 FOR TESTING RAISING lcx_graph.
    METHODS no_retry_post_after_504 FOR TESTING.
    METHODS new_token_after_401 FOR TESTING RAISING lcx_graph.
    METHODS paging FOR TESTING RAISING lcx_graph.
    METHODS paging_stops_early FOR TESTING RAISING lcx_graph.
    METHODS paging_limit FOR TESTING.
    METHODS paths FOR TESTING.
    METHODS roles_in_token FOR TESTING.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.
ENDCLASS.


CLASS ltc_graph_client IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    " Every test gets its own tenant, so no token is cached from another test
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `t` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    ls_config-max_retries = 2.
    CREATE OBJECT mo_cut
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD token_request.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_value TYPE string.
    DATA lv_auth TYPE string.

    mo_http->token_answer( ).
    mo_http->answer( iv_status = 200 iv_body = `{"displayName":"Contoso"}` ).
    lo_json = mo_cut->get_json( `/organization` ).
    lv_value = lo_json->get( `displayName` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Contoso` ).

    ls_request = request_at( 1 ).
    cl_aunit_assert=>assert_equals( act = ls_request-destination exp = lif_graph=>default_login_destination ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `POST` ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/t*.onmicrosoft.com/oauth2/v2.0/token' ).
    lv_value = ls_request-body.
    TRANSLATE lv_value TO LOWER CASE.
    cl_aunit_assert=>assert_equals(
      act = lv_value
      exp = `grant_type=client_credentials&scope=https%3a%2f%2fgraph.microsoft.com%2f.default` ).

    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-destination exp = lif_graph=>default_api_destination ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/organization` ).
    lv_auth = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Authorization` ).
    cl_aunit_assert=>assert_equals( act = lv_auth exp = `Bearer TOKEN1` ).
  ENDMETHOD.


  METHOD token_cached.
    DATA lv_count TYPE i.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_cut->get_json( `/organization` ).
    mo_cut->get_json( `/organization` ).
    " One token request, two Graph calls
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
  ENDMETHOD.


  METHOD token_error_hint.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_hint TYPE string.
    mo_http->answer( iv_status = 401
                     iv_body = `{"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided."}` ).
    TRY.
        mo_cut->get_json( `/organization` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_equals( act = lx_graph->error_code exp = `invalid_client` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->hint exp = '*client secret is wrong*' ).
    " The answer A4H really got from Microsoft for a made-up client ID
    lv_hint = lcl_graph_token=>hint_for(
      `AADSTS700038: 00000000-0000-0000-0000-000000000000 is not a valid application identifier.` ).
    cl_aunit_assert=>assert_char_cp( act = lv_hint exp = '*Application (client) ID*' ).
  ENDMETHOD.


  METHOD graph_error.
    DATA lx_graph TYPE REF TO lcx_graph.
    mo_http->token_answer( ).
    mo_http->answer(
      iv_status = 403
      iv_body = `{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges.","innerError":{"request-id":"r-1"}}}` ).
    TRY.
        mo_cut->get_json( `/users` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_equals( act = lx_graph->http_status exp = 403 ).
    cl_aunit_assert=>assert_equals( act = lx_graph->error_code exp = `Authorization_RequestDenied` ).
    cl_aunit_assert=>assert_equals( act = lx_graph->request_id exp = `r-1` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->hint exp = '*permission*' ).
  ENDMETHOD.


  METHOD retry_after_429.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 429 iv_body = `{"error":{"code":"TooManyRequests"}}` iv_retry_after = `0` ).
    mo_http->answer( iv_status = 200 iv_body = `{"ok":true}` ).
    lo_json = mo_cut->get_json( `/users` ).
    lv_value = lo_json->get( `ok` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `true` ).
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
  ENDMETHOD.


  METHOD retry_get_after_503.
    DATA lv_count TYPE i.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 503 iv_retry_after = `0` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_cut->get_json( `/users` ).
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
  ENDMETHOD.


  METHOD no_retry_post_after_504.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_count TYPE i.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 504 iv_retry_after = `0` ).
    mo_http->answer( iv_status = 202 ).
    TRY.
        mo_cut->send_json( iv_method = 'POST' iv_path = `/users/sap@contoso.com/sendMail` iv_json = `{}` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_equals( act = lx_graph->http_status exp = 504 ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->hint exp = '*outcome is unknown*' ).
    " The token request and one POST; the mail was not sent a second time
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
  ENDMETHOD.


  METHOD new_token_after_401.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_auth TYPE string.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 401 iv_body = `{"error":{"code":"InvalidAuthenticationToken"}}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"access_token":"TOKEN2","expires_in":3599}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_cut->get_json( `/users` ).
    ls_request = request_at( 4 ).
    lv_auth = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `authorization` ).
    cl_aunit_assert=>assert_equals( act = lv_auth exp = `Bearer TOKEN2` ).
  ENDMETHOD.


  METHOD paging_stops_early.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lv_count TYPE i.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 200
                     iv_body = `{"value":[{"id":"1"},{"id":"2"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?$skiptoken=X1"}` ).
    lt_pages = mo_cut->get_pages( iv_path = `/users` iv_max_items = 2 ).
    lv_count = lines( lt_pages ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    " The token and one page; the second page was not asked for
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
  ENDMETHOD.


  METHOD paging_limit.
    DATA lx_graph TYPE REF TO lcx_graph.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 200
                     iv_body = `{"value":[{"id":"1"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?$skiptoken=X1"}` ).
    TRY.
        mo_cut->get_pages( iv_path = `/users` iv_max_pages = 1 ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `a cut result was returned as complete` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*more than 1 pages*not be complete*' ).
  ENDMETHOD.


  METHOD paging.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lv_count TYPE i.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    mo_http->token_answer( ).
    mo_http->answer( iv_status = 200
                     iv_body = `{"value":[{"id":"1"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?$skiptoken=X1"}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"2"}]}` ).
    lt_pages = mo_cut->get_pages( `/users` ).
    lv_count = lines( lt_pages ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users?$skiptoken=X1` ).
  ENDMETHOD.


  METHOD paths.
    DATA lv_path TYPE string.
    lv_path = lcl_graph_client=>path_of_url( `https://graph.microsoft.com/beta/me?$top=1` ).
    cl_aunit_assert=>assert_equals( act = lv_path exp = `/beta/me?$top=1` ).
    " Two blanks inside a name are another file than one blank
    lv_path = lcl_graph_conv=>clean_path( ` \Raporlar\a  b.pdf ` ).
    cl_aunit_assert=>assert_equals( act = lv_path exp = `Raporlar/a  b.pdf` ).
  ENDMETHOD.


  METHOD roles_in_token.
    DATA lt_roles TYPE lcl_graph_json=>ty_names.
    DATA lv_roles TYPE string.
    DATA lv_payload TYPE string.
    DATA lv_bytes TYPE xstring.
    DATA lv_token TYPE string.

    lv_bytes = lcl_graph_conv=>to_utf8( `{"aud":"https://graph.microsoft.com","roles":["Mail.Send","Sites.Selected"]}` ).
    lv_payload = lcl_graph_conv=>to_base64( lv_bytes ).
    " Tokens use Base64url without padding
    TRANSLATE lv_payload USING '+-/_= '.
    CONDENSE lv_payload NO-GAPS.
    CONCATENATE `eyJhbGciOiJub25lIn0.` lv_payload `.signature` INTO lv_token.
    lt_roles = lcl_graph_token=>roles_of( lv_token ).
    CONCATENATE LINES OF lt_roles INTO lv_roles SEPARATED BY ','.
    cl_aunit_assert=>assert_equals( act = lv_roles exp = `Mail.Send,Sites.Selected` ).
  ENDMETHOD.

ENDCLASS.
