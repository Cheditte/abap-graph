*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_TEAMS: a message to a Microsoft Teams channel
*& abap-graph 0.8.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE and ZCHE_GRAPH_TEAMS_LIB first,
*& then SE38, create executable program ZCHE_GRAPH_TEAMS, paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Sends one message (a card) to the channel behind the Workflows webhook
*& of an SM59 destination; see ZCHE_GRAPH_TEAMS_LIB for the setup.
*& As a step of a background job it reports, for example, that the
*& steps before it have run. Your own programs call LCL_GRAPH_TEAMS
*& directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_teams LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_teams_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_conn WITH FRAME TITLE t_conn.
PARAMETERS p_dest TYPE rfcdest OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_conn.

SELECTION-SCREEN BEGIN OF BLOCK b_msg WITH FRAME TITLE t_msg.
PARAMETERS p_title TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_text TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_level TYPE c LENGTH 10 LOWER CASE DEFAULT 'info'.
PARAMETERS p_facts1 TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_facts2 TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_url TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_ltitle TYPE c LENGTH 60 LOWER CASE.
PARAMETERS p_sys AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_msg.


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

    t_conn = get( iv_en = 'Channel' iv_tr = 'Kanal' ).
    t_msg = get( iv_en = 'Message' iv_tr = 'Mesaj' ).
    add( EXPORTING iv_name = 'P_DEST' iv_en = 'SM59: Teams webhook' iv_tr = 'SM59: Teams web kancası' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TITLE' iv_en = 'Title' iv_tr = 'Başlık' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TEXT' iv_en = 'Text' iv_tr = 'Metin' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LEVEL' iv_en = 'Level: info/good/warning/error' iv_tr = 'Düzey: info/good/warning/error' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FACTS1' iv_en = 'Lines: Name=Value | ...' iv_tr = 'Satırlar: Ad=Değer | ...' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FACTS2' iv_en = 'Lines (more)' iv_tr = 'Satırlar (devamı)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_URL' iv_en = 'Button: link' iv_tr = 'Buton: bağlantı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LTITLE' iv_en = 'Button: text' iv_tr = 'Buton: yazı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SYS' iv_en = 'Add system, user and time' iv_tr = 'Sistem, kullanıcı, saat ekle' CHANGING ct_texts = lt_texts ).

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
* The action, written as a list (also works as a background job)
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run
      RAISING
        lcx_graph.

    CLASS-METHODS error
      IMPORTING
        ix_graph TYPE REF TO lcx_graph.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD error.
    DATA lv_text TYPE string.
    DATA lv_line TYPE string.
    lv_text = ix_graph->get_text( ).
    CONCATENATE `ERROR ` lv_text INTO lv_text.
    WRITE: / lv_text.
    IF ix_graph->hint IS NOT INITIAL.
      CONCATENATE `      ` ix_graph->hint INTO lv_line.
      WRITE: / lv_line.
    ENDIF.
    " In the background an E message ends the job as "Cancelled"; it carries
    " the error itself, not the hint or request-id lines
    IF sy-batch = abap_true.
      MESSAGE lv_text TYPE 'E'.
    ENDIF.
  ENDMETHOD.


  METHOD run.
    DATA lo_teams TYPE REF TO lcl_graph_teams.
    DATA ls_card TYPE lif_graph_teams=>ty_card.
    DATA ls_fact TYPE lif_graph_teams=>ty_fact.
    DATA lv_facts TYPE string.
    DATA lv_text TYPE string.
    DATA lv_date TYPE c LENGTH 10.
    DATA lv_time TYPE c LENGTH 8.

    ls_card-title = p_title.
    ls_card-text = p_text.
    ls_card-level = p_level.
    CONCATENATE p_facts1 '|' p_facts2 INTO lv_facts.
    ls_card-facts = lcl_graph_teams=>facts_from_text( lv_facts ).
    IF p_sys = abap_true.
      ls_fact-name = lcl_text=>get( iv_en = `System` iv_tr = `Sistem` ).
      CONCATENATE sy-sysid `/` sy-mandt INTO ls_fact-value.
      APPEND ls_fact TO ls_card-facts.
      ls_fact-name = lcl_text=>get( iv_en = `User` iv_tr = `Kullanıcı` ).
      ls_fact-value = sy-uname.
      APPEND ls_fact TO ls_card-facts.
      ls_fact-name = lcl_text=>get( iv_en = `Time` iv_tr = `Zaman` ).
      " The user's own date and time, which belong to SY-ZONLO; SY-DATUM and
      " SY-UZEIT are the server's and may be in another zone
      CONCATENATE sy-datlo(4) `-` sy-datlo+4(2) `-` sy-datlo+6(2) INTO lv_date.
      CONCATENATE sy-timlo(2) `:` sy-timlo+2(2) `:` sy-timlo+4(2) INTO lv_time.
      CONCATENATE lv_date lv_time sy-zonlo INTO ls_fact-value SEPARATED BY space.
      APPEND ls_fact TO ls_card-facts.
    ENDIF.
    ls_card-link_url = p_url.
    ls_card-link_title = p_ltitle.

    CREATE OBJECT lo_teams
      EXPORTING
        iv_destination = p_dest.
    lo_teams->send( ls_card ).
    lv_text = lcl_text=>get( iv_en = `OK Sent to the channel of SM59 destination ` iv_tr = `OK Şu SM59 hedefinin kanalına gönderildi: ` ).
    CONCATENATE lv_text p_dest INTO lv_text.
    WRITE: / lv_text.
  ENDMETHOD.

ENDCLASS.


DATA gx_graph TYPE REF TO lcx_graph.

INITIALIZATION.
  lcl_text=>set_selection_texts( ).

START-OF-SELECTION.
  TRY.
      lcl_app=>run( ).
    CATCH lcx_graph INTO gx_graph.
      lcl_app=>error( gx_graph ).
  ENDTRY.
