*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_EXCEL_LIB: Excel workbooks in SharePoint or OneDrive
*& through Microsoft Graph (INCLUDE)
*& abap-graph 0.7.4, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_EXCEL_LIB with type "Include
*& program", paste this source, save. It needs ZCHE_GRAPH_CORE and
*& ZCHE_GRAPH_FILES_LIB:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_files_lib.
*&   INCLUDE zche_graph_excel_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Works inside an .xlsx file that is in a SharePoint library or a
*& OneDrive, without downloading it:
*&   - worksheets: list, add
*&   - ranges: read (values or the text Excel shows), write, clear
*&   - tables (Insert > Table in Excel): header, rows, add rows
*&   - recalculate
*& Excel cannot create a new file this way; start from a workbook that
*& exists (for example a template uploaded with the files module).
*&
*& Application permissions: the same as for the files module
*& (Sites.Selected with write access on the site, or Files.ReadWrite.All).
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
INTERFACE lif_graph_excel.
  " A row of cells and a block of rows, as text
  TYPES ty_row TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
  TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY.
ENDINTERFACE.


*----------------------------------------------------------------------*
* One workbook
*----------------------------------------------------------------------*
CLASS lcl_graph_excel DEFINITION FINAL.
  PUBLIC SECTION.
    "! The workbook at IV_PATH in the library of IO_FILES, for example Reports/sales.xlsx
    CLASS-METHODS for_file
      IMPORTING
        io_client       TYPE REF TO lcl_graph_client
        io_files        TYPE REF TO lcl_graph_files
        iv_path         TYPE string
      RETURNING
        value(ro_excel) TYPE REF TO lcl_graph_excel
      RAISING
        lcx_graph.

    "! Column number to letters: 1 -> A, 27 -> AA
    CLASS-METHODS column_letters
      IMPORTING
        iv_column         TYPE i
      RETURNING
        value(rv_letters) TYPE string.

    "! The address of a block: start B3, 2 rows, 3 columns -> B3:D4
    CLASS-METHODS block_address
      IMPORTING
        iv_start          TYPE string
        iv_rows           TYPE i
        iv_columns        TYPE i
      RETURNING
        value(rv_address) TYPE string
      RAISING
        lcx_graph.

    "! "Date;Amount | 2026-11-02;1234.5" -> rows; rows separated by |, cells by ;
    CLASS-METHODS rows_from_text
      IMPORTING
        iv_text        TYPE string
      RETURNING
        value(rt_rows) TYPE lif_graph_excel=>ty_rows.

    METHODS constructor
      IMPORTING
        io_client   TYPE REF TO lcl_graph_client
        iv_drive_id TYPE string
        iv_item_id  TYPE string.

    "! Keeps the workbook open between calls: faster for many changes. With
    "! IV_PERSIST = space the changes are thrown away when the session ends.
    METHODS open_session
      IMPORTING
        iv_persist TYPE abap_bool DEFAULT abap_true
      RAISING
        lcx_graph.

    METHODS close_session
      RAISING
        lcx_graph.

    METHODS worksheets
      RETURNING
        value(rt_names) TYPE lcl_graph_json=>ty_names
      RAISING
        lcx_graph.

    METHODS add_worksheet
      IMPORTING
        iv_name TYPE string
      RAISING
        lcx_graph.

    "! IV_ADDRESS: for example A1:D20. IV_AS_TEXT = X: the text Excel shows
    "! (dates as dates, numbers formatted); otherwise the stored values
    "! (dates as serial numbers).
    METHODS read_range
      IMPORTING
        iv_sheet       TYPE string
        iv_address     TYPE string
        iv_as_text     TYPE abap_bool DEFAULT abap_false
      RETURNING
        value(rt_rows) TYPE lif_graph_excel=>ty_rows
      RAISING
        lcx_graph.

    "! Everything that is filled on the sheet; EV_ADDRESS tells where it is
    METHODS read_used
      IMPORTING
        iv_sheet   TYPE string
        iv_as_text TYPE abap_bool DEFAULT abap_false
      EXPORTING
        et_rows    TYPE lif_graph_excel=>ty_rows
        ev_address TYPE string
      RAISING
        lcx_graph.

    "! Writes the rows from IV_START on. Cells that look like numbers are written
    "! as numbers (IV_NUMBERS = X), texts starting with = as formulas. Other texts
    "! go with a leading apostrophe, so 00123 or 2026-11-02 stay text; Excel
    "! does not show it and reading gives the text back without it. Shorter rows
    "! leave the rest of the block unchanged.
    METHODS write_range
      IMPORTING
        iv_sheet          TYPE string
        iv_start          TYPE string DEFAULT `A1`
        it_rows           TYPE lif_graph_excel=>ty_rows
        iv_numbers        TYPE abap_bool DEFAULT abap_true
      RETURNING
        value(rv_address) TYPE string
      RAISING
        lcx_graph.

    "! Clears the contents (not the formats) of a range
    METHODS clear_range
      IMPORTING
        iv_sheet   TYPE string
        iv_address TYPE string
      RAISING
        lcx_graph.

    METHODS table_names
      RETURNING
        value(rt_names) TYPE lcl_graph_json=>ty_names
      RAISING
        lcx_graph.

    METHODS table_header
      IMPORTING
        iv_table      TYPE string
      RETURNING
        value(rt_row) TYPE lif_graph_excel=>ty_row
      RAISING
        lcx_graph.

    METHODS table_rows
      IMPORTING
        iv_table       TYPE string
        iv_max         TYPE i DEFAULT 100000
      RETURNING
        value(rt_rows) TYPE lif_graph_excel=>ty_rows
      RAISING
        lcx_graph.

    "! Adds rows at the end of a table; the table grows
    METHODS add_table_rows
      IMPORTING
        iv_table   TYPE string
        it_rows    TYPE lif_graph_excel=>ty_rows
        iv_numbers TYPE abap_bool DEFAULT abap_true
      RAISING
        lcx_graph.

    METHODS calculate
      RAISING
        lcx_graph.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mv_drive_id TYPE string.
    DATA mv_item_id TYPE string.
    DATA mv_session_id TYPE string.

    METHODS book_path
      IMPORTING
        iv_rest        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    CLASS-METHODS sheet_part
      IMPORTING
        iv_sheet       TYPE string
      RETURNING
        value(rv_part) TYPE string.

    CLASS-METHODS name_part
      IMPORTING
        iv_kind        TYPE string
        iv_name        TYPE string
      RETURNING
        value(rv_part) TYPE string.

    METHODS headers
      RETURNING
        value(rt_headers) TYPE tihttpnvp.

    CLASS-METHODS rows_from_json
      IMPORTING
        io_json        TYPE REF TO lcl_graph_json
        iv_path        TYPE string
      RETURNING
        value(rt_rows) TYPE lif_graph_excel=>ty_rows.

    CLASS-METHODS write_rows
      IMPORTING
        io_writer  TYPE REF TO lcl_graph_json_writer
        it_rows    TYPE lif_graph_excel=>ty_rows
        iv_columns TYPE i
        iv_numbers TYPE abap_bool.

    CLASS-METHODS is_number
      IMPORTING
        iv_value         TYPE string
      RETURNING
        value(rv_number) TYPE abap_bool.

    CLASS-METHODS width
      IMPORTING
        it_rows         TYPE lif_graph_excel=>ty_rows
      RETURNING
        value(rv_width) TYPE i.
ENDCLASS.


CLASS lcl_graph_excel IMPLEMENTATION.

  METHOD constructor.
    mo_client = io_client.
    mv_drive_id = iv_drive_id.
    mv_item_id = iv_item_id.
  ENDMETHOD.


  METHOD for_file.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA lv_drive_id TYPE string.
    DATA lv_text TYPE string.

    ls_item = io_files->item( iv_path ).
    IF ls_item-is_folder = abap_true.
      CONCATENATE iv_path ` is a folder, not a workbook.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
    lv_drive_id = io_files->drive_id( ).
    CREATE OBJECT ro_excel
      EXPORTING
        io_client   = io_client
        iv_drive_id = lv_drive_id
        iv_item_id  = ls_item-id.
  ENDMETHOD.


  METHOD book_path.
    CONCATENATE `/drives/` mv_drive_id `/items/` mv_item_id `/workbook` iv_rest INTO rv_path.
  ENDMETHOD.


  METHOD name_part.
    " worksheets('Sheet 1'): a quote in the name is doubled, the rest URL-encoded
    DATA lv_name TYPE string.
    lv_name = iv_name.
    REPLACE ALL OCCURRENCES OF `'` IN lv_name WITH `''`.
    lv_name = lcl_graph_conv=>url_encode( lv_name ).
    CONCATENATE `/` iv_kind `('` lv_name `')` INTO rv_part.
  ENDMETHOD.


  METHOD sheet_part.
    rv_part = name_part( iv_kind = `worksheets` iv_name = iv_sheet ).
  ENDMETHOD.


  METHOD headers.
    DATA ls_header TYPE ihttpnvp.
    IF mv_session_id IS INITIAL.
      RETURN.
    ENDIF.
    ls_header-name = 'workbook-session-id'.
    ls_header-value = mv_session_id.
    APPEND ls_header TO rt_headers.
  ENDMETHOD.


  METHOD column_letters.
    DATA lv_rest TYPE i.
    DATA lv_index TYPE i.

    lv_rest = iv_column.
    WHILE lv_rest > 0.
      lv_index = ( lv_rest - 1 ) MOD 26.
      CONCATENATE sy-abcde+lv_index(1) rv_letters INTO rv_letters.
      lv_rest = ( lv_rest - 1 ) DIV 26.
    ENDWHILE.
  ENDMETHOD.


  METHOD block_address.
    DATA lv_start TYPE string.
    DATA lv_letters TYPE string.
    DATA lv_digits TYPE string.
    DATA lv_length TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_position TYPE i.
    DATA lv_column TYPE i.
    DATA lv_row TYPE i.
    DATA lv_last_column TYPE i.
    DATA lv_last_row TYPE i.
    DATA lv_end_letters TYPE string.
    DATA lv_end_digits TYPE string.
    DATA lv_text TYPE string.

    lv_start = iv_start.
    CONDENSE lv_start NO-GAPS.
    TRANSLATE lv_start TO UPPER CASE.
    lv_length = strlen( lv_start ).
    DO lv_length TIMES.
      lv_offset = sy-index - 1.
      lv_char = lv_start+lv_offset(1).
      " At most XFD and 1048576: longer ones would overflow the numbers below
      IF ( lv_char CA sy-abcde AND strlen( lv_letters ) >= 3 )
         OR ( lv_char CA '0123456789' AND strlen( lv_digits ) >= 7 ).
        CLEAR lv_letters.
        EXIT.
      ENDIF.
      IF lv_char CA sy-abcde AND lv_digits IS INITIAL.
        CONCATENATE lv_letters lv_char INTO lv_letters.
        FIND lv_char IN sy-abcde MATCH OFFSET lv_position.
        lv_column = lv_column * 26 + lv_position + 1.
      ELSEIF lv_char CA '0123456789'.
        CONCATENATE lv_digits lv_char INTO lv_digits.
      ELSE.
        CLEAR lv_letters.
        EXIT.
      ENDIF.
    ENDDO.
    IF lv_letters IS INITIAL OR lv_digits IS INITIAL OR iv_rows <= 0 OR iv_columns <= 0.
      CONCATENATE `"` iv_start `" is not a cell address like A1 or B3, or the block is empty.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
    lv_row = lv_digits.
    " A sheet has 1048576 rows and 16384 columns (A to XFD)
    IF lv_row < 1 OR iv_rows > 1048576 OR iv_columns > 16384.
      lv_last_row = 0.
    ELSE.
      lv_last_column = lv_column + iv_columns - 1.
      lv_last_row = lv_row + iv_rows - 1.
    ENDIF.
    IF lv_last_row < 1 OR lv_last_row > 1048576 OR lv_last_column > 16384.
      CONCATENATE `The block from "` iv_start `" does not fit on a sheet (rows 1 to 1048576, columns A to XFD).` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
    lv_end_letters = column_letters( lv_last_column ).
    lv_end_digits = lcl_graph_conv=>num( lv_last_row ).
    CONCATENATE lv_letters lv_digits ':' lv_end_letters lv_end_digits INTO rv_address.
  ENDMETHOD.


  METHOD rows_from_text.
    DATA lt_lines TYPE lcl_graph_json=>ty_names.
    DATA lv_line TYPE string.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    DATA lv_cell TYPE string.

    SPLIT iv_text AT '|' INTO TABLE lt_lines.
    LOOP AT lt_lines INTO lv_line.
      IF lv_line CO ' '.
        CONTINUE.
      ENDIF.
      CLEAR lt_row.
      SPLIT lv_line AT ';' INTO TABLE lt_row.
      LOOP AT lt_row INTO lv_cell.
        " Blanks inside a cell stay: ACME  LTD, ="A  B"
        lv_cell = lcl_graph_conv=>trim( lv_cell ).
        MODIFY lt_row FROM lv_cell.
      ENDLOOP.
      APPEND lt_row TO rt_rows.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_number.
    " 1234, -12.5, 1e3 are numbers; 00123, 1.234,50, +5 and 2026-11-02 are not
    rv_number = lcl_graph_conv=>is_json_number( iv_value ).
  ENDMETHOD.


  METHOD width.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    DATA lv_lines TYPE i.
    LOOP AT it_rows INTO lt_row.
      lv_lines = lines( lt_row ).
      IF lv_lines > rv_width.
        rv_width = lv_lines.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD write_rows.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    DATA lv_cell TYPE string.
    DATA lv_number TYPE abap_bool.
    DATA lv_lines TYPE i.

    io_writer->begin_array( `values` ).
    LOOP AT it_rows INTO lt_row.
      io_writer->begin_array( ).
      LOOP AT lt_row INTO lv_cell.
        lv_number = abap_false.
        IF iv_numbers = abap_true.
          lv_number = is_number( lv_cell ).
        ENDIF.
        IF lv_number = abap_true.
          io_writer->add_raw( iv_json = lv_cell ).
        ELSE.
          " Excel takes a text like a typed entry: 00123 would become 123 and
          " 2026-11-02 a date. A leading apostrophe keeps it text, as in Excel
          IF lv_cell IS NOT INITIAL AND lv_cell(1) <> '='.
            CONCATENATE `'` lv_cell INTO lv_cell.
          ENDIF.
          io_writer->add_string( iv_value = lv_cell ).
        ENDIF.
      ENDLOOP.
      " A block must be rectangular; null leaves a cell as it is
      lv_lines = lines( lt_row ).
      WHILE lv_lines < iv_columns.
        io_writer->add_raw( iv_json = `null` ).
        lv_lines = lv_lines + 1.
      ENDWHILE.
      io_writer->end_array( ).
    ENDLOOP.
    io_writer->end_array( ).
  ENDMETHOD.


  METHOD rows_from_json.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    DATA lv_rows TYPE i.
    DATA lv_columns TYPE i.
    DATA lv_row TYPE i.
    DATA lv_column TYPE i.
    DATA lv_row_text TYPE string.
    DATA lv_column_text TYPE string.
    DATA lv_row_path TYPE string.
    DATA lv_cell_path TYPE string.
    DATA lv_value TYPE string.

    lv_rows = io_json->count( iv_path ).
    DO lv_rows TIMES.
      lv_row = sy-index - 1.
      lv_row_text = lcl_graph_conv=>num( lv_row ).
      CONCATENATE iv_path `/` lv_row_text INTO lv_row_path.
      lv_columns = io_json->count( lv_row_path ).
      CLEAR lt_row.
      DO lv_columns TIMES.
        lv_column = sy-index - 1.
        lv_column_text = lcl_graph_conv=>num( lv_column ).
        CONCATENATE lv_row_path `/` lv_column_text INTO lv_cell_path.
        lv_value = io_json->get( lv_cell_path ).
        APPEND lv_value TO lt_row.
      ENDDO.
      APPEND lt_row TO rt_rows.
    ENDDO.
  ENDMETHOD.


  METHOD open_session.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_boolean( iv_name = `persistChanges` iv_value = iv_persist ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = book_path( `/createSession` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    mv_session_id = lo_json->get( `id` ).
  ENDMETHOD.


  METHOD close_session.
    DATA lv_path TYPE string.
    DATA lt_headers TYPE tihttpnvp.
    IF mv_session_id IS INITIAL.
      RETURN.
    ENDIF.
    lt_headers = headers( ).
    lv_path = book_path( `/closeSession` ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = `{}` it_headers = lt_headers ).
    CLEAR mv_session_id.
  ENDMETHOD.


  METHOD worksheets.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_name TYPE string.

    lt_headers = headers( ).
    lv_path = book_path( `/worksheets?$select=name,position` ).
    lo_json = mo_client->get_json( iv_path = lv_path it_headers = lt_headers ).
    lv_count = lo_json->count( `value` ).
    DO lv_count TIMES.
      lv_index = sy-index - 1.
      lv_number = lcl_graph_conv=>num( lv_index ).
      CONCATENATE `value/` lv_number `/name` INTO lv_field.
      lv_name = lo_json->get( lv_field ).
      APPEND lv_name TO rt_names.
    ENDDO.
  ENDMETHOD.


  METHOD add_worksheet.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `name` iv_value = iv_name ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lt_headers = headers( ).
    " The worksheets collection has an action of its own for this
    lv_path = book_path( `/worksheets/add` ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json it_headers = lt_headers ).
  ENDMETHOD.


  METHOD read_range.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_sheet TYPE string.
    DATA lv_address TYPE string.
    DATA lv_property TYPE string.

    IF iv_as_text = abap_true.
      lv_property = `text`.
    ELSE.
      lv_property = `values`.
    ENDIF.
    lv_sheet = sheet_part( iv_sheet ).
    lv_address = iv_address.
    CONDENSE lv_address NO-GAPS.
    CONCATENATE lv_sheet `/range(address='` lv_address `')?$select=address,` lv_property INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    lo_json = mo_client->get_json( iv_path = lv_path it_headers = lt_headers ).
    rt_rows = rows_from_json( io_json = lo_json iv_path = lv_property ).
  ENDMETHOD.


  METHOD read_used.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_sheet TYPE string.
    DATA lv_property TYPE string.

    CLEAR: et_rows, ev_address.
    IF iv_as_text = abap_true.
      lv_property = `text`.
    ELSE.
      lv_property = `values`.
    ENDIF.
    lv_sheet = sheet_part( iv_sheet ).
    " valuesOnly: formats alone do not count as used
    CONCATENATE lv_sheet `/usedRange(valuesOnly=true)?$select=address,` lv_property INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    lo_json = mo_client->get_json( iv_path = lv_path it_headers = lt_headers ).
    ev_address = lo_json->get( `address` ).
    et_rows = rows_from_json( io_json = lo_json iv_path = lv_property ).
  ENDMETHOD.


  METHOD write_range.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_sheet TYPE string.
    DATA lv_rows TYPE i.
    DATA lv_columns TYPE i.

    lv_rows = lines( it_rows ).
    lv_columns = width( it_rows ).
    rv_address = block_address( iv_start = iv_start iv_rows = lv_rows iv_columns = lv_columns ).
    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    write_rows( io_writer = lo_writer it_rows = it_rows iv_columns = lv_columns iv_numbers = iv_numbers ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_sheet = sheet_part( iv_sheet ).
    CONCATENATE lv_sheet `/range(address='` rv_address `')` INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    mo_client->send_json( iv_method = 'PATCH' iv_path = lv_path iv_json = lv_json it_headers = lt_headers ).
  ENDMETHOD.


  METHOD clear_range.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_sheet TYPE string.
    DATA lv_address TYPE string.

    lv_sheet = sheet_part( iv_sheet ).
    lv_address = iv_address.
    CONDENSE lv_address NO-GAPS.
    CONCATENATE lv_sheet `/range(address='` lv_address `')/clear` INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = `{"applyTo":"Contents"}` it_headers = lt_headers ).
  ENDMETHOD.


  METHOD table_names.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_name TYPE string.

    lt_headers = headers( ).
    lv_path = book_path( `/tables?$select=name` ).
    lo_json = mo_client->get_json( iv_path = lv_path it_headers = lt_headers ).
    lv_count = lo_json->count( `value` ).
    DO lv_count TIMES.
      lv_index = sy-index - 1.
      lv_number = lcl_graph_conv=>num( lv_index ).
      CONCATENATE `value/` lv_number `/name` INTO lv_field.
      lv_name = lo_json->get( lv_field ).
      APPEND lv_name TO rt_names.
    ENDDO.
  ENDMETHOD.


  METHOD table_header.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lt_rows TYPE lif_graph_excel=>ty_rows.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.

    lv_rest = name_part( iv_kind = `tables` iv_name = iv_table ).
    CONCATENATE lv_rest `/headerRowRange?$select=values` INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    lo_json = mo_client->get_json( iv_path = lv_path it_headers = lt_headers ).
    lt_rows = rows_from_json( io_json = lo_json iv_path = `values` ).
    READ TABLE lt_rows INDEX 1 INTO rt_row.
  ENDMETHOD.


  METHOD table_rows.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA lt_headers TYPE tihttpnvp.
    DATA lt_values TYPE lif_graph_excel=>ty_rows.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_lines TYPE i.

    lv_rest = name_part( iv_kind = `tables` iv_name = iv_table ).
    CONCATENATE lv_rest `/rows?$select=values` INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    lt_pages = mo_client->get_pages( iv_path = lv_path iv_max_items = iv_max it_headers = lt_headers ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        " Each table row carries its values as a block of one row
        CONCATENATE `value/` lv_number `/values` INTO lv_field.
        lt_values = rows_from_json( io_json = lo_page iv_path = lv_field ).
        READ TABLE lt_values INDEX 1 INTO lt_row.
        APPEND lt_row TO rt_rows.
        lv_lines = lines( rt_rows ).
        IF lv_lines >= iv_max.
          RETURN.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_table_rows.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_columns TYPE i.

    IF it_rows IS INITIAL.
      RETURN.
    ENDIF.
    lv_columns = width( it_rows ).
    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    write_rows( io_writer = lo_writer it_rows = it_rows iv_columns = lv_columns iv_numbers = iv_numbers ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_rest = name_part( iv_kind = `tables` iv_name = iv_table ).
    CONCATENATE lv_rest `/rows` INTO lv_rest.
    lv_path = book_path( lv_rest ).
    lt_headers = headers( ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json it_headers = lt_headers ).
  ENDMETHOD.


  METHOD calculate.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    lv_path = book_path( `/application/calculate` ).
    lt_headers = headers( ).
    mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = `{"calculationType":"Full"}` it_headers = lt_headers ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for Excel. A test double from ZCHE_GRAPH_CORE answers
*& instead of Microsoft; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_excel DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mo_cut TYPE REF TO lcl_graph_excel.

    METHODS setup.
    METHODS letters FOR TESTING.
    METHODS addresses FOR TESTING RAISING lcx_graph.
    METHODS addresses_off_sheet FOR TESTING RAISING lcx_graph.
    METHODS text_to_rows FOR TESTING.
    METHODS workbook_of_file FOR TESTING RAISING lcx_graph.
    METHODS read_values FOR TESTING RAISING lcx_graph.
    METHODS write_block FOR TESTING RAISING lcx_graph.
    METHODS session_header FOR TESTING RAISING lcx_graph.
    METHODS table_rows FOR TESTING RAISING lcx_graph.
    METHODS add_sheet FOR TESTING RAISING lcx_graph.
    METHODS clear_and_calculate FOR TESTING RAISING lcx_graph.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.

    METHODS cell
      IMPORTING
        it_rows         TYPE lif_graph_excel=>ty_rows
        iv_row          TYPE i
        iv_column       TYPE i
      RETURNING
        value(rv_value) TYPE string.
ENDCLASS.


CLASS ltc_graph_excel IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `excel` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    CREATE OBJECT mo_client
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
    CREATE OBJECT mo_cut
      EXPORTING
        io_client   = mo_client
        iv_drive_id = `D1`
        iv_item_id  = `X1`.
    mo_http->token_answer( ).
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD cell.
    DATA lt_row TYPE lif_graph_excel=>ty_row.
    READ TABLE it_rows INDEX iv_row INTO lt_row.
    READ TABLE lt_row INDEX iv_column INTO rv_value.
  ENDMETHOD.


  METHOD letters.
    DATA lv_letters TYPE string.
    lv_letters = lcl_graph_excel=>column_letters( 1 ).
    cl_aunit_assert=>assert_equals( act = lv_letters exp = `A` ).
    lv_letters = lcl_graph_excel=>column_letters( 26 ).
    cl_aunit_assert=>assert_equals( act = lv_letters exp = `Z` ).
    lv_letters = lcl_graph_excel=>column_letters( 27 ).
    cl_aunit_assert=>assert_equals( act = lv_letters exp = `AA` ).
    lv_letters = lcl_graph_excel=>column_letters( 702 ).
    cl_aunit_assert=>assert_equals( act = lv_letters exp = `ZZ` ).
    lv_letters = lcl_graph_excel=>column_letters( 703 ).
    cl_aunit_assert=>assert_equals( act = lv_letters exp = `AAA` ).
  ENDMETHOD.


  METHOD addresses.
    DATA lv_address TYPE string.
    DATA lv_failed TYPE abap_bool.

    lv_address = lcl_graph_excel=>block_address( iv_start = `b3` iv_rows = 2 iv_columns = 3 ).
    cl_aunit_assert=>assert_equals( act = lv_address exp = `B3:D4` ).
    lv_address = lcl_graph_excel=>block_address( iv_start = `Y10` iv_rows = 1 iv_columns = 3 ).
    cl_aunit_assert=>assert_equals( act = lv_address exp = `Y10:AA10` ).
    TRY.
        lcl_graph_excel=>block_address( iv_start = `3B` iv_rows = 1 iv_columns = 1 ).
      CATCH lcx_graph.
        lv_failed = abap_true.
    ENDTRY.
    cl_aunit_assert=>assert_equals( act = lv_failed exp = abap_true ).
  ENDMETHOD.


  METHOD addresses_off_sheet.
    " Too long for the numbers, row 0, and a block past the last row: errors,
    " not an overflow; the last cell itself is fine
    DATA lt_starts TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
    DATA lv_start TYPE string.
    DATA lv_address TYPE string.
    DATA lv_failed TYPE abap_bool.

    APPEND `AAAAAAAA1` TO lt_starts.
    APPEND `A99999999999` TO lt_starts.
    APPEND `A0` TO lt_starts.
    APPEND `XFE1` TO lt_starts.
    APPEND `XFD1048576` TO lt_starts.
    LOOP AT lt_starts INTO lv_start.
      lv_failed = abap_false.
      TRY.
          lcl_graph_excel=>block_address( iv_start = lv_start iv_rows = 2 iv_columns = 1 ).
        CATCH lcx_graph.
          lv_failed = abap_true.
      ENDTRY.
      cl_aunit_assert=>assert_equals( act = lv_failed exp = abap_true msg = lv_start ).
    ENDLOOP.
    lv_address = lcl_graph_excel=>block_address( iv_start = `XFD1048576` iv_rows = 1 iv_columns = 1 ).
    cl_aunit_assert=>assert_equals( act = lv_address exp = `XFD1048576:XFD1048576` ).
  ENDMETHOD.


  METHOD clear_and_calculate.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    mo_cut->clear_range( iv_sheet = `Data` iv_address = `b2:d5` ).
    mo_cut->calculate( ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri
                                    exp = `/v1.0/drives/D1/items/X1/workbook/worksheets('Data')/range(address='b2:d5')/clear` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"applyTo":"Contents"}` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D1/items/X1/workbook/application/calculate` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"calculationType":"Full"}` ).
  ENDMETHOD.


  METHOD add_sheet.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 201 iv_body = `{"id":"S2","name":"Kasım"}` ).
    mo_cut->add_worksheet( `Kasım` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `POST` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D1/items/X1/workbook/worksheets/add` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"name":"Kasım"}` ).
  ENDMETHOD.


  METHOD text_to_rows.
    DATA lt_rows TYPE lif_graph_excel=>ty_rows.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.

    lt_rows = lcl_graph_excel=>rows_from_text( `Date ; Amount | 2026-11-02;1234.5 |` ).
    lv_count = lines( lt_rows ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    lv_value = cell( it_rows = lt_rows iv_row = 1 iv_column = 2 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Amount` ).
    lv_value = cell( it_rows = lt_rows iv_row = 2 iv_column = 2 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `1234.5` ).
    " Blanks inside a cell stay
    lt_rows = lcl_graph_excel=>rows_from_text( ` ACME  LTD ;="A  B" ` ).
    lv_value = cell( it_rows = lt_rows iv_row = 1 iv_column = 1 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `ACME  LTD` ).
    lv_value = cell( it_rows = lt_rows iv_row = 1 iv_column = 2 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `="A  B"` ).
  ENDMETHOD.


  METHOD workbook_of_file.
    DATA lo_files TYPE REF TO lcl_graph_files.
    DATA lo_excel TYPE REF TO lcl_graph_excel.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_names TYPE string.

    CREATE OBJECT lo_files
      EXPORTING
        io_client   = mo_client
        iv_drive_id = `D9`.
    mo_http->answer( iv_status = 200 iv_body = `{"id":"BOOK","name":"sales.xlsx","file":{}}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"name":"Data","position":0},{"name":"Özet","position":1}]}` ).
    lo_excel = lcl_graph_excel=>for_file( io_client = mo_client io_files = lo_files iv_path = `Reports/sales.xlsx` ).
    lt_names = lo_excel->worksheets( ).
    CONCATENATE LINES OF lt_names INTO lv_names SEPARATED BY ','.
    cl_aunit_assert=>assert_equals( act = lv_names exp = `Data,Özet` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D9/items/BOOK/workbook/worksheets?$select=name,position` ).
  ENDMETHOD.


  METHOD read_values.
    DATA lt_rows TYPE lif_graph_excel=>ty_rows.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_value TYPE string.
    DATA lv_address TYPE string.

    mo_http->answer( iv_status = 200
                     iv_body = `{"address":"Data!A1:C2","values":[["Name","Amount","Paid"],["Derya",1234.5,true]]}` ).
    mo_http->answer( iv_status = 200
                     iv_body = `{"address":"'Sheet 1'!A1:B1","text":[["30.11.2026",""]]}` ).
    lt_rows = mo_cut->read_range( iv_sheet = `Data` iv_address = `A1:C2` ).
    lv_value = cell( it_rows = lt_rows iv_row = 2 iv_column = 2 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `1234.5` ).
    lv_value = cell( it_rows = lt_rows iv_row = 2 iv_column = 3 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `true` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri
                                    exp = `/v1.0/drives/D1/items/X1/workbook/worksheets('Data')/range(address='A1:C2')?$select=address,values` ).

    mo_cut->read_used( EXPORTING iv_sheet = `Sheet 1` iv_as_text = abap_true IMPORTING et_rows = lt_rows ev_address = lv_address ).
    lv_value = cell( it_rows = lt_rows iv_row = 1 iv_column = 1 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `30.11.2026` ).
    cl_aunit_assert=>assert_equals( act = lv_address exp = `'Sheet 1'!A1:B1` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '*worksheets(*Sheet*1*)/usedRange(valuesOnly=true)?$select=address,text' ).
  ENDMETHOD.


  METHOD write_block.
    DATA lt_rows TYPE lif_graph_excel=>ty_rows.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_address TYPE string.
    DATA lv_expected TYPE string.

    lt_rows = lcl_graph_excel=>rows_from_text( `Material;Quantity;Price | 00123;5;-12.50 | =SUM(B2:B3) | 2026-11-02;1e-3;+5` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    lv_address = mo_cut->write_range( iv_sheet = `Data` iv_start = `B2` it_rows = lt_rows ).
    cl_aunit_assert=>assert_equals( act = lv_address exp = `B2:D5` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `PATCH` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri
                                    exp = `/v1.0/drives/D1/items/X1/workbook/worksheets('Data')/range(address='B2:D5')` ).
    " Texts get an apostrophe, so 00123, a date and +5 stay text; 5, -12.50 and 1e-3
    " are numbers; a formula goes as it is; a short row is filled with null
    CONCATENATE `{"values":[["'Material","'Quantity","'Price"],["'00123",5,-12.50],["=SUM(B2:B3)",null,null],`
                `["'2026-11-02",1e-3,"'+5"]]}` INTO lv_expected.
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = lv_expected ).
  ENDMETHOD.


  METHOD session_header.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_session TYPE string.

    mo_http->answer( iv_status = 201 iv_body = `{"id":"SESSION-1","persistChanges":true}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[]}` ).
    mo_http->answer( iv_status = 204 ).
    mo_cut->open_session( ).
    mo_cut->table_names( ).
    mo_cut->close_session( ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"persistChanges":true}` ).
    ls_request = request_at( 3 ).
    lv_session = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `workbook-session-id` ).
    cl_aunit_assert=>assert_equals( act = lv_session exp = `SESSION-1` ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '*/workbook/closeSession' ).
  ENDMETHOD.


  METHOD table_rows.
    DATA lt_rows TYPE lif_graph_excel=>ty_rows.
    DATA lt_header TYPE lif_graph_excel=>ty_row.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.

    mo_http->answer( iv_status = 200 iv_body = `{"values":[["Invoice","Amount"]]}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"values":[["4711",100]]},{"values":[["4712",250.5]]}]}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"index":2}` ).
    lt_header = mo_cut->table_header( `Invoices` ).
    READ TABLE lt_header INDEX 2 INTO lv_value.
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Amount` ).
    lt_rows = mo_cut->table_rows( `Invoices` ).
    lv_count = lines( lt_rows ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    lv_value = cell( it_rows = lt_rows iv_row = 2 iv_column = 2 ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `250.5` ).
    lt_rows = lcl_graph_excel=>rows_from_text( `4713;99` ).
    mo_cut->add_table_rows( iv_table = `Invoices` it_rows = lt_rows ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D1/items/X1/workbook/tables('Invoices')/rows` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"values":[[4713,99]]}` ).
  ENDMETHOD.

ENDCLASS.
