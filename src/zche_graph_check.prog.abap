*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_CHECK: test the connection from SAP to Microsoft Graph
*& abap-graph 0.7.1, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: first the include ZCHE_GRAPH_CORE, then SE38, create
*& executable program ZCHE_GRAPH_CHECK, paste this source, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Checks step by step and says what is missing:
*&   1. the two SM59 destinations exist
*&   2. Microsoft gives the application a token (client ID and secret
*&      in SM59 are right), and which permissions the token carries
*&   3. one Graph call works (default: /organization)
*& It only reads; nothing is changed in SAP or in Microsoft 365.
*&---------------------------------------------------------------------*
REPORT zche_graph_check LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.

SELECTION-SCREEN BEGIN OF BLOCK b_main WITH FRAME TITLE t_main.
SELECTION-SCREEN COMMENT /1(75) t_hint.
PARAMETERS p_tenant TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
PARAMETERS p_login TYPE rfcdest DEFAULT 'ZCHE_GRAPH_LOGIN'.
PARAMETERS p_api TYPE rfcdest DEFAULT 'ZCHE_GRAPH_API'.
PARAMETERS p_path TYPE c LENGTH 200 LOWER CASE DEFAULT '/organization'.
SELECTION-SCREEN END OF BLOCK b_main.


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

    t_main = get( iv_en = 'Microsoft Graph connection' iv_tr = 'Microsoft Graph bağlantısı' ).
    t_hint = get( iv_en = 'Reads only. Tenant: directory (tenant) ID or domain, e.g. contoso.onmicrosoft.com'
                  iv_tr = 'Yalnızca okur. Tenant: dizin (tenant) ID ya da alan adı, örn. contoso.onmicrosoft.com' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı'
         CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi'
         CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph'
         CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_PATH' iv_en = 'Graph call to test' iv_tr = 'Denenecek Graph çağrısı'
         CHANGING ct_texts = lt_texts ).

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
* The checks, written as a list (also works as a background job)
*----------------------------------------------------------------------*
CLASS lcl_check DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run
      IMPORTING
        is_config TYPE lif_graph=>ty_config
        iv_path   TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS line
      IMPORTING
        iv_status TYPE csequence
        iv_text   TYPE csequence.

    CLASS-METHODS error
      IMPORTING
        ix_graph TYPE REF TO lcx_graph.

    "! Step 1: returns abap_false when the destination is missing or of the wrong type
    CLASS-METHODS destination_ok
      IMPORTING
        iv_destination TYPE rfcdest
        iv_host        TYPE string
      RETURNING
        value(rv_ok)   TYPE abap_bool.
ENDCLASS.


CLASS lcl_check IMPLEMENTATION.

  METHOD line.
    " Status and text in one string, so a long text does not push the status onto its own line
    DATA lv_line TYPE string.
    DATA lv_text TYPE string.
    lv_text = iv_text.
    IF iv_status IS INITIAL.
      CONCATENATE `       ` lv_text INTO lv_line.
    ELSE.
      CONCATENATE iv_status lv_text INTO lv_line SEPARATED BY space.
    ENDIF.
    WRITE: / lv_line.
  ENDMETHOD.


  METHOD error.
    DATA lv_text TYPE string.
    lv_text = ix_graph->get_text( ).
    line( iv_status = 'ERROR' iv_text = lv_text ).
    IF ix_graph->hint IS NOT INITIAL.
      line( iv_status = '' iv_text = ix_graph->hint ).
    ENDIF.
    IF ix_graph->request_id IS NOT INITIAL.
      CONCATENATE `request-id: ` ix_graph->request_id INTO lv_text.
      line( iv_status = '' iv_text = lv_text ).
    ENDIF.
  ENDMETHOD.


  METHOD destination_ok.
    DATA lv_type TYPE rfcdes-rfctype.
    DATA lv_text TYPE string.
    DATA lv_en TYPE string.
    DATA lv_tr TYPE string.

    SELECT SINGLE rfctype FROM rfcdes INTO lv_type WHERE rfcdest = iv_destination.
    IF sy-subrc <> 0.
      CONCATENATE `SM59 destination ` iv_destination ` does not exist. Create it as type G (HTTP connection to external server), host `
                  iv_host `, port 443, SSL active.` INTO lv_en.
      CONCATENATE `SM59 hedefi ` iv_destination ` yok. G tipinde (dış sunucuya HTTP bağlantısı) oluşturun: host `
                  iv_host `, port 443, SSL etkin.` INTO lv_tr.
      lv_text = lcl_text=>get( iv_en = lv_en iv_tr = lv_tr ).
      line( iv_status = 'ERROR' iv_text = lv_text ).
      rv_ok = abap_false.
      RETURN.
    ENDIF.
    IF lv_type <> 'G'.
      CONCATENATE `SM59 destination ` iv_destination ` has type ` lv_type `; it must be type G.` INTO lv_en.
      CONCATENATE `SM59 hedefi ` iv_destination ` ` lv_type ` tipinde; G tipinde olmalı.` INTO lv_tr.
      lv_text = lcl_text=>get( iv_en = lv_en iv_tr = lv_tr ).
      line( iv_status = 'ERROR' iv_text = lv_text ).
      rv_ok = abap_false.
      RETURN.
    ENDIF.
    CONCATENATE `SM59 destination ` iv_destination ` exists (type G).` INTO lv_en.
    CONCATENATE `SM59 hedefi ` iv_destination ` var (G tipi).` INTO lv_tr.
    lv_text = lcl_text=>get( iv_en = lv_en iv_tr = lv_tr ).
    line( iv_status = 'OK' iv_text = lv_text ).
    rv_ok = abap_true.
  ENDMETHOD.


  METHOD run.
    DATA lo_http TYPE REF TO lcl_graph_http.
    DATA lo_token TYPE REF TO lcl_graph_token.
    DATA lo_client TYPE REF TO lcl_graph_client.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_token TYPE string.
    DATA lt_roles TYPE lcl_graph_json=>ty_names.
    DATA lv_roles TYPE string.
    DATA lv_text TYPE string.
    DATA lv_en TYPE string.
    DATA lv_tr TYPE string.
    DATA lv_ok TYPE abap_bool.
    DATA lv_login_ok TYPE abap_bool.
    DATA lv_api_ok TYPE abap_bool.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA lv_names TYPE string.
    DATA lv_value TYPE string.
    DATA lv_version TYPE string.

    lv_version = lif_graph=>version.
    CONCATENATE `abap-graph ` lv_version INTO lv_text.
    WRITE: / lv_text.
    ULINE.

    " 1. SM59
    lv_text = lcl_text=>get( iv_en = '1. SM59 destinations' iv_tr = '1. SM59 hedefleri' ).
    WRITE: / lv_text COLOR COL_HEADING.
    lv_login_ok = destination_ok( iv_destination = is_config-login_destination iv_host = `login.microsoftonline.com` ).
    lv_api_ok = destination_ok( iv_destination = is_config-api_destination iv_host = `graph.microsoft.com` ).
    IF lv_login_ok = abap_false.
      RETURN.
    ENDIF.

    " 2. Token
    SKIP.
    lv_text = lcl_text=>get( iv_en = '2. Sign-in of the application (token)' iv_tr = '2. Uygulamanın girişi (token)' ).
    WRITE: / lv_text COLOR COL_HEADING.
    CREATE OBJECT lo_http.
    CREATE OBJECT lo_token
      EXPORTING
        is_config = is_config
        io_http   = lo_http.
    TRY.
        lv_token = lo_token->get( ).
      CATCH lcx_graph INTO lx_graph.
        error( lx_graph ).
        RETURN.
    ENDTRY.
    lv_text = lcl_text=>get( iv_en = 'Microsoft gave the application a token: client ID, secret and tenant are right.'
                             iv_tr = 'Microsoft uygulamaya token verdi: client ID, secret ve tenant doğru.' ).
    line( iv_status = 'OK' iv_text = lv_text ).
    lt_roles = lcl_graph_token=>roles_of( lv_token ).
    IF lt_roles IS INITIAL.
      lv_text = lcl_text=>get(
        iv_en = 'The token carries no application permissions yet: add them to the app registration and grant admin consent.'
        iv_tr = 'Token henüz hiçbir uygulama izni taşımıyor: uygulama kaydına izinleri ekleyip yönetici onayı verin.' ).
      line( iv_status = 'NOTE' iv_text = lv_text ).
    ELSE.
      CONCATENATE LINES OF lt_roles INTO lv_roles SEPARATED BY `, `.
      " A char literal loses its trailing blank, so the blank comes from SEPARATED BY
      lv_text = lcl_text=>get( iv_en = 'Permissions in the token:' iv_tr = 'Token''daki izinler:' ).
      CONCATENATE lv_text lv_roles INTO lv_text SEPARATED BY space.
      line( iv_status = 'OK' iv_text = lv_text ).
    ENDIF.

    " 3. Graph call
    SKIP.
    lv_text = lcl_text=>get( iv_en = '3. A Microsoft Graph call' iv_tr = '3. Bir Microsoft Graph çağrısı' ).
    CONCATENATE lv_text `: GET ` iv_path INTO lv_text.
    WRITE: / lv_text COLOR COL_HEADING.
    IF lv_api_ok = abap_false.
      RETURN.
    ENDIF.
    CREATE OBJECT lo_client
      EXPORTING
        is_config = is_config.
    TRY.
        lo_json = lo_client->get_json( iv_path ).
        lv_ok = abap_true.
      CATCH lcx_graph INTO lx_graph.
        error( lx_graph ).
        IF lx_graph->http_status = 403.
          lv_text = lcl_text=>get(
            iv_en = 'Connection and sign-in work; only the permission for this call is missing.'
            iv_tr = 'Bağlantı ve giriş çalışıyor; yalnızca bu çağrı için izin eksik.' ).
          line( iv_status = 'NOTE' iv_text = lv_text ).
        ENDIF.
    ENDTRY.
    IF lv_ok = abap_false.
      RETURN.
    ENDIF.
    lv_text = lcl_text=>get( iv_en = 'Microsoft Graph answered.' iv_tr = 'Microsoft Graph cevap verdi.' ).
    line( iv_status = 'OK' iv_text = lv_text ).
    " Show the first values, for example the organization's name
    lv_value = lo_json->get( `value/0/displayName` ).
    IF lv_value IS INITIAL.
      lv_value = lo_json->get( `displayName` ).
    ENDIF.
    IF lv_value IS NOT INITIAL.
      CONCATENATE `displayName: ` lv_value INTO lv_text.
      line( iv_status = '' iv_text = lv_text ).
    ENDIF.
    lt_names = lo_json->names( `` ).
    CONCATENATE LINES OF lt_names INTO lv_names SEPARATED BY `, `.
    lv_en = 'Fields in the answer:'.
    lv_tr = 'Cevaptaki alanlar:'.
    lv_text = lcl_text=>get( iv_en = lv_en iv_tr = lv_tr ).
    CONCATENATE lv_text lv_names INTO lv_text SEPARATED BY space.
    line( iv_status = '' iv_text = lv_text ).
  ENDMETHOD.

ENDCLASS.


DATA gs_config TYPE lif_graph=>ty_config.
DATA gv_path TYPE string.
DATA gv_tenant TYPE string.

INITIALIZATION.
  lcl_text=>set_selection_texts( ).

START-OF-SELECTION.
  gv_tenant = p_tenant.
  CONDENSE gv_tenant.
  gs_config = lcl_graph_client=>default_config( gv_tenant ).
  gs_config-login_destination = p_login.
  gs_config-api_destination = p_api.
  gv_path = p_path.
  gv_path = lcl_graph_conv=>trim( gv_path ).
  lcl_check=>run( is_config = gs_config iv_path = gv_path ).
