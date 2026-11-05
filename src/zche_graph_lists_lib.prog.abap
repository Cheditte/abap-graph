*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_LISTS_LIB: SharePoint lists through Microsoft Graph
*& (INCLUDE)
*& abap-graph 0.7.3, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_LISTS_LIB with type "Include
*& program", paste this source, save. It needs ZCHE_GRAPH_CORE:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_lists_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& One SharePoint list (a table that people keep in SharePoint):
*&   - its columns, with their types
*&   - read items (chosen columns, a filter, many pages)
*&   - create, update, delete items
*&   - update-or-create by a key column, to keep a list in step with SAP
*& Values travel as text; numbers, yes/no, multiple choices and lookups
*& are converted by the type of their column.
*&
*& Application permissions (Microsoft Entra ID, with admin consent):
*& Sites.Selected with write access on the site (preferred), or
*& Sites.ReadWrite.All (every site of the company).
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
INTERFACE lif_graph_lists.
  " NAME is the column's internal name (for example Title, Amount, OwnerLookupId)
  TYPES:
    BEGIN OF ty_field,
      name  TYPE string,
      value TYPE string,
    END OF ty_field,
    ty_fields TYPE STANDARD TABLE OF ty_field WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_item,
      id       TYPE string,
      created  TYPE string,
      modified TYPE string,
      web_url  TYPE string,
      fields   TYPE ty_fields,
    END OF ty_item,
    ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  " TYPE: text, note, number, currency, dateTime, boolean, choice, lookup,
  " personOrGroup, calculated, hyperlinkOrPicture or other
  TYPES:
    BEGIN OF ty_column,
      name         TYPE string,
      display_name TYPE string,
      type         TYPE string,
      multiple     TYPE abap_bool,
      read_only    TYPE abap_bool,
      required     TYPE abap_bool,
      hidden       TYPE abap_bool,
      " "Enforce unique values" in the column settings
      unique       TYPE abap_bool,
    END OF ty_column,
    ty_columns TYPE STANDARD TABLE OF ty_column WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_list,
      id           TYPE string,
      name         TYPE string,
      display_name TYPE string,
      web_url      TYPE string,
    END OF ty_list,
    ty_lists TYPE STANDARD TABLE OF ty_list WITH DEFAULT KEY.
ENDINTERFACE.


*----------------------------------------------------------------------*
* One SharePoint list
*----------------------------------------------------------------------*
CLASS lcl_graph_list DEFINITION FINAL.
  PUBLIC SECTION.
    "! The list IV_LIST (its name as shown, its internal name or its ID) of a
    "! SharePoint site. IV_HOST: contoso.sharepoint.com; IV_SITE: /sites/Finance
    CLASS-METHODS for_site
      IMPORTING
        io_client      TYPE REF TO lcl_graph_client
        iv_host        TYPE string
        iv_site        TYPE string OPTIONAL
        iv_list        TYPE string
      RETURNING
        value(ro_list) TYPE REF TO lcl_graph_list
      RAISING
        lcx_graph.

    "! The lists of a site, hidden system lists left out
    CLASS-METHODS lists
      IMPORTING
        io_client       TYPE REF TO lcl_graph_client
        iv_site_id      TYPE string
      RETURNING
        value(rt_lists) TYPE lif_graph_lists=>ty_lists
      RAISING
        lcx_graph.

    "! "Title=Paid | Amount=12.5 | Tags=red;blue" -> fields. Fields are separated
    "! by |, the values of a multiple choice or lookup by ;
    CLASS-METHODS fields_from_text
      IMPORTING
        iv_text          TYPE string
      RETURNING
        value(rt_fields) TYPE lif_graph_lists=>ty_fields.

    CLASS-METHODS value_of
      IMPORTING
        it_fields       TYPE lif_graph_lists=>ty_fields
        iv_name         TYPE string
      RETURNING
        value(rv_value) TYPE string.

    METHODS constructor
      IMPORTING
        io_client  TYPE REF TO lcl_graph_client
        iv_site_id TYPE string
        iv_list_id TYPE string.

    METHODS list_id
      RETURNING
        value(rv_id) TYPE string.

    METHODS columns
      RETURNING
        value(rt_columns) TYPE lif_graph_lists=>ty_columns
      RAISING
        lcx_graph.

    "! IT_SELECT: internal column names to read (empty: all).
    "! IV_FILTER: an OData filter on the columns, for example
    "!   fields/Status eq 'Open'      fields/Amount gt 1000
    METHODS items
      IMPORTING
        it_select       TYPE lcl_graph_json=>ty_names OPTIONAL
        iv_filter       TYPE string OPTIONAL
        iv_max          TYPE i DEFAULT 5000
      RETURNING
        value(rt_items) TYPE lif_graph_lists=>ty_items
      RAISING
        lcx_graph.

    METHODS item
      IMPORTING
        iv_id          TYPE string
      RETURNING
        value(rs_item) TYPE lif_graph_lists=>ty_item
      RAISING
        lcx_graph.

    METHODS create
      IMPORTING
        it_fields      TYPE lif_graph_lists=>ty_fields
      RETURNING
        value(rs_item) TYPE lif_graph_lists=>ty_item
      RAISING
        lcx_graph.

    "! Changes only the given fields
    METHODS update
      IMPORTING
        iv_id     TYPE string
        it_fields TYPE lif_graph_lists=>ty_fields
      RAISING
        lcx_graph.

    METHODS delete
      IMPORTING
        iv_id TYPE string
      RAISING
        lcx_graph.

    "! Updates the item whose IV_KEY column has the value given in IT_FIELDS,
    "! or creates it. Returns the item ID; EV_CREATED = X when it was created.
    "! Two jobs that run at the same time can both find nothing and both
    "! create. Only SharePoint can stop that: switch on "Enforce unique
    "! values" for the key column. Then the second create is refused, and
    "! the item that the other job created is read and updated instead.
    METHODS upsert
      IMPORTING
        iv_key        TYPE string
        it_fields     TYPE lif_graph_lists=>ty_fields
      EXPORTING
        ev_id         TYPE string
        ev_created    TYPE abap_bool
      RAISING
        lcx_graph.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mv_site_id TYPE string.
    DATA mv_list_id TYPE string.
    DATA mt_columns TYPE lif_graph_lists=>ty_columns.
    DATA mv_columns_read TYPE abap_bool.

    METHODS list_path
      IMPORTING
        iv_rest        TYPE string OPTIONAL
      RETURNING
        value(rv_path) TYPE string.

    METHODS write_fields
      IMPORTING
        io_writer TYPE REF TO lcl_graph_json_writer
        it_fields TYPE lif_graph_lists=>ty_fields
      RAISING
        lcx_graph.

    CLASS-METHODS item_from_json
      IMPORTING
        io_json        TYPE REF TO lcl_graph_json
        iv_prefix      TYPE string
      RETURNING
        value(rs_item) TYPE lif_graph_lists=>ty_item.

    "! The value of a field that is an object: the name of a person or lookup,
    "! the address of a link, the name of a location, or its first plain member
    CLASS-METHODS object_value
      IMPORTING
        io_json         TYPE REF TO lcl_graph_json
        iv_path         TYPE string
      RETURNING
        value(rv_value) TYPE string.

    CLASS-METHODS number_json
      IMPORTING
        iv_name        TYPE string
        iv_value       TYPE string
      RETURNING
        value(rv_json) TYPE string
      RAISING
        lcx_graph.

    CLASS-METHODS prefer_headers
      RETURNING
        value(rt_headers) TYPE tihttpnvp.
ENDCLASS.


CLASS lcl_graph_list IMPLEMENTATION.

  METHOD constructor.
    mo_client = io_client.
    mv_site_id = iv_site_id.
    mv_list_id = iv_list_id.
  ENDMETHOD.


  METHOD list_id.
    rv_id = mv_list_id.
  ENDMETHOD.


  METHOD list_path.
    CONCATENATE `/sites/` mv_site_id `/lists/` mv_list_id iv_rest INTO rv_path.
  ENDMETHOD.


  METHOD prefer_headers.
    " Filters on columns without an index are refused unless this header is sent;
    " with very large lists SharePoint may still refuse them
    DATA ls_header TYPE ihttpnvp.
    ls_header-name = 'Prefer'.
    ls_header-value = 'HonorNonIndexedQueriesWarningMayFailRandomly'.
    APPEND ls_header TO rt_headers.
  ENDMETHOD.


  METHOD lists.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_list TYPE lif_graph_lists=>ty_list.
    DATA lv_path TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_hidden TYPE string.

    CONCATENATE `/sites/` iv_site_id `/lists?$select=id,name,displayName,webUrl,list` INTO lv_path.
    lt_pages = io_client->get_pages( lv_path ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        CONCATENATE lv_prefix `list/hidden` INTO lv_field.
        lv_hidden = lo_page->get( lv_field ).
        IF lv_hidden = `true`.
          CONTINUE.
        ENDIF.
        CLEAR ls_list.
        CONCATENATE lv_prefix `id` INTO lv_field.
        ls_list-id = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `name` INTO lv_field.
        ls_list-name = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `displayName` INTO lv_field.
        ls_list-display_name = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `webUrl` INTO lv_field.
        ls_list-web_url = lo_page->get( lv_field ).
        APPEND ls_list TO rt_lists.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD for_site.
    DATA lt_lists TYPE lif_graph_lists=>ty_lists.
    DATA ls_list TYPE lif_graph_lists=>ty_list.
    DATA lv_site_id TYPE string.
    DATA lv_list_id TYPE string.
    DATA lv_wanted TYPE string.
    DATA lv_name TYPE string.
    DATA lv_display TYPE string.
    DATA lv_names TYPE string.
    DATA lv_text TYPE string.

    lv_site_id = lcl_graph_site=>id( io_client = io_client iv_host = iv_host iv_site = iv_site ).
    lt_lists = lists( io_client = io_client iv_site_id = lv_site_id ).
    lv_wanted = iv_list.
    lv_wanted = lcl_graph_conv=>trim( lv_wanted ).
    TRANSLATE lv_wanted TO UPPER CASE.
    LOOP AT lt_lists INTO ls_list.
      lv_name = ls_list-name.
      TRANSLATE lv_name TO UPPER CASE.
      lv_display = ls_list-display_name.
      TRANSLATE lv_display TO UPPER CASE.
      IF lv_display = lv_wanted OR lv_name = lv_wanted OR ls_list-id = iv_list.
        lv_list_id = ls_list-id.
        EXIT.
      ENDIF.
      IF lv_names IS INITIAL.
        lv_names = ls_list-display_name.
      ELSE.
        CONCATENATE lv_names `, ` ls_list-display_name INTO lv_names.
      ENDIF.
    ENDLOOP.
    IF lv_list_id IS INITIAL.
      CONCATENATE `The site has no list "` iv_list `". Lists: ` lv_names INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = `Use the list's name as SharePoint shows it.`.
    ENDIF.
    CREATE OBJECT ro_list
      EXPORTING
        io_client  = io_client
        iv_site_id = lv_site_id
        iv_list_id = lv_list_id.
  ENDMETHOD.


  METHOD fields_from_text.
    DATA lt_parts TYPE lcl_graph_json=>ty_names.
    DATA lv_part TYPE string.
    DATA ls_field TYPE lif_graph_lists=>ty_field.
    DATA lv_length TYPE i.
    DATA lv_last TYPE i.

    SPLIT iv_text AT '|' INTO TABLE lt_parts.
    LOOP AT lt_parts INTO lv_part.
      IF lv_part NA '='.
        CONTINUE.
      ENDIF.
      CLEAR ls_field.
      " Only the first = separates; the value may contain more
      SPLIT lv_part AT '=' INTO ls_field-name ls_field-value IN CHARACTER MODE.
      CONDENSE ls_field-name.
      " Blanks around the value go; blanks inside it stay
      SHIFT ls_field-value LEFT DELETING LEADING space.
      DO.
        lv_length = strlen( ls_field-value ).
        IF lv_length = 0.
          EXIT.
        ENDIF.
        lv_last = lv_length - 1.
        " A string literal: the character constant SPACE would count as empty here
        IF ls_field-value+lv_last(1) <> ` `.
          EXIT.
        ENDIF.
        ls_field-value = ls_field-value(lv_last).
      ENDDO.
      IF ls_field-name IS NOT INITIAL.
        APPEND ls_field TO rt_fields.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD value_of.
    DATA ls_field TYPE lif_graph_lists=>ty_field.
    READ TABLE it_fields INTO ls_field WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv_value = ls_field-value.
    ENDIF.
  ENDMETHOD.


  METHOD columns.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_column TYPE lif_graph_lists=>ty_column.
    DATA lt_types TYPE lcl_graph_json=>ty_names.
    DATA lv_type TYPE string.
    DATA lv_path TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_value TYPE string.
    DATA lv_exists TYPE abap_bool.

    IF mv_columns_read = abap_true.
      rt_columns = mt_columns.
      RETURN.
    ENDIF.
    " The facet that is present tells the type, for example "number": {...}
    SPLIT `text,note,number,currency,dateTime,boolean,choice,lookup,personOrGroup,calculated,hyperlinkOrPicture`
      AT ',' INTO TABLE lt_types.
    lv_path = list_path( `/columns` ).
    lt_pages = mo_client->get_pages( lv_path ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        CLEAR ls_column.
        CONCATENATE lv_prefix `name` INTO lv_field.
        ls_column-name = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `displayName` INTO lv_field.
        ls_column-display_name = lo_page->get( lv_field ).
        CONCATENATE lv_prefix `readOnly` INTO lv_field.
        lv_value = lo_page->get( lv_field ).
        IF lv_value = `true`.
          ls_column-read_only = abap_true.
        ENDIF.
        CONCATENATE lv_prefix `required` INTO lv_field.
        lv_value = lo_page->get( lv_field ).
        IF lv_value = `true`.
          ls_column-required = abap_true.
        ENDIF.
        CONCATENATE lv_prefix `hidden` INTO lv_field.
        lv_value = lo_page->get( lv_field ).
        IF lv_value = `true`.
          ls_column-hidden = abap_true.
        ENDIF.
        CONCATENATE lv_prefix `enforceUniqueValues` INTO lv_field.
        lv_value = lo_page->get( lv_field ).
        IF lv_value = `true`.
          ls_column-unique = abap_true.
        ENDIF.
        ls_column-type = `other`.
        LOOP AT lt_types INTO lv_type.
          CONCATENATE lv_prefix lv_type INTO lv_field.
          lv_exists = lo_page->exists( lv_field ).
          IF lv_exists = abap_true.
            ls_column-type = lv_type.
            EXIT.
          ENDIF.
        ENDLOOP.
        " Multiple values: choice with checkboxes, lookup or person with several entries
        IF ls_column-type = `choice`.
          CONCATENATE lv_prefix `choice/displayAs` INTO lv_field.
          lv_value = lo_page->get( lv_field ).
          IF lv_value = `checkBoxes`.
            ls_column-multiple = abap_true.
          ENDIF.
        ELSEIF ls_column-type = `lookup` OR ls_column-type = `personOrGroup`.
          " Graph names the flag differently for the two facets
          IF ls_column-type = `lookup`.
            CONCATENATE lv_prefix `lookup/allowMultipleValues` INTO lv_field.
          ELSE.
            CONCATENATE lv_prefix `personOrGroup/allowMultipleSelection` INTO lv_field.
          ENDIF.
          lv_value = lo_page->get( lv_field ).
          IF lv_value = `true`.
            ls_column-multiple = abap_true.
          ENDIF.
        ENDIF.
        APPEND ls_column TO mt_columns.
      ENDDO.
    ENDLOOP.
    mv_columns_read = abap_true.
    rt_columns = mt_columns.
  ENDMETHOD.


  METHOD number_json.
    DATA lv_text TYPE string.
    DATA lv_number TYPE abap_bool.
    " Blanks only at the ends: "1 2" is not 12
    rv_json = lcl_graph_conv=>trim( iv_value ).
    IF rv_json IS INITIAL.
      rv_json = `null`.
      RETURN.
    ENDIF.
    lv_number = lcl_graph_conv=>is_json_number( rv_json ).
    IF lv_number = abap_false.
      CONCATENATE `Field ` iv_name `: "` iv_value `" is not a number. Write numbers with a dot, for example 1234.56.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
  ENDMETHOD.


  METHOD write_fields.
    DATA ls_field TYPE lif_graph_lists=>ty_field.
    DATA ls_column TYPE lif_graph_lists=>ty_column.
    DATA lt_values TYPE lcl_graph_json=>ty_names.
    DATA lv_value TYPE string.
    DATA lv_json TYPE string.
    DATA lv_upper TYPE string.
    DATA lv_annotation TYPE string.
    DATA lv_true TYPE abap_bool.
    DATA lv_found TYPE abap_bool.
    DATA lv_lookup TYPE abap_bool.
    DATA lv_multiple TYPE abap_bool.
    DATA lv_base TYPE string.
    DATA lv_length TYPE i.
    DATA ls_base TYPE lif_graph_lists=>ty_column.

    columns( ).
    LOOP AT it_fields INTO ls_field.
      CLEAR: ls_column, lv_lookup, lv_multiple.
      READ TABLE mt_columns INTO ls_column WITH KEY name = ls_field-name.
      IF sy-subrc = 0.
        lv_found = abap_true.
      ELSE.
        lv_found = abap_false.
      ENDIF.
      lv_upper = ls_field-name.
      TRANSLATE lv_upper TO UPPER CASE.
      lv_value = lcl_graph_conv=>trim( ls_field-value ).

      " OwnerLookupId is no column of its own but the ID side of the column
      " Owner; a real column whose name ends in LookupId keeps its own type
      IF lv_found = abap_false AND lv_upper CP '*LOOKUPID'.
        lv_lookup = abap_true.
        lv_length = strlen( ls_field-name ) - 8.
        lv_base = ls_field-name(lv_length).
        READ TABLE mt_columns INTO ls_base WITH KEY name = lv_base.
        IF sy-subrc = 0.
          lv_multiple = ls_base-multiple.
        ENDIF.
      ENDIF.

      IF lv_lookup = abap_true.
        " Lookup and person columns are written as numbers: OwnerLookupId = 12, or 12;15.
        " A column that allows several gets a list even for one value.
        SPLIT ls_field-value AT ';' INTO TABLE lt_values.
        IF lines( lt_values ) > 1 OR lv_multiple = abap_true.
          CONCATENATE ls_field-name `@odata.type` INTO lv_annotation.
          io_writer->add_string( iv_name = lv_annotation iv_value = `Collection(Edm.Int32)` ).
          io_writer->begin_array( ls_field-name ).
          LOOP AT lt_values INTO lv_value.
            lv_json = number_json( iv_name = ls_field-name iv_value = lv_value ).
            io_writer->add_raw( iv_json = lv_json ).
          ENDLOOP.
          io_writer->end_array( ).
        ELSE.
          lv_json = number_json( iv_name = ls_field-name iv_value = ls_field-value ).
          io_writer->add_raw( iv_name = ls_field-name iv_json = lv_json ).
        ENDIF.

      ELSEIF ls_column-type = `number` OR ls_column-type = `currency`.
        lv_json = number_json( iv_name = ls_field-name iv_value = ls_field-value ).
        io_writer->add_raw( iv_name = ls_field-name iv_json = lv_json ).

      ELSEIF ( ls_column-type = `boolean` OR ls_column-type = `dateTime` ) AND lv_value IS INITIAL.
        " Empty clears the field; false or "" would be a value
        io_writer->add_raw( iv_name = ls_field-name iv_json = `null` ).

      ELSEIF ls_column-type = `boolean`.
        lv_value = ls_field-value.
        TRANSLATE lv_value TO LOWER CASE.
        CONDENSE lv_value.
        IF lv_value = `x` OR lv_value = `true` OR lv_value = `1` OR lv_value = `yes` OR lv_value = `evet`.
          lv_true = abap_true.
        ELSE.
          lv_true = abap_false.
        ENDIF.
        io_writer->add_boolean( iv_name = ls_field-name iv_value = lv_true ).

      ELSEIF ls_column-type = `choice` AND ls_column-multiple = abap_true.
        CONCATENATE ls_field-name `@odata.type` INTO lv_annotation.
        io_writer->add_string( iv_name = lv_annotation iv_value = `Collection(Edm.String)` ).
        io_writer->begin_array( ls_field-name ).
        SPLIT ls_field-value AT ';' INTO TABLE lt_values.
        LOOP AT lt_values INTO lv_value.
          CONDENSE lv_value.
          IF lv_value IS NOT INITIAL.
            io_writer->add_string( iv_value = lv_value ).
          ENDIF.
        ENDLOOP.
        io_writer->end_array( ).

      ELSE.
        " Text, note, single choice, date (2026-11-02 or 2026-11-02T10:00:00Z) and the rest
        io_writer->add_string( iv_name = ls_field-name iv_value = ls_field-value ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD object_value.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA lt_known TYPE lcl_graph_json=>ty_names.
    DATA lv_name TYPE string.
    DATA lv_path TYPE string.
    DATA lv_kind TYPE char1.
    DATA lv_exists TYPE abap_bool.

    SPLIT `LookupValue,Url,DisplayName,Email,Description` AT ',' INTO TABLE lt_known.
    LOOP AT lt_known INTO lv_name.
      CONCATENATE iv_path `/` lv_name INTO lv_path.
      lv_exists = io_json->exists( lv_path ).
      IF lv_exists = abap_true.
        rv_value = io_json->get( lv_path ).
        RETURN.
      ENDIF.
    ENDLOOP.
    lt_names = io_json->names( iv_path ).
    LOOP AT lt_names INTO lv_name.
      CONCATENATE iv_path `/` lv_name INTO lv_path.
      lv_kind = io_json->kind_of( lv_path ).
      IF lv_kind <> lcl_graph_json=>kind-object AND lv_kind <> lcl_graph_json=>kind-array AND lv_name(1) <> '@'.
        rv_value = io_json->get( lv_path ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD item_from_json.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA lv_name TYPE string.
    DATA ls_field TYPE lif_graph_lists=>ty_field.
    DATA lv_field TYPE string.
    DATA lv_kind TYPE char1.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_element TYPE string.
    DATA lv_value TYPE string.
    DATA lv_fields TYPE string.

    CONCATENATE iv_prefix `id` INTO lv_field.
    rs_item-id = io_json->get( lv_field ).
    CONCATENATE iv_prefix `createdDateTime` INTO lv_field.
    rs_item-created = io_json->get( lv_field ).
    CONCATENATE iv_prefix `lastModifiedDateTime` INTO lv_field.
    rs_item-modified = io_json->get( lv_field ).
    CONCATENATE iv_prefix `webUrl` INTO lv_field.
    rs_item-web_url = io_json->get( lv_field ).

    CONCATENATE iv_prefix `fields` INTO lv_fields.
    lt_names = io_json->names( lv_fields ).
    LOOP AT lt_names INTO lv_name.
      " @odata.etag and other annotations are not columns
      IF lv_name(1) = '@'.
        CONTINUE.
      ENDIF.
      CLEAR ls_field.
      ls_field-name = lv_name.
      CONCATENATE lv_fields `/` lv_name INTO lv_field.
      lv_kind = io_json->kind_of( lv_field ).
      IF lv_kind = lcl_graph_json=>kind-array.
        " Multiple values: joined with ;
        lv_count = io_json->count( lv_field ).
        DO lv_count TIMES.
          lv_index = sy-index - 1.
          lv_number = lcl_graph_conv=>num( lv_index ).
          CONCATENATE lv_field `/` lv_number INTO lv_element.
          lv_value = io_json->get( lv_element ).
          IF lv_value IS INITIAL.
            " An object in the array, for example a person: take its name
            lv_value = object_value( io_json = io_json iv_path = lv_element ).
          ENDIF.
          IF ls_field-value IS INITIAL.
            ls_field-value = lv_value.
          ELSE.
            CONCATENATE ls_field-value `;` lv_value INTO ls_field-value.
          ENDIF.
        ENDDO.
      ELSEIF lv_kind = lcl_graph_json=>kind-object.
        " A link, a location, a single person or lookup: not left out
        ls_field-value = object_value( io_json = io_json iv_path = lv_field ).
      ELSE.
        ls_field-value = io_json->get( lv_field ).
      ENDIF.
      APPEND ls_field TO rs_item-fields.
    ENDLOOP.
  ENDMETHOD.


  METHOD items.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_item TYPE lif_graph_lists=>ty_item.
    DATA lt_headers TYPE tihttpnvp.
    DATA lv_path TYPE string.
    DATA lv_select TYPE string.
    DATA lv_filter TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_lines TYPE i.

    IF iv_max <= 0.
      RETURN.
    ENDIF.
    IF it_select IS INITIAL.
      lv_path = list_path( `/items?$top=500&$expand=fields` ).
    ELSE.
      CONCATENATE LINES OF it_select INTO lv_select SEPARATED BY ','.
      CONCATENATE `/items?$top=500&$expand=fields($select=` lv_select `)` INTO lv_path.
      lv_path = list_path( lv_path ).
    ENDIF.
    IF iv_filter IS NOT INITIAL.
      lv_filter = lcl_graph_conv=>url_encode( iv_filter ).
      CONCATENATE lv_path `&$filter=` lv_filter INTO lv_path.
      lt_headers = prefer_headers( ).
    ENDIF.
    lt_pages = mo_client->get_pages( iv_path = lv_path iv_max_items = iv_max it_headers = lt_headers ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        ls_item = item_from_json( io_json = lo_page iv_prefix = lv_prefix ).
        APPEND ls_item TO rt_items.
        lv_lines = lines( rt_items ).
        IF lv_lines >= iv_max.
          RETURN.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD item.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_id TYPE string.

    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/items/` lv_id `?$expand=fields` INTO lv_rest.
    lv_path = list_path( lv_rest ).
    lo_json = mo_client->get_json( lv_path ).
    rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD create.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->begin_object( `fields` ).
    write_fields( io_writer = lo_writer it_fields = it_fields ).
    lo_writer->end_object( ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = list_path( `/items` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD update.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_id TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    write_fields( io_writer = lo_writer it_fields = it_fields ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/items/` lv_id `/fields` INTO lv_rest.
    lv_path = list_path( lv_rest ).
    mo_client->send_json( iv_method = 'PATCH' iv_path = lv_path iv_json = lv_json ).
  ENDMETHOD.


  METHOD delete.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_id TYPE string.

    lv_id = lcl_graph_conv=>url_encode( iv_id ).
    CONCATENATE `/items/` lv_id INTO lv_rest.
    lv_path = list_path( lv_rest ).
    mo_client->delete_path( lv_path ).
  ENDMETHOD.


  METHOD upsert.
    DATA lt_items TYPE lif_graph_lists=>ty_items.
    DATA ls_item TYPE lif_graph_lists=>ty_item.
    DATA ls_column TYPE lif_graph_lists=>ty_column.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lt_select TYPE lcl_graph_json=>ty_names.
    DATA lv_key_value TYPE string.
    DATA lv_filter TYPE string.
    DATA lv_text TYPE string.
    DATA lv_lines TYPE i.

    CLEAR: ev_id, ev_created.
    lv_key_value = value_of( it_fields = it_fields iv_name = iv_key ).
    IF lv_key_value IS INITIAL.
      CONCATENATE `The fields have no value for the key column ` iv_key `.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
    " A number column is compared with a number, a text with a quoted text
    " (a single quote inside doubled)
    columns( ).
    READ TABLE mt_columns INTO ls_column WITH KEY name = iv_key.
    IF sy-subrc = 0 AND ( ls_column-type = `number` OR ls_column-type = `currency` ).
      lv_key_value = number_json( iv_name = iv_key iv_value = lv_key_value ).
      CONCATENATE `fields/` iv_key ` eq ` lv_key_value INTO lv_filter.
    ELSE.
      REPLACE ALL OCCURRENCES OF `'` IN lv_key_value WITH `''`.
      CONCATENATE `fields/` iv_key ` eq '` lv_key_value `'` INTO lv_filter.
    ENDIF.
    APPEND iv_key TO lt_select.
    lt_items = items( it_select = lt_select iv_filter = lv_filter iv_max = 2 ).
    lv_lines = lines( lt_items ).
    IF lv_lines > 1.
      CONCATENATE `More than one item has ` iv_key ` = ` lv_key_value `; the key column must be unique.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ELSEIF lv_lines = 1.
      READ TABLE lt_items INDEX 1 INTO ls_item.
      update( iv_id = ls_item-id it_fields = it_fields ).
      ev_id = ls_item-id.
    ELSE.
      TRY.
          ls_item = create( it_fields ).
          ev_id = ls_item-id.
          ev_created = abap_true.
        CATCH lcx_graph INTO lx_graph.
          " Refused: perhaps another job created the key in the meantime.
          " Only a unique key column makes that certain, and only an item
          " that is really there now counts; any other error stays an error.
          READ TABLE mt_columns INTO ls_column WITH KEY name = iv_key.
          IF sy-subrc <> 0 OR ls_column-unique = abap_false
             OR ( lx_graph->http_status <> 400 AND lx_graph->http_status <> 409 ).
            RAISE EXCEPTION lx_graph.
          ENDIF.
          lt_items = items( it_select = lt_select iv_filter = lv_filter iv_max = 2 ).
          IF lines( lt_items ) <> 1.
            RAISE EXCEPTION lx_graph.
          ENDIF.
          READ TABLE lt_items INDEX 1 INTO ls_item.
          update( iv_id = ls_item-id it_fields = it_fields ).
          ev_id = ls_item-id.
      ENDTRY.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for lists. A test double from ZCHE_GRAPH_CORE answers
*& instead of Microsoft; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_list DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mo_cut TYPE REF TO lcl_graph_list.

    METHODS setup.
    METHODS text_to_fields FOR TESTING.
    METHODS site_and_list FOR TESTING RAISING lcx_graph.
    METHODS column_types FOR TESTING RAISING lcx_graph.
    METHODS read_items FOR TESTING RAISING lcx_graph.
    METHODS create_with_types FOR TESTING RAISING lcx_graph.
    METHODS wrong_number FOR TESTING.
    METHODS upsert_creates FOR TESTING RAISING lcx_graph.
    METHODS upsert_updates FOR TESTING RAISING lcx_graph.
    METHODS upsert_race_unique FOR TESTING RAISING lcx_graph.
    METHODS upsert_other_error FOR TESTING.
    METHODS upsert_number_key FOR TESTING RAISING lcx_graph.
    METHODS clear_fields FOR TESTING RAISING lcx_graph.
    METHODS one_item_and_delete FOR TESTING RAISING lcx_graph.

    METHODS answer_columns.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.
ENDCLASS.


CLASS ltc_graph_list IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `lists` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    CREATE OBJECT mo_client
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
    CREATE OBJECT mo_cut
      EXPORTING
        io_client  = mo_client
        iv_site_id = `S1`
        iv_list_id = `L1`.
    mo_http->token_answer( ).
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD answer_columns.
    DATA lv_json TYPE string.
    CONCATENATE `{"value":[`
                `{"name":"Title","displayName":"Title","text":{},"required":true},`
                `{"name":"Amount","displayName":"Tutar","currency":{"locale":"tr-TR"}},`
                `{"name":"Done","displayName":"Bitti","boolean":{}},`
                `{"name":"Tags","displayName":"Etiketler","choice":{"displayAs":"checkBoxes","choices":["a","b"]}},`
                `{"name":"Owner","displayName":"Sorumlu","personOrGroup":{"allowMultipleSelection":true}},`
                `{"name":"Modified","displayName":"Modified","dateTime":{},"readOnly":true}]}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
  ENDMETHOD.


  METHOD text_to_fields.
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.

    lt_fields = lcl_graph_list=>fields_from_text( `Title = Fatura 4711 | Amount=1234.5 | Note=a=b | Tags=a;b |` ).
    lv_count = lines( lt_fields ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 4 ).
    lv_value = lcl_graph_list=>value_of( it_fields = lt_fields iv_name = `Title` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Fatura 4711` ).
    lv_value = lcl_graph_list=>value_of( it_fields = lt_fields iv_name = `Note` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `a=b` ).
  ENDMETHOD.


  METHOD site_and_list.
    DATA lo_list TYPE REF TO lcl_graph_list.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.
    DATA lv_json TYPE string.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"S9"}` ).
    CONCATENATE `{"value":[{"id":"H","name":"hidden","displayName":"Hidden","list":{"hidden":true}},`
                `{"id":"L7","name":"Faturalar","displayName":"Açık Faturalar","list":{"hidden":false}}]}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    lo_list = lcl_graph_list=>for_site( io_client = mo_client
                                        iv_host   = `contoso.sharepoint.com`
                                        iv_site   = `/sites/Finance`
                                        iv_list   = `açık faturalar` ).
    lv_id = lo_list->list_id( ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `L7` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/sites/S9/lists?$select=*' ).
  ENDMETHOD.


  METHOD column_types.
    DATA lt_columns TYPE lif_graph_lists=>ty_columns.
    DATA ls_column TYPE lif_graph_lists=>ty_column.
    DATA lv_count TYPE i.

    answer_columns( ).
    lt_columns = mo_cut->columns( ).
    lv_count = lines( lt_columns ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 6 ).
    READ TABLE lt_columns INTO ls_column WITH KEY name = `Amount`.
    cl_aunit_assert=>assert_equals( act = ls_column-type exp = `currency` ).
    READ TABLE lt_columns INTO ls_column WITH KEY name = `Tags`.
    cl_aunit_assert=>assert_equals( act = ls_column-multiple exp = abap_true ).
    READ TABLE lt_columns INTO ls_column WITH KEY name = `Modified`.
    cl_aunit_assert=>assert_equals( act = ls_column-read_only exp = abap_true ).
    READ TABLE lt_columns INTO ls_column WITH KEY name = `Owner`.
    cl_aunit_assert=>assert_equals( act = ls_column-multiple exp = abap_true ).
    " The second call is answered from memory
    lt_columns = mo_cut->columns( ).
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
  ENDMETHOD.


  METHOD read_items.
    DATA lt_items TYPE lif_graph_lists=>ty_items.
    DATA ls_item TYPE lif_graph_lists=>ty_item.
    DATA lt_select TYPE lcl_graph_json=>ty_names.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_value TYPE string.
    DATA lv_prefer TYPE string.
    DATA lv_json TYPE string.
    DATA lv_count TYPE i.

    CONCATENATE `{"value":[{"id":"5","createdDateTime":"2026-11-01T08:00:00Z",`
                `"fields":{"@odata.etag":"\"x,1\"","Title":"Fatura 4711","Amount":1234.5,"Tags":["a","b"],`
                `"Link":{"Description":"PDF","Url":"https://x/f.pdf"},"Owner":{"LookupId":"7","LookupValue":"Derya Kaya"}}}]}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    APPEND `Title` TO lt_select.
    APPEND `Amount` TO lt_select.
    lt_items = mo_cut->items( it_select = lt_select iv_filter = `fields/Status eq 'Open'` ).
    READ TABLE lt_items INDEX 1 INTO ls_item.
    cl_aunit_assert=>assert_equals( act = ls_item-id exp = `5` ).
    lv_count = lines( ls_item-fields ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 5 ).
    lv_value = lcl_graph_list=>value_of( it_fields = ls_item-fields iv_name = `Link` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `https://x/f.pdf` ).
    lv_value = lcl_graph_list=>value_of( it_fields = ls_item-fields iv_name = `Owner` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `Derya Kaya` ).
    lv_value = lcl_graph_list=>value_of( it_fields = ls_item-fields iv_name = `Amount` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `1234.5` ).
    lv_value = lcl_graph_list=>value_of( it_fields = ls_item-fields iv_name = `Tags` ).
    cl_aunit_assert=>assert_equals( act = lv_value exp = `a;b` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri
                                     exp = '/v1.0/sites/S1/lists/L1/items?$top=500&$expand=fields($select=Title,Amount)&$filter=fields*Status*Open*' ).
    lv_prefer = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Prefer` ).
    cl_aunit_assert=>assert_equals( act = lv_prefer exp = `HonorNonIndexedQueriesWarningMayFailRandomly` ).
  ENDMETHOD.


  METHOD create_with_types.
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA ls_item TYPE lif_graph_lists=>ty_item.
    DATA lv_expected TYPE string.

    answer_columns( ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"9","fields":{"Title":"Fatura 4711"}}` ).
    lt_fields = lcl_graph_list=>fields_from_text(
      `Title=Fatura 4711|Amount=1234.50|Done=X|Tags=a; b|OwnerLookupId=12` ).
    ls_item = mo_cut->create( lt_fields ).
    cl_aunit_assert=>assert_equals( act = ls_item-id exp = `9` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/sites/S1/lists/L1/items` ).
    CONCATENATE `{"fields":{"Title":"Fatura 4711","Amount":1234.50,"Done":true,`
                `"Tags@odata.type":"Collection(Edm.String)","Tags":["a","b"],`
                `"OwnerLookupId@odata.type":"Collection(Edm.Int32)","OwnerLookupId":[12]}}` INTO lv_expected.
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = lv_expected ).
  ENDMETHOD.


  METHOD wrong_number.
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA lx_graph TYPE REF TO lcx_graph.

    answer_columns( ).
    lt_fields = lcl_graph_list=>fields_from_text( `Amount=1.234,50` ).
    TRY.
        mo_cut->update( iv_id = `9` it_fields = lt_fields ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*not a number*' ).
  ENDMETHOD.


  METHOD upsert_creates.
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.
    DATA lv_uri TYPE string.
    DATA lv_created TYPE abap_bool.

    answer_columns( ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[]}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"10","fields":{}}` ).
    lt_fields = lcl_graph_list=>fields_from_text( `Title=O'Brien Ltd|Amount=5` ).
    mo_cut->upsert( EXPORTING iv_key = `Title` it_fields = lt_fields IMPORTING ev_id = lv_id ev_created = lv_created ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `10` ).
    cl_aunit_assert=>assert_equals( act = lv_created exp = abap_true ).
    ls_request = request_at( 3 ).
    " The quote of O'Brien doubled, then encoded
    lv_uri = cl_http_utility=>unescape_url( escaped = ls_request-uri ).
    cl_aunit_assert=>assert_char_cp( act = lv_uri exp = `*$filter=fields/Title eq 'O''Brien Ltd'` ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `POST` ).
  ENDMETHOD.


  METHOD upsert_race_unique.
    " Nothing found, but another job creates the key before this one does
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.
    DATA lv_created TYPE abap_bool.
    DATA lv_count TYPE i.

    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"name":"Title","text":{},"enforceUniqueValues":true},{"name":"Amount","number":{}}]}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[]}` ).
    mo_http->answer( iv_status = 409 iv_body = `{"error":{"code":"conflict","message":"duplicate values were found in Title"}}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"8","fields":{"Title":"4711"}}]}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    lt_fields = lcl_graph_list=>fields_from_text( `Title=4711|Amount=5` ).
    mo_cut->upsert( EXPORTING iv_key = `Title` it_fields = lt_fields IMPORTING ev_id = lv_id ev_created = lv_created ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `8` ).
    cl_aunit_assert=>assert_equals( act = lv_created exp = abap_false ).
    ls_request = request_at( 6 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `PATCH` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/sites/S1/lists/L1/items/8/fields` ).
    " One item POST only (the other POST is the token): no second item
    lv_count = 0.
    LOOP AT mo_http->mt_requests INTO ls_request WHERE method = `POST` AND uri CP '*/items'.
      lv_count = lv_count + 1.
    ENDLOOP.
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
  ENDMETHOD.


  METHOD upsert_other_error.
    " Without a unique key column a refused create is not taken for a race
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_id TYPE string.

    answer_columns( ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[]}` ).
    mo_http->answer( iv_status = 400 iv_body = `{"error":{"code":"invalidRequest","message":"Field 'Amount' is not recognized"}}` ).
    lt_fields = lcl_graph_list=>fields_from_text( `Title=4711|Amount=5` ).
    TRY.
        mo_cut->upsert( EXPORTING iv_key = `Title` it_fields = lt_fields IMPORTING ev_id = lv_id ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `the error was hidden` ).
    cl_aunit_assert=>assert_equals( act = lx_graph->http_status exp = 400 ).
  ENDMETHOD.


  METHOD upsert_number_key.
    " A currency key is compared as a number, without quotes
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.
    DATA lv_uri TYPE string.

    answer_columns( ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"3","fields":{"Amount":5}}]}` ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    lt_fields = lcl_graph_list=>fields_from_text( `Amount=5|Title=Beş` ).
    mo_cut->upsert( EXPORTING iv_key = `Amount` it_fields = lt_fields IMPORTING ev_id = lv_id ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `3` ).
    ls_request = request_at( 3 ).
    lv_uri = cl_http_utility=>unescape_url( escaped = ls_request-uri ).
    cl_aunit_assert=>assert_char_cp( act = lv_uri exp = `*$filter=fields/Amount eq 5` ).
  ENDMETHOD.


  METHOD one_item_and_delete.
    DATA ls_item TYPE lif_graph_lists=>ty_item.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"7","fields":{"Title":"F-007"}}` ).
    mo_http->answer( iv_status = 204 ).
    ls_item = mo_cut->item( `7` ).
    cl_aunit_assert=>assert_equals( act = ls_item-id exp = `7` ).
    mo_cut->delete( `7` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/sites/S1/lists/L1/items/7?$expand=fields` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `DELETE` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/sites/S1/lists/L1/items/7` ).
  ENDMETHOD.


  METHOD clear_fields.
    " Empty clears a yes/no and a date column
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    answer_columns( ).
    mo_http->answer( iv_status = 200 iv_body = `{}` ).
    lt_fields = lcl_graph_list=>fields_from_text( `Done= | Modified=` ).
    mo_cut->update( iv_id = `9` it_fields = lt_fields ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"Done":null,"Modified":null}` ).
  ENDMETHOD.


  METHOD upsert_updates.
    DATA lt_fields TYPE lif_graph_lists=>ty_fields.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.
    DATA lv_created TYPE abap_bool.

    answer_columns( ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"7","fields":{"Title":"4711"}}]}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"Title":"4711","Amount":5}` ).
    lt_fields = lcl_graph_list=>fields_from_text( `Title=4711|Amount=5` ).
    mo_cut->upsert( EXPORTING iv_key = `Title` it_fields = lt_fields IMPORTING ev_id = lv_id ev_created = lv_created ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `7` ).
    cl_aunit_assert=>assert_equals( act = lv_created exp = abap_false ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `PATCH` ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/sites/S1/lists/L1/items/7/fields` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"Title":"4711","Amount":5}` ).
  ENDMETHOD.

ENDCLASS.
