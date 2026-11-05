# SAP and Microsoft 365: setup roadmap

[Project overview](README.md) · **English** | [Türkçe — illustrated guides](WALKTHROUGH.tr.md)

Start with the operation you need. Each section below links to its detailed setup and a guide with real SAP and Microsoft screenshots. The illustrated module guides are currently in Turkish; the technical instructions and ABAP examples are available in English.

## 1. Choose your route

### Teams channel notifications

Send a card to a Teams channel. Create a Teams Workflow for that channel, store its connection in SAP, and send a sample card. This route uses its own connection; it does not need the Graph application registration, the two Graph destinations or the connection-check program below.

[English instructions](TECHNICAL.md#teams-channel-messages) · [Screenshots](docs/guides/teams.tr.md)

### Calendar and Teams meetings

Read a calendar or create an event with a Teams join link. Prepare access to the chosen mailbox; Teams meetings also need a suitable licensed account. Start with a test event without attendees and check its time in Outlook.

[English instructions](TECHNICAL.md#outlook-calendar) · [Screenshots](docs/guides/calendar.tr.md)

### E-mail

Read incoming messages or send a message from a mailbox. Prepare access to that mailbox, read a small set of messages, then send a test message and check its delivery in Outlook.

[English instructions](TECHNICAL.md#e-mail-module) · [Screenshots](docs/guides/mail.tr.md)

### Files

Upload, download or list files in SharePoint or OneDrive. Prepare access to a test location, list a folder first, then transfer a sample file. This route also handles complete `.xlsx` files.

[English instructions](TECHNICAL.md#sharepoint-and-onedrive-files) · [Screenshots](docs/guides/files.tr.md)

### Excel cells

Read or change cells in an existing workbook. **Read the support limitation first:** the project signs in as an application, which Microsoft does not list as supported for these Workbook API operations. The tests used broad site permissions; they do not establish support with a restricted configuration. Use Files if you only need to transfer a whole workbook.

[Support limitation and English instructions](TECHNICAL.md#excel-workbooks) · [Screenshots](docs/guides/excel.tr.md)

### SharePoint lists

Read or update records in a SharePoint list. Prepare access to a test site and list, read its existing records, then try one new test record and check it in SharePoint.

[English instructions](TECHNICAL.md#sharepoint-lists) · [Screenshots](docs/guides/lists.tr.md)

### Users and groups

List Microsoft users and group members. Start with a search limited to five users, then compare the names with your Microsoft environment. These operations read account information without changing accounts or membership.

[English instructions](TECHNICAL.md#entra-id-users-and-groups) · [Screenshots](docs/guides/users.tr.md)

## 2. Prepare the connection your route needs

For mail, calendars, files, lists, users and Excel:

1. **Microsoft preparation:** register an application and grant only the access required for your task. A tenant is your organization's Microsoft environment; the application registration identifies SAP to it.
2. **SAP preparation:** configure the sign-in and API connections in SM59, SAP's connection settings. Your SAP application server must be able to reach Microsoft over HTTPS.
3. **First connection:** run the supplied check program to check the destinations and application sign-in. The final default `/organization` call has its own permission requirement; a successful sign-in and a denied final call are different results.

[Detailed connection setup](TECHNICAL.md#set-up) · [Connection screenshots](docs/guides/connection.tr.md)

**Only sending Teams channel notifications?** Follow the [Teams route](#teams-channel-notifications) instead. Do not create the two Graph connections just for that task.

## 3. Install the selected files and try one operation

Add `ZCHE_GRAPH_CORE`, the shared helper file, once. Then add only the files required by your chosen route. The section's **Install** instructions give their names and types for SE38, the SAP program editor.

- Excel also needs the Files **library**, but not the Files screen or Mail library.
- The supplied Files screen also uses the Mail **library** for PDF conversion. It does not need mail permissions.
- You need SAP development authorization to install the files. If another person handles installation, give them the instructions for your selected route.

[File structure and dependencies](TECHNICAL.md#file-structure-and-use-cases) · [SE38 screenshots](docs/guides/install.tr.md)

Use a development or test system for the first run. Check the result in SAP and, where relevant, in Outlook, Teams or SharePoint. The supplied screens let you try operations; connecting them to an existing business process requires ABAP development.

## Read the evidence in context

The screenshots come from A4H/001 and a Microsoft 365 test environment. Names, addresses, IDs and dates are examples: use your own values. Captions distinguish field examples from executed results and identify older test versions. Neither ECC 6.0 runtime compatibility nor a least-privilege setup has been fully verified.

[Validation records](VALIDATION.md) · [Technical reference](TECHNICAL.md) · [Back to project overview](README.md)
