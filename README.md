# abap-graph

> **English** | [Türkçe](README.tr.md)

Connect SAP with Microsoft 365 from ABAP alone, through **Microsoft Graph**: no middleware, no add-on. A shared core does the sign-in, the HTTP calls, JSON, retries and paging. Modules for each Microsoft product build on it: e-mail first, then SharePoint/OneDrive, Lists, Excel, Entra ID, calendar.

- **Copy and paste:** you paste the source into SE38. No tables, no dictionary objects; abapGit is optional.
- **ABAP 7.00 syntax:** runs on ECC 6.0 and later, S/4HANA included.
- **The secret stays in SM59:** the code never sees it.

> **Status: v0.3, not released.** The core, the connection test, the e-mail module and the files module work on an SAP ABAP Platform 2023 trial with a test double and up to Microsoft's sign-in, but no call has been made with a real Microsoft 365 tenant yet (see [What has been verified](#what-has-been-verified)).

## How it works

```
SAP program ──INCLUDE zche_graph_core──┐
                                        ├─ SM59 ZCHE_GRAPH_LOGIN ──> login.microsoftonline.com  (token)
                                        └─ SM59 ZCHE_GRAPH_API   ──> graph.microsoft.com        (calls)
```

1. The application signs in with the **OAuth2 client credentials** flow. The client ID and secret travel as HTTP basic authentication from SM59 destination `ZCHE_GRAPH_LOGIN`; Microsoft accepts this (`client_secret_basic`). The token is kept until five minutes before it expires.
2. Calls go through SM59 destination `ZCHE_GRAPH_API` with that token.
3. HTTP 429, 503 and 504 are retried after the time Microsoft asks for (`Retry-After`, at most 60 seconds). HTTP 401 gets one new token. Other errors raise `LCX_GRAPH` with Microsoft's error code, message, `request-id` and a hint on what to check.

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

## E-mail module

Send and read mail as one mailbox, for example `sap@contoso.com`. The module consists of the include `ZCHE_GRAPH_MAIL_LIB` (class `LCL_GRAPH_MAIL`) and the program `ZCHE_GRAPH_MAIL`, which sends a test mail or lists a folder.

**Sending:**
- text or HTML, To/Cc/Bcc, reply-to, importance;
- attachments of any kind, including a spool request as PDF (ABAP list, SAPscript or Smart Forms);
- inline pictures for HTML (`<img src="cid:logo">`);
- mails up to about 2.9 MB of attachments in one call. Larger mails are created as a draft, get their attachments one by one (single attachments over 2.9 MB in pieces of 3.2 MB, up to 150 MB) and are then sent.

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
| For attachments over 2.9 MB: SAP may reach `outlook.office.com` with HTTPS (SICF proxy settings, STRUST) | Microsoft hands out an upload URL on that host; no SM59 destination is used for it | Basis |

**Restricting the mailboxes.** Exchange Online offers two ways. Check Microsoft's current documentation for which to use; Microsoft now recommends the first.

1. **RBAC for Applications:** a management scope with the SAP mailboxes, and the application roles `Application Mail.Send` / `Application Mail.ReadWrite` on that scope only. When you use this, do **not** also grant the tenant-wide `Mail.*` permissions in Entra ID.
2. **Application access policy (older):** keep the permissions in Entra ID and limit them with PowerShell (Exchange Online module):
   ```powershell
   New-DistributionGroup -Name "SAP Graph mailboxes" -Type Security -Members sap@contoso.com
   New-ApplicationAccessPolicy -AppId <application (client) ID> -PolicyScopeGroupId "SAP Graph mailboxes" -AccessRight RestrictAccess -Description "abap-graph"
   Test-ApplicationAccessPolicy -Identity sap@contoso.com -AppId <application (client) ID>
   ```

Neither way has been tried with this project yet.

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

**Granting a site to the application (`Sites.Selected`).** An administrator does this once per site. Two common ways; check Microsoft's current documentation, as neither has been tried with this project yet:

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

## Modules (plan)

| Module | Content | Status |
|---|---|---|
| Core + connection test | `ZCHE_GRAPH_CORE`, `ZCHE_GRAPH_CHECK` | v0.3 |
| E-mail | `ZCHE_GRAPH_MAIL_LIB`, `ZCHE_GRAPH_MAIL`: sending and reading, see above | v0.3 |
| SharePoint / OneDrive files | `ZCHE_GRAPH_FILES_LIB`, `ZCHE_GRAPH_FILES`, see above | v0.3 |
| SharePoint Lists, Excel, Entra ID users, calendar, Teams notifications | | planned |

## What has been verified

On an SAP ABAP Platform 2023 trial (SAP_BASIS 7.58), 2 November 2026:

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

- **A real token and a successful Graph call.** No Microsoft 365 tenant was available. So no mail has actually been sent or read; Microsoft's answers are known only from its documentation.
- **Large attachments against Microsoft:** the upload URL host and the SICF proxy route.
- **Mailbox restriction** (RBAC for Applications or an application access policy).
- **SharePoint:** granting a site with `Sites.Selected`, real uploads and downloads, and the route to `*.sharepoint.com` through the SICF proxy.
- **SAPscript / Smart Forms spool requests** (only an ABAP list was converted).
- **A real ABAP 7.00–7.02 system.** In particular, it is not verified that:
  - the SM59 user and password fields take a 36-character client ID and a 40-character secret;
  - the classes used (`CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`, `CL_ABAP_CONV_IN_CE`, `CL_ABAP_TSTMP`) behave the same.
- **SAP GUI:** the selection screen was not looked at, and pasting in SE38 was not tried.
- **Proxy and real STRUST setup:** the trial already trusted Microsoft's certificates.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
