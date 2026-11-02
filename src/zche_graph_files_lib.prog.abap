*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_FILES_LIB: SharePoint and OneDrive files through
*& Microsoft Graph (INCLUDE)
*& abap-graph 0.5.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_FILES_LIB with type "Include
*& program", paste this source, save. It needs ZCHE_GRAPH_CORE:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_files_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& Works in one document library (a "drive"): a library of a SharePoint
*& site, or the OneDrive of a user. Files and folders are named by their
*& path in the library, for example Reports/2026/11/sales.xlsx.
*&   - upload (large files in pieces), download, list a folder
*&   - create folders (also a whole path at once), rename, move, delete
*&   - sharing links
*&
*& Application permissions (Microsoft Entra ID, with admin consent):
*& preferably Sites.Selected, and then write access granted to the
*& application on the SharePoint sites SAP may use. Files.ReadWrite.All
*& or Sites.ReadWrite.All also work, but reach every site and every
*& OneDrive of the company.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types and limits
*----------------------------------------------------------------------*
INTERFACE lif_graph_files.
  TYPES:
    BEGIN OF ty_item,
      id           TYPE string,
      name         TYPE string,
      path         TYPE string,
      is_folder    TYPE abap_bool,
      size         TYPE p LENGTH 16 DECIMALS 0,
      content_type TYPE string,
      modified     TYPE string,
      modified_by  TYPE string,
      web_url      TYPE string,
    END OF ty_item,
    ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  " What happens when a file or folder of that name already exists
  CONSTANTS:
    BEGIN OF conflict,
      replace TYPE string VALUE `replace`,
      rename  TYPE string VALUE `rename`,
      fail    TYPE string VALUE `fail`,
    END OF conflict.

  " Sharing links: TYPE view or edit; SCOPE organization (people of the company)
  " or anonymous (anyone with the link, if the tenant allows it)
  CONSTANTS:
    BEGIN OF link,
      view         TYPE string VALUE `view`,
      edit         TYPE string VALUE `edit`,
      organization TYPE string VALUE `organization`,
      anonymous    TYPE string VALUE `anonymous`,
    END OF link.

  " Files up to this size go in one request; larger ones in pieces
  CONSTANTS max_direct_bytes TYPE i VALUE 4000000.
  " Pieces must be multiples of 320 KiB: 10 x 320 KiB
  CONSTANTS upload_chunk_bytes TYPE i VALUE 3276800.
ENDINTERFACE.


*----------------------------------------------------------------------*
* Files of one document library
*----------------------------------------------------------------------*
CLASS lcl_graph_files DEFINITION FINAL.
  PUBLIC SECTION.
    "! A library of a SharePoint site. IV_HOST: contoso.sharepoint.com;
    "! IV_SITE: /sites/Finance (empty for the root site); IV_LIBRARY: the
    "! library's name as shown in SharePoint (empty for the default
    "! library, which is called Documents or Belgeler depending on language)
    CLASS-METHODS for_site
      IMPORTING
        io_client       TYPE REF TO lcl_graph_client
        iv_host         TYPE string
        iv_site         TYPE string OPTIONAL
        iv_library      TYPE string OPTIONAL
      RETURNING
        value(ro_files) TYPE REF TO lcl_graph_files
      RAISING
        lcx_graph.

    "! The OneDrive of a user, for example derya@contoso.com
    CLASS-METHODS for_user
      IMPORTING
        io_client       TYPE REF TO lcl_graph_client
        iv_user         TYPE string
      RETURNING
        value(ro_files) TYPE REF TO lcl_graph_files
      RAISING
        lcx_graph.

    "! A library by its drive ID, if you already know it
    METHODS constructor
      IMPORTING
        io_client   TYPE REF TO lcl_graph_client
        iv_drive_id TYPE string.

    METHODS drive_id
      RETURNING
        value(rv_id) TYPE string.

    "! "/Reports/2026/a b.pdf" -> "Reports/2026/a%20b.pdf"; each part is encoded, slashes stay
    CLASS-METHODS encode_path
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    "! Uploads a file; returns the new item. Missing folders on the way are not created
    "! (see ENSURE_FOLDER).
    METHODS upload
      IMPORTING
        iv_path        TYPE string
        iv_content     TYPE xstring
        iv_conflict    TYPE string DEFAULT `replace`
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item
      RAISING
        lcx_graph.

    METHODS download
      IMPORTING
        iv_path           TYPE string
      RETURNING
        value(rv_content) TYPE xstring
      RAISING
        lcx_graph.

    "! The file or folder at the path; raises LCX_GRAPH with HTTP 404 if there is none
    METHODS item
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item
      RAISING
        lcx_graph.

    METHODS exists
      IMPORTING
        iv_path          TYPE string
      RETURNING
        value(rv_exists) TYPE abap_bool
      RAISING
        lcx_graph.

    "! Contents of a folder; empty path = the top of the library
    METHODS list
      IMPORTING
        iv_folder       TYPE string OPTIONAL
        iv_max          TYPE i DEFAULT 1000
      RETURNING
        value(rt_items) TYPE lif_graph_files=>ty_items
      RAISING
        lcx_graph.

    METHODS create_folder
      IMPORTING
        iv_parent      TYPE string OPTIONAL
        iv_name        TYPE string
        iv_conflict    TYPE string DEFAULT `fail`
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item
      RAISING
        lcx_graph.

    "! Creates every missing folder of the path, for example Reports/2026/11
    METHODS ensure_folder
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item
      RAISING
        lcx_graph.

    METHODS delete
      IMPORTING
        iv_path TYPE string
      RAISING
        lcx_graph.

    "! Moves and/or renames. Empty IV_NEW_FOLDER: stays in its folder; empty IV_NEW_NAME: keeps its name
    METHODS move_to
      IMPORTING
        iv_path        TYPE string
        iv_new_folder  TYPE string OPTIONAL
        iv_new_name    TYPE string OPTIONAL
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item
      RAISING
        lcx_graph.

    "! A sharing link to a file or folder
    METHODS share_link
      IMPORTING
        iv_path       TYPE string
        iv_type       TYPE string DEFAULT `view`
        iv_scope      TYPE string DEFAULT `organization`
      RETURNING
        value(rv_url) TYPE string
      RAISING
        lcx_graph.

    "! For tests only: smaller limits, so tests need no megabytes
    METHODS set_limits
      IMPORTING
        iv_max_direct_bytes   TYPE i
        iv_upload_chunk_bytes TYPE i.

  PRIVATE SECTION.
    CONSTANTS select_fields TYPE string
      VALUE `id,name,size,file,folder,lastModifiedDateTime,lastModifiedBy,webUrl,parentReference`.

    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mv_drive_id TYPE string.
    DATA mv_max_direct_bytes TYPE i.
    DATA mv_upload_chunk_bytes TYPE i.

    "! /drives/{id}/root:/{path}: ; for an empty path /drives/{id}/root
    METHODS item_path
      IMPORTING
        iv_path        TYPE string
        iv_rest        TYPE string OPTIONAL
      RETURNING
        value(rv_path) TYPE string.

    CLASS-METHODS clean_path
      IMPORTING
        iv_path        TYPE string
      RETURNING
        value(rv_path) TYPE string.

    CLASS-METHODS item_from_json
      IMPORTING
        io_json        TYPE REF TO lcl_graph_json
        iv_prefix      TYPE string
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item.

    METHODS upload_in_pieces
      IMPORTING
        iv_path        TYPE string
        iv_content     TYPE xstring
        iv_conflict    TYPE string
      RETURNING
        value(rs_item) TYPE lif_graph_files=>ty_item
      RAISING
        lcx_graph.
ENDCLASS.


CLASS lcl_graph_files IMPLEMENTATION.

  METHOD constructor.
    mo_client = io_client.
    mv_drive_id = iv_drive_id.
    mv_max_direct_bytes = lif_graph_files=>max_direct_bytes.
    mv_upload_chunk_bytes = lif_graph_files=>upload_chunk_bytes.
  ENDMETHOD.


  METHOD set_limits.
    mv_max_direct_bytes = iv_max_direct_bytes.
    mv_upload_chunk_bytes = iv_upload_chunk_bytes.
  ENDMETHOD.


  METHOD drive_id.
    rv_id = mv_drive_id.
  ENDMETHOD.


  METHOD for_site.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_site_id TYPE string.
    DATA lv_drive_id TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_field TYPE string.
    DATA lv_name TYPE string.
    DATA lv_wanted TYPE string.
    DATA lv_text TYPE string.
    DATA lt_names TYPE lcl_graph_json=>ty_names.
    DATA lv_names TYPE string.

    lv_site_id = lcl_graph_site=>id( io_client = io_client iv_host = iv_host iv_site = iv_site ).

    " The library: the default one, or the one with this name
    IF iv_library IS INITIAL.
      CONCATENATE `/sites/` lv_site_id `/drive?$select=id` INTO lv_path.
      lo_json = io_client->get_json( lv_path ).
      lv_drive_id = lo_json->get( `id` ).
    ELSE.
      CONCATENATE `/sites/` lv_site_id `/drives?$select=id,name` INTO lv_path.
      lo_json = io_client->get_json( lv_path ).
      lv_wanted = iv_library.
      TRANSLATE lv_wanted TO UPPER CASE.
      lv_count = lo_json->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/name` INTO lv_field.
        lv_name = lo_json->get( lv_field ).
        APPEND lv_name TO lt_names.
        TRANSLATE lv_name TO UPPER CASE.
        IF lv_name = lv_wanted.
          CONCATENATE `value/` lv_number `/id` INTO lv_field.
          lv_drive_id = lo_json->get( lv_field ).
          EXIT.
        ENDIF.
      ENDDO.
      IF lv_drive_id IS INITIAL.
        CONCATENATE LINES OF lt_names INTO lv_names SEPARATED BY `, `.
        CONCATENATE `The site has no library "` iv_library `". Libraries: ` lv_names INTO lv_text.
        RAISE EXCEPTION TYPE lcx_graph
          EXPORTING
            text = lv_text
            hint = `Use the library's name as SharePoint shows it, or leave it empty for the default library.`.
      ENDIF.
    ENDIF.

    CREATE OBJECT ro_files
      EXPORTING
        io_client   = io_client
        iv_drive_id = lv_drive_id.
  ENDMETHOD.


  METHOD for_user.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_drive_id TYPE string.

    CONCATENATE `/users/` iv_user `/drive?$select=id` INTO lv_path.
    lo_json = io_client->get_json( lv_path ).
    lv_drive_id = lo_json->get( `id` ).
    CREATE OBJECT ro_files
      EXPORTING
        io_client   = io_client
        iv_drive_id = lv_drive_id.
  ENDMETHOD.


  METHOD clean_path.
    rv_path = lcl_graph_conv=>clean_path( iv_path ).
  ENDMETHOD.


  METHOD encode_path.
    rv_path = lcl_graph_conv=>encode_path( iv_path ).
  ENDMETHOD.


  METHOD item_path.
    DATA lv_path TYPE string.
    lv_path = encode_path( iv_path ).
    IF lv_path IS INITIAL.
      CONCATENATE `/drives/` mv_drive_id `/root` iv_rest INTO rv_path.
    ELSEIF iv_rest IS INITIAL.
      CONCATENATE `/drives/` mv_drive_id `/root:/` lv_path INTO rv_path.
    ELSE.
      " After the path, a colon ends it: /root:/a/b.pdf:/content
      CONCATENATE `/drives/` mv_drive_id `/root:/` lv_path `:` iv_rest INTO rv_path.
    ENDIF.
  ENDMETHOD.


  METHOD item_from_json.
    DATA lv_field TYPE string.
    DATA lv_parent TYPE string.
    DATA lv_offset TYPE i.
    DATA lv_exists TYPE abap_bool.

    CONCATENATE iv_prefix `id` INTO lv_field.
    rs_item-id = io_json->get( lv_field ).
    CONCATENATE iv_prefix `name` INTO lv_field.
    rs_item-name = io_json->get( lv_field ).
    CONCATENATE iv_prefix `size` INTO lv_field.
    rs_item-size = io_json->get( lv_field ).
    CONCATENATE iv_prefix `lastModifiedDateTime` INTO lv_field.
    rs_item-modified = io_json->get( lv_field ).
    CONCATENATE iv_prefix `lastModifiedBy/user/displayName` INTO lv_field.
    rs_item-modified_by = io_json->get( lv_field ).
    CONCATENATE iv_prefix `webUrl` INTO lv_field.
    rs_item-web_url = io_json->get( lv_field ).
    CONCATENATE iv_prefix `file/mimeType` INTO lv_field.
    rs_item-content_type = io_json->get( lv_field ).
    CONCATENATE iv_prefix `folder` INTO lv_field.
    lv_exists = io_json->exists( lv_field ).
    IF lv_exists = abap_true.
      rs_item-is_folder = abap_true.
    ENDIF.
    " parentReference/path looks like /drive/root:/Reports/2026
    CONCATENATE iv_prefix `parentReference/path` INTO lv_field.
    lv_parent = io_json->get( lv_field ).
    FIND 'root:' IN lv_parent MATCH OFFSET lv_offset.
    IF sy-subrc = 0.
      lv_offset = lv_offset + 5.
      lv_parent = lv_parent+lv_offset.
    ELSE.
      CLEAR lv_parent.
    ENDIF.
    IF lv_parent IS INITIAL OR lv_parent = '/'.
      rs_item-path = rs_item-name.
    ELSE.
      CONCATENATE lv_parent '/' rs_item-name INTO rs_item-path.
      rs_item-path = clean_path( rs_item-path ).
    ENDIF.
  ENDMETHOD.


  METHOD upload.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_text TYPE string.
    DATA lv_size TYPE i.

    lv_size = xstrlen( iv_content ).
    IF lv_size > mv_max_direct_bytes.
      rs_item = upload_in_pieces( iv_path = iv_path iv_content = iv_content iv_conflict = iv_conflict ).
      RETURN.
    ENDIF.
    CONCATENATE `/content?@microsoft.graph.conflictBehavior=` iv_conflict INTO lv_rest.
    lv_path = item_path( iv_path = iv_path iv_rest = lv_rest ).
    ls_response = mo_client->request( iv_method       = 'PUT'
                                      iv_path         = lv_path
                                      iv_body         = iv_content
                                      iv_content_type = `application/octet-stream` ).
    lv_text = lcl_graph_conv=>from_utf8( ls_response-body ).
    lo_json = lcl_graph_json=>parse( lv_text ).
    rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD upload_in_pieces.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_url TYPE string.
    DATA lv_size TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_length TYPE i.
    DATA lv_last TYPE i.
    DATA lv_chunk TYPE xstring.
    DATA lt_headers TYPE tihttpnvp.
    DATA ls_header TYPE ihttpnvp.
    DATA lv_from TYPE string.
    DATA lv_to TYPE string.
    DATA lv_total TYPE string.
    DATA lv_text TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->begin_object( `item` ).
    lo_writer->add_string( iv_name = `@microsoft.graph.conflictBehavior` iv_value = iv_conflict ).
    lo_writer->end_object( ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = item_path( iv_path = iv_path iv_rest = `/createUploadSession` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    lv_url = lo_json->get( `uploadUrl` ).
    IF lv_url IS INITIAL.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = `Microsoft Graph opened no upload session for the file.`.
    ENDIF.

    lv_size = xstrlen( iv_content ).
    lv_total = lcl_graph_conv=>num( lv_size ).
    WHILE lv_offset < lv_size.
      lv_length = lv_size - lv_offset.
      IF lv_length > mv_upload_chunk_bytes.
        lv_length = mv_upload_chunk_bytes.
      ENDIF.
      lv_chunk = iv_content+lv_offset(lv_length).
      lv_last = lv_offset + lv_length - 1.
      lv_from = lcl_graph_conv=>num( lv_offset ).
      lv_to = lcl_graph_conv=>num( lv_last ).
      CLEAR lt_headers.
      ls_header-name = 'Content-Type'.
      ls_header-value = 'application/octet-stream'.
      APPEND ls_header TO lt_headers.
      ls_header-name = 'Content-Range'.
      CONCATENATE `bytes ` lv_from '-' lv_to '/' lv_total INTO ls_header-value.
      APPEND ls_header TO lt_headers.
      ls_response = mo_client->request_url( iv_method = 'PUT' iv_url = lv_url iv_body = lv_chunk it_headers = lt_headers ).
      lv_offset = lv_offset + lv_length.
    ENDWHILE.

    " The answer to the last piece is the new file
    lv_text = lcl_graph_conv=>from_utf8( ls_response-body ).
    IF lv_text IS NOT INITIAL.
      lo_json = lcl_graph_json=>parse( lv_text ).
      rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
    ENDIF.
  ENDMETHOD.


  METHOD download.
    " Graph hands out a short-lived download URL with its own key; no token goes there
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA ls_response TYPE lif_graph=>ty_response.
    DATA lv_path TYPE string.
    DATA lv_url TYPE string.
    DATA lv_text TYPE string.

    lv_path = item_path( iv_path = iv_path ).
    CONCATENATE lv_path `?$select=id,@microsoft.graph.downloadUrl` INTO lv_path.
    lo_json = mo_client->get_json( lv_path ).
    lv_url = lo_json->get( `@microsoft.graph.downloadUrl` ).
    IF lv_url IS INITIAL.
      CONCATENATE iv_path ` is not a file that can be downloaded.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text.
    ENDIF.
    ls_response = mo_client->request_url( iv_method = 'GET' iv_url = lv_url ).
    rv_content = ls_response-body.
  ENDMETHOD.


  METHOD item.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_path TYPE string.
    lv_path = item_path( iv_path = iv_path ).
    CONCATENATE lv_path `?$select=` select_fields INTO lv_path.
    lo_json = mo_client->get_json( lv_path ).
    rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD exists.
    DATA lx_graph TYPE REF TO lcx_graph.
    rv_exists = abap_true.
    TRY.
        item( iv_path ).
      CATCH lcx_graph INTO lx_graph.
        IF lx_graph->http_status = 404.
          rv_exists = abap_false.
        ELSE.
          RAISE EXCEPTION lx_graph.
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD list.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_lines TYPE i.

    IF iv_max <= 0.
      RETURN.
    ENDIF.
    CONCATENATE `/children?$top=200&$select=` select_fields INTO lv_rest.
    lv_path = item_path( iv_path = iv_folder iv_rest = lv_rest ).
    lt_pages = mo_client->get_pages( iv_path = lv_path ).
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


  METHOD create_folder.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `name` iv_value = iv_name ).
    lo_writer->begin_object( `folder` ).
    lo_writer->end_object( ).
    lo_writer->add_string( iv_name = `@microsoft.graph.conflictBehavior` iv_value = iv_conflict ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = item_path( iv_path = iv_parent iv_rest = `/children` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD ensure_folder.
    DATA lt_parts TYPE lcl_graph_json=>ty_names.
    DATA lv_part TYPE string.
    DATA lv_parent TYPE string.
    DATA lv_current TYPE string.
    DATA lv_path TYPE string.
    DATA lv_exists TYPE abap_bool.
    DATA lv_missing TYPE abap_bool.

    lv_path = clean_path( iv_path ).
    SPLIT lv_path AT '/' INTO TABLE lt_parts.
    LOOP AT lt_parts INTO lv_part.
      IF lv_current IS INITIAL.
        lv_current = lv_part.
      ELSE.
        CONCATENATE lv_current '/' lv_part INTO lv_current.
      ENDIF.
      " Once one folder was missing, all below it are missing too
      IF lv_missing = abap_false.
        lv_exists = exists( lv_current ).
        IF lv_exists = abap_false.
          lv_missing = abap_true.
        ENDIF.
      ENDIF.
      IF lv_missing = abap_true.
        rs_item = create_folder( iv_parent = lv_parent iv_name = lv_part iv_conflict = lif_graph_files=>conflict-fail ).
      ENDIF.
      lv_parent = lv_current.
    ENDLOOP.
    IF lv_missing = abap_false AND lv_path IS NOT INITIAL.
      rs_item = item( lv_path ).
    ENDIF.
  ENDMETHOD.


  METHOD delete.
    DATA lv_path TYPE string.
    lv_path = item_path( iv_path = iv_path ).
    mo_client->delete_path( lv_path ).
  ENDMETHOD.


  METHOD move_to.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA ls_folder TYPE lif_graph_files=>ty_item.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.
    DATA lv_folder TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lv_folder = clean_path( iv_new_folder ).
    IF iv_new_folder IS NOT INITIAL.
      lo_writer->begin_object( `parentReference` ).
      IF lv_folder IS INITIAL.
        " The top of the library
        lv_path = item_path( iv_path = `` ).
        lo_json = mo_client->get_json( lv_path ).
        ls_folder-id = lo_json->get( `id` ).
      ELSE.
        ls_folder = item( lv_folder ).
      ENDIF.
      lo_writer->add_string( iv_name = `id` iv_value = ls_folder-id ).
      lo_writer->end_object( ).
    ENDIF.
    IF iv_new_name IS NOT INITIAL.
      lo_writer->add_string( iv_name = `name` iv_value = iv_new_name ).
    ENDIF.
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = item_path( iv_path = iv_path ).
    lo_json = mo_client->send_json( iv_method = 'PATCH' iv_path = lv_path iv_json = lv_json ).
    rs_item = item_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD share_link.
    DATA lo_writer TYPE REF TO lcl_graph_json_writer.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_json TYPE string.
    DATA lv_path TYPE string.

    CREATE OBJECT lo_writer.
    lo_writer->begin_object( ).
    lo_writer->add_string( iv_name = `type` iv_value = iv_type ).
    lo_writer->add_string( iv_name = `scope` iv_value = iv_scope ).
    lo_writer->end_object( ).
    lv_json = lo_writer->result( ).
    lv_path = item_path( iv_path = iv_path iv_rest = `/createLink` ).
    lo_json = mo_client->send_json( iv_method = 'POST' iv_path = lv_path iv_json = lv_json ).
    rv_url = lo_json->get( `link/webUrl` ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for files. A test double from ZCHE_GRAPH_CORE answers
*& instead of Microsoft; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_files DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mo_cut TYPE REF TO lcl_graph_files.

    METHODS setup.
    METHODS paths FOR TESTING.
    METHODS site_and_library FOR TESTING RAISING lcx_graph.
    METHODS library_missing FOR TESTING.
    METHODS upload_small FOR TESTING RAISING lcx_graph.
    METHODS upload_large FOR TESTING RAISING lcx_graph.
    METHODS download_by_url FOR TESTING RAISING lcx_graph.
    METHODS list_folder FOR TESTING RAISING lcx_graph.
    METHODS ensure_folders FOR TESTING RAISING lcx_graph.
    METHODS move_and_link FOR TESTING RAISING lcx_graph.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.
ENDCLASS.


CLASS ltc_graph_files IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `files` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    CREATE OBJECT mo_client
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
    CREATE OBJECT mo_cut
      EXPORTING
        io_client   = mo_client
        iv_drive_id = `D1`.
    mo_http->token_answer( ).
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD paths.
    DATA lv_path TYPE string.
    lv_path = lcl_graph_files=>encode_path( `/Reports\2026/a b.pdf/` ).
    cl_aunit_assert=>assert_equals( act = lv_path exp = `Reports/2026/a%20b.pdf` ).
    lv_path = lcl_graph_files=>encode_path( `` ).
    cl_aunit_assert=>assert_initial( lv_path ).
  ENDMETHOD.


  METHOD site_and_library.
    DATA lo_files TYPE REF TO lcl_graph_files.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_id TYPE string.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"contoso.sharepoint.com,s1,w1"}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"D-DOC","name":"Documents"},{"id":"D-FIN","name":"Finans Arşivi"}]}` ).
    lo_files = lcl_graph_files=>for_site( io_client  = mo_client
                                          iv_host    = `contoso.sharepoint.com`
                                          iv_site    = `/sites/Finance`
                                          iv_library = `finans arşivi` ).
    lv_id = lo_files->drive_id( ).
    cl_aunit_assert=>assert_equals( act = lv_id exp = `D-FIN` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri
                                    exp = `/v1.0/sites/contoso.sharepoint.com:/sites/Finance?$select=id` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri
                                    exp = `/v1.0/sites/contoso.sharepoint.com,s1,w1/drives?$select=id,name` ).
  ENDMETHOD.


  METHOD library_missing.
    DATA lx_graph TYPE REF TO lcx_graph.
    mo_http->answer( iv_status = 200 iv_body = `{"id":"S"}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"D","name":"Documents"}]}` ).
    TRY.
        lcl_graph_files=>for_site( io_client = mo_client iv_host = `contoso.sharepoint.com` iv_library = `SAP` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*Libraries: Documents*' ).
  ENDMETHOD.


  METHOD upload_small.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_content TYPE xstring.
    DATA lv_size TYPE i.

    lv_content = lcl_graph_conv=>to_utf8( `hello` ).
    mo_http->answer( iv_status = 201
                     iv_body = `{"id":"F1","name":"a b.txt","size":5,"file":{"mimeType":"text/plain"},"parentReference":{"path":"/drives/D1/root:/Reports/2026"}}` ).
    ls_item = mo_cut->upload( iv_path = `Reports/2026/a b.txt` iv_content = lv_content ).
    cl_aunit_assert=>assert_equals( act = ls_item-id exp = `F1` ).
    cl_aunit_assert=>assert_equals( act = ls_item-path exp = `Reports/2026/a b.txt` ).
    lv_size = ls_item-size.
    cl_aunit_assert=>assert_equals( act = lv_size exp = 5 ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `PUT` ).
    cl_aunit_assert=>assert_equals(
      act = ls_request-uri
      exp = `/v1.0/drives/D1/root:/Reports/2026/a%20b.txt:/content?@microsoft.graph.conflictBehavior=replace` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `hello` ).
  ENDMETHOD.


  METHOD upload_large.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_content TYPE xstring.
    DATA lv_range TYPE string.
    DATA lv_auth TYPE string.

    mo_cut->set_limits( iv_max_direct_bytes = 5 iv_upload_chunk_bytes = 4 ).
    lv_content = lcl_graph_conv=>to_utf8( `ABCDEFGHIJ` ).
    mo_http->answer( iv_status = 200 iv_body = `{"uploadUrl":"https://contoso.sharepoint.com/up?k=1"}` ).
    mo_http->answer( iv_status = 202 iv_body = `{"nextExpectedRanges":["4-"]}` ).
    mo_http->answer( iv_status = 202 iv_body = `{"nextExpectedRanges":["8-"]}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"F2","name":"big.bin","size":10}` ).
    ls_item = mo_cut->upload( iv_path = `big.bin` iv_content = lv_content iv_conflict = `rename` ).
    cl_aunit_assert=>assert_equals( act = ls_item-id exp = `F2` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D1/root:/big.bin:/createUploadSession` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"item":{"@microsoft.graph.conflictBehavior":"rename"}}` ).
    ls_request = request_at( 5 ).
    lv_range = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Content-Range` ).
    cl_aunit_assert=>assert_equals( act = lv_range exp = `bytes 8-9/10` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `IJ` ).
    lv_auth = lcl_graph_client=>header_value( it_headers = ls_request-headers iv_name = `Authorization` ).
    cl_aunit_assert=>assert_initial( lv_auth ).
  ENDMETHOD.


  METHOD download_by_url.
    DATA lv_content TYPE xstring.
    DATA lv_expected TYPE xstring.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"F1","@microsoft.graph.downloadUrl":"https://contoso.sharepoint.com/dl?k=2"}` ).
    mo_http->answer( iv_status = 200 iv_body = `%PDF-1.7` ).
    lv_content = mo_cut->download( `Reports/a.pdf` ).
    lv_expected = lcl_graph_conv=>to_utf8( `%PDF-1.7` ).
    cl_aunit_assert=>assert_equals( act = lv_content exp = lv_expected ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `https://contoso.sharepoint.com/dl?k=2` ).
  ENDMETHOD.


  METHOD list_folder.
    DATA lt_items TYPE lif_graph_files=>ty_items.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_count TYPE i.
    DATA lv_json TYPE string.

    CONCATENATE `{"value":[{"id":"1","name":"2026","folder":{"childCount":3}},`
                `{"id":"2","name":"a.pdf","size":1234,"file":{"mimeType":"application/pdf"},`
                `"lastModifiedBy":{"user":{"displayName":"Derya"}}}],`
                `"@odata.nextLink":"https://graph.microsoft.com/v1.0/drives/D1/root/children?$skiptoken=X"}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"3","name":"b.xlsx","size":1}]}` ).
    lt_items = mo_cut->list( ).
    lv_count = lines( lt_items ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
    READ TABLE lt_items INDEX 1 INTO ls_item.
    cl_aunit_assert=>assert_equals( act = ls_item-is_folder exp = abap_true ).
    READ TABLE lt_items INDEX 2 INTO ls_item.
    cl_aunit_assert=>assert_equals( act = ls_item-modified_by exp = `Derya` ).
    cl_aunit_assert=>assert_equals( act = ls_item-content_type exp = `application/pdf` ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/drives/D1/root/children?$top=200&$select=*' ).
  ENDMETHOD.


  METHOD ensure_folders.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_count TYPE i.

    " Reports exists, 2026 does not: 2026 and 11 are created, 11 is not looked up
    mo_http->answer( iv_status = 200 iv_body = `{"id":"R","name":"Reports","folder":{}}` ).
    mo_http->answer( iv_status = 404 iv_body = `{"error":{"code":"itemNotFound","message":"The resource could not be found."}}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"Y","name":"2026","folder":{}}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"id":"M","name":"11","folder":{}}` ).
    ls_item = mo_cut->ensure_folder( `Reports/2026/11` ).
    cl_aunit_assert=>assert_equals( act = ls_item-id exp = `M` ).
    lv_count = lines( mo_http->mt_requests ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 5 ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D1/root:/Reports:/children` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body
                                    exp = `{"name":"2026","folder":{},"@microsoft.graph.conflictBehavior":"fail"}` ).
    ls_request = request_at( 5 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/drives/D1/root:/Reports/2026:/children` ).
  ENDMETHOD.


  METHOD move_and_link.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_url TYPE string.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"ARCH","name":"Archive","folder":{}}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"id":"F1","name":"a_2026.pdf"}` ).
    mo_http->answer( iv_status = 201 iv_body = `{"link":{"type":"view","webUrl":"https://contoso.sharepoint.com/:b:/s/x"}}` ).
    ls_item = mo_cut->move_to( iv_path = `Reports/a.pdf` iv_new_folder = `Archive` iv_new_name = `a_2026.pdf` ).
    cl_aunit_assert=>assert_equals( act = ls_item-name exp = `a_2026.pdf` ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-method exp = `PATCH` ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"parentReference":{"id":"ARCH"},"name":"a_2026.pdf"}` ).
    lv_url = mo_cut->share_link( `Archive/a_2026.pdf` ).
    cl_aunit_assert=>assert_equals( act = lv_url exp = `https://contoso.sharepoint.com/:b:/s/x` ).
    ls_request = request_at( 4 ).
    cl_aunit_assert=>assert_equals( act = ls_request-body exp = `{"type":"view","scope":"organization"}` ).
  ENDMETHOD.

ENDCLASS.
