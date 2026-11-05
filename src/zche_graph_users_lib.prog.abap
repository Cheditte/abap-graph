*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_USERS_LIB: users and groups of Microsoft Entra ID through
*& Microsoft Graph (INCLUDE)
*& abap-graph 0.7.2, https://github.com/Cheditte/abap-graph
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create program ZCHE_GRAPH_USERS_LIB with type "Include
*& program", paste this source, save. It needs ZCHE_GRAPH_CORE:
*&   INCLUDE zche_graph_core.
*&   INCLUDE zche_graph_users_lib.
*& Written in ABAP 7.00 syntax, so it also runs on older releases.
*&
*& The people of the company as Microsoft knows them (read only):
*&   - a user by e-mail address, user principal name or ID
*&   - users by an OData filter, for example department eq 'Finance'
*&   - the manager and the direct reports of a user
*&   - the groups of a user, the members of a group
*&   - SAP users whose Microsoft account is disabled or missing
*&
*& Application permissions (Microsoft Entra ID, with admin consent):
*& User.Read.All, and GroupMember.Read.All for groups.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
INTERFACE lif_graph_users.
  TYPES:
    BEGIN OF ty_user,
      id                  TYPE string,
      user_principal_name TYPE string,
      display_name        TYPE string,
      given_name          TYPE string,
      surname             TYPE string,
      mail                TYPE string,
      job_title           TYPE string,
      department          TYPE string,
      office_location     TYPE string,
      mobile_phone        TYPE string,
      employee_id         TYPE string,
      company_name        TYPE string,
      account_enabled     TYPE abap_bool,
    END OF ty_user,
    ty_users TYPE STANDARD TABLE OF ty_user WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_group,
      id           TYPE string,
      display_name TYPE string,
      mail         TYPE string,
    END OF ty_group,
    ty_groups TYPE STANDARD TABLE OF ty_group WITH DEFAULT KEY.

  " An SAP user with the e-mail address of its user master (SU01)
  TYPES:
    BEGIN OF ty_sap_user,
      bname  TYPE xubname,
      mail   TYPE string,
      active TYPE abap_bool,
    END OF ty_sap_user,
    ty_sap_users TYPE STANDARD TABLE OF ty_sap_user WITH DEFAULT KEY.

  " FINDING: missing (no Microsoft account with this address) or disabled
  TYPES:
    BEGIN OF ty_finding,
      bname        TYPE xubname,
      mail         TYPE string,
      finding      TYPE string,
      display_name TYPE string,
    END OF ty_finding,
    ty_findings TYPE STANDARD TABLE OF ty_finding WITH DEFAULT KEY.

  TYPES ty_bname_range TYPE RANGE OF xubname.
ENDINTERFACE.


*----------------------------------------------------------------------*
* Users and groups
*----------------------------------------------------------------------*
CLASS lcl_graph_users DEFINITION FINAL.
  PUBLIC SECTION.
    "! The properties read for every user
    CONSTANTS user_select TYPE string VALUE `id,userPrincipalName,displayName,givenName,surname,mail,jobTitle,department,officeLocation,mobilePhone,employeeId,companyName,accountEnabled`.

    METHODS constructor
      IMPORTING
        io_client TYPE REF TO lcl_graph_client.

    "! IV_USER: user principal name, e-mail address or ID.
    "! An e-mail address that is not also the user principal name is looked up.
    METHODS user
      IMPORTING
        iv_user        TYPE string
      RETURNING
        value(rs_user) TYPE lif_graph_users=>ty_user
      RAISING
        lcx_graph.

    "! IV_FILTER: an OData filter, for example
    "!   department eq 'Finance'      startswith(displayName,'Ay')
    "!   employeeId eq '00001234'      accountEnabled eq false
    "! Empty: all users of the company.
    METHODS find
      IMPORTING
        iv_filter       TYPE string OPTIONAL
        iv_max          TYPE i DEFAULT 100000
      RETURNING
        value(rt_users) TYPE lif_graph_users=>ty_users
      RAISING
        lcx_graph.

    "! Empty when the user has no manager
    METHODS manager
      IMPORTING
        iv_user        TYPE string
      RETURNING
        value(rs_user) TYPE lif_graph_users=>ty_user
      RAISING
        lcx_graph.

    METHODS direct_reports
      IMPORTING
        iv_user         TYPE string
      RETURNING
        value(rt_users) TYPE lif_graph_users=>ty_users
      RAISING
        lcx_graph.

    "! IV_NESTED = X: also the groups the user belongs to through other groups
    METHODS groups_of
      IMPORTING
        iv_user          TYPE string
        iv_nested        TYPE abap_bool DEFAULT abap_false
      RETURNING
        value(rt_groups) TYPE lif_graph_users=>ty_groups
      RAISING
        lcx_graph.

    "! IV_GROUP: the group's name as shown, or its ID
    METHODS group
      IMPORTING
        iv_group        TYPE string
      RETURNING
        value(rs_group) TYPE lif_graph_users=>ty_group
      RAISING
        lcx_graph.

    "! The users in a group (IV_GROUP: name or ID). IV_NESTED = X: also the
    "! users of the groups inside it
    METHODS members
      IMPORTING
        iv_group        TYPE string
        iv_nested       TYPE abap_bool DEFAULT abap_false
      RETURNING
        value(rt_users) TYPE lif_graph_users=>ty_users
      RAISING
        lcx_graph.

    "! Dialog users of this SAP system with the e-mail address of their user
    "! master. ACTIVE = X: not locked and valid today.
    CLASS-METHODS sap_users
      IMPORTING
        it_bname        TYPE lif_graph_users=>ty_bname_range OPTIONAL
      RETURNING
        value(rt_users) TYPE lif_graph_users=>ty_sap_users.

    "! Active SAP users whose address has no Microsoft account (missing) or
    "! a disabled one. The address is compared with mail and user principal
    "! name, without regard to case. SAP users without an address are skipped.
    CLASS-METHODS compare
      IMPORTING
        it_sap             TYPE lif_graph_users=>ty_sap_users
        it_entra           TYPE lif_graph_users=>ty_users
      RETURNING
        value(rt_findings) TYPE lif_graph_users=>ty_findings.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO lcl_graph_client.

    METHODS user_path
      IMPORTING
        iv_user        TYPE string
        iv_rest        TYPE string OPTIONAL
      RETURNING
        value(rv_path) TYPE string.

    METHODS read_users
      IMPORTING
        iv_path         TYPE string
        iv_max          TYPE i DEFAULT 100000
      RETURNING
        value(rt_users) TYPE lif_graph_users=>ty_users
      RAISING
        lcx_graph.

    CLASS-METHODS user_from_json
      IMPORTING
        io_json        TYPE REF TO lcl_graph_json
        iv_prefix      TYPE string
      RETURNING
        value(rs_user) TYPE lif_graph_users=>ty_user.

    CLASS-METHODS group_from_json
      IMPORTING
        io_json         TYPE REF TO lcl_graph_json
        iv_prefix       TYPE string
      RETURNING
        value(rs_group) TYPE lif_graph_users=>ty_group.

    CLASS-METHODS is_guid
      IMPORTING
        iv_text        TYPE string
      RETURNING
        value(rv_guid) TYPE abap_bool.

    CLASS-METHODS quote
      IMPORTING
        iv_value       TYPE string
      RETURNING
        value(rv_text) TYPE string.
ENDCLASS.


CLASS lcl_graph_users IMPLEMENTATION.

  METHOD constructor.
    mo_client = io_client.
  ENDMETHOD.


  METHOD user_path.
    DATA lv_user TYPE string.
    lv_user = iv_user.
    lv_user = lcl_graph_conv=>trim( lv_user ).
    lv_user = lcl_graph_conv=>url_encode( lv_user ).
    CONCATENATE `/users/` lv_user iv_rest INTO rv_path.
  ENDMETHOD.


  METHOD quote.
    " A value in an OData filter: in single quotes, a quote inside doubled
    rv_text = iv_value.
    rv_text = lcl_graph_conv=>trim( rv_text ).
    REPLACE ALL OCCURRENCES OF `'` IN rv_text WITH `''`.
    CONCATENATE `'` rv_text `'` INTO rv_text.
  ENDMETHOD.


  METHOD is_guid.
    DATA lv_text TYPE string.
    lv_text = iv_text.
    CONDENSE lv_text.
    TRANSLATE lv_text TO LOWER CASE.
    IF strlen( lv_text ) = 36 AND lv_text CO '0123456789abcdef-'
       AND lv_text+8(1) = '-' AND lv_text+13(1) = '-'.
      rv_guid = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD user_from_json.
    DATA lv_field TYPE string.
    DATA lv_value TYPE string.

    CONCATENATE iv_prefix `id` INTO lv_field.
    rs_user-id = io_json->get( lv_field ).
    CONCATENATE iv_prefix `userPrincipalName` INTO lv_field.
    rs_user-user_principal_name = io_json->get( lv_field ).
    CONCATENATE iv_prefix `displayName` INTO lv_field.
    rs_user-display_name = io_json->get( lv_field ).
    CONCATENATE iv_prefix `givenName` INTO lv_field.
    rs_user-given_name = io_json->get( lv_field ).
    CONCATENATE iv_prefix `surname` INTO lv_field.
    rs_user-surname = io_json->get( lv_field ).
    CONCATENATE iv_prefix `mail` INTO lv_field.
    rs_user-mail = io_json->get( lv_field ).
    CONCATENATE iv_prefix `jobTitle` INTO lv_field.
    rs_user-job_title = io_json->get( lv_field ).
    CONCATENATE iv_prefix `department` INTO lv_field.
    rs_user-department = io_json->get( lv_field ).
    CONCATENATE iv_prefix `officeLocation` INTO lv_field.
    rs_user-office_location = io_json->get( lv_field ).
    CONCATENATE iv_prefix `mobilePhone` INTO lv_field.
    rs_user-mobile_phone = io_json->get( lv_field ).
    CONCATENATE iv_prefix `employeeId` INTO lv_field.
    rs_user-employee_id = io_json->get( lv_field ).
    CONCATENATE iv_prefix `companyName` INTO lv_field.
    rs_user-company_name = io_json->get( lv_field ).
    CONCATENATE iv_prefix `accountEnabled` INTO lv_field.
    lv_value = io_json->get( lv_field ).
    IF lv_value = `true`.
      rs_user-account_enabled = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD group_from_json.
    DATA lv_field TYPE string.
    CONCATENATE iv_prefix `id` INTO lv_field.
    rs_group-id = io_json->get( lv_field ).
    CONCATENATE iv_prefix `displayName` INTO lv_field.
    rs_group-display_name = io_json->get( lv_field ).
    CONCATENATE iv_prefix `mail` INTO lv_field.
    rs_group-mail = io_json->get( lv_field ).
  ENDMETHOD.


  METHOD read_users.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_field TYPE string.
    DATA lv_type TYPE string.
    DATA lv_lines TYPE i.
    DATA lv_max_pages TYPE i.

    IF iv_max <= 0.
      RETURN.
    ENDIF.
    " 999 users per page
    lv_max_pages = iv_max DIV 999 + 2.
    lt_pages = mo_client->get_pages( iv_path = iv_path iv_max_pages = lv_max_pages iv_max_items = iv_max ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        " Members and reports may also be groups, devices or contacts
        CONCATENATE lv_prefix `@odata.type` INTO lv_field.
        lv_type = lo_page->get( lv_field ).
        IF lv_type IS NOT INITIAL AND lv_type <> `#microsoft.graph.user`.
          CONTINUE.
        ENDIF.
        ls_user = user_from_json( io_json = lo_page iv_prefix = lv_prefix ).
        APPEND ls_user TO rt_users.
        lv_lines = lines( rt_users ).
        IF lv_lines >= iv_max.
          RETURN.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD user.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lt_users TYPE lif_graph_users=>ty_users.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.
    DATA lv_filter TYPE string.
    DATA lv_value TYPE string.
    DATA lv_text TYPE string.

    CONCATENATE `?$select=` user_select INTO lv_rest.
    lv_path = user_path( iv_user = iv_user iv_rest = lv_rest ).
    TRY.
        lo_json = mo_client->get_json( lv_path ).
        rs_user = user_from_json( io_json = lo_json iv_prefix = `` ).
        RETURN.
      CATCH lcx_graph INTO lx_graph.
        IF lx_graph->http_status <> 404 OR iv_user NA '@'.
          RAISE EXCEPTION lx_graph.
        ENDIF.
    ENDTRY.
    " The address is not a user principal name: look for it as mail
    lv_value = quote( iv_user ).
    CONCATENATE `mail eq ` lv_value INTO lv_filter.
    lt_users = find( iv_filter = lv_filter iv_max = 2 ).
    IF lines( lt_users ) = 1.
      READ TABLE lt_users INDEX 1 INTO rs_user.
      RETURN.
    ENDIF.
    IF lt_users IS INITIAL.
      CONCATENATE `Microsoft Entra ID has no user ` iv_user `.` INTO lv_text.
    ELSE.
      CONCATENATE `More than one user has the address ` iv_user `.` INTO lv_text.
    ENDIF.
    RAISE EXCEPTION TYPE lcx_graph
      EXPORTING
        text        = lv_text
        hint        = `Check the address, or use the user principal name or the user ID.`
        http_status = 404.
  ENDMETHOD.


  METHOD find.
    DATA lv_path TYPE string.
    DATA lv_filter TYPE string.

    CONCATENATE `/users?$top=999&$select=` user_select INTO lv_path.
    IF iv_filter IS NOT INITIAL.
      lv_filter = lcl_graph_conv=>url_encode( iv_filter ).
      CONCATENATE lv_path `&$filter=` lv_filter INTO lv_path.
    ENDIF.
    rt_users = read_users( iv_path = lv_path iv_max = iv_max ).
  ENDMETHOD.


  METHOD manager.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lx_graph TYPE REF TO lcx_graph.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.

    " Through the ID, so that an address that is only a mail also works
    ls_user = user( iv_user ).
    CONCATENATE `/manager?$select=` user_select INTO lv_rest.
    lv_path = user_path( iv_user = ls_user-id iv_rest = lv_rest ).
    TRY.
        lo_json = mo_client->get_json( lv_path ).
      CATCH lcx_graph INTO lx_graph.
        " Microsoft answers 404 when no manager is set
        IF lx_graph->http_status = 404.
          RETURN.
        ENDIF.
        RAISE EXCEPTION lx_graph.
    ENDTRY.
    rs_user = user_from_json( io_json = lo_json iv_prefix = `` ).
  ENDMETHOD.


  METHOD direct_reports.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.

    ls_user = user( iv_user ).
    CONCATENATE `/directReports?$top=999&$select=` user_select INTO lv_rest.
    lv_path = user_path( iv_user = ls_user-id iv_rest = lv_rest ).
    rt_users = read_users( lv_path ).
  ENDMETHOD.


  METHOD groups_of.
    DATA lt_pages TYPE lcl_graph_client=>ty_pages.
    DATA lo_page TYPE REF TO lcl_graph_json.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA ls_group TYPE lif_graph_users=>ty_group.
    DATA lv_rest TYPE string.
    DATA lv_path TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.
    DATA lv_number TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_field TYPE string.
    DATA lv_type TYPE string.

    ls_user = user( iv_user ).
    IF iv_nested = abap_true.
      lv_rest = `/transitiveMemberOf?$top=999&$select=id,displayName,mail`.
    ELSE.
      lv_rest = `/memberOf?$top=999&$select=id,displayName,mail`.
    ENDIF.
    lv_path = user_path( iv_user = ls_user-id iv_rest = lv_rest ).
    lt_pages = mo_client->get_pages( lv_path ).
    LOOP AT lt_pages INTO lo_page.
      lv_count = lo_page->count( `value` ).
      DO lv_count TIMES.
        lv_index = sy-index - 1.
        lv_number = lcl_graph_conv=>num( lv_index ).
        CONCATENATE `value/` lv_number `/` INTO lv_prefix.
        " Directory roles and administrative units come in the same answer
        CONCATENATE lv_prefix `@odata.type` INTO lv_field.
        lv_type = lo_page->get( lv_field ).
        IF lv_type <> `#microsoft.graph.group`.
          CONTINUE.
        ENDIF.
        ls_group = group_from_json( io_json = lo_page iv_prefix = lv_prefix ).
        APPEND ls_group TO rt_groups.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD group.
    DATA lo_json TYPE REF TO lcl_graph_json.
    DATA lv_group TYPE string.
    DATA lv_path TYPE string.
    DATA lv_filter TYPE string.
    DATA lv_text TYPE string.
    DATA lv_count TYPE i.
    DATA lv_guid TYPE abap_bool.

    lv_group = iv_group.
    lv_group = lcl_graph_conv=>trim( lv_group ).
    lv_guid = is_guid( lv_group ).
    IF lv_guid = abap_true.
      CONCATENATE `/groups/` lv_group `?$select=id,displayName,mail` INTO lv_path.
      lo_json = mo_client->get_json( lv_path ).
      rs_group = group_from_json( io_json = lo_json iv_prefix = `` ).
      RETURN.
    ENDIF.
    lv_filter = quote( lv_group ).
    CONCATENATE `displayName eq ` lv_filter INTO lv_filter.
    lv_filter = lcl_graph_conv=>url_encode( lv_filter ).
    CONCATENATE `/groups?$select=id,displayName,mail&$filter=` lv_filter INTO lv_path.
    lo_json = mo_client->get_json( lv_path ).
    lv_count = lo_json->count( `value` ).
    IF lv_count = 1.
      rs_group = group_from_json( io_json = lo_json iv_prefix = `value/0/` ).
      RETURN.
    ENDIF.
    IF lv_count = 0.
      CONCATENATE `Microsoft Entra ID has no group named "` lv_group `".` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_graph
        EXPORTING
          text = lv_text
          hint = `Use the group's name exactly as Entra ID or Outlook shows it, or its object ID.`.
    ENDIF.
    CONCATENATE `More than one group is named "` lv_group `".` INTO lv_text.
    RAISE EXCEPTION TYPE lcx_graph
      EXPORTING
        text = lv_text
        hint = `Use the group's object ID instead of its name.`.
  ENDMETHOD.


  METHOD members.
    DATA ls_group TYPE lif_graph_users=>ty_group.
    DATA lv_path TYPE string.
    DATA lv_kind TYPE string.

    ls_group = group( iv_group ).
    IF iv_nested = abap_true.
      lv_kind = `/transitiveMembers`.
    ELSE.
      lv_kind = `/members`.
    ENDIF.
    CONCATENATE `/groups/` ls_group-id lv_kind `?$top=999&$select=` user_select INTO lv_path.
    rt_users = read_users( lv_path ).
  ENDMETHOD.


  METHOD sap_users.
    TYPES:
      BEGIN OF lty_row,
        bname      TYPE usr02-bname,
        uflag      TYPE usr02-uflag,
        gltgv      TYPE usr02-gltgv,
        gltgb      TYPE usr02-gltgb,
        flgdefault TYPE adr6-flgdefault,
        smtp_addr  TYPE adr6-smtp_addr,
      END OF lty_row.
    DATA lt_rows TYPE STANDARD TABLE OF lty_row WITH DEFAULT KEY.
    DATA ls_row TYPE lty_row.
    DATA ls_user TYPE lif_graph_users=>ty_sap_user.

    " Dialog users; the address comes from the user's address in SU01
    SELECT u~bname u~uflag u~gltgv u~gltgb a~flgdefault a~smtp_addr
      FROM usr02 AS u
      INNER JOIN usr21 AS r ON r~bname = u~bname
      LEFT OUTER JOIN adr6 AS a ON a~addrnumber = r~addrnumber
                               AND a~persnumber = r~persnumber
      INTO TABLE lt_rows
      WHERE u~bname IN it_bname
        AND u~ustyp = 'A'.
    " The standard address first when a user has several
    SORT lt_rows BY bname ASCENDING flgdefault DESCENDING.
    DELETE ADJACENT DUPLICATES FROM lt_rows COMPARING bname.
    LOOP AT lt_rows INTO ls_row.
      CLEAR ls_user.
      ls_user-bname = ls_row-bname.
      ls_user-mail = ls_row-smtp_addr.
      IF ls_row-uflag = 0
         AND ( ls_row-gltgv IS INITIAL OR ls_row-gltgv <= sy-datum )
         AND ( ls_row-gltgb IS INITIAL OR ls_row-gltgb >= sy-datum ).
        ls_user-active = abap_true.
      ENDIF.
      APPEND ls_user TO rt_users.
    ENDLOOP.
  ENDMETHOD.


  METHOD compare.
    TYPES:
      BEGIN OF lty_address,
        address TYPE string,
        enabled TYPE abap_bool,
        name    TYPE string,
      END OF lty_address.
    DATA lt_addresses TYPE SORTED TABLE OF lty_address WITH NON-UNIQUE KEY address.
    DATA ls_address TYPE lty_address.
    DATA ls_entra TYPE lif_graph_users=>ty_user.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_user.
    DATA ls_finding TYPE lif_graph_users=>ty_finding.
    DATA lv_mail TYPE string.
    DATA lv_enabled TYPE abap_bool.

    LOOP AT it_entra INTO ls_entra.
      ls_address-enabled = ls_entra-account_enabled.
      ls_address-name = ls_entra-display_name.
      lv_mail = ls_entra-mail.
      TRANSLATE lv_mail TO LOWER CASE.
      IF lv_mail IS NOT INITIAL.
        ls_address-address = lv_mail.
        INSERT ls_address INTO TABLE lt_addresses.
      ENDIF.
      ls_address-address = ls_entra-user_principal_name.
      TRANSLATE ls_address-address TO LOWER CASE.
      IF ls_address-address IS NOT INITIAL AND ls_address-address <> lv_mail.
        INSERT ls_address INTO TABLE lt_addresses.
      ENDIF.
    ENDLOOP.

    LOOP AT it_sap INTO ls_sap WHERE active = abap_true.
      lv_mail = ls_sap-mail.
      CONDENSE lv_mail.
      TRANSLATE lv_mail TO LOWER CASE.
      IF lv_mail IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_finding.
      ls_finding-bname = ls_sap-bname.
      ls_finding-mail = lv_mail.
      " One enabled account with the address is enough
      CLEAR: lv_enabled, ls_address.
      LOOP AT lt_addresses INTO ls_address WHERE address = lv_mail.
        ls_finding-display_name = ls_address-name.
        IF ls_address-enabled = abap_true.
          lv_enabled = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF sy-subrc <> 0.
        ls_finding-finding = `missing`.
        APPEND ls_finding TO rt_findings.
      ELSEIF lv_enabled = abap_false.
        ls_finding-finding = `disabled`.
        APPEND ls_finding TO rt_findings.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests for users and groups. A test double from ZCHE_GRAPH_CORE
*& answers instead of Microsoft; nothing leaves the system.
*&---------------------------------------------------------------------*
CLASS ltc_graph_users DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    CLASS-DATA gv_tests TYPE i.
    DATA mo_http TYPE REF TO ltd_graph_http.
    DATA mo_client TYPE REF TO lcl_graph_client.
    DATA mo_cut TYPE REF TO lcl_graph_users.

    METHODS setup.
    METHODS user_by_name FOR TESTING RAISING lcx_graph.
    METHODS user_by_mail FOR TESTING RAISING lcx_graph.
    METHODS find_with_filter FOR TESTING RAISING lcx_graph.
    METHODS no_manager FOR TESTING RAISING lcx_graph.
    METHODS groups_only FOR TESTING RAISING lcx_graph.
    METHODS members_by_name FOR TESTING RAISING lcx_graph.
    METHODS group_not_found FOR TESTING.
    METHODS compare_sap FOR TESTING.

    METHODS request_at
      IMPORTING
        iv_index          TYPE i
      RETURNING
        value(rs_request) TYPE ltd_graph_http=>ty_request.
ENDCLASS.


CLASS ltc_graph_users IMPLEMENTATION.

  METHOD setup.
    DATA ls_config TYPE lif_graph=>ty_config.
    DATA lv_number TYPE string.
    DATA lv_tenant TYPE string.

    CREATE OBJECT mo_http.
    gv_tests = gv_tests + 1.
    lv_number = lcl_graph_conv=>num( gv_tests ).
    CONCATENATE `users` lv_number `.onmicrosoft.com` INTO lv_tenant.
    ls_config = lcl_graph_client=>default_config( lv_tenant ).
    CREATE OBJECT mo_client
      EXPORTING
        is_config = ls_config
        io_http   = mo_http.
    CREATE OBJECT mo_cut
      EXPORTING
        io_client = mo_client.
    mo_http->token_answer( ).
  ENDMETHOD.


  METHOD request_at.
    READ TABLE mo_http->mt_requests INDEX iv_index INTO rs_request.
  ENDMETHOD.


  METHOD user_by_name.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_json TYPE string.

    CONCATENATE `{"id":"U1","userPrincipalName":"derya@contoso.com","displayName":"Derya Kaya",`
                `"department":"Muhasebe","employeeId":"00001234","accountEnabled":false}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    ls_user = mo_cut->user( ` derya@contoso.com ` ).
    cl_aunit_assert=>assert_equals( act = ls_user-id exp = `U1` ).
    cl_aunit_assert=>assert_equals( act = ls_user-department exp = `Muhasebe` ).
    cl_aunit_assert=>assert_equals( act = ls_user-employee_id exp = `00001234` ).
    cl_aunit_assert=>assert_equals( act = ls_user-account_enabled exp = abap_false ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/users/derya*contoso.com?$select=id,userPrincipalName,*accountEnabled' ).
  ENDMETHOD.


  METHOD user_by_mail.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 404 iv_body = `{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"U2","mail":"d.kaya@contoso.com","accountEnabled":true}]}` ).
    ls_user = mo_cut->user( `d.kaya@contoso.com` ).
    cl_aunit_assert=>assert_equals( act = ls_user-id exp = `U2` ).
    cl_aunit_assert=>assert_equals( act = ls_user-account_enabled exp = abap_true ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/users?$top=999&$select=*&$filter=mail*eq*d.kaya*' ).
  ENDMETHOD.


  METHOD find_with_filter.
    DATA lt_users TYPE lif_graph_users=>ty_users.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_count TYPE i.

    mo_http->answer( iv_status = 200
                     iv_body   = `{"value":[{"id":"U1"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?$skiptoken=X"}` ).
    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"U2"},{"id":"U3"}]}` ).
    lt_users = mo_cut->find( iv_filter = `department eq 'O''Brien'` ).
    lv_count = lines( lt_users ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '*&$filter=department*eq*O*Brien*' ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_equals( act = ls_request-uri exp = `/v1.0/users?$skiptoken=X` ).
  ENDMETHOD.


  METHOD no_manager.
    DATA ls_user TYPE lif_graph_users=>ty_user.
    DATA ls_request TYPE ltd_graph_http=>ty_request.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"U1","userPrincipalName":"derya@contoso.com"}` ).
    mo_http->answer( iv_status = 404 iv_body = `{"error":{"code":"Request_ResourceNotFound","message":"Resource 'manager' does not exist."}}` ).
    ls_user = mo_cut->manager( `derya@contoso.com` ).
    cl_aunit_assert=>assert_initial( act = ls_user ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/users/U1/manager?$select=*' ).
  ENDMETHOD.


  METHOD groups_only.
    DATA lt_groups TYPE lif_graph_users=>ty_groups.
    DATA ls_group TYPE lif_graph_users=>ty_group.
    DATA lv_json TYPE string.
    DATA lv_count TYPE i.

    mo_http->answer( iv_status = 200 iv_body = `{"id":"U1"}` ).
    CONCATENATE `{"value":[{"@odata.type":"#microsoft.graph.directoryRole","id":"R1","displayName":"Global Reader"},`
                `{"@odata.type":"#microsoft.graph.group","id":"G1","displayName":"SAP Onaycılar","mail":"onay@contoso.com"}]}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    lt_groups = mo_cut->groups_of( `U1` ).
    lv_count = lines( lt_groups ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    READ TABLE lt_groups INDEX 1 INTO ls_group.
    cl_aunit_assert=>assert_equals( act = ls_group-display_name exp = `SAP Onaycılar` ).
  ENDMETHOD.


  METHOD members_by_name.
    DATA lt_users TYPE lif_graph_users=>ty_users.
    DATA ls_request TYPE ltd_graph_http=>ty_request.
    DATA lv_json TYPE string.
    DATA lv_count TYPE i.

    mo_http->answer( iv_status = 200 iv_body = `{"value":[{"id":"G1","displayName":"SAP Onaycılar"}]}` ).
    CONCATENATE `{"value":[{"@odata.type":"#microsoft.graph.user","id":"U1","mail":"a@contoso.com"},`
                `{"@odata.type":"#microsoft.graph.group","id":"G2","displayName":"Alt grup"},`
                `{"@odata.type":"#microsoft.graph.user","id":"U2","mail":"b@contoso.com"}]}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    lt_users = mo_cut->members( iv_group = `SAP Onaycılar` iv_nested = abap_true ).
    lv_count = lines( lt_users ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    ls_request = request_at( 2 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/groups?$select=id,displayName,mail&$filter=displayName*eq*' ).
    ls_request = request_at( 3 ).
    cl_aunit_assert=>assert_char_cp( act = ls_request-uri exp = '/v1.0/groups/G1/transitiveMembers?$top=999&$select=*' ).
  ENDMETHOD.


  METHOD group_not_found.
    DATA lx_graph TYPE REF TO lcx_graph.

    mo_http->answer( iv_status = 200 iv_body = `{"value":[]}` ).
    TRY.
        mo_cut->group( `Yok` ).
      CATCH lcx_graph INTO lx_graph.
    ENDTRY.
    cl_aunit_assert=>assert_bound( act = lx_graph msg = `no error raised` ).
    cl_aunit_assert=>assert_char_cp( act = lx_graph->text exp = '*no group named*Yok*' ).
  ENDMETHOD.


  METHOD compare_sap.
    DATA lt_sap TYPE lif_graph_users=>ty_sap_users.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_user.
    DATA lt_entra TYPE lif_graph_users=>ty_users.
    DATA ls_entra TYPE lif_graph_users=>ty_user.
    DATA lt_findings TYPE lif_graph_users=>ty_findings.
    DATA ls_finding TYPE lif_graph_users=>ty_finding.
    DATA lv_count TYPE i.

    ls_entra-mail = `Derya@Contoso.com`.
    ls_entra-account_enabled = abap_true.
    APPEND ls_entra TO lt_entra.
    CLEAR ls_entra.
    ls_entra-user_principal_name = `ayse@contoso.com`.
    ls_entra-display_name = `Ayşe Yılmaz`.
    ls_entra-account_enabled = abap_false.
    APPEND ls_entra TO lt_entra.

    " Enabled through the mail, case ignored: no finding
    ls_sap-bname = 'DKAYA'.
    ls_sap-mail = `derya@contoso.com`.
    ls_sap-active = abap_true.
    APPEND ls_sap TO lt_sap.
    " Disabled, found through the user principal name
    ls_sap-bname = 'AYILMAZ'.
    ls_sap-mail = `AYSE@contoso.com`.
    APPEND ls_sap TO lt_sap.
    " No Microsoft account
    ls_sap-bname = 'MOZTURK'.
    ls_sap-mail = `mehmet@contoso.com`.
    APPEND ls_sap TO lt_sap.
    " No address, or locked in SAP: not compared
    ls_sap-bname = 'BATCH'.
    CLEAR ls_sap-mail.
    APPEND ls_sap TO lt_sap.
    ls_sap-bname = 'OLD'.
    ls_sap-mail = `old@contoso.com`.
    ls_sap-active = abap_false.
    APPEND ls_sap TO lt_sap.

    lt_findings = lcl_graph_users=>compare( it_sap = lt_sap it_entra = lt_entra ).
    lv_count = lines( lt_findings ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 2 ).
    READ TABLE lt_findings INTO ls_finding WITH KEY bname = 'AYILMAZ'.
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `disabled` ).
    cl_aunit_assert=>assert_equals( act = ls_finding-display_name exp = `Ayşe Yılmaz` ).
    READ TABLE lt_findings INTO ls_finding WITH KEY bname = 'MOZTURK'.
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `missing` ).
  ENDMETHOD.

ENDCLASS.
