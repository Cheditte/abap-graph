# abap-graph

> [English](README.md) | **Türkçe**

SAP'yi Microsoft 365 ile yalnızca ABAP kullanarak, **Microsoft Graph** üzerinden konuşturur. Araya middleware ya da eklenti girmez.

**Ortak çekirdek** şunları yapar:
- giriş (token alma);
- HTTP çağrıları;
- JSON okuma ve yazma;
- yeniden denemeler ve sayfalama.

**Ürün modülleri** bunun üstüne kurulur: önce e-posta, sonra SharePoint/OneDrive, Listeler, Excel, Entra ID ve takvim.

- **Kopyala-yapıştır:** kaynak SE38'e yapıştırılır. Tablo ya da sözlük nesnesi yok; abapGit isteğe bağlı.
- **ABAP 7.00 sözdizimi:** ECC 6.0 ve sonrasında çalışır, S/4HANA dahil.
- **Gizli anahtar SM59'da durur:** kod onu hiç görmez.

> **Durum: v0.2, henüz yayınlanmadı.** Çekirdek, bağlantı testi ve e-posta modülü SAP ABAP Platform 2023 deneme sisteminde, test dublörüyle ve Microsoft'un giriş adımına kadar çalışıyor. Ama gerçek bir Microsoft 365 tenant'ıyla henüz çağrı yapılmadı (bkz. [Neler doğrulandı](#neler-doğrulandı)).

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
   - HTTP 429, 503 ve 504'te Microsoft'un istediği süre beklenip yeniden denenir (`Retry-After`, en fazla 60 saniye).
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

## E-posta modülü

Tek bir posta kutusu adına (örneğin `sap@contoso.com`) e-posta gönderir ve okur. Modülün iki nesnesi var:
- `ZCHE_GRAPH_MAIL_LIB` include'u (sınıf `LCL_GRAPH_MAIL`);
- `ZCHE_GRAPH_MAIL` programı: deneme e-postası gönderir ya da bir klasörü listeler.

**Gönderme:**
- metin ya da HTML, Kime/Bilgi/Gizli, yanıt adresi, önem;
- her türlü ek; spool talebi de PDF olarak eklenebilir (ABAP listesi, SAPscript ya da Smart Forms);
- HTML içinde gömülü resimler (`<img src="cid:logo">`);
- ekleri toplam yaklaşık 2,9 MB'a kadar olan e-postalar tek çağrıda gider.
- Daha büyükleri önce taslak olarak oluşturulur, ekler tek tek eklenir ve sonra gönderilir. 2,9 MB'ı aşan tek bir ek 3,2 MB'lık parçalar halinde yüklenir; bir ek en fazla 150 MB olabilir.

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
| 2,9 MB'ı aşan ekler için: SAP'nin `outlook.office.com`'a HTTPS ile çıkabilmesi (SICF proxy ayarları, STRUST) | Microsoft yükleme adresini bu host'ta veriyor; bunun için SM59 hedefi kullanılmıyor | Basis |

**Posta kutularını sınırlamak.** Exchange Online'da iki yol var. Hangisini kullanacağınızı Microsoft'un güncel belgelerinden kontrol edin; Microsoft artık ilkini öneriyor.

1. **RBAC for Applications:** SAP posta kutularını içeren bir yönetim kapsamı oluşturulur; uygulama rolleri `Application Mail.Send` / `Application Mail.ReadWrite` yalnızca bu kapsamda verilir. Bu yolu kullanırsanız Entra ID'de tenant genelinde `Mail.*` izinlerini **ayrıca vermeyin**.
2. **Application access policy (eski yol):** izinler Entra ID'de kalır ve PowerShell ile (Exchange Online modülü) sınırlanır:
   ```powershell
   New-DistributionGroup -Name "SAP Graph mailboxes" -Type Security -Members sap@contoso.com
   New-ApplicationAccessPolicy -AppId <application (client) ID> -PolicyScopeGroupId "SAP Graph mailboxes" -AccessRight RestrictAccess -Description "abap-graph"
   Test-ApplicationAccessPolicy -Identity sap@contoso.com -AppId <application (client) ID>
   ```

İki yol da bu projeyle henüz denenmedi.

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

## Modüller (plan)

| Modül | İçerik | Durum |
|---|---|---|
| Çekirdek + bağlantı testi | `ZCHE_GRAPH_CORE`, `ZCHE_GRAPH_CHECK` | v0.2 |
| E-posta | `ZCHE_GRAPH_MAIL_LIB`, `ZCHE_GRAPH_MAIL`: gönderme ve okuma, yukarıya bakın | v0.2 |
| SharePoint / OneDrive | Yükleme, indirme, listeleme, klasörler, paylaşım bağlantıları | planlandı |
| SharePoint Listeleri, Excel, Entra ID kullanıcıları, takvim, Teams bildirimleri | | planlandı |

## Neler doğrulandı

2 Kasım 2026'da, SAP ABAP Platform 2023 deneme sisteminde (SAP_BASIS 7.58):

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
- **Gerçek bir token ve başarılı bir Graph çağrısı.** Microsoft 365 tenant'ı yoktu. Bu yüzden henüz gerçekten e-posta gönderilmedi ya da okunmadı; Microsoft'un cevapları yalnızca belgelerinden biliniyor.
- **Büyük eklerin Microsoft'a yüklenmesi:** yükleme adresinin host'u ve SICF proxy yolu.
- **Posta kutusu sınırlaması** (RBAC for Applications ya da application access policy).
- **SAPscript / Smart Forms spool talepleri** (yalnızca bir ABAP listesi dönüştürüldü).
- **Gerçek bir ABAP 7.00–7.02 sistemi.** Özellikle şunlar doğrulanmadı:
  - SM59'un kullanıcı ve şifre alanlarının 36 karakterlik client ID'yi ve 40 karakterlik secret'ı alıp almadığı;
  - kullanılan sınıfların (`CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`, `CL_ABAP_CONV_IN_CE`, `CL_ABAP_TSTMP`) aynı şekilde çalışıp çalışmadığı.
- **SAP GUI:** seçim ekranına bakılmadı, SE38'e yapıştırma denenmedi.
- **Proxy ve gerçek STRUST kurulumu:** deneme sistemi Microsoft'un sertifikalarına zaten güveniyordu.

## Lisans

MIT, bkz. [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
