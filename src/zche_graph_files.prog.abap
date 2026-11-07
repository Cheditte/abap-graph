*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_FILES: SharePoint and OneDrive files through Microsoft
*& Graph
*& abap-graph 0.8.0, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE, ZCHE_GRAPH_MAIL_LIB (for the
*& spool to PDF conversion) and ZCHE_GRAPH_FILES_LIB first, then SE38,
*& create executable program ZCHE_GRAPH_FILES, paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& What you can do from the screen (also as a background job):
*&   - list a folder
*&   - upload a spool request as PDF, or a file of the application server
*&   - download a file to the application server
*&   - create a folder path, for example Reports/2026/11
*&   - create a sharing link
*& Your own programs call LCL_GRAPH_FILES directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_files LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_mail_lib.
INCLUDE zche_graph_files_lib.

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
SELECTION-SCREEN END OF BLOCK b_lib.

SELECTION-SCREEN BEGIN OF BLOCK b_do WITH FRAME TITLE t_do.
PARAMETERS r_list RADIOBUTTON GROUP do DEFAULT 'X'.
PARAMETERS r_upspl RADIOBUTTON GROUP do.
PARAMETERS r_upsrv RADIOBUTTON GROUP do.
PARAMETERS r_down RADIOBUTTON GROUP do.
PARAMETERS r_mkdir RADIOBUTTON GROUP do.
PARAMETERS r_link RADIOBUTTON GROUP do.
SELECTION-SCREEN END OF BLOCK b_do.

SELECTION-SCREEN BEGIN OF BLOCK b_what WITH FRAME TITLE t_what.
PARAMETERS p_path TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_spool TYPE rspoid.
PARAMETERS p_file TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_confl TYPE c LENGTH 7 LOWER CASE DEFAULT 'replace'.
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
    t_lib = get( iv_en = 'Library' iv_tr = 'Kitaplık' ).
    t_do = get( iv_en = 'What to do' iv_tr = 'Ne yapılacak' ).
    t_what = get( iv_en = 'File or folder' iv_tr = 'Dosya ya da klasör' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_SITE' iv_en = 'SharePoint site' iv_tr = 'SharePoint sitesi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_HOST' iv_en = 'Host (x.sharepoint.com)' iv_tr = 'Host (x.sharepoint.com)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SITE' iv_en = 'Site path (/sites/...)' iv_tr = 'Site yolu (/sites/...)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LIB' iv_en = 'Library (empty = default)' iv_tr = 'Kitaplık (boş = varsayılan)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_USER' iv_en = 'OneDrive of a user' iv_tr = 'Bir kullanıcının OneDrive''ı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_USER' iv_en = 'User (name@company.com)' iv_tr = 'Kullanıcı (ad@sirket.com)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_LIST' iv_en = 'List a folder' iv_tr = 'Klasörü listele' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_UPSPL' iv_en = 'Upload spool as PDF' iv_tr = 'Spool''u PDF olarak yükle' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_UPSRV' iv_en = 'Upload a server file' iv_tr = 'Sunucudaki dosyayı yükle' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_DOWN' iv_en = 'Download to the server' iv_tr = 'Sunucuya indir' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_MKDIR' iv_en = 'Create folder path' iv_tr = 'Klasör yolunu oluştur' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_LINK' iv_en = 'Create a sharing link' iv_tr = 'Paylaşım bağlantısı oluştur' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_PATH' iv_en = 'Path in the library' iv_tr = 'Kitaplıktaki yol' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_SPOOL' iv_en = 'Spool request' iv_tr = 'Spool talebi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FILE' iv_en = 'Application server file' iv_tr = 'Uygulama sunucusu dosyası' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_CONFL' iv_en = 'If exists: replace/rename/fail' iv_tr = 'Varsa: replace/rename/fail' CHANGING ct_texts = lt_texts ).

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
        io_files TYPE REF TO lcl_graph_files
      RAISING
        lcx_graph.

    CLASS-METHODS error
      IMPORTING
        ix_graph TYPE REF TO lcx_graph.

    CLASS-METHODS read_server_file
      IMPORTING
        iv_file           TYPE string
      RETURNING
        value(rv_content) TYPE xstring
      RAISING
        lcx_graph.

    CLASS-METHODS write_server_file
      IMPORTING
        iv_file    TYPE string
        iv_content TYPE xstring
      RAISING
        lcx_graph.

  PRIVATE SECTION.
    CLASS-METHODS show_item
      IMPORTING
        is_item TYPE lif_graph_files=>ty_item.
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


  METHOD show_item.
    DATA lv_text TYPE string.
    DATA lv_size TYPE string.
    DATA lv_kind TYPE string.

    IF is_item-is_folder = abap_true.
      lv_kind = `[folder]`.
    ELSE.
      lv_size = is_item-size.
      CONDENSE lv_size.
      CONCATENATE lv_size ` bytes` INTO lv_kind.
    ENDIF.
    CONCATENATE is_item-path lv_kind is_item-modified is_item-modified_by INTO lv_text SEPARATED BY ` | `.
    WRITE: / lv_text.
  ENDMETHOD.


  METHOD read_server_file.
    DATA lv_file TYPE string.
    DATA lv_message TYPE string.
    DATA lv_text TYPE string.

    lv_file = iv_file.
    OPEN DATASET lv_file FOR INPUT IN BINARY MODE MESSAGE lv_message.
    IF sy-subrc <> 0.
      CONCATENATE `File ` iv_file ` cannot be read on the application server: ` lv_message INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = `Check the path in AL11 and your authorization S_DATASET.`.
    ENDIF.
    READ DATASET lv_file INTO rv_content.
    CLOSE DATASET lv_file.
  ENDMETHOD.


  METHOD write_server_file.
    DATA lv_file TYPE string.
    DATA lv_message TYPE string.
    DATA lv_text TYPE string.

    lv_file = iv_file.
    OPEN DATASET lv_file FOR OUTPUT IN BINARY MODE MESSAGE lv_message.
    IF sy-subrc <> 0.
      CONCATENATE `File ` iv_file ` cannot be written on the application server: ` lv_message INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = `Check the folder in AL11 and your authorization S_DATASET.`.
    ENDIF.
    TRANSFER iv_content TO lv_file.
    CLOSE DATASET lv_file.
  ENDMETHOD.


  METHOD run.
    DATA lt_items TYPE lif_graph_files=>ty_items.
    DATA ls_item TYPE lif_graph_files=>ty_item.
    DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
    DATA lv_path TYPE string.
    DATA lv_file TYPE string.
    DATA lv_conflict TYPE string.
    DATA lv_content TYPE xstring.
    DATA lv_text TYPE string.
    DATA lv_size TYPE i.
    DATA lv_number TYPE string.
    DATA lv_lines TYPE i.

    lv_path = p_path.
    lv_path = lcl_graph_conv=>trim( lv_path ).
    lv_file = p_file.
    lv_file = lcl_graph_conv=>trim( lv_file ).
    lv_conflict = p_confl.
    CONDENSE lv_conflict.

    IF r_list = abap_true.
      lt_items = io_files->list( iv_folder = lv_path ).
      lv_lines = lines( lt_items ).
      lv_number = lcl_graph_conv=>num( lv_lines ).
      lv_text = lcl_text=>get( iv_en = `Items: ` iv_tr = `Öğeler: ` ).
      CONCATENATE lv_text lv_number INTO lv_text.
      WRITE: / lv_text COLOR COL_HEADING.
      ULINE.
      LOOP AT lt_items INTO ls_item.
        show_item( ls_item ).
      ENDLOOP.

    ELSEIF r_upspl = abap_true OR r_upsrv = abap_true.
      IF r_upspl = abap_true.
        ls_attachment = lcl_graph_mail=>attachment_from_spool( p_spool ).
        lv_content = ls_attachment-content.
        " A path that ends with / means: this folder, with the spool's own name
        IF lv_path IS INITIAL OR lv_path CP '*/'.
          CONCATENATE lv_path ls_attachment-name INTO lv_path.
        ENDIF.
      ELSE.
        lv_content = read_server_file( lv_file ).
      ENDIF.
      lv_size = xstrlen( lv_content ).
      ls_item = io_files->upload( iv_path = lv_path iv_content = lv_content iv_conflict = lv_conflict ).
      lv_number = lcl_graph_conv=>num( lv_size ).
      lv_text = lcl_text=>get( iv_en = `Uploaded: ` iv_tr = `Yüklendi: ` ).
      CONCATENATE `OK ` lv_text ls_item-path ` (` lv_number ` bytes)` INTO lv_text.
      WRITE: / lv_text.
      CONCATENATE `      ` ls_item-web_url INTO lv_text.
      WRITE: / lv_text.

    ELSEIF r_down = abap_true.
      lv_content = io_files->download( lv_path ).
      write_server_file( iv_file = lv_file iv_content = lv_content ).
      lv_size = xstrlen( lv_content ).
      lv_number = lcl_graph_conv=>num( lv_size ).
      lv_text = lcl_text=>get( iv_en = `Downloaded to ` iv_tr = `İndirildi: ` ).
      CONCATENATE `OK ` lv_text lv_file ` (` lv_number ` bytes)` INTO lv_text.
      WRITE: / lv_text.

    ELSEIF r_mkdir = abap_true.
      ls_item = io_files->ensure_folder( lv_path ).
      lv_text = lcl_text=>get( iv_en = `Folder ready: ` iv_tr = `Klasör hazır: ` ).
      CONCATENATE `OK ` lv_text lv_path INTO lv_text.
      WRITE: / lv_text.
      CONCATENATE `      ` ls_item-web_url INTO lv_text.
      WRITE: / lv_text.

    ELSEIF r_link = abap_true.
      lv_text = io_files->share_link( lv_path ).
      CONCATENATE `OK ` lv_text INTO lv_text.
      WRITE: / lv_text.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


DATA gs_config TYPE lif_graph=>ty_config.
DATA go_client TYPE REF TO lcl_graph_client.
DATA go_files TYPE REF TO lcl_graph_files.
DATA gx_graph TYPE REF TO lcx_graph.
DATA gv_text TYPE string.
DATA gv_host TYPE string.
DATA gv_site TYPE string.
DATA gv_lib TYPE string.

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
      lcl_app=>run( go_files ).
    CATCH lcx_graph INTO gx_graph.
      lcl_app=>error( gx_graph ).
  ENDTRY.
