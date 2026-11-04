# abap-graph

> [English](README.md) | **Türkçe**

SAP'yi Microsoft 365 ile yalnızca ABAP kullanarak, **Microsoft Graph** üzerinden konuşturur. Araya middleware ya da eklenti girmez.

**Ortak çekirdek** şunları yapar:
- giriş (token alma);
- HTTP çağrıları;
- JSON okuma ve yazma;
- yeniden denemeler ve sayfalama.

**Ürün modülleri** bunun üstüne kurulur: e-posta, SharePoint/OneDrive, Listeler, Excel, Entra ID, takvim ve Teams.

- **Kopyala-yapıştır:** kaynak SE38'e yapıştırılır. Tablo ya da sözlük nesnesi yok; abapGit isteğe bağlı.
- **ABAP 7.00 sözdizimi:** ECC 6.0 ve sonrası için yazıldı, S/4HANA dahil. Şimdiye kadar yalnız SAP_BASIS 816'da çalıştı; bkz. [Neler doğrulandı](#neler-doğrulandı).
- **Gizli anahtar SM59'da durur:** kod onu hiç görmez.

> **Durum: v0.7.0, henüz yayınlanmadı.** Çekirdek, bağlantı testi ve e-posta, dosya, liste, Excel, kullanıcı ve takvim modülleri SAP ABAP Cloud Developer Trial sisteminden gerçek bir Microsoft 365 test tenant'ına karşı denendi; Teams modülü henüz gerçek bir kanalla denenmedi. En az yetkiyle ve gerçek bir 7.00 sisteminde denenmedi (bkz. [Neler doğrulandı](#neler-doğrulandı)).

## Nasıl çalışır

```
SAP programı ──INCLUDE zche_graph_core──┐
                                         ├─ SM59 ZCHE_GRAPH_LOGIN ──> login.microsoftonline.com  (token)
                                         └─ SM59 ZCHE_GRAPH_API   ──> graph.microsoft.com        (çağrılar)
```

1. **Giriş:** uygulama **OAuth2 client credentials** akışıyla giriş yapar.
   - Client ID ve secret, SM59 hedefi `ZCHE_GRAPH_LOGIN`'den HTTP Basic kimlik doğrulamasıyla gider; Microsoft bunu kabul ediyor (`client_secret_basic`).
   - Token, süresinin dolmasına beş dakika kalana kadar saklanır.
2. **Çağrılar:** SM59 hedefi `ZCHE_GRAPH_API` üzerinden, bu token'la yapılır.
3. **Hatalar:**
   - HTTP 429'da Microsoft'un istediği süre beklenip yeniden denenir (`Retry-After`, en fazla 60 saniye).
   - HTTP 503 ve 504'te aynısı yalnız GET, PUT ve DELETE için yapılır. POST ya da PATCH (e-posta gönderme, kayıt oluşturma) hatadan önce yerine getirilmiş olabilir; bu yüzden tekrar gönderilmez ve hata, sonucun belirsiz olduğunu söyler.
   - HTTP 401'de bir kez yeni token alınır.
   - Diğer hatalarda `LCX_GRAPH` fırlatılır. İçinde Microsoft'un hata kodu, mesajı, `request-id` ve neyin kontrol edileceğine dair bir ipucu vardır.

## Neler gerekiyor

| Ne | Neden | Kimden |
|---|---|---|
| SAP_BASIS 7.00 ya da üstü; internete (ya da proxy üzerinden) giden HTTPS | Çağrılar Microsoft'un bulutuna gider | Basis, ağ ekibi |
| **TLS 1.2** destekleyen çekirdek ve CommonCryptoLib | Microsoft yalnızca TLS 1.2 ve üstünü kabul ediyor. Eski çekirdeklerde güncelleme gerekebilir. | Basis |
| Microsoft 365 tenant'ı ve Microsoft Entra ID'de bir **uygulama kaydı** | SAP'nin Microsoft karşısındaki kimliği | Microsoft 365 / Entra yöneticisi |
| Modül başına, yönetici onaylı **uygulama izinleri** | Örneğin e-posta için `Mail.Send`. Bağlantı testi için izin gerekmez. | Microsoft 365 / Entra yöneticisi |
| Geliştirici anahtarı | Bir include ve bir program oluşturmak için | Geliştirici |

## Kurulum

### 1. Microsoft Entra ID: uygulamayı kaydedin

[Microsoft Entra yönetim merkezinde](https://entra.microsoft.com) **App registrations → New registration**.

1. **Ad:** örneğin `SAP abap-graph PRD`. **Accounts in this organizational directory only** seçin. Redirect URI gerekmez.
2. **Overview** sayfasından iki değeri not edin:
   - **Application (client) ID:** SM59'da *kullanıcı* olur;
   - **Directory (tenant) ID:** programlara bu girilir.
3. **Certificates & secrets → New client secret.** Secret'ın **Value** değerini hemen kopyalayın; yalnızca bir kez gösterilir. *Secret ID* secret değildir. Bitiş tarihini not edin: secret'ın süresi dolunca bağlantı durur.
4. **API permissions:** modüllerin istediği **uygulama** (application) izinlerini ekleyip **Grant admin consent** deyin. Yalnızca bağlantı testi için izin gerekmez.

Uygulamanın erişimini sınırlayın. Tek başına `Mail.Send`, **her** posta kutusu adına gönderebilir. Modül rehberleri bunu belirli posta kutularıyla ya da sitelerle nasıl sınırlayacağınızı anlatıyor.

### 2. Basis: sertifikalar (STRUST)

`https://login.microsoftonline.com` ve `https://graph.microsoft.com` adreslerini tarayıcıda açın, sertifika zincirine bakın ve kök ile ara sertifikaları dışa aktarın. **STRUST**'ta bunları hedeflerin kullandığı SSL client PSE'ye aktarın (aşağıdaki adımlarda **SSL Client Anonymous**) ve kaydedin. Sürümünüz gerektiriyorsa ICM'yi yeniden başlatın.

Test için kullanılan deneme sisteminde iki adres zaten güvenilir durumdaydı.

### 3. Basis: iki SM59 hedefi (G tipi, "dış sunucuya HTTP bağlantısı")

| Alan | `ZCHE_GRAPH_LOGIN` | `ZCHE_GRAPH_API` |
|---|---|---|
| Hedef host | `login.microsoftonline.com` | `graph.microsoft.com` |
| Servis no. (port) | `443` | `443` |
| Path prefix | boş | boş |
| Logon & Security | **Basic authentication**: kullanıcı = Application (client) ID, şifre = secret'ın *Value* değeri | **Oturum açma yok** |
| SSL | Etkin, sertifika listesi **ANONYM** (SSL Client Anonymous) | Etkin, **ANONYM** |
| Proxy | SAP internete proxy üzerinden çıkıyorsa proxy'niz | aynı |

Hedef adları farklı olabilir; programlarda girilebiliyor.

### 4. Kurulum (kopyala-yapıştır)

1. **SE38** → program `ZCHE_GRAPH_CORE` → **Oluştur** → tür **Include program** → paketinize kaydedin (ilk deneme için **Yerel nesne** de olur). [`src/zche_graph_core.prog.abap`](src/zche_graph_core.prog.abap) dosyasını yapıştırıp kaydedin. Bir sonraki adımdaki programla birlikte aktifleşir.
2. **SE38** → program `ZCHE_GRAPH_CHECK` → **Oluştur** → tür **Yürütülebilir program**. [`src/zche_graph_check.prog.abap`](src/zche_graph_check.prog.abap) dosyasını yapıştırıp aktifleştirin (**Ctrl+F3**). Sorulursa include'u da aktifleştirin.
3. İsteğe bağlı: `ZCHE_GRAPH_CHECK`'in birim testlerini çalıştırın (**Program → Yürüt → Birim testleri** ya da ADT'de **Ctrl+Shift+F10**). 16 testin geçmesi gerekir. Testler Microsoft'u çağırmaz.

İkinci bir program da `ZCHE_GRAPH_CORE`'u kullanmaya başladıktan sonra include'u aktifleştirirseniz, SAP hangi ana program içinde kontrol edeceğini sorar. Herhangi birini seçin.

**Aktifleştirirken "satır çok uzun" hatası alırsanız:** SE38'de **Yardımcı programlar → Ayarlar → ABAP Editor → Editör** altında **Downwards-compatible line length (72)** işaretini kaldırıp tekrar yapıştırın.

**Alternatif: abapGit.** Bu repoyu bir pakete de çekebilirsiniz.

### 5. Bağlantıyı test edin

`ZCHE_GRAPH_CHECK`'i çalıştırıp **Directory (tenant) ID**'yi girin. Program her adımı kontrol eder ve neyin eksik olduğunu söyler:

1. **SM59 hedefleri:** ikisi de var ve G tipinde.
2. **Giriş:** Microsoft uygulamaya token veriyor; bu, client ID, secret ve tenant'ın doğru olduğunu gösterir. Program token'daki izinleri de listeler.
3. **Bir Graph çağrısı:** varsayılan `/organization`; `Organization.Read.All` izni gerekir. İzin yoksa da "HTTP 403, yalnızca izin eksik" sonucu bağlantının çalıştığını gösterir.

Sık görülen cevaplar:

| Mesaj | Anlamı |
|---|---|
| `AADSTS7000215` | Secret yanlış: *Secret ID* değil, *Value* girilmeli |
| `AADSTS7000222` | Secret'ın süresi dolmuş |
| `AADSTS700016`, `AADSTS700038` | Application (client) ID ya da tenant yanlış |
| `AADSTS90002` | Tenant bulunamadı |
| No connection through SM59 destination … | Host, port, SSL, STRUST sertifikaları, proxy ya da TLS 1.2 |

## Çekirdeği kendi programınızda kullanmak

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
    lv_name = lx_graph->if_message~get_longtext( ).   " metin, ipucu ve request-id
ENDTRY.
```

| Parça | Görevi |
|---|---|
| `LCL_GRAPH_CLIENT` | `get_json`, `get_pages` (`@odata.nextLink`'i takip eder), `send_json` (POST/PATCH/PUT), `delete_path`, `request` (her türlü çağrı, ikili gövde dahil) |
| `LCL_GRAPH_JSON` | Cevapları yol ile okur: `get( 'value/0/id' )`, `count( 'value' )`, `names( '' )`, `exists`, `kind_of` |
| `LCL_GRAPH_JSON_WRITER` | İstek gövdesi oluşturur: `begin_object`, `add_string`, `add_number`, `add_boolean`, `begin_array`, … |
| `LCL_GRAPH_CONV` | UTF-8, Base64 (ekler için), URL kodlama |
| `LCX_GRAPH` | HTTP durumu, Microsoft hata kodu, `request-id`, ipucu |

### Microsoft çağrıları ve SAP işlemleri (transaction)

Microsoft'a yapılan çağrı SAP işleminin parçası değildir: gönderilen e-posta ya da oluşturulan kayıt, programınız sonra hata verse ya da geri alsa (rollback) da kalır. Ayrıca çekirdek, HTTP 429 sonrası yeniden denerken `WAIT UP TO` ile bekler; bu da programınızın açık veritabanı değişikliklerini kaydeder (commit). Bu yüzden:
- modülleri veritabanı değişiklikleriniz ile commit arasında değil, `COMMIT WORK`'ten **sonra** çağırın;
- bir çağrı kaybolmamalıysa, gönderilecek olanı aynı işlemde kendi tablonuza yazın; bir iş onu göndersin ve gönderildi diye işaretlesin (*outbox*).

HTTP çağrısının kendisinin de veritabanını kaydedip kaydetmediği ölçülmedi.

## E-posta modülü

Tek bir posta kutusu adına (örneğin `sap@contoso.com`) e-posta gönderir ve okur. Modülün iki nesnesi var:
- `ZCHE_GRAPH_MAIL_LIB` include'u (sınıf `LCL_GRAPH_MAIL`);
- `ZCHE_GRAPH_MAIL` programı: deneme e-postası gönderir ya da bir klasörü listeler.

**Gönderme:**
- metin ya da HTML, Kime/Bilgi/Gizli, yanıt adresi, önem;
- her türlü ek; spool talebi de PDF olarak eklenebilir (ABAP listesi, SAPscript ya da Smart Forms);
- HTML içinde gömülü resimler (`<img src="cid:logo">`);
- ekleri toplam yaklaşık 2,9 MB'a kadar olan e-postalar tek çağrıda gider.
- Daha büyükleri önce taslak olarak oluşturulur, ekler tek tek eklenir ve sonra gönderilir. 3 MB ve daha büyük bir ek yükleme oturumuyla, 3,2 MB'lık parçalar halinde yüklenir; bir ek en fazla 150 MB olabilir.

**Okuma:**
- bir klasörün mesajları (istenirse yalnızca okunmamışlar), gönderen, konu ve önizlemeyle;
- gövde (metin ya da HTML) ve her bir ekin baytları;
- okundu işaretleme ve başka klasöre taşıma (`archive` gibi bilinen adlarla ya da klasörün görünen adıyla).

### E-posta modülünün ek gereksinimleri

| Ne | Neden | Kimden |
|---|---|---|
| Yönetici onaylı uygulama izinleri **`Mail.Send`** (gönderme) ve **`Mail.ReadWrite`** (büyük e-postalar, okuma, işaretleme, taşıma) | Olmazsa Microsoft HTTP 403 döner | Microsoft 365 / Entra yöneticisi |
| **SAP posta kutularıyla sınırlama** | Olmazsa uygulama şirketteki **her** posta kutusu adına gönderebilir ve her kutuyu okuyabilir | Exchange Online yöneticisi |
| SAP için bir posta kutusu, örneğin `sap@contoso.com` | Gönderen | Microsoft 365 yöneticisi |
| 3 MB ve daha büyük ekler için: SAP'nin `outlook.office.com`'a HTTPS ile çıkabilmesi (SICF proxy ayarları, STRUST) | Microsoft yükleme adresini bu host'ta veriyor; bunun için SM59 hedefi kullanılmıyor | Basis |

**Posta kutularını sınırlamak.** Exchange Online'da iki yol var. Hangisini kullanacağınızı Microsoft'un güncel belgelerinden kontrol edin; Microsoft artık ilkini öneriyor.

1. **RBAC for Applications:** SAP posta kutularını içeren bir yönetim kapsamı oluşturulur; uygulama rolleri `Application Mail.Send` / `Application Mail.ReadWrite` yalnızca bu kapsamda verilir. Bu yolu kullanırsanız Entra ID'de tenant genelinde `Mail.*` izinlerini **ayrıca vermeyin**.
2. **Application access policy (eski yol):** izinler Entra ID'de kalır ve PowerShell ile (Exchange Online modülü) sınırlanır:
   ```powershell
   New-DistributionGroup -Name "SAP Graph mailboxes" -Type Security -Members sap@contoso.com
   New-ApplicationAccessPolicy -AppId <application (client) ID> -PolicyScopeGroupId "SAP Graph mailboxes" -AccessRight RestrictAccess -Description "abap-graph"
   Test-ApplicationAccessPolicy -Identity sap@contoso.com -AppId <application (client) ID>
   ```

İki yol da bu projeyle henüz denenmedi.

**Posta kutusuna Outlook'tan bakmak.** Uygulamanın izinleri yalnız SAP içindir; bir kişinin paylaşılan kutuyu açmasını sağlamaz. Outlook web'de görmek için yönetici o kişiye erişim verir: Microsoft 365 yönetim merkezi → Ekipler ve gruplar → Paylaşılan posta kutuları → kutu → Posta kutusu izinleri → **Okuma ve yönetme**. Bir süre sonra kutu Outlook'ta görünür; ya da kişi profil resmi → **Başka bir posta kutusu aç** ile açar.

### Kurulum

`ZCHE_GRAPH_CORE`'dan sonra iki adım:
1. **SE38** → `ZCHE_GRAPH_MAIL_LIB` (tür **Include program**) → [`src/zche_graph_mail_lib.prog.abap`](src/zche_graph_mail_lib.prog.abap) dosyasını yapıştırın.
2. **SE38** → `ZCHE_GRAPH_MAIL` (tür **Yürütülebilir program**) → [`src/zche_graph_mail.prog.abap`](src/zche_graph_mail.prog.abap) dosyasını yapıştırın ve include ile birlikte aktifleştirin.

### Deneyin

`ZCHE_GRAPH_MAIL`'i çalıştırın.

**E-posta gönder:**
- tenant ve posta kutusu (gönderen);
- Kime (birden fazla adres `;` ile ayrılır, `Ad <adres>` biçimi de olur), konu ve metin;
- isteğe bağlı: SP01'deki bir spool talebi numarası; talep PDF olarak eklenir.

Bir raporun ardından arka plan job'ı olarak çalıştırmak için o raporun spool numarasını girin. Hata olursa job "Cancelled" biter.

**Klasör oku:**
- klasör (`inbox`, `archive`, … ya da klasörün görünen adı);
- yalnızca okunmamışlar;
- en çok N mesaj;
- isteğe bağlı olarak her mesajın ekleri.

### Kendi programınızda kullanmak

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
DATA lv_spool TYPE rspoid.          " faturanızın spool talebi
DATA lv_text TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
CREATE OBJECT lo_mail EXPORTING io_client = lo_client iv_mailbox = `sap@contoso.com`.

ls_mail-subject = `Fatura 4711`.
ls_mail-body = `<p>Sayın müşterimiz, faturanız ektedir.</p>`.
ls_mail-html = abap_true.
ls_mail-to = lcl_graph_mail=>addresses( `Derya Kaya <derya@musteri.com>; muhasebe@musteri.com` ).
TRY.
    ls_attachment = lcl_graph_mail=>attachment_from_spool( iv_spool = lv_spool iv_name = `fatura_4711.pdf` ).
    APPEND ls_attachment TO ls_mail-attachments.
    lo_mail->send( ls_mail ).
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).   " metin, ipucu ve request-id
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

Okuma; örneğin bir posta kutusuna gelen tedarikçi faturalarını işlemek için:

```abap
DATA lt_messages TYPE lif_graph_mail=>ty_messages.
DATA ls_message TYPE lif_graph_mail=>ty_message.
DATA lt_attachments TYPE lif_graph_mail=>ty_attachment_infos.
DATA ls_info TYPE lif_graph_mail=>ty_attachment_info.
DATA lv_pdf TYPE xstring.
DATA lv_archive TYPE string.

lt_messages = lo_mail->list( iv_folder = `inbox` iv_unread_only = abap_true iv_max = 50 ).
lv_archive = lo_mail->folder_id( `SAP islendi` ).
LOOP AT lt_messages INTO ls_message WHERE has_attachments = abap_true.
  lt_attachments = lo_mail->attachments( ls_message-id ).
  LOOP AT lt_attachments INTO ls_info WHERE kind = `file` AND inline = abap_false.
    lv_pdf = lo_mail->attachment_content( iv_message_id = ls_message-id iv_attachment_id = ls_info-id ).
    " ... sizin işleminiz
  ENDLOOP.
  lo_mail->move_to( iv_message_id = ls_message-id iv_folder = lv_archive ).
ENDLOOP.
```

## SharePoint ve OneDrive dosyaları

Tek bir belge kitaplığındaki dosyalarla çalışır: bir SharePoint sitesinin kitaplığı ya da bir kullanıcının OneDrive'ı. Dosya ve klasörler kitaplıktaki yollarıyla anılır, örneğin `Raporlar/2026/11/satis.xlsx`.

Modülün iki nesnesi var: `ZCHE_GRAPH_FILES_LIB` include'u (sınıf `LCL_GRAPH_FILES`) ve `ZCHE_GRAPH_FILES` programı.

- **Yükleme:** 4 MB'a kadar dosyalar tek istekte, daha büyükleri 3,2 MB'lık parçalarla gider. Aynı adda dosya varsa, seçiminize göre değiştirilir, yeni adla kaydedilir ya da reddedilir.
- **İndirme:** Microsoft'un verdiği kısa ömürlü indirme adresi üzerinden.
- **Listeleme:** bir klasörün içeriği; boyut, tarih, son değiştiren ve web bağlantısıyla.
- **Klasörler:** tek klasör ya da tek seferde bütün bir yol (`ensure_folder` yalnızca eksik klasörleri oluşturur).
- **Taşıma, yeniden adlandırma, silme.**
- **Paylaşım bağlantıları:** görüntüleme ya da düzenleme; şirket içindekiler için ya da bağlantıya sahip herkes için.

### Dosya modülünün ek gereksinimleri

| Ne | Neden | Kimden |
|---|---|---|
| Yönetici onaylı **`Sites.Selected`** uygulama izni ve ardından SAP'nin kullanacağı **her site için uygulamaya yazma yetkisi** | En az yetki: uygulama yalnızca bu sitelere erişir | Microsoft 365 / SharePoint yöneticisi |
| *Ya da* `Sites.ReadWrite.All` / `Files.ReadWrite.All` | Daha kolay, ama uygulama **her** siteye erişir; `Files.ReadWrite.All` her OneDrive'a da erişir. Kullanıcı OneDrive'ı için `Files.ReadWrite.All` gerekir. | Microsoft 365 yöneticisi |
| SAP'nin `<tenant>.sharepoint.com`'a HTTPS ile çıkabilmesi (SICF proxy ayarları, STRUST) | İndirme adresleri ve büyük dosyaların yükleme adresleri oraya gidiyor; bunlar için SM59 hedefi kullanılmıyor | Basis |

**Uygulamaya site yetkisi vermek (`Sites.Selected`).** Yönetici bunu her site için bir kez yapar. Yaygın iki yol var; Microsoft'un güncel belgelerinden kontrol edin. Graph yolu test tenant'ında bir kez kullanıldı (bir sitede `write`); PnP yolu denenmedi.
- **PnP PowerShell** ile:
  ```powershell
  Grant-PnPAzureADAppSitePermission -AppId <application (client) ID> -DisplayName "SAP abap-graph" -Site https://contoso.sharepoint.com/sites/Finance -Permissions Write
  ```
- **Graph** ile: `Sites.FullControl.All` iznine sahip ayrı bir yönetici uygulamasıyla `POST /sites/{site-id}/permissions` gönderilir. Gövde: `{"roles":["write"],"grantedToIdentities":[{"application":{"id":"<application (client) ID>","displayName":"SAP abap-graph"}}]}`.

### Kurulum

`ZCHE_GRAPH_CORE` ve `ZCHE_GRAPH_MAIL_LIB`'den sonra iki adım:
1. **SE38** → `ZCHE_GRAPH_FILES_LIB` (tür **Include program**) → [`src/zche_graph_files_lib.prog.abap`](src/zche_graph_files_lib.prog.abap) dosyasını yapıştırın.
2. **SE38** → `ZCHE_GRAPH_FILES` (tür **Yürütülebilir program**) → [`src/zche_graph_files.prog.abap`](src/zche_graph_files.prog.abap) dosyasını yapıştırıp aktifleştirin.

Program e-posta include'unu yalnızca spool talebini PDF'e çevirmek için kullanıyor. Kendi programlarınıza yalnızca çekirdek ve dosya include'u gerekir.

### Deneyin

`ZCHE_GRAPH_FILES`'ı çalıştırıp önce kitaplığı seçin.

**SharePoint sitesi:**
- host: örneğin `contoso.sharepoint.com`;
- site yolu: örneğin `/sites/Finance`; kök site için boş bırakın;
- kitaplık adı: SharePoint'te göründüğü gibi; boşsa varsayılan kitaplık kullanılır (*Belgeler* ya da *Documents*).

**Bir kullanıcının OneDrive'ı:**
- kullanıcı: örneğin `derya@contoso.com`.

Sonra işlemi seçin:

| İşlem | Girilecekler |
|---|---|
| **Klasörü listele** | Yol; boşsa kitaplığın en üstü |
| **Spool'u PDF olarak yükle** | Spool talebi ve yol. Yol `/` ile bitiyorsa dosya spool'un kendi adını alır. |
| **Sunucudaki dosyayı yükle** | Uygulama sunucusundaki dosya (AL11'e bakın) ve yol |
| **Sunucuya indir** | Yol ve uygulama sunucusundaki dosya |
| **Klasör yolunu oluştur** | Örneğin `Raporlar/2026/11` |
| **Paylaşım bağlantısı oluştur** | Yol |

Arka plan job'ında hata job'ı "Cancelled" yapar. Böylece bir raporun PDF'ini her gece SharePoint'e koyabilirsiniz.

### Kendi programınızda kullanmak

```abap
REPORT zmy_report_to_sharepoint.
INCLUDE zche_graph_core.
INCLUDE zche_graph_files_lib.

DATA lo_client TYPE REF TO lcl_graph_client.
DATA lo_files TYPE REF TO lcl_graph_files.
DATA ls_config TYPE lif_graph=>ty_config.
DATA ls_item TYPE lif_graph_files=>ty_item.
DATA lx_graph TYPE REF TO lcx_graph.
DATA lv_xlsx TYPE xstring.          " dosyanız, örneğin bir Excel çıktısı
DATA lv_text TYPE string.

ls_config = lcl_graph_client=>default_config( `<directory (tenant) ID>` ).
CREATE OBJECT lo_client EXPORTING is_config = ls_config.
TRY.
    lo_files = lcl_graph_files=>for_site( io_client = lo_client
                                          iv_host   = `contoso.sharepoint.com`
                                          iv_site   = `/sites/Finance` ).
    lo_files->ensure_folder( `Raporlar/2026/11` ).
    ls_item = lo_files->upload( iv_path = `Raporlar/2026/11/satis.xlsx` iv_content = lv_xlsx ).
    " ls_item-web_url: dosyanın bağlantısı
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

## SharePoint listeleri

SharePoint listesi, insanların SharePoint'te tuttuğu bir tablodur. Örnekler: açık faturalar, tedarikçi iletişim listesi, onaylar, fiyat listesi. Bu modül böyle bir listeyi SAP ile uyumlu tutar.

Modülün iki nesnesi var: `ZCHE_GRAPH_LISTS_LIB` include'u (sınıf `LCL_GRAPH_LIST`) ve `ZCHE_GRAPH_LISTS` programı.

- **Sitenin listeleri ve bir listenin sütunları:** iç ad, görünen ad, tür (metin, sayı, para, tarih, evet/hayır, seçim, arama, kişi, …), zorunlu, salt okunur, çoklu değer.
- **Kayıt okuma:** tüm sütunlar ya da seçilenler, `fields/Status eq 'Open'` gibi bir OData filtresiyle, birden çok sayfa boyunca.
- **Kayıt oluşturma, değiştirme ve silme.** Yalnızca verdiğiniz alanlar değişir.
- **Anahtar sütuna göre güncelle ya da oluştur (`upsert`):** örneğin "`InvoiceNo`'su 4711 olan kaydı güncelle, yoksa oluştur". SAP verisini her gece bir listeye yansıtmanın temel adımı bu. Aynı anda çalışan iki iş ikisi de kaydı bulamayıp ikisi de oluşturabilir. Bunu önlemek için SharePoint'te anahtar sütunda **Benzersiz değerler zorunlu** (Enforce unique values) ayarını açın. İkinci oluşturma o zaman reddedilir ve modül diğer işin oluşturduğu kaydı günceller.

Değerler metin olarak taşınır ve sütunun türüne göre çevrilir:

| Sütun | Nasıl yazılır | Ne olarak gider |
|---|---|---|
| Metin, not, tek seçim | `Status=Açık` | metin |
| Sayı, para | `Amount=1234.56` (ondalık ayırıcı nokta) | sayı |
| Evet/Hayır | `Paid=X` (ya da `true`, `1`, `yes`, `evet`) | true/false |
| Tarih | `DueDate=2026-11-30` ya da `2026-11-30T10:00:00Z` | ISO biçiminde metin |
| Çok değerli seçim | `Tags=kırmızı;mavi` | metin listesi |
| Arama (lookup) ya da kişi | `CustomerLookupId=12` (ya da `12;15`) | sayı (liste) |

Sütunların **iç adlarını** kullanın: örneğin `Title`, ya da "Tutar" diye görünen bir sütun için `Tutar`. İç adları **Sütunları göster** listeler. Boşluk ya da Türkçe harfle oluşturulmuş bir sütunun iç adı kodlanmış olabilir, örneğin `Fatura_x0020_No`.

### Liste modülünün ek gereksinimleri

| Ne | Neden | Kimden |
|---|---|---|
| Sitede yazma yetkili **`Sites.Selected`** (dosya modülüne bakın) ya da `Sites.ReadWrite.All` | Kayıt okuma ve yazma | Microsoft 365 / SharePoint yöneticisi |
| Büyük listelerde filtre için filtrelenen sütunda **dizin** (liste ayarları → Dizinlenmiş sütunlar) | Dizin yoksa SharePoint 5.000'den fazla kayıtlı listelerde filtreyi reddedebilir. Modül `Prefer: HonorNonIndexedQueriesWarningMayFailRandomly` başlığını gönderir; bu, daha küçük listelerde filtreye izin verir. | Site sahibi |

### Kurulum

`ZCHE_GRAPH_CORE`'dan sonra iki adım:
1. **SE38** → `ZCHE_GRAPH_LISTS_LIB` (tür **Include program**) → [`src/zche_graph_lists_lib.prog.abap`](src/zche_graph_lists_lib.prog.abap) dosyasını yapıştırın.
2. **SE38** → `ZCHE_GRAPH_LISTS` (tür **Yürütülebilir program**) → [`src/zche_graph_lists.prog.abap`](src/zche_graph_lists.prog.abap) dosyasını yapıştırıp aktifleştirin.

### Deneyin

`ZCHE_GRAPH_LISTS`'i host, site yolu ve SharePoint'te göründüğü haliyle liste adıyla çalıştırın.

| İşlem | Girilecekler |
|---|---|
| **Sitenin listelerini göster** | yok |
| **Sütunları göster** | yok |
| **Kayıtları oku** | Sütunlar (`Title,Amount`; boşsa tümü), filtre, en çok N |
| **Kayıt oluştur ya da değiştir** | Kayıt ID (boşsa yeni kayıt) ve alanlar: `Title=Fatura 4711 \| Amount=1234.56 \| Paid=X` |
| **Anahtara göre güncelle/oluştur** | Anahtar sütun (örneğin `Title`) ve anahtarın değeri dahil alanlar |

### Kendi programınızda kullanmak

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
                                        iv_list   = `Açık faturalar` ).
    " SAP'deki her açık kalem için:
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

## Excel çalışma kitapları

> **Kullanıcısız oturum.** Microsoft'un Excel çağrılarına ait başvuru sayfalarında (örneğin [Get Range](https://learn.microsoft.com/en-us/graph/api/range-get) ve [Create TableRow](https://learn.microsoft.com/en-us/graph/api/table-post-rows)) uygulama izinleri için **"Not supported"** yazıyor. Bu modül de diğerleri gibi uygulama olarak oturum açıyor. Gerçek bir test tenant'ında programın bütün çağrıları çalıştı ([Neler doğrulandı](#neler-doğrulandı) bölümüne bakın), ama orada uygulamada geniş `Sites.FullControl.All` izni de vardı. Yalnız `Sites.Selected` ile çalışıp çalışmadıkları henüz bilinmiyor; Microsoft'un neye izin verdiği de değişebilir. Dosya modülüyle `.xlsx` dosyasını bütün olarak yükleme ve indirme bundan etkilenmez.

SharePoint kitaplığında ya da OneDrive'da duran bir `.xlsx` dosyasının hücrelerini, dosyayı indirmeden okur ve yazar. Tipik kullanımlar:
- iş biriminin SharePoint'te tuttuğu bir planlama ya da raporlama kitabını doldurmak;
- iş biriminin Excel'de bakımını yaptığı bir fiyat ya da oran tablosunu okumak.

Modülün iki nesnesi var: `ZCHE_GRAPH_EXCEL_LIB` include'u (sınıf `LCL_GRAPH_EXCEL`) ve `ZCHE_GRAPH_EXCEL` programı. Dosyayı dosya modülüyle bulur, bu yüzden `ZCHE_GRAPH_FILES_LIB` de gerekir.

- **Çalışma sayfaları:** listeleme, yeni sayfa ekleme.
- **Aralıklar:**
  - saklanan değerler ya da Excel'in gösterdiği metin olarak okuma (tarihler tarih, sayılar biçimli);
  - bir sayfada dolu olan her şeyi okuma;
  - bir başlangıç hücresinden itibaren yazma;
  - temizleme.
- **Excel tabloları** (*Ekle → Tablo*): başlık, satırlar, sona satır ekleme. Tablo kendiliğinden büyür; onu kullanan formüller, pivot tablolar ve grafikler çalışmaya devam eder.
- **Yeniden hesaplama.**
- **Oturum:** çok sayıda değişiklik yaparken kitabı açık tutar (`open_session` / `close_session`). Daha hızlıdır. Bir işlem (transaction) değildir: sonraki bir değişiklik hata verirse öncekiler yazılmış kalır.

Yazarken sayı gibi görünen hücreler (`1234`, `-12.5`, `1e-3`) sayı olarak, `=` ile başlayan metinler formül olarak gider. Diğer metinler, Excel'e `'00123` yazar gibi başlarında bir kesme işaretiyle gider. Böylece `00123`, `+5` ve `2026-11-02` gibi tarihler metin kalır, malzeme numaraları baştaki sıfırlarını korur. Excel kesme işaretini göstermez; okurken metin kesme işareti olmadan geri gelir. Diğerlerinden kısa bir satırın geri kalan hücreleri değişmeden kalır.

Bu yolla yeni Excel dosyası oluşturulamıyor. Var olan bir kitapla başlayın; örneğin dosya modülüyle bir kez yüklediğiniz bir şablon.

### Kurulum

`ZCHE_GRAPH_CORE` ve `ZCHE_GRAPH_FILES_LIB`'den sonra iki adım:
1. **SE38** → `ZCHE_GRAPH_EXCEL_LIB` (tür **Include program**) → [`src/zche_graph_excel_lib.prog.abap`](src/zche_graph_excel_lib.prog.abap) dosyasını yapıştırın.
2. **SE38** → `ZCHE_GRAPH_EXCEL` (tür **Yürütülebilir program**) → [`src/zche_graph_excel.prog.abap`](src/zche_graph_excel.prog.abap) dosyasını yapıştırıp aktifleştirin.

İzinler dosya modülüyle aynı.

### Deneyin

`ZCHE_GRAPH_EXCEL`'i kitaplıkla (`ZCHE_GRAPH_FILES`'taki gibi) ve kitabın yoluyla çalıştırın, örneğin `Raporlar/satis.xlsx`.

| İşlem | Girilecekler |
|---|---|
| **Sayfaları ve tabloları göster** | yok |
| **Aralık oku** | Çalışma sayfası ve aralık: `A1:D20`; boş ya da tek hücre yazılırsa sayfada dolu olan her şey okunur. İsteğe bağlı: "Excel'in gösterdiği gibi". |
| **Değer yaz** | Çalışma sayfası, başlangıç hücresi (varsayılan `A1`) ve değerler: `Tarih;Tutar \| 2026-11-02;1234.5` (hücreler `;`, satırlar `\|` ile ayrılır) |
| **Tablo oku** | Tablo adı |
| **Tabloya satır ekle** | Tablo adı ve yukarıdaki gibi değerler |

### Kendi programınızda kullanmak

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
                                          iv_path   = `Raporlar/satis.xlsx` ).
    " SAP verinizin her satırı için:
    CLEAR lt_row.
    lv_cell = `4711`.    APPEND lv_cell TO lt_row.
    lv_cell = `1234.56`. APPEND lv_cell TO lt_row.
    APPEND lt_row TO lt_rows.
    lo_excel->open_session( ).
    lo_excel->add_table_rows( iv_table = `Satislar` it_rows = lt_rows ).
    lo_excel->close_session( ).
  CATCH lcx_graph INTO lx_graph.
    lv_text = lx_graph->if_message~get_longtext( ).
    MESSAGE lv_text TYPE 'I'.
ENDTRY.
```

## Entra ID kullanıcıları ve grupları

Şirketin çalışanlarını Microsoft Entra ID'de göründükleri gibi okur. Hiçbir şeyi değiştirmez. Tipik kullanımlar:
- onay için talep sahibinin yöneticisini bulmak;
- bir grubun üyelerine (örneğin "SAP onaycıları") e-posta göndermek;
- ayrılan çalışanların SAP kullanıcılarını bulmak: Microsoft hesabı kapatılmış ya da silinmiş, ama SAP kullanıcısı hâlâ aktif.

Modül, `ZCHE_GRAPH_USERS_LIB` include'u (`LCL_GRAPH_USERS` sınıfı) ve `ZCHE_GRAPH_USERS` programından oluşur.

- **Bir kullanıcı:** kullanıcı asıl adı (UPN), e-posta adresi ya da ID ile. Ad, unvan, departman, ofis, telefon, personel no, şirket ve hesabın açık olup olmadığı gelir.
- **Filtreyle kullanıcılar:** örneğin `department eq 'Finance'`, `employeeId eq '00001234'` ya da `accountEnabled eq false`. Filtre yoksa tüm kullanıcılar gelir.
- **Yönetici ve doğrudan bağlı çalışanlar.**
- **Kullanıcının grupları** ve **bir grubun üyeleri** (adıyla ya da ID'siyle); istenirse iç içe gruplar dahil.
- **SAP hesap kontrolü:** SU01'deki e-posta adresinin Microsoft hesabı olmayan ya da yalnız kapalı hesabı olan aktif SAP diyalog kullanıcıları (kilitli değil, bugün geçerli). Adres, büyük-küçük harfe bakılmadan e-posta ve UPN ile karşılaştırılır. SU01'de adresi olmayan kullanıcılar sayılır ama karşılaştırılmaz.

### Kullanıcı modülünün ek gereksinimleri

| Ne | Neden | Kim |
|---|---|---|
| Yönetici onaylı **`User.Read.All`** uygulama izni | Kullanıcıları, yöneticileri, bağlı çalışanları okumak | Microsoft 365 / Entra yöneticisi |
| Yönetici onaylı **`GroupMember.Read.All`** uygulama izni | Gruplar ve üyeleri | Microsoft 365 / Entra yöneticisi |
| SAP hesap kontrolü için `USR02`, `USR21` ve `ADR6` okuma yetkisi | Program kullanıcı ana verisini doğrudan okur | SAP yetki yöneticisi |

Bu izinler şirketin bütün kullanıcılarını ve gruplarını kapsar.

### Kurulum

`ZCHE_GRAPH_CORE`'dan sonra: **SE38** → `ZCHE_GRAPH_USERS_LIB` (tür **Include program**) → [`src/zche_graph_users_lib.prog.abap`](src/zche_graph_users_lib.prog.abap) yapıştırın. Sonra **SE38** → `ZCHE_GRAPH_USERS` (tür **Executable program**) → [`src/zche_graph_users.prog.abap`](src/zche_graph_users.prog.abap) yapıştırın → etkinleştirin.

### Deneyin

| İşlem | Alanlar |
|---|---|
| **Kullanıcıyı göster** | Kullanıcı: adres, UPN ya da ID. Ayrıntıları, yöneticiyi, bağlı çalışanları ve grupları gösterir. |
| **Kullanıcı ara** | Filtre (boş: tümü) ve en çok kaç kullanıcı |
| **Grubun üyeleri** | Grup adı ya da ID; istenirse "İç içe grupları da al" |
| **SAP kullanıcıları: hesap** | SAP kullanıcıları (boş: tüm diyalog kullanıcıları) |

Hesap kontrolü aylık bir arka plan işine uygundur; listesi spool'a düşer.

### Kendi programınızda kullanmak

```abap
DATA lo_users TYPE REF TO lcl_graph_users.
DATA ls_manager TYPE lif_graph_users=>ty_user.
DATA lt_members TYPE lif_graph_users=>ty_users.

CREATE OBJECT lo_users EXPORTING io_client = lo_client.
ls_manager = lo_users->manager( `derya@contoso.com` ).
IF ls_manager IS INITIAL.
  " Entra ID'de yönetici tanımlı değil
ENDIF.
lt_members = lo_users->members( iv_group = `SAP onaycıları` iv_nested = abap_true ).
```

## Outlook takvimi

SAP'deki tarihleri Outlook takvimlerine koyar. Tipik kullanımlar:
- bir bakım emri, bakım ekibinin takviminde etkinlik olur;
- bir teslim ya da muayene tarihi ilgililere davet olarak gider;
- ortak bir takvim (paylaşılan posta kutusunun takvimi) bir SAP sürecinin tarihlerini gösterir.

Modül, `ZCHE_GRAPH_CALENDAR_LIB` include'u (`LCL_GRAPH_CALENDAR` sınıfı) ve `ZCHE_GRAPH_CALENDAR` programından oluşur.

- **Etkinlik oluşturma:** bir kullanıcının ya da paylaşılan posta kutusunun takviminde. Konu, metin, saat ya da tüm gün, yer, zorunlu ve isteğe bağlı katılımcılar (davet alırlar), hatırlatma, "farklı göster", kategoriler.
- **Kendi anahtarınız** (`transaction_id`), örneğin emir numarası: Microsoft bir anahtar için yalnız bir etkinlik oluşturur. Aynı iş iki kez çalışsa da iki etkinlik olmaz.
- **Listeleme:** bir dönemin etkinlikleri; yinelenen etkinliklerin her tekrarı ayrı satırdır.
- **Değiştirme** (katılımcılara güncelleme gider), **iptal** (katılımcılara açıklamayla iptal gider) ya da yalnız bu takvimden **silme**.
- **Teams toplantısı:** `teams_meeting = X` ile Microsoft bir Teams toplantısı açar ve katılma bağlantısını davete ve `join_url` alanına koyar. Düzenleyici posta kutusudur; Teams lisansı gerekir, paylaşılan kutunun lisansı yoktur.
- **Tekrar:** günlük, haftalık ya da aylık; her n gün, hafta ya da ay; bir tarihe kadar ya da n kez. Haftalık seri ilk başlangıcın haftanın gününe, aylık seri ayın gününe düşer; ikisi de UTC'ye göre hesaplanır. Yaz saati uygulanan bir saat diliminde seri UTC saatini korur, bu yüzden yerel saatte yılda iki kez bir saat kayar.
- **Kim geliyor:** liste her katılımcının cevabını verir (`accepted`, `declined`, `tentativelyAccepted`, `none`).
- **Boş zaman:** bir günün belli bir aralığında, verilen herkesin boş olduğu ilk 30 (ya da n) dakika; "belki" dolu sayılır.

Tarih ve saatler, bir SAP saat dilimindeki SAP tarih ve saatleridir; varsayılan, kullanıcının saat dilimidir (`SY-ZONLO`, SU01'de). Microsoft'a UTC olarak gider ve aynı SAP saat dilimine çevrilerek döner; yaz saati SAP'nin kendi saat dilimi tablolarıyla hesaplanır.

### Takvim modülünün ek gereksinimleri

| Ne | Neden | Kim |
|---|---|---|
| Yönetici onaylı **`Calendars.ReadWrite`** uygulama izni | Etkinlik oluşturmak ve okumak | Microsoft 365 / Entra yöneticisi |
| **SAP posta kutularıyla sınırlama** | Sınırlama olmazsa uygulama şirketin **her** takvimine yazabilir | Exchange Online yöneticisi |

Sınırlamayı e-posta modülünde anlatıldığı gibi yapın; RBAC for Applications ile rol `Application Calendars.ReadWrite` olur.

### Kurulum

`ZCHE_GRAPH_CORE`'dan sonra: **SE38** → `ZCHE_GRAPH_CALENDAR_LIB` (tür **Include program**) → [`src/zche_graph_calendar_lib.prog.abap`](src/zche_graph_calendar_lib.prog.abap) yapıştırın. Sonra **SE38** → `ZCHE_GRAPH_CALENDAR` (tür **Executable program**) → [`src/zche_graph_calendar.prog.abap`](src/zche_graph_calendar.prog.abap) yapıştırın → etkinleştirin.

### Deneyin

`ZCHE_GRAPH_CALENDAR`'ı tenant ve takvimi kullanılacak posta kutusuyla çalıştırın.

| İşlem | Alanlar |
|---|---|
| **Etkinlikleri listele** | Başlangıç ve bitiş tarihi |
| **Etkinlik oluştur** | Tarih, başlangıç ve bitiş saati ya da "Tüm gün", konu; isteğe bağlı yer, katılımcılar (`a@x.com; b@x.com`), metin, hatırlatma, anahtarınız; "Teams toplantısı"; tekrar, her, bitiş tarihi ya da kez |
| **Boş zaman bul** | Tarih, aralığın başı ve sonu, dakika olarak süre, katılımcılar |
| **İptal et** | Etkinlik ID (listeden) ve açıklama |
| **Bu takvimden sil** | Etkinlik ID |

### Kendi programınızda kullanmak

```abap
DATA lo_calendar TYPE REF TO lcl_graph_calendar.
DATA ls_event TYPE lif_graph_calendar=>ty_event.

CREATE OBJECT lo_calendar EXPORTING io_client = lo_client iv_mailbox = `bakim@contoso.com`.
ls_event-subject = `Bakım: Pres 3`.
ls_event-start_date = '20261110'.
ls_event-start_time = '090000'.
ls_event-end_time = '113000'.
ls_event-location = `Hol B`.
ls_event-transaction_id = `PM-4711`.
APPEND `derya@contoso.com` TO ls_event-attendees.
ls_event-teams_meeting = abap_true.
ls_event = lo_calendar->create( ls_event ).
" Etkinliği sonra değiştirmek ya da iptal etmek için ls_event-id'yi emirle birlikte saklayın;
" ls_event-join_url Teams bağlantısıdır
```

## Teams kanal mesajları

Bir Microsoft Teams kanalına mesaj gönderir: bir iş hata verdi, bir belge onay bekliyor, gece işi bitti. Modül, `ZCHE_GRAPH_TEAMS_LIB` include'u (`LCL_GRAPH_TEAMS` sınıfı) ve `ZCHE_GRAPH_TEAMS` programından oluşur; yalnız `ZCHE_GRAPH_CORE`'a ihtiyaç duyar.

Microsoft Graph, bir uygulamanın kanala mesaj yazmasına izin vermiyor. Teams bunun yerine **Workflows web kancası** sunuyor: kanala uzun, gizli bir adres verilir; bu adrese ne gönderilirse kanalda görünür. Token ya da Entra izni gerekmez; bu modül diğerlerinin oturum açma adımını kullanmaz.

Mesaj bir karttır (*Adaptive Card*):
- düzeyinin renginde bir başlık: `info`, `good`, `warning` ya da `error`;
- bir metin;
- ad/değer satırları, örneğin `Sipariş=4711 | Üretim yeri=1000`;
- bir bağlantı açan buton, örneğin bir Fiori uygulamasına.

Hatadan sonra mesaj tekrar gönderilmez: ulaşmış olabilir.

### Teams modülünün gereksinimleri

| Ne | Neden | Kim |
|---|---|---|
| Kanalda: **⋯ → Workflows → "Send webhook alerts to a channel"**, kaydedilir. Teams adresi gösterir. | Mesajların gideceği adres | Ekibin bir üyesi |
| **SM59 hedefi, G tipi**: hedef host = adresin host'u; port 443; yol öneki = host'tan sonraki ilk `/`'tan sonuna kadar, `?...&sig=...` dahil; SSL etkin, `ANONYM`; oturum bilgisi yok | Adres gizlidir: bilen herkes kanala yazabilir. SM59'da bir parola gibi saklanır, kod yalnız hedefin adını bilir. | Basis |
| STRUST: o host'un sertifikasına güven; SAP internete proxy ile çıkıyorsa proxy | Microsoft host'larında olduğu gibi | Basis |

Akış, onu oluşturan hesapla çalışır; o kişi ayrılırsa akış durabilir. Gerçek sistemde bir hizmet hesabıyla oluşturun.

### Kurulum

`ZCHE_GRAPH_CORE`'dan sonra: **SE38** → `ZCHE_GRAPH_TEAMS_LIB` (tür **Include program**) → [`src/zche_graph_teams_lib.prog.abap`](src/zche_graph_teams_lib.prog.abap) yapıştırın. Sonra **SE38** → `ZCHE_GRAPH_TEAMS` (tür **Executable program**) → [`src/zche_graph_teams.prog.abap`](src/zche_graph_teams.prog.abap) yapıştırın → etkinleştirin.

### Deneyin

`ZCHE_GRAPH_TEAMS`'i SM59 hedefi, bir başlık ve bir metinle çalıştırın. "Sistem, kullanıcı, saat ekle" üç satır ekler. Bir arka plan işinin son adımı olarak, önceki adımların çalıştığını kanala bildirir.

### Kendi programınızda kullanmak

```abap
DATA lo_teams TYPE REF TO lcl_graph_teams.
DATA ls_card TYPE lif_graph_teams=>ty_card.

CREATE OBJECT lo_teams EXPORTING iv_destination = 'ZTEAMS_FINANS'.
ls_card-title = `5 Kasım ödeme çalıştırması durdu`.
ls_card-text = `Banka bilgisi olmayan 3 fatura`.
ls_card-level = `error`.
ls_card-facts = lcl_graph_teams=>facts_from_text( `Şirket kodu=1000 | Çalıştırma=F110/0511` ).
ls_card-link_url = `https://sap.contoso.com/fiori#PaymentRun-manage`.
ls_card-link_title = `Ödeme çalıştırmasını aç`.
lo_teams->send( ls_card ).
```

## Modüller (plan)

| Modül | İçerik | Durum |
|---|---|---|
| Çekirdek + bağlantı testi | `ZCHE_GRAPH_CORE`, `ZCHE_GRAPH_CHECK` | v0.5.1 |
| E-posta | `ZCHE_GRAPH_MAIL_LIB`, `ZCHE_GRAPH_MAIL`: gönderme ve okuma, yukarıya bakın | v0.5.1 |
| SharePoint / OneDrive dosyaları | `ZCHE_GRAPH_FILES_LIB`, `ZCHE_GRAPH_FILES`, yukarıya bakın | v0.5.1 |
| SharePoint listeleri | `ZCHE_GRAPH_LISTS_LIB`, `ZCHE_GRAPH_LISTS`, yukarıya bakın | v0.5.1 |
| Excel çalışma kitapları | `ZCHE_GRAPH_EXCEL_LIB`, `ZCHE_GRAPH_EXCEL`, yukarıya bakın | v0.5.1 |
| Entra ID kullanıcıları ve grupları | `ZCHE_GRAPH_USERS_LIB`, `ZCHE_GRAPH_USERS`, yukarıya bakın | v0.6.0 |
| Outlook takvimi | `ZCHE_GRAPH_CALENDAR_LIB`, `ZCHE_GRAPH_CALENDAR`, yukarıya bakın | v0.7.0 |
| Teams kanal mesajları | `ZCHE_GRAPH_TEAMS_LIB`, `ZCHE_GRAPH_TEAMS`, yukarıya bakın | v0.7.0 |

## Neler doğrulandı

SAP ABAP Cloud Developer Trial 2025 sisteminde (SAP_BASIS 816).

### Gerçek bir Microsoft 365 tenant'ında, 4 ve 5 Kasım 2026

Microsoft 365 Business Basic test tenant'ı, tek bir uygulama kaydı, secret SM59'da; programlar seçim ekranlarından çalıştırıldı.

> **Önce bunu okuyun:** uygulamada `Organization.Read.All` ve `Sites.Selected` (bir test sitesinde `write` yetkisiyle) dışında, testler sırasında geniş **`Sites.FullControl.All`** izni de vardı. Bu yüzden sonuçlar çağrıların çalıştığını gösterir. Yalnız `Sites.Selected`'ın yettiğini ya da başka sitelerin ve OneDrive'ların kapalı kaldığını **göstermez**. E-posta ve takvim için uygulamada tüm tenant'ı kapsayan `Mail.Send`, `Mail.ReadWrite` ve `Calendars.ReadWrite` vardı; yukarıda anlatılan posta kutusu sınırlaması yoktu.

![Test tenant'ında ZCHE_GRAPH_CHECK](docs/img/check-connection.png)

- **Bağlantı:** `ZCHE_GRAPH_CHECK` gerçek bir token aldı ve `GET /organization` çağrısını yaptı; tenant hem alan adı hem GUID olarak verildi. Var olmayan bir tenant `AADSTS90002` hatasını ve ipucunu verdi.
- **Dosyalar:**
  - klasör listeleme;
  - kitaplığı adıyla bulma (`Belgeler`, *Documents*'ın Türkçe adı) ve ad yanlışsa kitaplıkları sayan hata;
  - bir klasör yolunu iki kez oluşturma, kopya klasör olmadan;
  - Türkçe harfli ve boşluklu klasör adı;
  - bir spool talebini PDF olarak yükleme (4.791 bayt); `replace`, `rename` ve `fail` (HTTP 409);
  - 6.291.456 baytlık bir dosyayı uygulama sunucusuna indirme, parça parça yeniden yükleme ve tekrar indirme: her seferinde aynı SHA-256.
- **Listeler:**
  - sitenin listeleri ve sütunları; "Müşteri Adı" için `M_x00fc__x015f_teriAd_x0131_` gibi iç adlar;
  - seçilen sütunlar ve filtreyle okuma;
  - metin, sayı, evet/hayır, tarih ve çoklu seçimle kayıt oluşturma;
  - `12,5` değerini sayı olarak reddetme;
  - bir kaydın tek alanını değiştirme;
  - `Title` anahtarıyla, iki yönde de güncelle ya da oluştur.
- **Excel, uygulama olarak oturum açarak:** sayfalar ve tablolar, aralığı değer ve gösterilen metin olarak okuma, değer ve formül yazma, tablo okuma, tabloya satır ekleme.
- **E-posta:** `ZCHE_GRAPH_MAIL` paylaşılan bir posta kutusundan kendisine kısa bir metin e-postası gönderdi, sonra gelen kutusundaki okunmamış e-postaları listeledi; gönderilen e-posta listedeydi.

![Test e-postası, SAP'den geri okunurken](docs/img/mail-read.png)

- **Kullanıcılar ve gruplar (5 Kasım):** `ZCHE_GRAPH_USERS` kullanıcıları listeledi; paylaşılan bir posta kutusunun kullanıcısını gösterdi (hesap kapalı, her paylaşılan kutuda olduğu gibi; yönetici ve grup yok); bir Microsoft 365 grubunun üyelerini adıyla buldu. SAP hesap kontrolü kullanıcıları okudu ama hiçbirini karşılaştırmadı: deneme sistemindeki SAP kullanıcılarının SU01'de e-posta adresi yok. Karşılaştırmanın kendisi yalnız birim testiyle sınandı.
- **Takvim (5 Kasım):** `ZCHE_GRAPH_CALENDAR` paylaşılan bir posta kutusunun takviminde 10:00–10:30 arası bir etkinlik oluşturdu (SAP saat dilimi `TURKEY`) ve aynı saatlerle geri listeledi. Aynı anahtarla tekrar çalıştırılınca aynı etkinlik döndü; takvimde yine tek etkinlik vardı.
- **Teams toplantıları ve boş zaman (5 Kasım, 0.7.0):** lisanslı bir kullanıcının takviminde, katılımcısız, iki kez tekrarlanan haftalık bir Teams toplantısı: iki tekrar da katılma bağlantısıyla geri geldi, sonra seri silindi. Boş zaman araması iki posta kutusu için 09:00–09:30'u buldu; toplantının olduğu yarım saatte boş zaman bulmadı.
- **Teams kanal mesajları:** yalnız birim testleri ve var olmayan bir SM59 hedefinin hatası. Henüz gerçek bir kanal yok.

Tenant'ta bulunup 0.5.1'de düzeltilenler:

- **İndirme:** SharePoint, `$select` ile sorulunca `@microsoft.graph.downloadUrl` alanını döndürmüyor. Modül artık Microsoft'un [indirme sayfasındaki](https://learn.microsoft.com/en-us/graph/api/driveitem-get-content) gibi `select` ile soruyor.
- **Excel:** `00789` hücreye 789 olarak yazılıyordu, çünkü Excel metni elle yazılmış bir giriş gibi yorumluyor. Metinler artık başlarında kesme işaretiyle gidiyor.

  ![0.5.1 sonrası E2'de 00789](docs/img/excel-leading-zero.png)
- **`ZCHE_GRAPH_CHECK`:** "Token'daki izinler:" sonrasındaki boşluk eksikti.

### Birim testleri ve uydurma bilgiler, 2 Kasım 2026

- **Excel modülü:** aynı test dublörüyle 8 birim testi geçiyor. Kapsadıkları:
  - sütun harfleri (A, Z, AA, ZZ, AAA) ve blok adresleri;
  - metinden değerler;
  - kitabı dosya modülüyle bulma ve çalışma sayfaları;
  - değerleri ve gösterilen metni okuma, dolu alan;
  - blok yazma (sayılar, korunan baştaki sıfırlar, metin kalan tarih ve `+5`, formüller, kısa satırlar için `null`);
  - her çağrıda oturum başlığı;
  - tablo okuma ve satır ekleme.

  `ZCHE_GRAPH_EXCEL` uydurma bilgilerle Microsoft'un giriş adımına kadar çalışıyor.
- **Liste modülü:** aynı test dublörüyle 8 birim testi geçiyor. Kapsadıkları:
  - metinden alanlar;
  - sitenin listesini görünen adıyla bulma (gizli listeler dışarıda);
  - sütun türleri, bir kez okunup hatırlanıyor;
  - seçilen sütunlar, filtre ve `Prefer` başlığıyla kayıt okuma; çoklu değerler `;` ile birleştiriliyor;
  - metin, sayı, evet/hayır, çoklu seçim ve arama değerleriyle doğru JSON biçiminde kayıt oluşturma;
  - virgülle yazılmış sayıyı reddetme;
  - iki yönde de güncelle ya da oluştur.

  `ZCHE_GRAPH_LISTS` uydurma bilgilerle Microsoft'un giriş adımına kadar çalışıyor.
- **Dosya modülü:** aynı test dublörüyle 9 birim testi geçiyor. Kapsadıkları:
  - boşluklu yollar;
  - site ve kitaplığı adıyla bulma; kitaplık yoksa mevcut kitaplıkları sayan hata;
  - küçük ve büyük yükleme (doğru `Content-Range` ile parçalar, yükleme adresine token gitmiyor);
  - indirme adresiyle indirme;
  - iki sayfalık listeleme;
  - bir yolun yalnızca eksik klasörlerini oluşturma;
  - yeniden adlandırarak taşıma, paylaşım bağlantısı.

  `ZCHE_GRAPH_FILES` uydurma bilgilerle Microsoft'un giriş adımına kadar çalışıyor.
- **E-posta modülü:** aynı test dublörüyle 8 birim testi geçiyor. Kapsadıkları:
  - alıcılar, HTML ve ek içeren bir e-postanın istek gövdesi;
  - büyük e-posta: taslak, ek, yükleme oturumu, doğru `Content-Range` ile ve yükleme adresine token gitmeden üç parça, sonra gönderme;
  - klasör okuma, ek baytları, işaretleme, taşıma, ada göre klasör, adres metinleri.
- **Spool'dan PDF:** gerçek bir spool talebi (ABAP listesi) 20.215 baytlık geçerli bir PDF'e dönüştü; `%PDF-1.3` ile başlıyor, `%EOF` ile bitiyor. `ZCHE_GRAPH_MAIL` bunu ekledi ve uydurma bilgilerle beklendiği gibi giriş adımında durdu.
- **Çekirdeğin birim testleri:** 16 ABAP Unit testi geçiyor; Microsoft yerine bir test dublörü cevap veriyor. Kapsadıkları:
  - JSON: nesneler, diziler, Türkçe harfler dahil kaçış karakterleri, sayılar, hatalar;
  - JSON yazıcı;
  - token isteği ve saklama;
  - giriş hatası ipuçları;
  - Graph hataları;
  - 429 sonrası yeniden deneme, 401 sonrası yeni token, sayfalama;
  - token'daki izinler.
- **7.00 sözdizimi:** [abaplint](https://abaplint.org) 2.120, 7.00 ayarında ([abaplint.json](abaplint.json)) sorun bildirmiyor. abaplint 7.00'da olmayan her şeyi yakalamadığı için ana kurallar ayrıca elle kontrol edildi.
- **Canlı deneme, uydurma bilgilerle:** hedefler sıfır client ID ve yer tutucu bir secret ile oluşturuldu.
  - İki Microsoft adresine de TLS bağlantısı çalışıyor.
  - Microsoft `AADSTS700038: 00000000-… is not a valid application identifier` cevabını verdi. Microsoft bu ID'yi ancak Basic kimlik doğrulama başlığından öğrenebilirdi; yani SM59 client ID ve secret'ı gerçekten bu yolla gönderiyor.
  - `graph.microsoft.com`, çekirdeğin okuduğu yerde `request-id` bulunan bir `401 InvalidAuthenticationToken` cevabı verdi.

**Henüz doğrulanmadı:**
- **E-postanın Microsoft'ta denenmesi:** HTML e-postalar, ekler (spool'dan olanlar dahil), büyük e-postalar, işaretleme ve taşıma. Posta kutusu sınırlaması (RBAC for Applications) kurulamadı: yeni tenant'ta Exchange Online, `Enable-OrganizationCustomization` adımında kendi iç hatasıyla durdu.
- **Büyük eklerin Microsoft'a yüklenmesi:** yükleme adresinin host'u ve SICF proxy yolu.
- **Kullanıcıların ve takvimin Microsoft'ta denenmesi:** gerçek adreslerle SAP hesap kontrolü, yönetici ve bağlı çalışanlar (tanımlı değildi), iç içe gruplar; katılımcılı etkinlikler ve cevapları, tüm gün etkinlikler, değiştirme ve iptal, aylık seri, yaz saati olan bir saat diliminde seri, şirket dışındaki kişilerin boş zamanı.
- **En az yetki:** modüllerin yalnız `Sites.Selected` ile çalışması ve yetki verilmemiş bir sitenin ya da OneDrive'ın reddedilmesi.
- **SharePoint:** paylaşım bağlantıları, taşıma ve yeniden adlandırma, proxy üzerinden `*.sharepoint.com` yolu.
- **Excel'in Microsoft'ta denenmesi:** kısa satırlar için `null`; metin biçiminde olmayan bir tablo sütununa satır eklerken kesme işareti (bir aralıkta ve zaten metin biçimli bir tablo sütununda denendi). Çok büyük bloklar Microsoft'un istek boyutu sınırlarına takılabilir.
- **SharePoint listelerinin Microsoft'ta denenmesi:** arama (lookup) sütunları, kayıt silme, aynı anahtarı aynı anda oluşturan iki iş (yalnız uydurma cevaplı bir birim testi var).
- **SAPscript / Smart Forms spool talepleri** (yalnızca bir ABAP listesi dönüştürüldü).
- **Gerçek bir ABAP 7.00–7.02 sistemi.** Özellikle şunlar doğrulanmadı:
  - SM59'un kullanıcı ve şifre alanlarının 36 karakterlik client ID'yi ve 40 karakterlik secret'ı alıp almadığı;
  - kullanılan sınıfların (`CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`, `CL_ABAP_CONV_IN_CE`, `CL_ABAP_TSTMP`) aynı şekilde çalışıp çalışmadığı.
- **SE38:** programlar ADT ile kuruldu; SE38'e yapıştırma denenmedi.
- **Proxy ve gerçek STRUST kurulumu:** deneme sistemi Microsoft'un sertifikalarına zaten güveniyordu.

## Lisans

MIT, bkz. [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
