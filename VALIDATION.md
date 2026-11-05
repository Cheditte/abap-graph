# Validation record

What was tried, on which system, and with which version. The details of each run are in the [README](README.md#what-has-been-verified).

**Test system:** SAP ABAP Cloud Developer Trial 2025 (SAP_BASIS 816), objects installed through ADT. **Test tenant:** Microsoft 365 Business Basic, one app registration, the secret in SM59.

| Check | Version | Result |
|---|---|---|
| ABAP Unit with a test double instead of Microsoft | 0.7.4 | 105 tests pass |
| abaplint in 7.00 mode (GitHub Actions) | 0.7.4 | No findings |
| Connection: token, `GET /organization`, tenant as domain and GUID, unknown tenant | 0.5.1 | Passed on the tenant |
| Files: list, library by name, folder paths, spool as PDF, 6 MB upload and download (same SHA-256) | 0.5.1 | Passed on the tenant |
| Lists: columns, read with filter, create, change, update-or-create | 0.5.1 | Passed on the tenant |
| Excel with application sign-in: sheets, ranges, formulas, tables | 0.5.1 | Passed on the tenant |
| E-mail: send from a shared mailbox, read the inbox | 0.5.1 – 0.7.2 | Passed on the tenant |
| Users and groups | 0.6.0 | Passed on the tenant (no SAP e-mail addresses to compare) |
| Calendar: events, Teams meeting series with join link, free time, delete | 0.6.0 – 0.7.2 | Passed on the tenant |
| Teams card through a Workflows webhook | 0.7.2 | Arrived in the channel |
| 0.7.3 and 0.7.4 changes | 0.7.3, 0.7.4 | Unit tests only; not tried again on the tenant |

## Not verified

- **A real ABAP 7.00–7.02 system.** The code targets 7.00 syntax; runtime behaviour there (SM59 field lengths for the client ID and secret, the HTTP and conversion classes) is not confirmed.
- **Least privilege.** During the tenant tests the application also held `Sites.FullControl.All`, and the mail and calendar permissions applied to the whole tenant. The results show that the calls work, not that `Sites.Selected` or a mailbox restriction is enough.
- **SE38 copy and paste**, a proxy route, a real STRUST setup.
- The longer list per module is in the README under "Not verified yet".

Reports from other systems are welcome: give the SAP_BASIS release, the version line of the source and what you ran, without tenant IDs, addresses or secrets.

## Türkçe

Testler SAP ABAP Cloud Developer Trial 2025 (SAP_BASIS 816) ve bir Microsoft 365 Business Basic deneme tenant'ında yapıldı. 0.7.4'te 105 birim testi geçiyor ve abaplint 7.00 modunda bulgu vermiyor. Bağlantı, dosyalar, listeler, Excel, e-posta, kullanıcılar, takvim ve Teams kartı 0.5.1–0.7.2 sürümlerinde gerçek tenant'ta denendi. 0.7.3 ve 0.7.4 değişiklikleri yalnız birim testleriyle doğrulandı.

Doğrulanmayanlar: gerçek bir 7.00–7.02 sistemi, en az yetkiyle çalışma (testlerde uygulamada `Sites.FullControl.All` da vardı), SE38'e yapıştırarak kurulum, proxy ve gerçek STRUST kurulumu. Ayrıntılar [README.tr.md](README.tr.md) içinde.
