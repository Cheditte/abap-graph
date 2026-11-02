# abap-graph

> **English** | [Türkçe](README.tr.md)

Connect SAP with Microsoft 365 from ABAP alone, through **Microsoft Graph**: no middleware, no add-on. A shared core does the sign-in, the HTTP calls, JSON, retries and paging. Modules for each Microsoft product build on it: e-mail first, then SharePoint/OneDrive, Lists, Excel, Entra ID, calendar.

- **Copy and paste:** you paste the source into SE38. No tables, no dictionary objects; abapGit is optional.
- **ABAP 7.00 syntax:** runs on ECC 6.0 and later, S/4HANA included.
- **The secret stays in SM59:** the code never sees it.

> **Status: v0.1, core only, not released.** The core and the connection test work on an SAP ABAP Platform 2023 trial, but no call has been made with a real Microsoft 365 tenant yet (see [What has been verified](#what-has-been-verified)). The e-mail module comes next.

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

## Modules (plan)

| Module | Content | Status |
|---|---|---|
| Core + connection test | this repository | v0.1 |
| E-mail | Send (HTML, attachments, spool as PDF, large attachments), then read mailboxes | next |
| SharePoint / OneDrive | Upload, download, list, folders, sharing links | planned |
| SharePoint Lists, Excel, Entra ID users, calendar, Teams notifications | | planned |

## What has been verified

On an SAP ABAP Platform 2023 trial (SAP_BASIS 7.58), 2 November 2026:

- **Unit tests:** 16 ABAP Unit tests pass, with a test double instead of Microsoft. They cover:
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

- **A real token and a successful Graph call.** No Microsoft 365 tenant was available.
- **A real ABAP 7.00–7.02 system.** In particular, it is not verified that:
  - the SM59 user and password fields take a 36-character client ID and a 40-character secret;
  - the classes used (`CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`, `CL_ABAP_CONV_IN_CE`, `CL_ABAP_TSTMP`) behave the same.
- **SAP GUI:** the selection screen was not looked at, and pasting in SE38 was not tried.
- **Proxy and real STRUST setup:** the trial already trusted Microsoft's certificates.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
