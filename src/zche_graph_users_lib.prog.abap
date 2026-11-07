*&---------------------------------------------------------------------*
*& ZCHE_GRAPH_USERS_LIB: users and groups of Microsoft Entra ID through
*& Microsoft Graph (INCLUDE)
*& abap-graph 0.8.0, https://github.com/Cheditte/abap-graph
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
*&   - SAP users whose Microsoft account is disabled or missing, and
*&     SAP users locked in SAP whose Microsoft account is still enabled
*&   - a group against the users of an SAP role
*&   - name, department, job title and telephone in SU01 against Entra ID
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
      " The first of businessPhones
      business_phone      TYPE string,
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

  " FINDING: missing (no Microsoft account with this address), disabled, or
  " locked_open (locked or not valid in SAP, Microsoft account enabled; only
  " when asked for)
  TYPES:
    BEGIN OF ty_finding,
      bname        TYPE xubname,
      mail         TYPE string,
      finding      TYPE string,
      display_name TYPE string,
    END OF ty_finding,
    ty_findings TYPE STANDARD TABLE OF ty_finding WITH DEFAULT KEY.

  TYPES ty_bname_range TYPE RANGE OF xubname.
  TYPES ty_bnames TYPE STANDARD TABLE OF xubname WITH DEFAULT KEY.

  " Group and role check. FINDING: no_role (in the group, the SAP user lacks
  " the role), extra_role (has the role, not in the group), no_sap_user (in
  " the group, no SAP user has the address), sap_locked (in the group, the
  " SAP user with the address is locked or not valid), no_mail (has the
  " role, no address in SU01, not compared)
  TYPES:
    BEGIN OF ty_role_finding,
      bname        TYPE xubname,
      mail         TYPE string,
      finding      TYPE string,
      display_name TYPE string,
    END OF ty_role_finding,
    ty_role_findings TYPE STANDARD TABLE OF ty_role_finding WITH DEFAULT KEY.

  " The user master data (SU01) that Microsoft Entra ID also holds
  TYPES:
    BEGIN OF ty_sap_detail,
      bname      TYPE xubname,
      mail       TYPE string,
      first_name TYPE string,
      last_name  TYPE string,
      department TYPE string,
      job_title  TYPE string,
      phone      TYPE string,
    END OF ty_sap_detail,
    ty_sap_details TYPE STANDARD TABLE OF ty_sap_detail WITH DEFAULT KEY.

  " FIELD: first_name, last_name, department, job_title or phone
  TYPES:
    BEGIN OF ty_difference,
      bname       TYPE xubname,
      mail        TYPE string,
      field       TYPE string,
      sap_value   TYPE string,
      entra_value TYPE string,
    END OF ty_difference,
    ty_differences TYPE STANDARD TABLE OF ty_difference WITH DEFAULT KEY.
ENDINTERFACE.


*----------------------------------------------------------------------*
* Users and groups
*----------------------------------------------------------------------*
CLASS lcl_graph_users DEFINITION FINAL.
  PUBLIC SECTION.
    "! The properties read for every user
    CONSTANTS user_select TYPE string VALUE `id,userPrincipalName,displayName,givenName,surname,mail,jobTitle,department,officeLocation,mobilePhone,employeeId,companyName,businessPhones,accountEnabled`.

    "! SAP users the last SAP_USERS or SAP_DETAILS call left out because the
    "! caller may not display them; the reports print the number
    CLASS-DATA skipped TYPE i READ-ONLY.

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
    "! master. ACTIVE = X: not locked and valid today. Users whose user group
    "! the caller may not display (S_USER_GRP, activity 03) are left out.
    CLASS-METHODS sap_users
      IMPORTING
        it_bname        TYPE lif_graph_users=>ty_bname_range OPTIONAL
      RETURNING
        value(rt_users) TYPE lif_graph_users=>ty_sap_users.

    "! Active SAP users whose address has no Microsoft account (missing) or
    "! a disabled one. The address is compared with mail and user principal
    "! name, without regard to case. SAP users without an address are skipped.
    "! IV_REVERSE: also SAP users that are locked or not valid while an
    "! enabled Microsoft account has their address (locked_open).
    CLASS-METHODS compare
      IMPORTING
        it_sap             TYPE lif_graph_users=>ty_sap_users
        it_entra           TYPE lif_graph_users=>ty_users
        iv_reverse         TYPE abap_bool DEFAULT abap_false
      RETURNING
        value(rt_findings) TYPE lif_graph_users=>ty_findings.

    "! SAP users that hold the role today (AGR_USERS, also through a
    "! composite role)
    CLASS-METHODS role_users
      IMPORTING
        iv_role          TYPE agr_name
      RETURNING
        value(rt_bnames) TYPE lif_graph_users=>ty_bnames.

    "! Group members against the users of an SAP role. People are matched by
    "! address (mail or user principal name, case ignored); only enabled
    "! accounts count as members. A member whose SAP user is locked or not
    "! valid is reported as such; only active SAP users need the group.
    CLASS-METHODS compare_role
      IMPORTING
        it_members         TYPE lif_graph_users=>ty_users
        it_sap             TYPE lif_graph_users=>ty_sap_users
        it_role            TYPE lif_graph_users=>ty_bnames
      RETURNING
        value(rt_findings) TYPE lif_graph_users=>ty_role_findings.

    "! Name, department, job title and telephone from SU01 for the active dialog users
    "! with an address. Read with BAPI_USER_GET_DETAIL, so its authority
    "! check applies; users it refuses are left out.
    CLASS-METHODS sap_details
      IMPORTING
        it_bname          TYPE lif_graph_users=>ty_bname_range OPTIONAL
      RETURNING
        value(rt_details) TYPE lif_graph_users=>ty_sap_details.

    "! Fields where SU01 differs from Microsoft Entra ID. Blanks and case are
    "! ignored; an empty value in Entra ID is never proposed for SAP. The SU01
    "! telephone is compared with the first business phone by its last ten
    "! digits, so 0212 555 0107 equals +90 (212) 555 01 07.
    CLASS-METHODS compare_details
      IMPORTING
        it_sap                TYPE lif_graph_users=>ty_sap_details
        it_entra              TYPE lif_graph_users=>ty_users
      RETURNING
        value(rt_differences) TYPE lif_graph_users=>ty_differences.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO lcl_graph_client.

    CLASS-METHODS address_key
      IMPORTING
        iv_address    TYPE string
      RETURNING
        value(rv_key) TYPE string.

    "! The last ten digits of a telephone number
    CLASS-METHODS phone_key
      IMPORTING
        iv_phone      TYPE string
      RETURNING
        value(rv_key) TYPE string.

    CLASS-METHODS add_difference
      IMPORTING
        is_sap         TYPE lif_graph_users=>ty_sap_detail
        iv_field       TYPE string
        iv_sap         TYPE string
        iv_entra       TYPE string
      CHANGING
        ct_differences TYPE lif_graph_users=>ty_differences.

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
    CONCATENATE iv_prefix `businessPhones/0` INTO lv_field.
    rs_user-business_phone = io_json->get( lv_field ).
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
        class      TYPE usr02-class,
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
    SELECT u~bname u~class u~uflag u~gltgv u~gltgb a~flgdefault a~smtp_addr
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
    skipped = 0.
    LOOP AT lt_rows INTO ls_row.
      " Only users the caller may display in SU01 (user group, activity 03)
      AUTHORITY-CHECK OBJECT 'S_USER_GRP'
        ID 'CLASS' FIELD ls_row-class
        ID 'ACTVT' FIELD '03'.
      IF sy-subrc <> 0.
        skipped = skipped + 1.
        CONTINUE.
      ENDIF.
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

    IF iv_reverse = abap_false.
      RETURN.
    ENDIF.
    " Locked or not valid in SAP, but the Microsoft account is still enabled
    LOOP AT it_sap INTO ls_sap WHERE active = abap_false.
      lv_mail = address_key( ls_sap-mail ).
      IF lv_mail IS INITIAL.
        CONTINUE.
      ENDIF.
      LOOP AT lt_addresses INTO ls_address WHERE address = lv_mail AND enabled = abap_true.
        CLEAR ls_finding.
        ls_finding-bname = ls_sap-bname.
        ls_finding-mail = lv_mail.
        ls_finding-display_name = ls_address-name.
        ls_finding-finding = `locked_open`.
        APPEND ls_finding TO rt_findings.
        EXIT.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD address_key.
    rv_key = iv_address.
    CONDENSE rv_key NO-GAPS.
    TRANSLATE rv_key TO LOWER CASE.
  ENDMETHOD.


  METHOD phone_key.
    DATA lv_text TYPE string.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_length TYPE i.
    DATA lv_offset TYPE i.

    lv_text = iv_phone.
    lv_length = strlen( lv_text ).
    DO lv_length TIMES.
      lv_offset = sy-index - 1.
      lv_char = lv_text+lv_offset(1).
      IF lv_char CA '0123456789'.
        CONCATENATE rv_key lv_char INTO rv_key.
      ENDIF.
    ENDDO.
    " +90 212 555 01 07 and 0212 555 0107 are the same line
    lv_length = strlen( rv_key ).
    IF lv_length > 10.
      lv_offset = lv_length - 10.
      rv_key = rv_key+lv_offset(10).
    ENDIF.
  ENDMETHOD.


  METHOD role_users.
    TYPES:
      BEGIN OF lty_assignment,
        uname    TYPE agr_users-uname,
        from_dat TYPE agr_users-from_dat,
        to_dat   TYPE agr_users-to_dat,
      END OF lty_assignment.
    DATA lt_rows TYPE STANDARD TABLE OF lty_assignment WITH DEFAULT KEY.
    DATA ls_row TYPE lty_assignment.

    SELECT uname from_dat to_dat FROM agr_users INTO TABLE lt_rows
      WHERE agr_name = iv_role.
    LOOP AT lt_rows INTO ls_row
         WHERE from_dat <= sy-datum AND to_dat >= sy-datum.
      APPEND ls_row-uname TO rt_bnames.
    ENDLOOP.
    SORT rt_bnames.
    DELETE ADJACENT DUPLICATES FROM rt_bnames.
  ENDMETHOD.


  METHOD compare_role.
    TYPES:
      BEGIN OF lty_sap,
        address TYPE string,
        bname   TYPE xubname,
        active  TYPE abap_bool,
      END OF lty_sap.
    DATA lt_sap_by_address TYPE SORTED TABLE OF lty_sap WITH NON-UNIQUE KEY address.
    DATA ls_sap_address TYPE lty_sap.
    DATA lt_member_addresses TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
    DATA lt_role TYPE SORTED TABLE OF xubname WITH UNIQUE KEY table_line.
    DATA ls_member TYPE lif_graph_users=>ty_user.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_user.
    DATA ls_finding TYPE lif_graph_users=>ty_role_finding.
    DATA lv_bname TYPE xubname.
    DATA lv_mail TYPE string.
    DATA lv_upn TYPE string.
    DATA lv_found TYPE abap_bool.

    LOOP AT it_role INTO lv_bname.
      INSERT lv_bname INTO TABLE lt_role.
    ENDLOOP.
    " Locked SAP users too, so that their member is not reported as having none
    LOOP AT it_sap INTO ls_sap.
      ls_sap_address-address = address_key( ls_sap-mail ).
      IF ls_sap_address-address IS INITIAL.
        CONTINUE.
      ENDIF.
      ls_sap_address-bname = ls_sap-bname.
      ls_sap_address-active = ls_sap-active.
      INSERT ls_sap_address INTO TABLE lt_sap_by_address.
    ENDLOOP.

    " Every enabled member needs an SAP user with the role
    LOOP AT it_members INTO ls_member WHERE account_enabled = abap_true.
      lv_mail = address_key( ls_member-mail ).
      lv_upn = address_key( ls_member-user_principal_name ).
      IF lv_mail IS NOT INITIAL.
        INSERT lv_mail INTO TABLE lt_member_addresses.
      ENDIF.
      IF lv_upn IS NOT INITIAL.
        INSERT lv_upn INTO TABLE lt_member_addresses.
      ENDIF.
      CLEAR ls_finding.
      ls_finding-display_name = ls_member-display_name.
      ls_finding-mail = lv_mail.
      IF ls_finding-mail IS INITIAL.
        ls_finding-mail = lv_upn.
      ENDIF.
      lv_found = abap_false.
      LOOP AT lt_sap_by_address INTO ls_sap_address
           WHERE address = lv_mail OR address = lv_upn.
        lv_found = abap_true.
        ls_finding-bname = ls_sap_address-bname.
        IF ls_sap_address-active = abap_false.
          ls_finding-finding = `sap_locked`.
          APPEND ls_finding TO rt_findings.
          CONTINUE.
        ENDIF.
        READ TABLE lt_role TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_sap_address-bname.
        IF sy-subrc <> 0.
          ls_finding-finding = `no_role`.
          APPEND ls_finding TO rt_findings.
        ENDIF.
      ENDLOOP.
      IF lv_found = abap_false.
        CLEAR ls_finding-bname.
        ls_finding-finding = `no_sap_user`.
        APPEND ls_finding TO rt_findings.
      ENDIF.
    ENDLOOP.

    " Every active role user needs to be in the group
    LOOP AT it_sap INTO ls_sap WHERE active = abap_true.
      READ TABLE lt_role TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_sap-bname.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      CLEAR ls_finding.
      ls_finding-bname = ls_sap-bname.
      lv_mail = address_key( ls_sap-mail ).
      ls_finding-mail = lv_mail.
      IF lv_mail IS INITIAL.
        ls_finding-finding = `no_mail`.
        APPEND ls_finding TO rt_findings.
        CONTINUE.
      ENDIF.
      READ TABLE lt_member_addresses TRANSPORTING NO FIELDS WITH TABLE KEY table_line = lv_mail.
      IF sy-subrc <> 0.
        ls_finding-finding = `extra_role`.
        APPEND ls_finding TO rt_findings.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD sap_details.
    DATA lt_users TYPE lif_graph_users=>ty_sap_users.
    DATA ls_user TYPE lif_graph_users=>ty_sap_user.
    DATA ls_detail TYPE lif_graph_users=>ty_sap_detail.
    DATA ls_address TYPE bapiaddr3.
    DATA lt_return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA ls_return TYPE bapiret2.
    DATA lv_failed TYPE abap_bool.
    DATA lv_skipped TYPE i.

    lt_users = sap_users( it_bname ).
    lv_skipped = skipped.
    LOOP AT lt_users INTO ls_user WHERE active = abap_true AND mail IS NOT INITIAL.
      CLEAR: ls_address, lt_return, lv_failed.
      CALL FUNCTION 'BAPI_USER_GET_DETAIL'
        EXPORTING
          username = ls_user-bname
        IMPORTING
          address  = ls_address
        TABLES
          return   = lt_return.
      LOOP AT lt_return INTO ls_return WHERE type = 'E' OR type = 'A'.
        lv_failed = abap_true.
        EXIT.
      ENDLOOP.
      IF lv_failed = abap_true.
        lv_skipped = lv_skipped + 1.
        CONTINUE.
      ENDIF.
      CLEAR ls_detail.
      ls_detail-bname = ls_user-bname.
      ls_detail-mail = ls_user-mail.
      ls_detail-first_name = ls_address-firstname.
      ls_detail-last_name = ls_address-lastname.
      ls_detail-department = ls_address-department.
      ls_detail-job_title = ls_address-function.
      ls_detail-phone = ls_address-tel1_numbr.
      APPEND ls_detail TO rt_details.
    ENDLOOP.
    skipped = lv_skipped.
  ENDMETHOD.


  METHOD add_difference.
    DATA lv_sap TYPE string.
    DATA lv_entra TYPE string.
    DATA ls_difference TYPE lif_graph_users=>ty_difference.

    lv_entra = iv_entra.
    CONDENSE lv_entra.
    IF lv_entra IS INITIAL.
      RETURN.
    ENDIF.
    lv_sap = iv_sap.
    CONDENSE lv_sap.
    TRANSLATE lv_sap TO UPPER CASE.
    TRANSLATE lv_entra TO UPPER CASE.
    IF lv_sap = lv_entra.
      RETURN.
    ENDIF.
    ls_difference-bname = is_sap-bname.
    ls_difference-mail = is_sap-mail.
    ls_difference-field = iv_field.
    ls_difference-sap_value = iv_sap.
    CONDENSE ls_difference-sap_value.
    ls_difference-entra_value = iv_entra.
    CONDENSE ls_difference-entra_value.
    APPEND ls_difference TO ct_differences.
  ENDMETHOD.


  METHOD compare_details.
    TYPES:
      BEGIN OF lty_entra,
        address TYPE string,
        index   TYPE i,
      END OF lty_entra.
    DATA lt_by_address TYPE SORTED TABLE OF lty_entra WITH NON-UNIQUE KEY address.
    DATA ls_by_address TYPE lty_entra.
    DATA ls_entra TYPE lif_graph_users=>ty_user.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_detail.
    DATA lv_mail TYPE string.
    DATA lv_upn TYPE string.
    DATA lv_count TYPE i.

    LOOP AT it_entra INTO ls_entra.
      ls_by_address-index = sy-tabix.
      lv_mail = address_key( ls_entra-mail ).
      lv_upn = address_key( ls_entra-user_principal_name ).
      IF lv_mail IS NOT INITIAL.
        ls_by_address-address = lv_mail.
        INSERT ls_by_address INTO TABLE lt_by_address.
      ENDIF.
      IF lv_upn IS NOT INITIAL AND lv_upn <> lv_mail.
        ls_by_address-address = lv_upn.
        INSERT ls_by_address INTO TABLE lt_by_address.
      ENDIF.
    ENDLOOP.

    LOOP AT it_sap INTO ls_sap.
      lv_mail = address_key( ls_sap-mail ).
      " The address must lead to exactly one Microsoft account
      CLEAR: ls_by_address, lv_count.
      LOOP AT lt_by_address INTO ls_by_address WHERE address = lv_mail.
        lv_count = lv_count + 1.
      ENDLOOP.
      IF lv_count <> 1.
        CONTINUE.
      ENDIF.
      READ TABLE it_entra INDEX ls_by_address-index INTO ls_entra.
      add_difference( EXPORTING is_sap = ls_sap iv_field = `first_name`
                                iv_sap = ls_sap-first_name iv_entra = ls_entra-given_name
                      CHANGING  ct_differences = rt_differences ).
      add_difference( EXPORTING is_sap = ls_sap iv_field = `last_name`
                                iv_sap = ls_sap-last_name iv_entra = ls_entra-surname
                      CHANGING  ct_differences = rt_differences ).
      add_difference( EXPORTING is_sap = ls_sap iv_field = `department`
                                iv_sap = ls_sap-department iv_entra = ls_entra-department
                      CHANGING  ct_differences = rt_differences ).
      add_difference( EXPORTING is_sap = ls_sap iv_field = `job_title`
                                iv_sap = ls_sap-job_title iv_entra = ls_entra-job_title
                      CHANGING  ct_differences = rt_differences ).
      IF phone_key( ls_sap-phone ) <> phone_key( ls_entra-business_phone ).
        add_difference( EXPORTING is_sap = ls_sap iv_field = `phone`
                                  iv_sap = ls_sap-phone iv_entra = ls_entra-business_phone
                        CHANGING  ct_differences = rt_differences ).
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
    METHODS compare_group_and_role FOR TESTING.
    METHODS compare_su01_details FOR TESTING.
    METHODS compare_sap_reverse FOR TESTING.
    METHODS compare_su01_phone FOR TESTING.

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
                `"department":"Muhasebe","employeeId":"00001234","businessPhones":["+90 212 555 0101"],`
                `"accountEnabled":false}` INTO lv_json.
    mo_http->answer( iv_status = 200 iv_body = lv_json ).
    ls_user = mo_cut->user( ` derya@contoso.com ` ).
    cl_aunit_assert=>assert_equals( act = ls_user-id exp = `U1` ).
    cl_aunit_assert=>assert_equals( act = ls_user-department exp = `Muhasebe` ).
    cl_aunit_assert=>assert_equals( act = ls_user-employee_id exp = `00001234` ).
    cl_aunit_assert=>assert_equals( act = ls_user-business_phone exp = `+90 212 555 0101` ).
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


  METHOD compare_group_and_role.
    DATA lt_members TYPE lif_graph_users=>ty_users.
    DATA ls_member TYPE lif_graph_users=>ty_user.
    DATA lt_sap TYPE lif_graph_users=>ty_sap_users.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_user.
    DATA lt_role TYPE lif_graph_users=>ty_bnames.
    DATA lt_findings TYPE lif_graph_users=>ty_role_findings.
    DATA ls_finding TYPE lif_graph_users=>ty_role_finding.
    DATA lv_count TYPE i.

    " Members: Derya (has the role), Ayşe (lacks it, found through the user
    " principal name), Can (no SAP user), Eski (disabled: not a member)
    ls_member-mail = `Derya@Contoso.com`.
    ls_member-account_enabled = abap_true.
    APPEND ls_member TO lt_members.
    CLEAR ls_member.
    ls_member-user_principal_name = `ayse@contoso.com`.
    ls_member-display_name = `Ayşe Yılmaz`.
    ls_member-account_enabled = abap_true.
    APPEND ls_member TO lt_members.
    CLEAR ls_member.
    ls_member-mail = `can@contoso.com`.
    ls_member-display_name = `Can Demir`.
    ls_member-account_enabled = abap_true.
    APPEND ls_member TO lt_members.
    CLEAR ls_member.
    ls_member-mail = `eski@contoso.com`.
    ls_member-account_enabled = abap_false.
    APPEND ls_member TO lt_members.
    " Kilit: a member whose SAP user is locked
    CLEAR ls_member.
    ls_member-mail = `locked@contoso.com`.
    ls_member-display_name = `Kilit Test`.
    ls_member-account_enabled = abap_true.
    APPEND ls_member TO lt_members.

    ls_sap-active = abap_true.
    ls_sap-bname = 'DKAYA'.
    ls_sap-mail = `derya@contoso.com`.
    APPEND ls_sap TO lt_sap.
    ls_sap-bname = 'AYILMAZ'.
    ls_sap-mail = ` AYSE@contoso.com`.
    APPEND ls_sap TO lt_sap.
    ls_sap-bname = 'ESKI'.
    ls_sap-mail = `eski@contoso.com`.
    APPEND ls_sap TO lt_sap.
    ls_sap-bname = 'NOMAIL'.
    CLEAR ls_sap-mail.
    APPEND ls_sap TO lt_sap.
    " Locked in SAP: not compared, even with the role
    ls_sap-bname = 'LOCKED'.
    ls_sap-mail = `locked@contoso.com`.
    ls_sap-active = abap_false.
    APPEND ls_sap TO lt_sap.

    APPEND 'DKAYA' TO lt_role.
    APPEND 'ESKI' TO lt_role.
    APPEND 'NOMAIL' TO lt_role.
    APPEND 'LOCKED' TO lt_role.

    lt_findings = lcl_graph_users=>compare_role( it_members = lt_members it_sap = lt_sap it_role = lt_role ).
    lv_count = lines( lt_findings ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 5 ).
    READ TABLE lt_findings INTO ls_finding WITH KEY bname = 'LOCKED'.
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `sap_locked` ).
    cl_aunit_assert=>assert_equals( act = ls_finding-display_name exp = `Kilit Test` ).
    READ TABLE lt_findings INTO ls_finding WITH KEY bname = 'AYILMAZ'.
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `no_role` ).
    cl_aunit_assert=>assert_equals( act = ls_finding-display_name exp = `Ayşe Yılmaz` ).
    READ TABLE lt_findings INTO ls_finding WITH KEY finding = `no_sap_user`.
    cl_aunit_assert=>assert_equals( act = ls_finding-mail exp = `can@contoso.com` ).
    READ TABLE lt_findings INTO ls_finding WITH KEY bname = 'ESKI'.
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `extra_role` ).
    READ TABLE lt_findings INTO ls_finding WITH KEY bname = 'NOMAIL'.
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `no_mail` ).
  ENDMETHOD.


  METHOD compare_su01_details.
    DATA lt_sap TYPE lif_graph_users=>ty_sap_details.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_detail.
    DATA lt_entra TYPE lif_graph_users=>ty_users.
    DATA ls_entra TYPE lif_graph_users=>ty_user.
    DATA lt_differences TYPE lif_graph_users=>ty_differences.
    DATA ls_difference TYPE lif_graph_users=>ty_difference.
    DATA lv_count TYPE i.

    ls_entra-mail = `derya@contoso.com`.
    ls_entra-given_name = `Derya`.
    ls_entra-surname = `Kaya`.
    ls_entra-department = `Finans`.
    ls_entra-job_title = ``.
    APPEND ls_entra TO lt_entra.
    " Two accounts with one address: not compared
    CLEAR ls_entra.
    ls_entra-mail = `ortak@contoso.com`.
    ls_entra-department = `A`.
    APPEND ls_entra TO lt_entra.
    ls_entra-user_principal_name = `ortak@contoso.com`.
    CLEAR ls_entra-mail.
    APPEND ls_entra TO lt_entra.

    " Name equal apart from case and blanks; department differs; the job
    " title is empty in Entra ID, so SAP's value stays
    ls_sap-bname = 'DKAYA'.
    ls_sap-mail = `Derya@contoso.com`.
    ls_sap-first_name = `DERYA `.
    ls_sap-last_name = `Kaya`.
    ls_sap-department = `Muhasebe`.
    ls_sap-job_title = `Uzman`.
    APPEND ls_sap TO lt_sap.
    CLEAR ls_sap.
    ls_sap-bname = 'ORTAK'.
    ls_sap-mail = `ortak@contoso.com`.
    APPEND ls_sap TO lt_sap.

    lt_differences = lcl_graph_users=>compare_details( it_sap = lt_sap it_entra = lt_entra ).
    lv_count = lines( lt_differences ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    READ TABLE lt_differences INDEX 1 INTO ls_difference.
    cl_aunit_assert=>assert_equals( act = ls_difference-bname exp = 'DKAYA' ).
    cl_aunit_assert=>assert_equals( act = ls_difference-field exp = `department` ).
    cl_aunit_assert=>assert_equals( act = ls_difference-sap_value exp = `Muhasebe` ).
    cl_aunit_assert=>assert_equals( act = ls_difference-entra_value exp = `Finans` ).
  ENDMETHOD.


  METHOD compare_sap_reverse.
    DATA lt_sap TYPE lif_graph_users=>ty_sap_users.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_user.
    DATA lt_entra TYPE lif_graph_users=>ty_users.
    DATA ls_entra TYPE lif_graph_users=>ty_user.
    DATA lt_findings TYPE lif_graph_users=>ty_findings.
    DATA ls_finding TYPE lif_graph_users=>ty_finding.
    DATA lv_count TYPE i.

    ls_entra-mail = `old@contoso.com`.
    ls_entra-display_name = `Eski Çalışan`.
    ls_entra-account_enabled = abap_true.
    APPEND ls_entra TO lt_entra.
    CLEAR ls_entra.
    ls_entra-mail = `gone@contoso.com`.
    ls_entra-account_enabled = abap_false.
    APPEND ls_entra TO lt_entra.

    " Locked in SAP, enabled in Entra ID: reported
    ls_sap-bname = 'OLD'.
    ls_sap-mail = `Old@contoso.com`.
    APPEND ls_sap TO lt_sap.
    " Locked in SAP, disabled in Entra ID, or no account: nothing to do
    ls_sap-bname = 'GONE'.
    ls_sap-mail = `gone@contoso.com`.
    APPEND ls_sap TO lt_sap.
    ls_sap-bname = 'NONE'.
    ls_sap-mail = `none@contoso.com`.
    APPEND ls_sap TO lt_sap.

    " Not asked for: no finding
    lt_findings = lcl_graph_users=>compare( it_sap = lt_sap it_entra = lt_entra ).
    lv_count = lines( lt_findings ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 0 ).

    lt_findings = lcl_graph_users=>compare( it_sap = lt_sap it_entra = lt_entra iv_reverse = abap_true ).
    lv_count = lines( lt_findings ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    READ TABLE lt_findings INDEX 1 INTO ls_finding.
    cl_aunit_assert=>assert_equals( act = ls_finding-bname exp = 'OLD' ).
    cl_aunit_assert=>assert_equals( act = ls_finding-finding exp = `locked_open` ).
    cl_aunit_assert=>assert_equals( act = ls_finding-display_name exp = `Eski Çalışan` ).
  ENDMETHOD.


  METHOD compare_su01_phone.
    DATA lt_sap TYPE lif_graph_users=>ty_sap_details.
    DATA ls_sap TYPE lif_graph_users=>ty_sap_detail.
    DATA lt_entra TYPE lif_graph_users=>ty_users.
    DATA ls_entra TYPE lif_graph_users=>ty_user.
    DATA lt_differences TYPE lif_graph_users=>ty_differences.
    DATA ls_difference TYPE lif_graph_users=>ty_difference.
    DATA lv_count TYPE i.

    ls_entra-mail = `derya@contoso.com`.
    ls_entra-business_phone = `+90 (212) 555 01 07`.
    APPEND ls_entra TO lt_entra.
    ls_entra-mail = `can@contoso.com`.
    ls_entra-business_phone = `+90 212 555 0199`.
    APPEND ls_entra TO lt_entra.
    ls_entra-mail = `bos@contoso.com`.
    CLEAR ls_entra-business_phone.
    APPEND ls_entra TO lt_entra.

    " The same line written differently: no difference
    ls_sap-bname = 'DKAYA'.
    ls_sap-mail = `derya@contoso.com`.
    ls_sap-phone = `0212 555 0107`.
    APPEND ls_sap TO lt_sap.
    " Another number: a difference
    ls_sap-bname = 'CDEMIR'.
    ls_sap-mail = `can@contoso.com`.
    ls_sap-phone = `0212 555 0100`.
    APPEND ls_sap TO lt_sap.
    " Empty in Entra ID: never proposed
    ls_sap-bname = 'BOS'.
    ls_sap-mail = `bos@contoso.com`.
    ls_sap-phone = `0212 555 0101`.
    APPEND ls_sap TO lt_sap.

    lt_differences = lcl_graph_users=>compare_details( it_sap = lt_sap it_entra = lt_entra ).
    lv_count = lines( lt_differences ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    READ TABLE lt_differences INDEX 1 INTO ls_difference.
    cl_aunit_assert=>assert_equals( act = ls_difference-bname exp = 'CDEMIR' ).
    cl_aunit_assert=>assert_equals( act = ls_difference-field exp = `phone` ).
    cl_aunit_assert=>assert_equals( act = ls_difference-entra_value exp = `+90 212 555 0199` ).
  ENDMETHOD.

ENDCLASS.
