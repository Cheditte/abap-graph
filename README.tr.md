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

> **Durum: v0.1, yalnızca çekirdek, henüz yayınlanmadı.** Çekirdek ve bağlantı testi SAP ABAP Platform 2023 deneme sisteminde çalışıyor. Ama gerçek bir Microsoft 365 tenant'ıyla henüz çağrı yapılmadı (bkz. [Neler doğrulandı](#neler-doğrulandı)). Sıradaki modül e-posta.

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

## Modüller (plan)

| Modül | İçerik | Durum |
|---|---|---|
| Çekirdek + bağlantı testi | bu repo | v0.1 |
| E-posta | Gönderme (HTML, ekler, spool'dan PDF, büyük ekler), sonra posta kutusu okuma | sıradaki |
| SharePoint / OneDrive | Yükleme, indirme, listeleme, klasörler, paylaşım bağlantıları | planlandı |
| SharePoint Listeleri, Excel, Entra ID kullanıcıları, takvim, Teams bildirimleri | | planlandı |

## Neler doğrulandı

2 Kasım 2026'da, SAP ABAP Platform 2023 deneme sisteminde (SAP_BASIS 7.58):

- **Birim testleri:** 16 ABAP Unit testi geçiyor; Microsoft yerine bir test dublörü cevap veriyor. Kapsadıkları:
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
- **Gerçek bir token ve başarılı bir Graph çağrısı.** Microsoft 365 tenant'ı yoktu.
- **Gerçek bir ABAP 7.00–7.02 sistemi.** Özellikle şunlar doğrulanmadı:
  - SM59'un kullanıcı ve şifre alanlarının 36 karakterlik client ID'yi ve 40 karakterlik secret'ı alıp almadığı;
  - kullanılan sınıfların (`CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`, `CL_ABAP_CONV_IN_CE`, `CL_ABAP_TSTMP`) aynı şekilde çalışıp çalışmadığı.
- **SAP GUI:** seçim ekranına bakılmadı, SE38'e yapıştırma denenmedi.
- **Proxy ve gerçek STRUST kurulumu:** deneme sistemi Microsoft'un sertifikalarına zaten güveniyordu.

## Lisans

MIT, bkz. [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
