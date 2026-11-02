*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_LISTS: SharePoint lists through Microsoft Graph
*& abap-graph 0.5.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE and ZCHE_GRAPH_LISTS_LIB first,
*& then SE38, create executable program ZCHE_GRAPH_LISTS, paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& What you can do from the screen (also as a background job):
*&   - show the lists of a site, or the columns of a list
*&   - read items (chosen columns, a filter)
*&   - create or change an item, or update-or-create by a key column
*& Fields are written as  Name=Value | Name2=Value2 , with the columns'
*& internal names (see "Show columns").
*& Your own programs call LCL_GRAPH_LIST directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_lists LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_lists_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_conn WITH FRAME TITLE t_conn.
PARAMETERS p_tenant TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
PARAMETERS p_login TYPE rfcdest DEFAULT 'ZCHE_GRAPH_LOGIN'.
PARAMETERS p_api TYPE rfcdest DEFAULT 'ZCHE_GRAPH_API'.
SELECTION-SCREEN END OF BLOCK b_conn.

SELECTION-SCREEN BEGIN OF BLOCK b_list WITH FRAME TITLE t_list.
PARAMETERS p_host TYPE c LENGTH 120 LOWER CASE OBLIGATORY.
PARAMETERS p_site TYPE c LENGTH 200 LOWER CASE.
PARAMETERS p_list TYPE c LENGTH 120 LOWER CASE.
SELECTION-SCREEN END OF BLOCK b_list.

SELECTION-SCREEN BEGIN OF BLOCK b_do WITH FRAME TITLE t_do.
PARAMETERS r_lists RADIOBUTTON GROUP do DEFAULT 'X'.
PARAMETERS r_cols RADIOBUTTON GROUP do.
PARAMETERS r_read RADIOBUTTON GROUP do.
PARAMETERS r_write RADIOBUTTON GROUP do.
PARAMETERS r_upsert RADIOBUTTON GROUP do.
SELECTION-SCREEN END OF BLOCK b_do.

SELECTION-SCREEN BEGIN OF BLOCK b_what WITH FRAME TITLE t_what.
PARAMETERS p_select TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_filter TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_max TYPE i DEFAULT 100.
PARAMETERS p_id TYPE c LENGTH 20 LOWER CASE.
PARAMETERS p_key TYPE c LENGTH 60 LOWER CASE.
PARAMETERS p_flds1 TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_flds2 TYPE c LENGTH 255 LOWER CASE.
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

    t_conn = get( iv_en = 'Connection' iv_tr = 'Bağlantı' ).
    t_list = get( iv_en = 'Site and list' iv_tr = 'Site ve liste' ).
    t_do = get( iv_en = 'What to do' iv_tr = 'Ne yapılacak' ).
    t_what = get( iv_en = 'Details' iv_tr = 'Ayrıntılar' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_HOST' iv_en = 'Host (x.sharepoint.com)' iv_tr = 'Host (x.sharepoint.com)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SITE' iv_en = 'Site path (/sites/...)' iv_tr = 'Site yolu (/sites/...)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LIST' iv_en = 'List name' iv_tr = 'Liste adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_LISTS' iv_en = 'Show the lists of the site' iv_tr = 'Sitenin listelerini göster' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_COLS' iv_en = 'Show the columns' iv_tr = 'Sütunları göster' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_READ' iv_en = 'Read items' iv_tr = 'Kayıtları oku' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_WRITE' iv_en = 'Create or change an item' iv_tr = 'Kayıt oluştur ya da değiştir' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_UPSERT' iv_en = 'Update or create by key' iv_tr = 'Anahtara göre güncelle/oluştur' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SELECT' iv_en = 'Columns (a,b,c; empty = all)' iv_tr = 'Sütunlar (a,b,c; boş = tümü)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FILTER' iv_en = 'Filter (fields/X eq ''Y'')' iv_tr = 'Filtre (fields/X eq ''Y'')' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_MAX' iv_en = 'At most (items)' iv_tr = 'En çok (kayıt)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_ID' iv_en = 'Item ID (empty = new)' iv_tr = 'Kayıt ID (boş = yeni)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_KEY' iv_en = 'Key column' iv_tr = 'Anahtar sütun' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FLDS1' iv_en = 'Fields: Name=Value | ...' iv_tr = 'Alanlar: Ad=Değer | ...' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FLDS2' iv_en = 'Fields (more)' iv_tr = 'Alanlar (devamı)' CHANGING ct_texts = lt_texts ).

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
    CLASS-METHODS show_item
      IMPORTING
        is_item TYPE lif_graph_lists=>ty_item.
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


  METHOD show_item.
    DATA ls_field TYPE lif_graph_lists=>ty_field.
    DATA lv_text TYPE string.
    DATA lv_pair TYPE string.

    CONCATENATE `#` is_item-id INTO lv_text.
    LOOP AT is_item-fields INTO ls_field.
      CONCATENATE ls_field-name `=` ls_field-value INTO lv_pair.
      CONCATENATE lv_text lv_pair INTO lv_text SEPARATED BY ` | `.
    ENDLOOP.
    WRITE: / lv_text.
  ENDMETHOD.


  METHOD run.
    DATA lo_list TYPE REF TO lcl_graph_list.
    DATA lt_lists TYPE lif_graph_lists=>ty_lists.
    DATA ls_list TYPE lif_graph_lists=>ty_list.
    DATA lt_columns TYPE lif_graph_lists=>ty_columns.
    DATA ls_column TYPE lif_graph_lists=>ty_column.
    DATA lt_items TYPE lif_graph_lists=>ty_items.
    DATA ls_item TYPE lif_graph_lists=>ty_item.
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA lt_select TYPE lcl_graph_json=>ty_names.
    DATA lv_host TYPE string.
    DATA lv_site TYPE string.
    DATA lv_list TYPE string.
    DATA lv_site_id TYPE string.
    DATA lv_text TYPE string.
    DATA lv_flags TYPE string.
    DATA lv_select TYPE string.
    DATA lv_filter TYPE string.
    DATA lv_fields TYPE string.
    DATA lv_id TYPE string.
    DATA lv_key TYPE string.
    DATA lv_created TYPE abap_bool.
    DATA lv_lines TYPE i.
    DATA lv_number TYPE string.

    lv_host = p_host.
    CONDENSE lv_host.
    lv_site = p_site.
    CONDENSE lv_site.
    lv_list = p_list.
    CONDENSE lv_list.

    IF r_lists = abap_true.
      lv_site_id = lcl_graph_site=>id( io_client = io_client iv_host = lv_host iv_site = lv_site ).
      lt_lists = lcl_graph_list=>lists( io_client = io_client iv_site_id = lv_site_id ).
      LOOP AT lt_lists INTO ls_list.
        CONCATENATE ls_list-display_name ls_list-name ls_list-web_url INTO lv_text SEPARATED BY ` | `.
        WRITE: / lv_text.
      ENDLOOP.
      RETURN.
    ENDIF.

    lo_list = lcl_graph_list=>for_site( io_client = io_client iv_host = lv_host iv_site = lv_site iv_list = lv_list ).

    IF r_cols = abap_true.
      lt_columns = lo_list->columns( ).
      lv_text = lcl_text=>get( iv_en = `Internal name | name shown | type | flags`
                               iv_tr = `İç ad | görünen ad | tür | işaretler` ).
      WRITE: / lv_text COLOR COL_HEADING.
      ULINE.
      LOOP AT lt_columns INTO ls_column WHERE hidden = abap_false.
        CLEAR lv_flags.
        IF ls_column-required = abap_true.
          CONCATENATE lv_flags `required` INTO lv_flags SEPARATED BY space.
        ENDIF.
        IF ls_column-read_only = abap_true.
          CONCATENATE lv_flags `read-only` INTO lv_flags SEPARATED BY space.
        ENDIF.
        IF ls_column-multiple = abap_true.
          CONCATENATE lv_flags `multiple` INTO lv_flags SEPARATED BY space.
        ENDIF.
        CONCATENATE ls_column-name ls_column-display_name ls_column-type lv_flags INTO lv_text SEPARATED BY ` | `.
        WRITE: / lv_text.
      ENDLOOP.

    ELSEIF r_read = abap_true.
      lv_select = p_select.
      CONDENSE lv_select NO-GAPS.
      IF lv_select IS NOT INITIAL.
        SPLIT lv_select AT ',' INTO TABLE lt_select.
      ENDIF.
      lv_filter = p_filter.
      CONDENSE lv_filter.
      lt_items = lo_list->items( it_select = lt_select iv_filter = lv_filter iv_max = p_max ).
      lv_lines = lines( lt_items ).
      lv_number = lcl_graph_conv=>num( lv_lines ).
      lv_text = lcl_text=>get( iv_en = `Items: ` iv_tr = `Kayıtlar: ` ).
      CONCATENATE lv_text lv_number INTO lv_text.
      WRITE: / lv_text COLOR COL_HEADING.
      ULINE.
      LOOP AT lt_items INTO ls_item.
        show_item( ls_item ).
      ENDLOOP.

    ELSE.
      CONCATENATE p_flds1 '|' p_flds2 INTO lv_fields.
      lt_fields = lcl_graph_list=>fields_from_text( lv_fields ).
      IF r_write = abap_true.
        lv_id = p_id.
        CONDENSE lv_id.
        IF lv_id IS INITIAL.
          ls_item = lo_list->create( lt_fields ).
          lv_text = lcl_text=>get( iv_en = `Created item #` iv_tr = `Oluşturulan kayıt #` ).
          CONCATENATE `OK ` lv_text ls_item-id INTO lv_text.
        ELSE.
          lo_list->update( iv_id = lv_id it_fields = lt_fields ).
          lv_text = lcl_text=>get( iv_en = `Changed item #` iv_tr = `Değiştirilen kayıt #` ).
          CONCATENATE `OK ` lv_text lv_id INTO lv_text.
        ENDIF.
      ELSE.
        lv_key = p_key.
        CONDENSE lv_key.
        lo_list->upsert( EXPORTING iv_key = lv_key it_fields = lt_fields IMPORTING ev_id = lv_id ev_created = lv_created ).
        IF lv_created = abap_true.
          lv_text = lcl_text=>get( iv_en = `Created item #` iv_tr = `Oluşturulan kayıt #` ).
        ELSE.
          lv_text = lcl_text=>get( iv_en = `Updated item #` iv_tr = `Güncellenen kayıt #` ).
        ENDIF.
        CONCATENATE `OK ` lv_text lv_id INTO lv_text.
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
