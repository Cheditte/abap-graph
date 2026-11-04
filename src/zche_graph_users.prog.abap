*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_USERS: users and groups of Microsoft Entra ID through
*& Microsoft Graph
*& abap-graph 0.7.1, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: the includes ZCHE_GRAPH_CORE and ZCHE_GRAPH_USERS_LIB first,
*& then SE38, create executable program ZCHE_GRAPH_USERS, paste, activate.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& What you can do from the screen (also as a background job):
*&   - show a user: details, manager, direct reports, groups
*&   - find users with an OData filter
*&   - show the members of a group
*&   - list the active SAP dialog users whose e-mail address (SU01) has
*&     no Microsoft account, or a disabled one
*& Nothing is changed, neither in SAP nor in Microsoft Entra ID.
*& Your own programs call LCL_GRAPH_USERS directly; see the README.
*&---------------------------------------------------------------------*
REPORT zche_graph_users LINE-SIZE 255.

TYPE-POOLS: abap.

INCLUDE zche_graph_core.
INCLUDE zche_graph_users_lib.

DATA gv_bname TYPE xubname.

SELECTION-SCREEN BEGIN OF BLOCK b_conn WITH FRAME TITLE t_conn.
PARAMETERS p_tenant TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
PARAMETERS p_login TYPE rfcdest DEFAULT 'ZCHE_GRAPH_LOGIN'.
PARAMETERS p_api TYPE rfcdest DEFAULT 'ZCHE_GRAPH_API'.
SELECTION-SCREEN END OF BLOCK b_conn.

SELECTION-SCREEN BEGIN OF BLOCK b_do WITH FRAME TITLE t_do.
PARAMETERS r_user RADIOBUTTON GROUP do DEFAULT 'X'.
PARAMETERS r_find RADIOBUTTON GROUP do.
PARAMETERS r_group RADIOBUTTON GROUP do.
PARAMETERS r_sap RADIOBUTTON GROUP do.
SELECTION-SCREEN END OF BLOCK b_do.

SELECTION-SCREEN BEGIN OF BLOCK b_what WITH FRAME TITLE t_what.
PARAMETERS p_user TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_filter TYPE c LENGTH 255 LOWER CASE.
PARAMETERS p_group TYPE c LENGTH 120 LOWER CASE.
PARAMETERS p_nested AS CHECKBOX.
PARAMETERS p_max TYPE i DEFAULT 100.
SELECT-OPTIONS s_user FOR gv_bname.
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
        iv_kind  TYPE c DEFAULT 'P'
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
    ls_text-kind = iv_kind.
    ls_text-text = get( iv_en = iv_en iv_tr = iv_tr ).
    APPEND ls_text TO ct_texts.
  ENDMETHOD.


  METHOD set_selection_texts.
    " The function module needs exactly this table type (default key)
    DATA lt_texts TYPE STANDARD TABLE OF rsseltexts WITH DEFAULT KEY.

    t_conn = get( iv_en = 'Connection' iv_tr = 'Bağlantı' ).
    t_do = get( iv_en = 'What to do' iv_tr = 'Ne yapılacak' ).
    t_what = get( iv_en = 'Details' iv_tr = 'Ayrıntılar' ).
    add( EXPORTING iv_name = 'P_TENANT' iv_en = 'Tenant ID or domain' iv_tr = 'Tenant ID ya da alan adı' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_LOGIN' iv_en = 'SM59: Microsoft sign-in' iv_tr = 'SM59: Microsoft girişi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_API' iv_en = 'SM59: Microsoft Graph' iv_tr = 'SM59: Microsoft Graph' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_USER' iv_en = 'Show a user' iv_tr = 'Kullanıcıyı göster' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_FIND' iv_en = 'Find users (filter)' iv_tr = 'Kullanıcı ara (filtre)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_GROUP' iv_en = 'Members of a group' iv_tr = 'Grubun üyeleri' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'R_SAP' iv_en = 'SAP users: account check' iv_tr = 'SAP kullanıcıları: hesap' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_USER' iv_en = 'User (address or ID)' iv_tr = 'Kullanıcı (adres ya da ID)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_FILTER' iv_en = 'Filter (department eq ''X'')' iv_tr = 'Filtre (department eq ''X'')' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_GROUP' iv_en = 'Group (name or ID)' iv_tr = 'Grup (ad ya da ID)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_NESTED' iv_en = 'Include nested groups' iv_tr = 'İç içe grupları da al' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_MAX' iv_en = 'At most (users)' iv_tr = 'En çok (kullanıcı)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'S_USER' iv_en = 'SAP users' iv_tr = 'SAP kullanıcıları' iv_kind = 'S' CHANGING ct_texts = lt_texts ).

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
    CLASS-METHODS show_user
      IMPORTING
        io_users TYPE REF TO lcl_graph_users
        iv_user  TYPE string
      RAISING
        lcx_graph.

    CLASS-METHODS show_users
      IMPORTING
        it_users TYPE lif_graph_users=>ty_users.

    CLASS-METHODS check_sap
      IMPORTING
        io_users TYPE REF TO lcl_graph_users
      RAISING
        lcx_graph.

    CLASS-METHODS field_line
      IMPORTING
        iv_en    TYPE csequence
        iv_tr    TYPE csequence
        iv_value TYPE string.

    CLASS-METHODS heading
      IMPORTING
        iv_en    TYPE csequence
        iv_tr    TYPE csequence
        iv_count TYPE i OPTIONAL.
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


  METHOD field_line.
    DATA lv_text TYPE string.
    IF iv_value IS INITIAL.
      RETURN.
    ENDIF.
    lv_text = lcl_text=>get( iv_en = iv_en iv_tr = iv_tr ).
    CONCATENATE lv_text `:` INTO lv_text.
    CONCATENATE lv_text iv_value INTO lv_text SEPARATED BY space.
    WRITE: / lv_text.
  ENDMETHOD.


  METHOD heading.
    DATA lv_text TYPE string.
    DATA lv_number TYPE string.
    SKIP.
    lv_text = lcl_text=>get( iv_en = iv_en iv_tr = iv_tr ).
    IF iv_count IS SUPPLIED.
      lv_number = lcl_graph_conv=>num( iv_count ).
      CONCATENATE lv_text `:` INTO lv_text.
      CONCATENATE lv_text lv_number INTO lv_text SEPARATED BY space.
    ENDIF.
    WRITE: / lv_text COLOR COL_HEADING.
    ULINE.
  ENDMETHOD.


  METHOD show_users.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA lv_text TYPE string.
    DATA lv_state TYPE string.

    LOOP AT it_users INTO ls_user.
      IF ls_user-account_enabled = abap_true.
        lv_state = ``.
      ELSE.
        lv_state = lcl_text=>get( iv_en = `disabled` iv_tr = `kapalı` ).
      ENDIF.
      CONCATENATE ls_user-display_name ls_user-user_principal_name ls_user-mail
                  ls_user-department ls_user-job_title lv_state
        INTO lv_text SEPARATED BY ` | `.
      WRITE: / lv_text.
    ENDLOOP.
  ENDMETHOD.


  METHOD show_user.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA ls_manager TYPE lif_graph_users=>ty_user.
    DATA lt_users TYPE lif_graph_users=>ty_users.
    DATA lt_groups TYPE lif_graph_users=>ty_groups.
    DATA ls_group TYPE lif_graph_users=>ty_group.
    DATA lv_text TYPE string.
    DATA lv_count TYPE i.

    ls_user = io_users->user( iv_user ).
    WRITE: / ls_user-display_name COLOR COL_HEADING.
    ULINE.
    field_line( iv_en = `User principal name` iv_tr = `Kullanıcı asıl adı` iv_value = ls_user-user_principal_name ).
    field_line( iv_en = `E-mail` iv_tr = `E-posta` iv_value = ls_user-mail ).
    field_line( iv_en = `Job title` iv_tr = `Unvan` iv_value = ls_user-job_title ).
    field_line( iv_en = `Department` iv_tr = `Departman` iv_value = ls_user-department ).
    field_line( iv_en = `Office` iv_tr = `Ofis` iv_value = ls_user-office_location ).
    field_line( iv_en = `Mobile phone` iv_tr = `Cep telefonu` iv_value = ls_user-mobile_phone ).
    field_line( iv_en = `Employee ID` iv_tr = `Personel no` iv_value = ls_user-employee_id ).
    field_line( iv_en = `Company` iv_tr = `Şirket` iv_value = ls_user-company_name ).
    field_line( iv_en = `Object ID` iv_tr = `Nesne ID` iv_value = ls_user-id ).
    IF ls_user-account_enabled = abap_true.
      lv_text = lcl_text=>get( iv_en = `enabled` iv_tr = `açık` ).
    ELSE.
      lv_text = lcl_text=>get( iv_en = `disabled` iv_tr = `kapalı` ).
    ENDIF.
    field_line( iv_en = `Account` iv_tr = `Hesap` iv_value = lv_text ).

    ls_manager = io_users->manager( ls_user-id ).
    IF ls_manager IS INITIAL.
      lv_text = lcl_text=>get( iv_en = `none` iv_tr = `yok` ).
    ELSE.
      CONCATENATE ls_manager-display_name ` (` ls_manager-user_principal_name `)` INTO lv_text.
    ENDIF.
    field_line( iv_en = `Manager` iv_tr = `Yönetici` iv_value = lv_text ).

    lt_users = io_users->direct_reports( ls_user-id ).
    lv_count = lines( lt_users ).
    heading( iv_en = `Direct reports` iv_tr = `Doğrudan bağlı çalışanlar` iv_count = lv_count ).
    show_users( lt_users ).

    lt_groups = io_users->groups_of( iv_user = ls_user-id iv_nested = p_nested ).
    lv_count = lines( lt_groups ).
    heading( iv_en = `Groups` iv_tr = `Gruplar` iv_count = lv_count ).
    LOOP AT lt_groups INTO ls_group.
      CONCATENATE ls_group-display_name ls_group-mail INTO lv_text SEPARATED BY ` | `.
      WRITE: / lv_text.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_sap.
    DATA lt_sap TYPE lif_graph_users=>ty_sap_users.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_user.
    DATA lt_entra TYPE lif_graph_users=>ty_users.
    DATA lt_findings TYPE lif_graph_users=>ty_findings.
    DATA ls_finding TYPE lif_graph_users=>ty_finding.
    DATA lv_text TYPE string.
    DATA lv_bname TYPE string.
    DATA lv_count TYPE i.
    DATA lv_compared TYPE i.
    DATA lv_no_mail TYPE i.

    lt_sap = lcl_graph_users=>sap_users( s_user[] ).
    LOOP AT lt_sap INTO ls_sap WHERE active = abap_true.
      IF ls_sap-mail IS INITIAL.
        lv_no_mail = lv_no_mail + 1.
      ELSE.
        lv_compared = lv_compared + 1.
      ENDIF.
    ENDLOOP.
    " All users of the company, read once
    lt_entra = io_users->find( ).
    lt_findings = lcl_graph_users=>compare( it_sap = lt_sap it_entra = lt_entra ).

    lv_count = lines( lt_entra ).
    heading( iv_en = `Microsoft Entra ID users read` iv_tr = `Okunan Microsoft Entra ID kullanıcısı` iv_count = lv_count ).
    heading( iv_en = `Active SAP dialog users compared` iv_tr = `Karşılaştırılan aktif SAP diyalog kullanıcısı` iv_count = lv_compared ).
    heading( iv_en = `Active SAP dialog users without an e-mail address (not compared)`
             iv_tr = `E-posta adresi olmayan aktif SAP diyalog kullanıcısı (karşılaştırılmadı)` iv_count = lv_no_mail ).
    lv_count = lines( lt_findings ).
    heading( iv_en = `Findings` iv_tr = `Bulgular` iv_count = lv_count ).
    LOOP AT lt_findings INTO ls_finding.
      IF ls_finding-finding = `missing`.
        lv_text = lcl_text=>get( iv_en = `no Microsoft account` iv_tr = `Microsoft hesabı yok` ).
      ELSE.
        lv_text = lcl_text=>get( iv_en = `Microsoft account disabled` iv_tr = `Microsoft hesabı kapalı` ).
      ENDIF.
      lv_bname = ls_finding-bname.
      CONCATENATE lv_bname ls_finding-mail lv_text ls_finding-display_name INTO lv_text SEPARATED BY ` | `.
      WRITE: / lv_text.
    ENDLOOP.
  ENDMETHOD.


  METHOD run.
    DATA lo_users TYPE REF TO lcl_graph_users.
    DATA lt_users TYPE lif_graph_users=>ty_users.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.

    CREATE OBJECT lo_users
      EXPORTING
        io_client = io_client.

    IF r_user = abap_true.
      lv_value = p_user.
      lv_value = lcl_graph_conv=>trim( lv_value ).
      show_user( io_users = lo_users iv_user = lv_value ).

    ELSEIF r_find = abap_true.
      lv_value = p_filter.
      lv_value = lcl_graph_conv=>trim( lv_value ).
      lt_users = lo_users->find( iv_filter = lv_value iv_max = p_max ).
      lv_count = lines( lt_users ).
      heading( iv_en = `Users` iv_tr = `Kullanıcılar` iv_count = lv_count ).
      show_users( lt_users ).

    ELSEIF r_group = abap_true.
      lv_value = p_group.
      lv_value = lcl_graph_conv=>trim( lv_value ).
      lt_users = lo_users->members( iv_group = lv_value iv_nested = p_nested ).
      lv_count = lines( lt_users ).
      heading( iv_en = `Members` iv_tr = `Üyeler` iv_count = lv_count ).
      show_users( lt_users ).

    ELSE.
      check_sap( lo_users ).
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
