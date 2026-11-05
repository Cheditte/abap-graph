# abap-graph

> **English** | [Türkçe](README.tr.md)

**Work with Microsoft 365 mail, files and calendars from SAP.**

I developed this project to reduce repeated connection and operation code when working with Microsoft 365 from SAP. It brings together example programs and the files they need, so you can use and adapt them in your own system.

**Install only the part you need.** Sending a Teams channel notification does not require the mail or Excel sections. Use the supplied screens to try an operation, then work with an ABAP developer to connect it to your business process.

**[Illustrated setup and first-use roadmap →](WALKTHROUGH.md)**

## What would you like to do?

| Your task | Where to start |
| --- | --- |
| Send a notification to a Teams channel | [Teams notifications](docs/guides/teams.md) |
| Create a Teams meeting link or read a calendar | [Calendar and meetings](docs/guides/calendar.md) |
| Send mail from a mailbox or read incoming messages | [E-mail](docs/guides/mail.md) |
| Upload or download SharePoint / OneDrive files | [Files](docs/guides/files.md) |
| Read or change cells in an existing Excel workbook | [Excel — read the support limitation](docs/guides/excel.md) |
| Work with records in a SharePoint list | [Lists](docs/guides/lists.md) |
| List Microsoft users and group members | [Users and groups](docs/guides/users.md) |

## Three things to prepare

1. **Choose your task.** Identify the mailbox, file, site or Teams channel you want to use.
2. **Prepare access.** Set up the required Microsoft permissions and SAP connection. If another team manages them, share the relevant guide with that team.
3. **Add the required files to SAP.** Install the shared helper and the files for your chosen task, then try the first operation in a test system.

Microsoft Graph is the interface that lets programs access Microsoft 365 services. You do not install Graph on your computer. Teams channel notifications use a separate Workflows connection; each guide explains the preparation it needs.

## Status and compatibility

| Topic | Status |
| --- | --- |
| Source version | 0.8.0; unreleased development version |
| Test environment | A4H/001, SAP_BASIS 816 and a Microsoft 365 test tenant; coverage varies by version and operation |
| Older SAP systems | Targets classic ABAP 7.00 syntax; ECC 6.0 has not been tested |
| Excel cell operations | Microsoft has a support limitation for the sign-in method used; use Files to transfer whole `.xlsx` files |

[Test results and remaining gaps →](VALIDATION.md)

## Explore further

- **Setup and first use:** [illustrated roadmap](WALKTHROUGH.md)
- **Fields, permissions and use in your own ABAP code:** [technical reference](TECHNICAL.md)
- **Source files:** [src folder](src)

---

[MIT license](LICENSE) · [Issues and feedback](https://github.com/Cheditte/abap-graph/issues)
