*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_EXCEL: Excel workbooks in SharePoint or OneDrive through
*& Microsoft Graph
*& abap-graph 0.7.1, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE, ZCHE_GRAPH_FILES_LIB and
*& ZCHE_GRAPH_EXCEL_LIB first, then SE38, create executable program
*& ZCHE_GRAPH_EXCEL, paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& What you can do from the screen (also as a background job):
*&   - show the worksheets and tables of a workbook
*&   - read a range, or everything that is filled on a sheet
*&   - write values from a cell on
*&   - read a table, or add rows to it
*& Values are written as  a;b;c | d;e;f : cells separated by ; rows by |
*& Your own programs call LCL_GRAPH_EXCEL directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_excel LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_files_lib.
INCLUDE zche_graph_excel_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_conn WITH FRAME TITLE t_conn.
PARAMETERS p_tenant TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
PARAMETERS p_login TYPE rfcdest DEFAULT 'ZCHE_GRAPH_LOGIN'.
PARAMETERS p_api TYPE rfcdest DEFAULT 'ZCHE_GRAPH_API'.
SELECTION-SCREEN END OF BLOCK b_conn.

SELECTION-SCREEN BEGIN OF BLOCK b_lib WITH FRAME TITLE t_lib.
PARAMETERS r_site RADIOBUTTON GROUP lib DEFAULT 'X'.
PARAMETERS p_host TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_site TYPE c LENGTH 200 LOWER CASE.
PARAMETERS p_lib TYPE c LENGTH 120 LOWER CASE.
PARAMETERS r_user RADIOBUTTON GROUP lib.
PARAMETERS p_user TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_path TYPE c LENGTH 255 LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_do WITH FRAME TITLE t_do.
PARAMETERS r_info RADIOBUTTON GROUP do DEFAULT 'X'.
PARAMETERS r_read RADIOBUTTON GROUP do.
PARAMETERS r_write RADIOBUTTON GROUP do.
PARAMETERS r_table RADIOBUTTON GROUP do.
PARAMETERS r_addrow RADIOBUTTON GROUP do.
SELECTION-SCREEN END OF BLOCK b_do.

SELECTION-SCREEN BEGIN OF BLOCK b_what WITH FRAME TITLE t_what.
PARAMETERS p_sheet TYPE c LENGTH 31 LOWER CASE.
PARAMETERS p_addr TYPE c LENGTH 40 LOWER CASE.
PARAMETERS p_text AS CHECKBOX.
PARAMETERS p_table TYPE c LENGTH 60 LOWER CASE.
PARAMETERS p_vals1 TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_vals2 TYPE c LENGTH 255 LOWER CASE.
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
    t_lib = get( iv_en = 'Workbook' iv_tr = 'Çalışma kitabı' ).
    t_do = get( iv_en = 'What to do' iv_tr = 'Ne yapılacak' ).
    t_what = get( iv_en = 'Details' iv_tr = 'Ayrıntılar' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_SITE' iv_en = 'SharePoint site' iv_tr = 'SharePoint sitesi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_HOST' iv_en = 'Host (x.sharepoint.com)' iv_tr = 'Host (x.sharepoint.com)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SITE' iv_en = 'Site path (/sites/...)' iv_tr = 'Site yolu (/sites/...)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LIB' iv_en = 'Library (empty = default)' iv_tr = 'Kitaplık (boş = varsayılan)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_USER' iv_en = 'OneDrive of a user' iv_tr = 'Bir kullanıcının OneDrive''ı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_USER' iv_en = 'User (name@company.com)' iv_tr = 'Kullanıcı (ad@sirket.com)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_PATH' iv_en = 'Workbook path (.xlsx)' iv_tr = 'Kitap yolu (.xlsx)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_INFO' iv_en = 'Show sheets and tables' iv_tr = 'Sayfaları ve tabloları göster' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_READ' iv_en = 'Read a range' iv_tr = 'Aralık oku' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_WRITE' iv_en = 'Write values' iv_tr = 'Değer yaz' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_TABLE' iv_en = 'Read a table' iv_tr = 'Tablo oku' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_ADDROW' iv_en = 'Add rows to a table' iv_tr = 'Tabloya satır ekle' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SHEET' iv_en = 'Worksheet' iv_tr = 'Çalışma sayfası' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_ADDR' iv_en = 'Range / start cell (A1)' iv_tr = 'Aralık / başlangıç (A1)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TEXT' iv_en = 'As Excel shows it' iv_tr = 'Excel''in gösterdiği gibi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TABLE' iv_en = 'Table' iv_tr = 'Tablo' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_VALS1' iv_en = 'Values: a;b | c;d' iv_tr = 'Değerler: a;b | c;d' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_VALS2' iv_en = 'Values (more)' iv_tr = 'Değerler (devamı)' CHANGING ct_texts = lt_texts ).

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
        io_excel TYPE REF TO lcl_graph_excel
      RAISING
        lcx_graph.

    CLASS-METHODS error
      IMPORTING
        ix_graph TYPE REF TO lcx_graph.

  PRIVATE SECTION.
    CLASS-METHODS show_rows
      IMPORTING
        it_rows TYPE lif_graph_excel=>ty_rows.
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
    IF ix_graph->request_id IS NOT INITIAL.
      CONCATENATE `      request-id: ` ix_graph->request_id INTO lv_line.
      WRITE: / lv_line.
    ENDIF.
    " In the background an E message ends the job as "Cancelled"; it carries
    " the error itself, not the hint or request-id lines
    IF sy-batch = abap_true.
      MESSAGE lv_text TYPE 'E'.
    ENDIF.
  ENDMETHOD.


  METHOD show_rows.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    DATA lv_text TYPE string.
    LOOP AT it_rows INTO lt_row.
      CONCATENATE LINES OF lt_row INTO lv_text SEPARATED BY ` ; `.
      WRITE: / lv_text.
    ENDLOOP.
  ENDMETHOD.


  METHOD run.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA lt_rows TYPE lif_graph_excel=>ty_rows.
    DATA lt_header TYPE lif_graph_excel=>ty_row.
    DATA lv_sheet TYPE string.
    DATA lv_address TYPE string.
    DATA lv_table TYPE string.
    DATA lv_values TYPE string.
    DATA lv_text TYPE string.
    DATA lv_names TYPE string.
    DATA lv_lines TYPE i.
    DATA lv_number TYPE string.

    lv_sheet = p_sheet.
    lv_sheet = lcl_graph_conv=>trim( lv_sheet ).
    lv_address = p_addr.
    CONDENSE lv_address NO-GAPS.
    lv_table = p_table.
    CONDENSE lv_table.

    IF r_info = abap_true.
      lt_names = io_excel->worksheets( ).
      CONCATENATE LINES OF lt_names INTO lv_names SEPARATED BY `, `.
      lv_text = lcl_text=>get( iv_en = `Worksheets: ` iv_tr = `Çalışma sayfaları: ` ).
      CONCATENATE lv_text lv_names INTO lv_text.
      WRITE: / lv_text.
      lt_names = io_excel->table_names( ).
      CONCATENATE LINES OF lt_names INTO lv_names SEPARATED BY `, `.
      lv_text = lcl_text=>get( iv_en = `Tables: ` iv_tr = `Tablolar: ` ).
      CONCATENATE lv_text lv_names INTO lv_text.
      WRITE: / lv_text.

    ELSEIF r_read = abap_true.
      IF lv_address IS INITIAL OR lv_address NA ':'.
        io_excel->read_used( EXPORTING iv_sheet = lv_sheet iv_as_text = p_text
                             IMPORTING et_rows = lt_rows ev_address = lv_address ).
      ELSE.
        lt_rows = io_excel->read_range( iv_sheet = lv_sheet iv_address = lv_address iv_as_text = p_text ).
      ENDIF.
      WRITE: / lv_address COLOR COL_HEADING.
      ULINE.
      show_rows( lt_rows ).

    ELSEIF r_write = abap_true OR r_addrow = abap_true.
      CONCATENATE p_vals1 '|' p_vals2 INTO lv_values.
      lt_rows = lcl_graph_excel=>rows_from_text( lv_values ).
      lv_lines = lines( lt_rows ).
      lv_number = lcl_graph_conv=>num( lv_lines ).
      IF r_write = abap_true.
        IF lv_address IS INITIAL.
          lv_address = `A1`.
        ENDIF.
        lv_address = io_excel->write_range( iv_sheet = lv_sheet iv_start = lv_address it_rows = lt_rows ).
        lv_text = lcl_text=>get( iv_en = `Written: ` iv_tr = `Yazıldı: ` ).
        CONCATENATE `OK ` lv_text lv_address INTO lv_text.
      ELSE.
        io_excel->add_table_rows( iv_table = lv_table it_rows = lt_rows ).
        lv_text = lcl_text=>get( iv_en = ` rows added to ` iv_tr = ` satır eklendi: ` ).
        CONCATENATE `OK ` lv_number lv_text lv_table INTO lv_text.
      ENDIF.
      WRITE: / lv_text.

    ELSEIF r_table = abap_true.
      lt_header = io_excel->table_header( lv_table ).
      CONCATENATE LINES OF lt_header INTO lv_text SEPARATED BY ` ; `.
      WRITE: / lv_text COLOR COL_HEADING.
      ULINE.
      lt_rows = io_excel->table_rows( lv_table ).
      show_rows( lt_rows ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.


DATA gs_config TYPE lif_graph=>ty_config.
DATA go_client TYPE REF TO lcl_graph_client.
DATA go_files TYPE REF TO lcl_graph_files.
DATA go_excel TYPE REF TO lcl_graph_excel.
DATA gx_graph TYPE REF TO lcx_graph.
DATA gv_text TYPE string.
DATA gv_host TYPE string.
DATA gv_site TYPE string.
DATA gv_lib TYPE string.
DATA gv_path TYPE string.

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
      IF r_site = abap_true.
        gv_host = p_host.
        CONDENSE gv_host.
        gv_site = p_site.
        gv_site = lcl_graph_conv=>trim( gv_site ).
        gv_lib = p_lib.
        gv_lib = lcl_graph_conv=>trim( gv_lib ).
        go_files = lcl_graph_files=>for_site( io_client  = go_client
                                              iv_host    = gv_host
                                              iv_site    = gv_site
                                              iv_library = gv_lib ).
      ELSE.
        gv_text = p_user.
        CONDENSE gv_text.
        go_files = lcl_graph_files=>for_user( io_client = go_client iv_user = gv_text ).
      ENDIF.
      gv_path = p_path.
      gv_path = lcl_graph_conv=>trim( gv_path ).
      go_excel = lcl_graph_excel=>for_file( io_client = go_client io_files = go_files iv_path = gv_path ).
      lcl_app=>run( go_excel ).
    CATCH lcx_graph INTO gx_graph.
      lcl_app=>error( gx_graph ).
  ENDTRY.
