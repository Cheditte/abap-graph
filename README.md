# abap-graph

> **English** | [Türkçe](README.tr.md)

Connect SAP with Microsoft 365 from ABAP alone, through **Microsoft Graph**: no middleware, no add-on. A shared core does the sign-in, the HTTP calls, JSON, retries and paging. Modules for each Microsoft product build on it: e-mail, SharePoint/OneDrive, Lists, Excel, Entra ID, calendar and Teams.

- **Copy and paste:** you paste the source into SE38. No tables, no dictionary objects; abapGit is optional.
- **ABAP 7.00 syntax:** written for ECC 6.0 and later, S/4HANA included. So far it has run on SAP_BASIS 816 only; see [What has been verified](#what-has-been-verified).
- **The secret stays in SM59:** the code never sees it.

> **Status: v0.7.0, not released.** The core, the connection test and the e-mail, files, lists, Excel, users and calendar modules were tried on an SAP ABAP Cloud Developer Trial against a real Microsoft 365 test tenant; the Teams module not yet with a real channel. They were not tried with least-privilege permissions or on a real 7.00 system (see [What has been verified](#what-has-been-verified)).

## How it works

```
SAP program ──INCLUDE zche_graph_core──┐
                                        ├─ SM59 ZCHE_GRAPH_LOGIN ──> login.microsoftonline.com  (token)
                                        └─ SM59 ZCHE_GRAPH_API   ──> graph.microsoft.com        (calls)
```

1. The application signs in with the **OAuth2 client credentials** flow. The client ID and secret travel as HTTP basic authentication from SM59 destination `ZCHE_GRAPH_LOGIN`; Microsoft accepts this (`client_secret_basic`). The token is kept until five minutes before it expires.
2. Calls go through SM59 destination `ZCHE_GRAPH_API` with that token.
3. HTTP 429 is retried after the time Microsoft asks for (`Retry-After`, at most 60 seconds). HTTP 503 and 504 are retried the same way for GET, PUT and DELETE only: a POST or PATCH (sending a mail, creating an item) may have been carried out before the error, so it is not sent again, and the error says that the outcome is unknown. HTTP 401 gets one new token. Other errors raise `LCX_GRAPH` with Microsoft's error code, message, `request-id` and a hint on what to check.

## What you need

| What | Why | Who |
|---|---|---|
| SAP_BASIS 7.00 or higher with outbound HTTPS to the internet (or through a proxy) | The calls go to Microsoft's cloud | Basis, network |
| A kernel and CommonCryptoLib that support **TLS 1.2** | Microsoft accepts only TLS 1.2 and newer. Old kernels may need an update. | Basis |
| A Microsoft 365 tenant and an **app registration** in Microsoft Entra ID | The identity of SAP towards Microsoft | Microsoft 365 / Entra administrator |
| **Application permissions** with admin consent, per module | For example `Mail.Send` for e-mail. The connection test needs none. | Microsoft 365 / Entra administrator |
| A developer key | To create one include and one program | Developer |

## Set up

### 1. Microsoft Entra ID: register the application

In the [Microsoft Entra admin center](https://entra.microsoft.com) go to **App registrations → New registration**.

1. **Name:** for example `SAP abap-graph PRD`. Choose **Accounts in this organizational directory only**. No redirect URI.
2. On the **Overview** page, note:
   - **Application (client) ID**: this becomes the *user* in SM59;
   - **Directory (tenant) ID**: you enter this in the programs.
3. **Certificates & secrets → New client secret.** Copy the **Value** at once; it is shown only once. The *Secret ID* is not the secret. Note the expiry date: the connection stops when the secret expires.
4. **API permissions:** add the **application** permissions the modules need, then **Grant admin consent**. For the connection test alone, nothing is needed.

Restrict what the application may reach: `Mail.Send` alone allows sending as **any** mailbox. The module guides explain how to limit it to certain mailboxes or sites.

### 2. Basis: certificates (STRUST)

Open `https://login.microsoftonline.com` and `https://graph.microsoft.com` in a browser. Look at the certificate chain and export the root and intermediate certificates. In **STRUST**, import them into the SSL client PSE that the destinations use (**SSL Client Anonymous** in the steps below), save, and restart ICM if your release requires it.

On the trial system used for testing, both hosts were already trusted.

### 3. Basis: two SM59 destinations (type G, "HTTP connection to external server")

| Field | `ZCHE_GRAPH_LOGIN` | `ZCHE_GRAPH_API` |
|---|---|---|
| Target host | `login.microsoftonline.com` | `graph.microsoft.com` |
| Service no. (port) | `443` | `443` |
| Path prefix | empty | empty |
| Logon & Security | **Basic authentication**: user = Application (client) ID, password = client secret *Value* | **No logon** |
| SSL | Active, certificate list **ANONYM** (SSL Client Anonymous) | Active, **ANONYM** |
| Proxy | your proxy, if SAP reaches the internet through one | same |

The destination names can be different; the programs let you enter them.

### 4. Install (copy and paste)

1. **SE38** → program `ZCHE_GRAPH_CORE` → **Create** → type **Include program** → save in your package (or **Local Object** for a first test). Paste [`src/zche_graph_core.prog.abap`](src/zche_graph_core.prog.abap) and save. It is activated together with the program in the next step.
2. **SE38** → program `ZCHE_GRAPH_CHECK` → **Create** → type **Executable program**. Paste [`src/zche_graph_check.prog.abap`](src/zche_graph_check.prog.abap) and activate (**Ctrl+F3**). When asked, activate the include too.
3. Optional: run the unit tests of `ZCHE_GRAPH_CHECK` (**Program → Execute → Unit Tests**, or **Ctrl+Shift+F10** in ADT). 16 tests should pass. They do not call Microsoft.

When you activate `ZCHE_GRAPH_CORE` later, after a second program already uses it, SAP asks in which main program to check it. Choose any of them.

**If activation says a line is too long:** in SE38 go to **Utilities → Settings → ABAP Editor → Editor** and clear **Downwards-compatible line length (72)**. Then paste again.

**Alternative: abapGit.** You can pull this repository into a package instead.

### 5. Test the connection

Run `ZCHE_GRAPH_CHECK` and enter the **Directory (tenant) ID**. The program checks each step and says what is missing:

1. **SM59 destinations:** both exist and are type G.
2. **Sign-in:** Microsoft gives the application a token, which proves the client ID, secret and tenant are right. The program also lists the permissions the token carries.
3. **One Graph call:** default `/organization`; it needs the permission `Organization.Read.All`. Without that permission, the result "HTTP 403, only the permission is missing" still proves the connection works.

Common answers:

| Message | Meaning |
|---|---|
| `AADSTS7000215` | Wrong secret: use the secret's *Value*, not its *Secret ID* |
| `AADSTS7000222` | The secret has expired |
| `AADSTS700016`, `AADSTS700038` | Wrong application (client) ID, or wrong tenant |
| `AADSTS90002` | Tenant not found |
| No connection through SM59 destination … | Host, port, SSL, STRUST certificates, proxy or TLS 1.2 |

## Use the core in your own program

```abap
REPORT zmy_report.
INCLUDE zche_graph_core.

DATA lo_client TYPE REF TO lcl_graph_client.
DATA ls_config TYPE lif_graph=>ty_config.
DATA lo_json TYPE REF TO lcl_graph_json.
DATA lx_graph TYPE REF TO lcx_graph.
DATA lv_name TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
TRY.
    lo_json = lo_client->get_json( `/organization` ).
    lv_name = lo_json->get( `value/0/displayName` ).
  CATCH lcx_graph INTO lx_graph.
    lv_name = lx_graph->if_message~get_longtext( ).   " text, hint and request-id
ENDTRY.
```

| Part | What it does |
|---|---|
| `LCL_GRAPH_CLIENT` | `get_json`, `get_pages` (follows `@odata.nextLink`), `send_json` (POST/PATCH/PUT), `delete_path`, `request` (any call, binary bodies too) |
| `LCL_GRAPH_JSON` | Reads answers by path: `get( 'value/0/id' )`, `count( 'value' )`, `names( '' )`, `exists`, `kind_of` |
| `LCL_GRAPH_JSON_WRITER` | Builds request bodies: `begin_object`, `add_string`, `add_number`, `add_boolean`, `begin_array`, … |
| `LCL_GRAPH_CONV` | UTF-8, Base64 (for attachments), URL encoding |
| `LCX_GRAPH` | HTTP status, Microsoft error code, `request-id`, hint |

### Microsoft calls and SAP transactions

A call to Microsoft is not part of the SAP transaction: a sent mail or a created item stays when your program later fails or rolls back. And while it retries after HTTP 429, the core waits with `WAIT UP TO`, which commits the open database changes of your program. So:
- call the modules **after** `COMMIT WORK`, not between your database changes and the commit;
- when a call must not get lost, write what is to be sent into a table of your own in the same transaction, and let a job send it and mark it as sent (an *outbox*).

Whether the HTTP call itself also commits the database was not measured.

## E-mail module

Send and read mail as one mailbox, for example `sap@contoso.com`. The module consists of the include `ZCHE_GRAPH_MAIL_LIB` (class `LCL_GRAPH_MAIL`) and the program `ZCHE_GRAPH_MAIL`, which sends a test mail or lists a folder.

**Sending:**
- text or HTML, To/Cc/Bcc, reply-to, importance;
- attachments of any kind, including a spool request as PDF (ABAP list, SAPscript or Smart Forms);
- inline pictures for HTML (`<img src="cid:logo">`);
- mails up to about 2.9 MB of attachments in one call. Larger mails are created as a draft, get their attachments one by one (an attachment of 3 MB or more through an upload session, in pieces of 3.2 MB, up to 150 MB) and are then sent.

**Reading:**
- the messages of a folder (only unread if wanted), with sender, subject and preview;
- the body (text or HTML) and the attachments, each as bytes;
- mark as read, and move to another folder (by well-known name such as `archive`, or by display name).

### What the e-mail module needs in addition

| What | Why | Who |
|---|---|---|
| Application permissions **`Mail.Send`** (sending) and **`Mail.ReadWrite`** (large mails, reading, marking, moving), with admin consent | Without them Microsoft answers HTTP 403 | Microsoft 365 / Entra administrator |
| **Restriction to the SAP mailbox(es)** | Without it the application may send as and read **any** mailbox of the company | Exchange Online administrator |
| A mailbox for SAP, for example `sap@contoso.com` | The sender | Microsoft 365 administrator |
| For attachments of 3 MB or more: SAP may reach `outlook.office.com` with HTTPS (SICF proxy settings, STRUST) | Microsoft hands out an upload URL on that host; no SM59 destination is used for it | Basis |

**Restricting the mailboxes.** Exchange Online offers two ways. Check Microsoft's current documentation for which to use; Microsoft now recommends the first.

1. **RBAC for Applications:** a management scope with the SAP mailboxes, and the application roles `Application Mail.Send` / `Application Mail.ReadWrite` on that scope only. When you use this, do **not** also grant the tenant-wide `Mail.*` permissions in Entra ID.
2. **Application access policy (older):** keep the permissions in Entra ID and limit them with PowerShell (Exchange Online module):
   ```powershell
   New-DistributionGroup -Name "SAP Graph mailboxes" -Type Security -Members sap@contoso.com
   New-ApplicationAccessPolicy -AppId <application (client) ID> -PolicyScopeGroupId "SAP Graph mailboxes" -AccessRight RestrictAccess -Description "abap-graph"
   Test-ApplicationAccessPolicy -Identity sap@contoso.com -AppId <application (client) ID>
   ```

Neither way has been tried with this project yet.

**Looking into the mailbox in Outlook.** The application's permissions are for SAP only; they do not let a person open the shared mailbox. To see it in Outlook on the web, an administrator gives that person access: Microsoft 365 admin center → Teams & groups → Shared mailboxes → the mailbox → Mailbox permissions → **Read and manage**. After a while it shows up in Outlook, or the person opens it with the profile picture → **Open another mailbox**.

### Install

After `ZCHE_GRAPH_CORE`: **SE38** → `ZCHE_GRAPH_MAIL_LIB` (type **Include program**) → paste [`src/zche_graph_mail_lib.prog.abap`](src/zche_graph_mail_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_MAIL` (type **Executable program**) → paste [`src/zche_graph_mail.prog.abap`](src/zche_graph_mail.prog.abap) → activate together with the include.

### Try it

Run `ZCHE_GRAPH_MAIL`:

- **Send a mail:**
  - tenant and mailbox (the sender);
  - To (several addresses separated by `;`, also as `Name <address>`), subject and text;
  - optional: a spool request number (from SP01), which is attached as PDF.

  As a background job after a report, enter the spool number of that report. An error ends the job as "Cancelled".
- **Read a folder:** folder (`inbox`, `archive`, … or a folder's display name), only unread, at most N messages, optionally with the attachments of each message.

### Use it in your own program

```abap
REPORT zmy_invoice_mail.
INCLUDE zche_graph_core.
INCLUDE zche_graph_mail_lib.

DATA lo_client TYPE REF TO lcl_graph_client.
DATA lo_mail TYPE REF TO lcl_graph_mail.
DATA ls_config TYPE lif_graph=>ty_config.
DATA ls_mail TYPE lif_graph_mail=>ty_mail.
DATA ls_attachment TYPE lif_graph_mail=>ty_attachment.
DATA lx_graph TYPE REF TO lcx_graph.
DATA lv_spool TYPE rspoid.          " the spool request of your invoice
DATA lv_text TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
CREATE OBJECT lo_mail EXPORTING io_client = lo_client iv_mailbox = `sap@contoso.com`.

ls_mail-subject = `Invoice 4711`.
ls_mail-body = `<p>Dear customer, please find the invoice attached.</p>`.
ls_mail-html = abap_true.
ls_mail-to = lcl_graph_mail=>addresses( `Derya Kaya <derya@customer.com>; ap@customer.com` ).
TRY.
    ls_attachment = lcl_graph_mail=>attachment_from_spool( iv_spool = lv_spool iv_name = `invoice_4711.pdf` ).
    APPEND ls_attachment TO ls_mail-attachments.
    lo_mail->send( ls_mail ).
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).   " text, hint and request-id
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

Reading, for example to process supplier invoices from a mailbox:

```abap
DATA lt_messages TYPE lif_graph_mail=>ty_messages.
DATA ls_message TYPE lif_graph_mail=>ty_message.
DATA lt_attachments TYPE lif_graph_mail=>ty_attachment_infos.
DATA ls_info TYPE lif_graph_mail=>ty_attachment_info.
DATA lv_pdf TYPE xstring.
DATA lv_archive TYPE string.

lt_messages = lo_mail->list( iv_folder = `inbox` iv_unread_only = abap_true iv_max = 50 ).
lv_archive = lo_mail->folder_id( `SAP processed` ).
LOOP AT lt_messages INTO ls_message WHERE has_attachments = abap_true.
  lt_attachments = lo_mail->attachments( ls_message-id ).
  LOOP AT lt_attachments INTO ls_info WHERE kind = `file` AND inline = abap_false.
    lv_pdf = lo_mail->attachment_content( iv_message_id = ls_message-id iv_attachment_id = ls_info-id ).
    " ... your processing
  ENDLOOP.
  lo_mail->move_to( iv_message_id = ls_message-id iv_folder = lv_archive ).
ENDLOOP.
```

## SharePoint and OneDrive files

Work with the files of one document library: a library of a SharePoint site, or the OneDrive of a user. Files and folders are named by their path in the library, for example `Reports/2026/11/sales.xlsx`. The module consists of the include `ZCHE_GRAPH_FILES_LIB` (class `LCL_GRAPH_FILES`) and the program `ZCHE_GRAPH_FILES`.

- **Upload:** files up to 4 MB in one request; larger ones in pieces of 3.2 MB. If a file of that name already exists, it is replaced, renamed or refused, as you choose.
- **Download:** through the short-lived download URL Microsoft hands out.
- **List** a folder, with size, date, who changed it and the web link.
- **Folders:** create a single folder, or a whole path at once (`ensure_folder`: only the missing folders are created).
- **Move, rename, delete.**
- **Sharing links:** view or edit, for the people of the company or for anyone with the link.

### What the files module needs in addition

| What | Why | Who |
|---|---|---|
| Application permission **`Sites.Selected`** with admin consent, and then **write access for the application on each site** SAP may use | Least privilege: the application reaches only those sites | Microsoft 365 / SharePoint administrator |
| *Or* `Sites.ReadWrite.All` / `Files.ReadWrite.All` | Simpler, but the application reaches **every** site; `Files.ReadWrite.All` also reaches every OneDrive. A user's OneDrive needs `Files.ReadWrite.All`. | Microsoft 365 administrator |
| SAP may reach `<tenant>.sharepoint.com` with HTTPS (SICF proxy settings, STRUST) | Download URLs and the upload URLs of large files point there; no SM59 destination is used for them | Basis |

**Granting a site to the application (`Sites.Selected`).** An administrator does this once per site. Two common ways; check Microsoft's current documentation. The Graph way was used once on the test tenant (`write` on one site); the PnP way was not tried.

- With **PnP PowerShell**:
  ```powershell
  Grant-PnPAzureADAppSitePermission -AppId <application (client) ID> -DisplayName "SAP abap-graph" -Site https://contoso.sharepoint.com/sites/Finance -Permissions Write
  ```
- With **Graph**, as a separate admin application that has `Sites.FullControl.All`: `POST /sites/{site-id}/permissions` with `{"roles":["write"],"grantedToIdentities":[{"application":{"id":"<application (client) ID>","displayName":"SAP abap-graph"}}]}`.

### Install

After `ZCHE_GRAPH_CORE` and `ZCHE_GRAPH_MAIL_LIB`: **SE38** → `ZCHE_GRAPH_FILES_LIB` (type **Include program**) → paste [`src/zche_graph_files_lib.prog.abap`](src/zche_graph_files_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_FILES` (type **Executable program**) → paste [`src/zche_graph_files.prog.abap`](src/zche_graph_files.prog.abap) → activate. The program uses the e-mail include only to turn a spool request into PDF; your own programs need only the core and the files include.

### Try it

Run `ZCHE_GRAPH_FILES` and choose the library:

| Library | Fields | Example |
|---|---|---|
| **SharePoint site** | Host | `contoso.sharepoint.com` |
| | Site path; empty for the root site | `/sites/Finance` |
| | Library name as SharePoint shows it; empty for the default library (*Documents*, or *Belgeler* in Turkish) | empty |
| **OneDrive of a user** | User | `derya@contoso.com` |

Then choose one action:

| Action | Fields |
|---|---|
| **List a folder** | Path; empty means the top of the library |
| **Upload spool as PDF** | Spool request and path. A path ending with `/` keeps the spool's own file name. |
| **Upload a server file** | Application server file (see AL11) and path |
| **Download to the server** | Path and application server file |
| **Create folder path** | Path, for example `Reports/2026/11` |
| **Create a sharing link** | Path |

As a background job, an error ends the job as "Cancelled". This lets you put a report's PDF into SharePoint every night.

### Use it in your own program

```abap
REPORT zmy_report_to_sharepoint.
INCLUDE zche_graph_core.
INCLUDE zche_graph_files_lib.

DATA lo_client TYPE REF TO lcl_graph_client.
DATA lo_files TYPE REF TO lcl_graph_files.
DATA ls_config TYPE lif_graph=>ty_config.
DATA ls_item TYPE lif_graph_files=>ty_item.
DATA lx_graph TYPE REF TO lcx_graph.
DATA lv_xlsx TYPE xstring.          " your file, for example an Excel export
DATA lv_text TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
TRY.
    lo_files = lcl_graph_files=>for_site( io_client = lo_client
                                          iv_host   = `contoso.sharepoint.com`
                                          iv_site   = `/sites/Finance` ).
    lo_files->ensure_folder( `Reports/2026/11` ).
    ls_item = lo_files->upload( iv_path = `Reports/2026/11/sales.xlsx` iv_content = lv_xlsx ).
    " ls_item-web_url: the link to the file
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

## SharePoint lists

A SharePoint list is a table that people keep in SharePoint: open invoices, a supplier contact list, approvals, a price list. The module keeps such a list in step with SAP. It consists of the include `ZCHE_GRAPH_LISTS_LIB` (class `LCL_GRAPH_LIST`) and the program `ZCHE_GRAPH_LISTS`.

- **The lists of a site, and the columns of a list:** internal name, name shown, type (text, number, currency, date, yes/no, choice, lookup, person, …), required, read-only, multiple values.
- **Read items:** all columns or chosen ones, with an OData filter such as `fields/Status eq 'Open'`, over many pages.
- **Create, change and delete items.** Only the fields you give are changed.
- **Update or create by a key column (`upsert`):** for example "update the item whose `InvoiceNo` is 4711, or create it". This is the basic step to mirror SAP data into a list every night. Two jobs that run at the same time could both find nothing and both create the item; to prevent that, switch on **Enforce unique values** for the key column in SharePoint. The second create is then refused, and the module updates the item the other job created.

Values travel as text. Each value is converted by the type of its column:

| Column | Write it as | Sent as |
|---|---|---|
| Text, note, single choice | `Status=Open` | text |
| Number, currency | `Amount=1234.56` (dot as decimal sign) | number |
| Yes/No | `Paid=X` (also `true`, `1`, `yes`, `evet`) | true/false |
| Date | `DueDate=2026-11-30` or `2026-11-30T10:00:00Z` | text in ISO format |
| Choice with several values | `Tags=red;blue` | a list of texts |
| Lookup or person | `CustomerLookupId=12` (or `12;15`) | a number (list) |

Use the columns' **internal** names (for example `Title`, or `Tutar` for a column shown as "Tutar"). **Show the columns** lists them; a column created with spaces or Turkish letters may have an encoded internal name such as `Fatura_x0020_No`.

### What the lists module needs in addition

| What | Why | Who |
|---|---|---|
| **`Sites.Selected`** with write access on the site (see the files module), or `Sites.ReadWrite.All` | Reading and writing items | Microsoft 365 / SharePoint administrator |
| For filters on large lists: an **index** on the filtered column (list settings → Indexed columns) | Without an index, SharePoint may refuse filters on lists with more than 5,000 items. The module sends the header `Prefer: HonorNonIndexedQueriesWarningMayFailRandomly`, which allows it for smaller lists. | Site owner |

### Install

After `ZCHE_GRAPH_CORE`: **SE38** → `ZCHE_GRAPH_LISTS_LIB` (type **Include program**) → paste [`src/zche_graph_lists_lib.prog.abap`](src/zche_graph_lists_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_LISTS` (type **Executable program**) → paste [`src/zche_graph_lists.prog.abap`](src/zche_graph_lists.prog.abap) → activate.

### Try it

Run `ZCHE_GRAPH_LISTS` with the host, the site path and the list name as SharePoint shows it.

| Action | Fields |
|---|---|
| **Show the lists of the site** | none |
| **Show the columns** | none |
| **Read items** | Columns (`Title,Amount`; empty means all), filter, at most N |
| **Create or change an item** | Item ID (empty creates a new item) and fields: `Title=Invoice 4711 \| Amount=1234.56 \| Paid=X` |
| **Update or create by key** | Key column (for example `Title`) and the fields, including the key's value |

### Use it in your own program

```abap
REPORT zmy_open_invoices_to_sharepoint.
INCLUDE zche_graph_core.
INCLUDE zche_graph_lists_lib.

DATA lo_client TYPE REF TO lcl_graph_client.
DATA lo_list TYPE REF TO lcl_graph_list.
DATA ls_config TYPE lif_graph=>ty_config.
DATA lt_fields TYPE lif_graph_lists=>ty_fields.
DATA ls_field TYPE lif_graph_lists=>ty_field.
DATA lx_graph TYPE REF TO lcx_graph.
DATA lv_id TYPE string.
DATA lv_created TYPE abap_bool.
DATA lv_text TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
TRY.
    lo_list = lcl_graph_list=>for_site( io_client = lo_client
                                        iv_host   = `contoso.sharepoint.com`
                                        iv_site   = `/sites/Finance`
                                        iv_list   = `Open invoices` ).
    " For each open item from SAP:
    CLEAR lt_fields.
    ls_field-name = `Title`.  ls_field-value = `4711`.     APPEND ls_field TO lt_fields.
    ls_field-name = `Amount`. ls_field-value = `1234.56`.  APPEND ls_field TO lt_fields.
    ls_field-name = `DueDate`. ls_field-value = `2026-11-30`. APPEND ls_field TO lt_fields.
    lo_list->upsert( EXPORTING iv_key = `Title` it_fields = lt_fields
                     IMPORTING ev_id = lv_id ev_created = lv_created ).
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

## Excel workbooks

> **Sign-in without a user.** Microsoft's reference pages for the Excel calls (for example [Get Range](https://learn.microsoft.com/en-us/graph/api/range-get) and [Create TableRow](https://learn.microsoft.com/en-us/graph/api/table-post-rows)) list application permissions as **"Not supported"**. This module signs in as an application, like the others. On a real test tenant all the calls of the program worked (see [What has been verified](#what-has-been-verified)), but the application also had the broad permission `Sites.FullControl.All` there. Whether they work with `Sites.Selected` alone is not known yet, and Microsoft may change what it allows. Uploading and downloading whole `.xlsx` files with the files module is not affected.

Read and write cells of an `.xlsx` file that is in a SharePoint library or a OneDrive, without downloading it. Typical uses:
- fill a planning or reporting workbook that the business keeps in SharePoint;
- read a price or rate table that the business maintains in Excel.

The module consists of the include `ZCHE_GRAPH_EXCEL_LIB` (class `LCL_GRAPH_EXCEL`) and the program `ZCHE_GRAPH_EXCEL`. It finds the file through the files module, so it needs `ZCHE_GRAPH_FILES_LIB` too.

- **Worksheets:** list them, add one.
- **Ranges:**
  - read, as stored values or as the text Excel shows (dates as dates, numbers formatted);
  - read everything that is filled on a sheet;
  - write from a start cell;
  - clear.
- **Excel tables** (*Insert → Table*): header, rows, add rows at the end. The table grows by itself, so formulas, pivot tables and charts that use it keep working.
- **Recalculate** the workbook.
- **Sessions:** keep the workbook open while you make many changes (`open_session` / `close_session`). This is faster. It is not a transaction: when a later change fails, the earlier ones stay written.

When writing, a cell that looks like a number (`1234`, `-12.5`, `1e-3`) goes as a number. A text starting with `=` is a formula. Any other text goes with a leading apostrophe, as you would type `'00123` in Excel. So `00123`, `+5` and dates like `2026-11-02` stay text, and material numbers keep their leading zeros. Excel does not show the apostrophe, and reading gives the text back without it. A row shorter than the others leaves the rest of its cells unchanged.

Excel cannot create a new file this way. Start from a workbook that exists, for example a template you uploaded once with the files module.

### Install

After `ZCHE_GRAPH_CORE` and `ZCHE_GRAPH_FILES_LIB`: **SE38** → `ZCHE_GRAPH_EXCEL_LIB` (type **Include program**) → paste [`src/zche_graph_excel_lib.prog.abap`](src/zche_graph_excel_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_EXCEL` (type **Executable program**) → paste [`src/zche_graph_excel.prog.abap`](src/zche_graph_excel.prog.abap) → activate. The permissions are the same as for the files module.

### Try it

Run `ZCHE_GRAPH_EXCEL` with the library (as in `ZCHE_GRAPH_FILES`) and the workbook's path, for example `Reports/sales.xlsx`.

| Action | Fields |
|---|---|
| **Show sheets and tables** | none |
| **Read a range** | Worksheet. Range: `A1:D20`, or empty / a single cell for everything that is filled. Optionally "As Excel shows it". |
| **Write values** | Worksheet, start cell (default `A1`) and values: `Date;Amount \| 2026-11-02;1234.5` (cells separated by `;`, rows by `\|`) |
| **Read a table** | Table name |
| **Add rows to a table** | Table name and values, as above |

### Use it in your own program

```abap
REPORT zmy_fill_sales_workbook.
INCLUDE zche_graph_core.
INCLUDE zche_graph_files_lib.
INCLUDE zche_graph_excel_lib.

DATA lo_client TYPE REF TO lcl_graph_client.
DATA lo_files TYPE REF TO lcl_graph_files.
DATA lo_excel TYPE REF TO lcl_graph_excel.
DATA ls_config TYPE lif_graph=>ty_config.
DATA lt_rows TYPE lif_graph_excel=>ty_rows.
DATA lt_row TYPE lif_graph_excel=>ty_row.
DATA lv_cell TYPE string.
DATA lx_graph TYPE REF TO lcx_graph.
DATA lv_text TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
TRY.
    lo_files = lcl_graph_files=>for_site( io_client = lo_client
                                          iv_host   = `contoso.sharepoint.com`
                                          iv_site   = `/sites/Sales` ).
    lo_excel = lcl_graph_excel=>for_file( io_client = lo_client io_files = lo_files
                                          iv_path   = `Reports/sales.xlsx` ).
    " For each line of your SAP data:
    CLEAR lt_row.
    lv_cell = `4711`.    APPEND lv_cell TO lt_row.
    lv_cell = `1234.56`. APPEND lv_cell TO lt_row.
    APPEND lt_row TO lt_rows.
    lo_excel->open_session( ).
    lo_excel->add_table_rows( iv_table = `Sales` it_rows = lt_rows ).
    lo_excel->close_session( ).
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

## Entra ID users and groups

Read the people of the company as Microsoft Entra ID knows them. Nothing is changed. Typical uses:
- find the manager of a requester for an approval;
- send a mail to the members of a group, for example "SAP approvers";
- find SAP users who have left: their Microsoft account is disabled or gone, but the SAP user is still active.

The module consists of the include `ZCHE_GRAPH_USERS_LIB` (class `LCL_GRAPH_USERS`) and the program `ZCHE_GRAPH_USERS`.

- **A user** by user principal name, e-mail address or ID: name, job title, department, office, phone, employee ID, company, and whether the account is enabled.
- **Users by a filter**, for example `department eq 'Finance'`, `employeeId eq '00001234'` or `accountEnabled eq false`. Without a filter: all users.
- **Manager and direct reports** of a user.
- **Groups of a user**, and **members of a group** (by its name or ID), optionally through nested groups.
- **SAP account check:** the active SAP dialog users (not locked, valid today) whose e-mail address in SU01 has no Microsoft account, or only a disabled one. The address is compared with the mail and the user principal name, without regard to case. Users without an address in SU01 are counted, not compared.

### What the users module needs in addition

| What | Why | Who |
|---|---|---|
| Application permission **`User.Read.All`** with admin consent | Reading users, managers, direct reports | Microsoft 365 / Entra administrator |
| Application permission **`GroupMember.Read.All`** with admin consent | Groups and their members | Microsoft 365 / Entra administrator |
| For the SAP account check: read access to `USR02`, `USR21` and `ADR6` | The program reads the user master directly | SAP authorization administrator |

These permissions cover every user and group of the company.

### Install

After `ZCHE_GRAPH_CORE`: **SE38** → `ZCHE_GRAPH_USERS_LIB` (type **Include program**) → paste [`src/zche_graph_users_lib.prog.abap`](src/zche_graph_users_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_USERS` (type **Executable program**) → paste [`src/zche_graph_users.prog.abap`](src/zche_graph_users.prog.abap) → activate.

### Try it

| Action | Fields |
|---|---|
| **Show a user** | User: address, user principal name or ID. Shows the details, the manager, the direct reports and the groups. |
| **Find users** | Filter (empty: all) and at most how many |
| **Members of a group** | Group name or ID; "Include nested groups" if wanted |
| **SAP users: account check** | SAP users (empty: all dialog users) |

The account check fits a monthly background job; its list goes to the spool.

### Use it in your own program

```abap
DATA lo_users TYPE REF TO lcl_graph_users.
DATA ls_manager TYPE lif_graph_users=>ty_user.
DATA lt_members TYPE lif_graph_users=>ty_users.

CREATE OBJECT lo_users EXPORTING io_client = lo_client.
ls_manager = lo_users->manager( `derya@contoso.com` ).
IF ls_manager IS INITIAL.
  " No manager set in Entra ID
ENDIF.
lt_members = lo_users->members( iv_group = `SAP approvers` iv_nested = abap_true ).
```

## Outlook calendar

Put SAP dates into Outlook calendars. Typical uses:
- a maintenance order becomes an event in the calendar of the maintenance team;
- a delivery or inspection date is sent as an invitation to the people involved;
- a shared calendar (of a shared mailbox) shows the dates of an SAP process.

The module consists of the include `ZCHE_GRAPH_CALENDAR_LIB` (class `LCL_GRAPH_CALENDAR`) and the program `ZCHE_GRAPH_CALENDAR`.

- **Create an event** in the calendar of a user or a shared mailbox: subject, text, time or whole days, location, required and optional attendees (they get an invitation), reminder, "show as", categories.
- **Your own key** (`transaction_id`), for example the order number: Microsoft creates an event only once per key, so running the same job twice does not make two events.
- **List** the events of a period, with the occurrences of series one by one.
- **Change** an event (attendees get the update), **cancel** it (attendees get the cancellation, with a comment) or **delete** it from this calendar only.
- **Teams meeting:** with `teams_meeting = X` Microsoft opens a Teams meeting and puts the join link into the invitation and into `join_url`. The organizer is the mailbox, so it needs a Teams licence; a shared mailbox has none.
- **Series:** daily, weekly or monthly, every n days, weeks or months, until a date or n times. A weekly series falls on the weekday of the first start, a monthly one on its day of the month, both counted in UTC; in a time zone with summer time a series keeps its UTC time, so it moves by an hour locally twice a year.
- **Who comes:** the list gives each attendee's answer (`accepted`, `declined`, `tentativelyAccepted`, `none`).
- **A free time:** the first 30 (or n) minutes in a window of a day when all given people are free; tentative counts as busy.

Dates and times are SAP dates and times in an SAP time zone, by default the user's (`SY-ZONLO`, set in SU01). They travel to Microsoft as UTC and come back in the same SAP time zone, so summer time is handled by SAP's own time zone tables.

### What the calendar module needs in addition

| What | Why | Who |
|---|---|---|
| Application permission **`Calendars.ReadWrite`** with admin consent | Creating and reading events | Microsoft 365 / Entra administrator |
| **Restriction to the SAP mailboxes** | Without it the application may write into **any** calendar of the company | Exchange Online administrator |

Restrict it as described for the e-mail module; with RBAC for Applications the role is `Application Calendars.ReadWrite`.

### Install

After `ZCHE_GRAPH_CORE`: **SE38** → `ZCHE_GRAPH_CALENDAR_LIB` (type **Include program**) → paste [`src/zche_graph_calendar_lib.prog.abap`](src/zche_graph_calendar_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_CALENDAR` (type **Executable program**) → paste [`src/zche_graph_calendar.prog.abap`](src/zche_graph_calendar.prog.abap) → activate.

### Try it

Run `ZCHE_GRAPH_CALENDAR` with the tenant and the mailbox whose calendar to use.

| Action | Fields |
|---|---|
| **List events** | Date (from) and date to |
| **Create an event** | Date, start and end time or "All day", subject; optionally location, attendees (`a@x.com; b@x.com`), text, reminder, your key; "Teams meeting"; repeat, every, until or times |
| **Find a free time** | Date, start and end of the window, length in minutes, attendees |
| **Cancel** | Event ID (from the list) and a comment |
| **Delete from this calendar** | Event ID |

### Use it in your own program

```abap
DATA lo_calendar TYPE REF TO lcl_graph_calendar.
DATA ls_event TYPE lif_graph_calendar=>ty_event.

CREATE OBJECT lo_calendar EXPORTING io_client = lo_client iv_mailbox = `maintenance@contoso.com`.
ls_event-subject = `Maintenance: press 3`.
ls_event-start_date = '20261110'.
ls_event-start_time = '090000'.
ls_event-end_time = '113000'.
ls_event-location = `Hall B`.
ls_event-transaction_id = `PM-4711`.
APPEND `derya@contoso.com` TO ls_event-attendees.
ls_event-teams_meeting = abap_true.
ls_event = lo_calendar->create( ls_event ).
" Keep ls_event-id with the order to change or cancel the event later;
" ls_event-join_url is the Teams link
```

## Teams channel messages

Post a message to a Microsoft Teams channel: a job ended with an error, a document waits for approval, the nightly run is done. The module consists of the include `ZCHE_GRAPH_TEAMS_LIB` (class `LCL_GRAPH_TEAMS`) and the program `ZCHE_GRAPH_TEAMS`; it needs only `ZCHE_GRAPH_CORE`.

Microsoft Graph does not let an application post to a channel. Teams has a **Workflows webhook** for this instead: a channel gets a long, secret address, and whatever is posted to it appears in the channel. No token and no Entra permission are involved, so this module does not use the sign-in of the others.

A message is a card (an *Adaptive Card*):
- a title in the colour of its level: `info`, `good`, `warning` or `error`;
- a text;
- name/value lines, for example `Order=4711 | Plant=1000`;
- a button that opens a link, for example to a Fiori app.

A message is not sent again after an error: it may have arrived already.

### What the Teams module needs

| What | Why | Who |
|---|---|---|
| In the channel: **⋯ → Workflows → "Send webhook alerts to a channel"**, saved. Teams then shows the address. | The address the messages go to | A member of the team |
| **SM59 destination, type G**: target host = the host of the address; port 443; path prefix = the rest of the address from the first `/` after the host, `?...&sig=...` included; SSL active, `ANONYM`; no logon data | The address is a secret: whoever has it can post to the channel. In SM59 it is kept like a password, and the code knows only the destination's name. | Basis |
| STRUST: the certificate of that host trusted; a proxy if SAP reaches the internet through one | As for the Microsoft hosts | Basis |

The workflow runs under the account that created it; when that person leaves, the workflow may stop. For a real system create it with a service account.

### Install

After `ZCHE_GRAPH_CORE`: **SE38** → `ZCHE_GRAPH_TEAMS_LIB` (type **Include program**) → paste [`src/zche_graph_teams_lib.prog.abap`](src/zche_graph_teams_lib.prog.abap). Then **SE38** → `ZCHE_GRAPH_TEAMS` (type **Executable program**) → paste [`src/zche_graph_teams.prog.abap`](src/zche_graph_teams.prog.abap) → activate.

### Try it

Run `ZCHE_GRAPH_TEAMS` with the SM59 destination, a title and a text. "Add system, user and time" adds three lines. As the last step of a background job it tells the channel that the steps before it have run.

### Use it in your own program

```abap
DATA lo_teams TYPE REF TO lcl_graph_teams.
DATA ls_card TYPE lif_graph_teams=>ty_card.

CREATE OBJECT lo_teams EXPORTING iv_destination = 'ZTEAMS_FINANCE'.
ls_card-title = `Payment run 2026-11-05 stopped`.
ls_card-text = `3 invoices without bank details`.
ls_card-level = `error`.
ls_card-facts = lcl_graph_teams=>facts_from_text( `Company code=1000 | Run=F110/0511` ).
ls_card-link_url = `https://sap.contoso.com/fiori#PaymentRun-manage`.
ls_card-link_title = `Open the payment run`.
lo_teams->send( ls_card ).
```

## Modules (plan)

| Module | Content | Status |
|---|---|---|
| Core + connection test | `ZCHE_GRAPH_CORE`, `ZCHE_GRAPH_CHECK` | v0.5.1 |
| E-mail | `ZCHE_GRAPH_MAIL_LIB`, `ZCHE_GRAPH_MAIL`: sending and reading, see above | v0.5.1 |
| SharePoint / OneDrive files | `ZCHE_GRAPH_FILES_LIB`, `ZCHE_GRAPH_FILES`, see above | v0.5.1 |
| SharePoint lists | `ZCHE_GRAPH_LISTS_LIB`, `ZCHE_GRAPH_LISTS`, see above | v0.5.1 |
| Excel workbooks | `ZCHE_GRAPH_EXCEL_LIB`, `ZCHE_GRAPH_EXCEL`, see above | v0.5.1 |
| Entra ID users and groups | `ZCHE_GRAPH_USERS_LIB`, `ZCHE_GRAPH_USERS`, see above | v0.6.0 |
| Outlook calendar | `ZCHE_GRAPH_CALENDAR_LIB`, `ZCHE_GRAPH_CALENDAR`, see above | v0.7.0 |
| Teams channel messages | `ZCHE_GRAPH_TEAMS_LIB`, `ZCHE_GRAPH_TEAMS`, see above | v0.7.0 |

## What has been verified

On an SAP ABAP Cloud Developer Trial 2025 (SAP_BASIS 816).

### Against a real Microsoft 365 tenant, 4 and 5 November 2026

A Microsoft 365 Business Basic test tenant, one app registration, the secret in SM59, the programs run from their selection screens.

> **Read this first:** besides `Organization.Read.All` and `Sites.Selected` (with `write` granted on one test site), the application also had **`Sites.FullControl.All`** during these tests. So the results show that the calls work. They do **not** show that `Sites.Selected` alone is enough, or that other sites and OneDrives stay closed. For e-mail and the calendar, the application had `Mail.Send`, `Mail.ReadWrite` and `Calendars.ReadWrite` for the whole tenant, without the mailbox restriction described above.

![ZCHE_GRAPH_CHECK on the test tenant](docs/img/check-connection.png)

- **Connection:** `ZCHE_GRAPH_CHECK` got a real token and called `GET /organization`, with the tenant given as domain and as GUID. A tenant that does not exist gave `AADSTS90002` and the hint.
- **Files:**
  - listing a folder;
  - a library by its name (`Belgeler`, the Turkish name of *Documents*), and the error that lists the libraries when the name is wrong;
  - creating a folder path twice, without a duplicate folder;
  - a folder name with Turkish letters and spaces;
  - a spool request uploaded as PDF (4,791 bytes) with `replace`, `rename` and `fail` (HTTP 409);
  - a file of 6,291,456 bytes downloaded to the application server, uploaded again in pieces and downloaded once more: the same SHA-256 every time.
- **Lists:**
  - lists and columns of a site, with internal names such as `M_x00fc__x015f_teriAd_x0131_` for "Müşteri Adı";
  - reading with chosen columns and a filter;
  - creating an item with text, number, yes/no, date and multiple choice;
  - refusing `12,5` as a number;
  - changing one field of an item;
  - update-or-create by `Title`, in both directions.
- **Excel, signed in as an application:** sheets and tables, reading a range as values and as shown text, writing values and a formula, reading a table, adding a row.
- **E-mail:** `ZCHE_GRAPH_MAIL` sent a short text mail from a shared mailbox to itself, then listed the unread mails of its inbox, with that mail in it.

![The test mail, read back from SAP](docs/img/mail-read.png)

- **Users and groups (5 November):** `ZCHE_GRAPH_USERS` listed the users, showed a shared mailbox's user (account disabled, as for every shared mailbox; no manager, no groups) and the members of a Microsoft 365 group by its name. The SAP account check read the users, but compared none: the SAP users of the trial have no e-mail address in SU01. The comparison itself is covered only by a unit test.
- **Calendar (5 November):** `ZCHE_GRAPH_CALENDAR` created an event from 10:00 to 10:30 (SAP time zone `TURKEY`) in a shared mailbox's calendar and listed it back with the same times. Run again with the same key, it got the same event back; the calendar still had one.
- **Teams meetings and free time (5 November, 0.7.0):** in a licensed user's calendar, a weekly Teams meeting twice, without attendees: both occurrences came back with the join link, then the series was deleted. The free-time search found 09:00–09:30 for two mailboxes, and no time in the half hour of the meeting.
- **Teams channel messages:** only unit tests, and the error for an SM59 destination that does not exist. No real channel yet.

Found on the tenant and fixed in 0.5.1:

- **Download:** SharePoint leaves `@microsoft.graph.downloadUrl` out when asked with `$select`. The module now asks with `select`, as Microsoft's [download page](https://learn.microsoft.com/en-us/graph/api/driveitem-get-content) shows.
- **Excel:** `00789` arrived as 789, because Excel takes a text like a typed entry. Texts now go with a leading apostrophe.

  ![00789 in E2 after 0.5.1](docs/img/excel-leading-zero.png)
- **`ZCHE_GRAPH_CHECK`:** the blank after "Permissions in the token:" was missing.

### Unit tests and made-up credentials, 2 November 2026

- **Excel module:** 8 unit tests pass with the same test double, covering:
  - column letters (A, Z, AA, ZZ, AAA) and block addresses;
  - values from text;
  - finding the workbook through the files module, and worksheets;
  - reading values and the shown text, and the used range;
  - writing a block (numbers, kept leading zeros, dates and `+5` as text, formulas, `null` for short rows);
  - the session header on every call;
  - reading a table and adding rows.

  `ZCHE_GRAPH_EXCEL` runs through to Microsoft's sign-in with made-up credentials.
- **Lists module:** 8 unit tests pass with the same test double, covering:
  - fields from text;
  - finding a site's list by the name shown (hidden lists left out);
  - column types, read once and then remembered;
  - reading items with chosen columns, a filter and the `Prefer` header, and multiple values joined with `;`;
  - creating an item with text, number, yes/no, multiple choice and lookup values in the right JSON form;
  - refusing a number written with a comma;
  - update-or-create in both directions.

  `ZCHE_GRAPH_LISTS` runs through to Microsoft's sign-in with made-up credentials.
- **Files module:** 9 unit tests pass with the same test double, covering:
  - paths with spaces;
  - finding a site and a library by name, and the error that lists the libraries that exist;
  - small and large uploads (pieces with the right `Content-Range`, no token on the upload URL);
  - download through the download URL;
  - listing over two pages;
  - creating only the missing folders of a path;
  - moving with renaming, and sharing links.

  `ZCHE_GRAPH_FILES` runs through to Microsoft's sign-in with made-up credentials.
- **E-mail module:** 8 unit tests pass with the same test double, covering:
  - the request body of a mail with recipients, HTML and an attachment;
  - a large mail: draft, attachment, upload session, three pieces with the right `Content-Range` and no token on the upload URL, then send;
  - reading a folder, attachment bytes, marking, moving, folders by name, address texts.
- **Spool to PDF:** a real spool request (an ABAP list) became a valid PDF of 20,215 bytes (it starts with `%PDF-1.3` and ends with `%EOF`). `ZCHE_GRAPH_MAIL` then attached it and stopped at sign-in, as expected with made-up credentials.
- **Core unit tests:** 16 ABAP Unit tests pass, with a test double instead of Microsoft. They cover:
  - JSON: objects, arrays, escapes including Turkish letters, numbers, errors;
  - the JSON writer;
  - the token request and caching;
  - sign-in error hints;
  - Graph errors;
  - retry after 429, a new token after 401, paging;
  - permissions in a token.
- **7.00 syntax:** [abaplint](https://abaplint.org) 2.120 reports no issues in 7.00 mode ([abaplint.json](abaplint.json)). abaplint does not catch everything 7.00 lacks, so the main rules were also checked by hand.
- **Live, with made-up credentials:** the destinations were created with a zero client ID and a placeholder secret.
  - TLS works to both Microsoft hosts.
  - Microsoft answered `AADSTS700038: 00000000-… is not a valid application identifier`. Microsoft could only know that ID from the basic authentication header, so SM59 does send the client ID and secret that way.
  - `graph.microsoft.com` answered `401 InvalidAuthenticationToken` with the `request-id` in the place the core reads it from.

**Not verified yet:**

- **E-mail against Microsoft:** HTML mails, attachments (also from spool), large mails, marking and moving. The mailbox restriction (RBAC for Applications) could not be set up: on the new tenant Exchange Online stopped at `Enable-OrganizationCustomization` with an error of its own.
- **Large attachments against Microsoft:** the upload URL host and the SICF proxy route.
- **Users and calendar against Microsoft:** the SAP account check with real addresses, managers and direct reports (none were set), nested groups; events with attendees and their answers, all-day events, changing and cancelling, monthly series, a series in a time zone with summer time, free time of people outside the company.
- **Least privilege:** the modules with `Sites.Selected` alone, and the refusal of a site or a OneDrive that was not granted.
- **SharePoint:** sharing links, moving and renaming, the route to `*.sharepoint.com` through a proxy.
- **Excel against Microsoft:** `null` for short rows; the apostrophe when adding table rows to a column that is not formatted as text (it was tried on a range, and on a table column that was already text). Large blocks may hit Microsoft's request size limits.
- **SharePoint lists against Microsoft:** lookup columns, deleting items, two jobs creating the same key at the same time (only a unit test with a made-up answer).
- **SAPscript / Smart Forms spool requests** (only an ABAP list was converted).
- **A real ABAP 7.00–7.02 system.** In particular, it is not verified that:
  - the SM59 user and password fields take a 36-character client ID and a 40-character secret;
  - the classes used (`CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`, `CL_ABAP_CONV_IN_CE`, `CL_ABAP_TSTMP`) behave the same.
- **SE38:** the programs were installed through ADT; pasting them in SE38 was not tried.
- **Proxy and real STRUST setup:** the trial already trusted Microsoft's certificates.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
