# Security

## Reporting an issue privately

Use **Security → Report a vulnerability** on this repository if the option is available; otherwise open an issue that only asks for a private contact, without the details.

Never put these into an issue, a screenshot or a log you share:

- the client secret, an access token, or the `Authorization` header;
- a Teams webhook address (the `sig=` part is the key: anyone who has it can post to the channel);
- tenant IDs, user and mailbox addresses, site names or file contents from your company.

Give the version line from the top of the source, the SAP_BASIS release, the module and a reproduction with made-up data. Fixes are made for the current version only.

## Where the secrets live

- **Client secret:** in the SM59 destination of the token call (user = client ID, password = secret). The code reads only the destination's name. Who may maintain SM59 (`S_ADMI_FCD`, `S_RFC_ADM`) decides who can see or change it.
- **Teams webhook:** the whole address is in an SM59 destination of type G. If it was ever shared, delete the flow in Teams Workflows, create it again and put the new address into SM59.
- **Tokens:** the core keeps the token in memory for the run of the program and does not store it anywhere.

Rotate the secret before it expires in Entra ID, and when someone who knew it leaves.

## What the application can reach

Microsoft Graph application permissions apply to the whole tenant unless you restrict them:

- **SharePoint and OneDrive:** prefer `Sites.Selected` and grant only the sites SAP needs.
- **E-mail and calendar:** restrict the application to the mailboxes SAP needs (RBAC for Applications in Exchange Online).
- Grant only the permissions of the modules you install.

Every SAP user who can run a program or a job that includes these modules acts with the application's permissions, not their own. Protect the programs with an authorization group or a transaction with its own authorization check, and check who can schedule them as jobs.

The tests behind this project ran with broader permissions than these (see [VALIDATION.md](VALIDATION.md)); the restrictions above are Microsoft's documented setup and were not all tried here.

## Türkçe

Güvenlik açığını varsa **Security → Report a vulnerability** ile bildirin. Issue, ekran görüntüsü veya log paylaşırken client secret'ı, token'ı, Teams webhook adresini (`sig=` kısmı anahtardır) ve şirketinize ait tenant ID, adres, site ya da dosya bilgisini koymayın.

Secret SM59'da durur; kod yalnız bağlantının adını bilir. Webhook adresi de SM59'dadır; bir yerde paylaşıldıysa Teams Workflows'ta akışı silip yeniden oluşturun ve yeni adresi SM59'a girin. Token yalnız program çalışırken bellekte tutulur.

Uygulama izinleri kısıtlanmadıkça bütün tenant için geçerlidir: SharePoint için `Sites.Selected`, e-posta ve takvim için posta kutusu kısıtlaması kullanın. Programı çalıştıran her SAP kullanıcısı uygulamanın izinleriyle iş yapar; programları yetki grubu veya kendi yetki kontrolü olan bir işlem koduyla koruyun.
