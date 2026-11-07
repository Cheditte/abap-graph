# Changelog

All versions are in `ZCHE_GRAPH_CORE` (`lif_graph=>version`) and in the header line of every source. Update every include and program together. What was tried against a real tenant is in [VALIDATION.md](VALIDATION.md).

## 0.8.0 — unreleased

Users and groups: two comparisons between Microsoft Entra ID and the SAP user master. Both only report. No new Microsoft permission is needed. Tried on SAP_BASIS 816 against the test tenant on 6 and 7 November (see [VALIDATION.md](VALIDATION.md)). abaplint (7.00) passed before the 7 November additions; they were not run through abaplint again.

- **Group against SAP role:** the members of a group against the users of an SAP role. Findings: in the group without the role, with the role outside the group, in the group without an SAP user, with the role but no address in SU01 (`LCL_GRAPH_USERS=>ROLE_USERS`, `COMPARE_ROLE`).
- **SU01 against Entra ID:** first name, last name, department and job title (`SAP_DETAILS`, `COMPARE_DETAILS`). An empty value in Entra ID is never proposed for SAP.
- Two unit tests for the comparisons.
- **Security:** the SAP side of every comparison now leaves out users whose user group the caller may not display (`S_USER_GRP`, activity 03). Before, the account check read every dialog user without an authorization check. Found by a scan with `ZCHE_AUTH_EXPLORER`.
- **The same checks as the on-premises Active Directory tool** (`ZCHE_LDAP_AD`, 7 November):
  - **Group against SAP role:** a member whose SAP user is locked or not valid today is reported as such (`sap_locked`). Before, it was reported as "no active SAP user has this address".
  - **SAP account check:** the new box "Locked in SAP, open in Entra" also lists the SAP users that are locked or not valid while an enabled Microsoft account has their address (`locked_open`). `COMPARE` has the optional `IV_REVERSE`; existing calls are unchanged.
  - **SU01 against Entra ID:** the telephone in SU01 is compared with the first business phone in Entra ID, by the last ten digits, so `+90 212 555 01 07` and `0212 555 0107` are the same line. An empty value in Entra ID is never proposed. "Show a user" shows the business phone.
  - The three SAP checks print how many SAP users were left out because the caller may not display them (`LCL_GRAPH_USERS=>SKIPPED`).
  - Two new unit tests and two extended; the 42 unit tests of `ZCHE_GRAPH_USERS` pass.

## 0.7.4 — 2026-11-05

Fixes from a second, independent code review. 105 unit tests pass on SAP_BASIS 816; not tried again on the tenant.

- **Calendar:** reading an event keeps its full text and kind (HTML or text); the short preview is a field of its own. Before, an event read and written back lost its text and the Teams join details.
- **Calendar:** "Delete" no longer promises that attendees are not told. In the organizer's calendar Microsoft sends them a cancellation.
- **Calendar:** with a maximum number of events, all-day events of the day before no longer take places in it; the list follows Microsoft's pages itself.
- **Lists:** blanks inside a multiple-choice value are kept (`ACME  LTD`).
- **E-mail:** whether a mail fits into one request is decided on the request itself, escaping included (limit 4,000,000 bytes, see `set_limits`).
- **Core:** SAP's HTTP client does not follow redirects itself.
- **Teams:** only HTTP 2xx counts as sent; a redirect gets a hint.
- **Excel:** a start cell or block that does not fit on a sheet is an error instead of an overflow dump.

## 0.7.3 — 2026-11-05

- **Teams:** the "Time" line of a card shows the user's own date and time (`SY-DATLO`, `SY-TIMLO`), not the server's clock.
- **Calendar:** the date `ZCHE_GRAPH_CALENDAR` proposes is the user's today.

## 0.7.2 — 2026-11-05

Second group of fixes from the 0.7.0 code review.

- **Files and e-mail:** upload pieces are retried after HTTP 429, 503 and 504. A failed upload closes its session; a failed large mail deletes its draft. An upload that ends with bytes missing is an error. The one-request size check counts the body too; HTTP 413 has a hint.
- **Core:** hints say "retried" only when a call was retried; a redirect (3xx) is an error.
- **Calendar:** all-day events of the day before are not listed; all-day events made in another time zone keep their date; a free-time search without people or with the end before the start is an error.
- **Lists:** several IDs for a multi-person column, columns whose own name ends in `LookupId`, clearing yes/no and date fields, number key columns in `upsert`.
- **Other:** guest addresses with `#`; decoded folder paths; the SAP account check stops above 100,000 users; a Teams error never repeats an answer that holds the webhook key.
- **Tests:** the weak tests of the review were strengthened (98 unit tests).

## 0.7.1 — 2026-11-05

First group of fixes from the 0.7.0 code review.

- An answer that is not UTF-8 gives the usual error instead of a dump.
- Faster JSON reading of large answers.
- In a background job, the job log shows the error itself.
- An unknown or missing time zone is an error instead of wrong times.
- `"Kaya, Derya" <derya@b.com>` is one recipient, not two.
- Lists: fields whose value is an object, and person columns that allow several people.
- Negative numbers are written as `-5` in JSON.
- Excel: the right address for adding a worksheet.

## 0.7.0 — 2026-11-05

- **Teams:** new module `ZCHE_GRAPH_TEAMS_LIB` / `ZCHE_GRAPH_TEAMS`: a card to a channel through a Workflows webhook whose address stays in SM59.
- **Calendar:** Teams meetings with join link, daily/weekly/monthly series, attendees' answers, first free time for several people.
- **E-mail:** attachments under 3 MB go in one request; the upload session is used from 3 MB on.
- GitHub Actions runs abaplint (7.00 mode) on every push and pull request.

## 0.6.0 — 2026-11-05

- **Users:** new module `ZCHE_GRAPH_USERS_LIB` / `ZCHE_GRAPH_USERS`: users, managers, groups and members, and SAP dialog users whose Microsoft account is disabled or missing.
- **Calendar:** new module `ZCHE_GRAPH_CALENDAR_LIB` / `ZCHE_GRAPH_CALENDAR`: create, list, change, cancel and delete events, SAP time converted to UTC.
- **Review fixes:** no second POST or PATCH after HTTP 503/504; blanks inside paths, names and filters are kept; the JSON writer escapes every control character; one number grammar for lists and Excel; `upsert` survives a parallel create; paging raises an error instead of returning a cut result.

## 0.5.1 — 2026-11-04

Fixes from the first real-tenant test.

- **Files:** downloads use `select`, because SharePoint leaves `@microsoft.graph.downloadUrl` out with `$select`.
- **Excel:** texts are written with a leading apostrophe, so `00789` stays `00789`.
- **`ZCHE_GRAPH_CHECK`:** a missing blank in the permissions line.

## 0.5.0 — 2026-11-02

- **Excel:** new module `ZCHE_GRAPH_EXCEL_LIB` / `ZCHE_GRAPH_EXCEL`: worksheets, ranges, blocks with numbers, formulas and leading zeros, tables, recalculation and sessions.

## 0.4.0 — 2026-11-02

- **Lists:** new module `ZCHE_GRAPH_LISTS_LIB` / `ZCHE_GRAPH_LISTS`: columns and items, filters, create, change, delete, update-or-create by a key column. Site lookup moved into the core.

## 0.3.0 — 2026-11-02

- **Files:** new module `ZCHE_GRAPH_FILES_LIB` / `ZCHE_GRAPH_FILES`: upload (large files in pieces), download, list, folders, move, rename, delete, sharing links, spool as PDF.

## 0.2.0 — 2026-11-02

- **E-mail:** new module `ZCHE_GRAPH_MAIL_LIB` / `ZCHE_GRAPH_MAIL`: text or HTML mail with attachments (spool as PDF, inline pictures, large attachments), reading folders, bodies and attachments, marking and moving.

## 0.1.0 — 2026-11-02

- **Core:** `ZCHE_GRAPH_CORE` with the token (client credentials, secret in SM59), HTTP through SM59, JSON reader and writer, retries, paging and errors with hints. `ZCHE_GRAPH_CHECK` tests the connection step by step.
