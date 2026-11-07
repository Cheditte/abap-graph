# Doğrulama kayıtları

[Proje özeti](README.tr.md) · [Görselli yol haritası](WALKTHROUGH.tr.md) · [Teknik başvuru](TECHNICAL.tr.md)

[English](VALIDATION.md) | **Türkçe**

Bu sayfa önceki denemeleri, sürümler arasındaki düzeltmeleri ve açık kalan doğrulama alanlarını kaydeder. Her sonuç yanında belirtilen sürüm ve işlem için geçerlidir; belge düzenlemesi sırasında testler yeniden çalıştırılmadı. Yerel kaynak sürümü 0.8.0, henüz yayımlanmamış olarak kayıtlıdır; SAP ile karşılaştırmaları 6 ve 7 Kasım'da tenant'ta denendi (aşağıya bakın).

## Neler doğrulandı

SAP ABAP Cloud Developer Trial 2025 sisteminde (SAP_BASIS 816).

### Gerçek bir Microsoft 365 tenant'ında, 4–7 Kasım 2026

Microsoft 365 Business Basic test tenant'ı, tek bir uygulama kaydı, secret SM59'da; programlar seçim ekranlarından çalıştırıldı.

> **Önce bunu okuyun:** uygulamada `Organization.Read.All` ve `Sites.Selected` (bir test sitesinde `write` yetkisiyle) dışında, testler sırasında geniş **`Sites.FullControl.All`** izni de vardı. Bu yüzden sonuçlar çağrıların çalıştığını gösterir. Yalnız `Sites.Selected`'ın yettiğini ya da başka sitelerin ve OneDrive'ların kapalı kaldığını **göstermez**. E-posta ve takvim için uygulamada tüm tenant'ı kapsayan `Mail.Send`, `Mail.ReadWrite` ve `Calendars.ReadWrite` vardı; [teknik rehberdeki posta kutusu sınırlaması](TECHNICAL.tr.md#e-posta-modülünün-ek-gereksinimleri) yoktu.

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

- **Kullanıcılar ve gruplar (5 Kasım):** `ZCHE_GRAPH_USERS` kullanıcıları listeledi; paylaşılan bir posta kutusunun kullanıcısını gösterdi (hesap kapalı; yönetici ve grup yok); bir Microsoft 365 grubunun üyelerini adıyla buldu. SAP hesap kontrolü kullanıcıları okudu ama hiçbirini karşılaştırmadı: o sırada deneme sistemindeki SAP kullanıcılarının SU01'de e-posta adresi yoktu. Karşılaştırma o tarihte yalnız birim testiyle sınanmıştı; aşağıdaki 6–7 Kasım kayıtları tenant karşılaştırmalarını ekler.
- **Takvim (5 Kasım):** `ZCHE_GRAPH_CALENDAR` paylaşılan bir posta kutusunun takviminde 10:00–10:30 arası bir etkinlik oluşturdu (SAP saat dilimi `TURKEY`) ve aynı saatlerle geri listeledi. Aynı anahtarla tekrar çalıştırılınca aynı etkinlik döndü; takvimde yine tek etkinlik vardı.
- **Teams toplantıları ve boş zaman (5 Kasım, 0.7.0):** lisanslı bir kullanıcının takviminde, katılımcısız, iki kez tekrarlanan haftalık bir Teams toplantısı: iki tekrar da katılma bağlantısıyla geri geldi, sonra seri silindi. Boş zaman araması iki posta kutusu için 09:00–09:30'u buldu; toplantının olduğu yarım saatte boş zaman bulmadı.
- **Takvim yeniden, 0.7.2 (5 Kasım):** lisanslı bir kullanıcının takviminde, 15:00–15:30 `TURKEY`, iki kez tekrarlanan haftalık bir Teams toplantısı: SAP iki tekrarı da katılma bağlantısıyla listeledi; kullanıcının İstanbul'a ayarlı Outlook'u 15:00–15:30'u **Katıl** düğmesiyle gösterdi. Boş zaman araması 14:00–16:00 penceresinde 14:00–14:30'u buldu; sonra seri silindi ve o haftanın listesi boş döndü. Daha önce 14:00'e oluşturulan bir etkinlik, bir paylaşılan posta kutusunun Outlook'unda 11:00'de görünmüştü: o kutu UTC'ye ayarlıydı (bkz. [Outlook takvimi](TECHNICAL.tr.md#outlook-takvimi)).
- **`"SAP, Test" <sap@…>` adresine e-posta (0.7.2):** tek alıcı; Microsoft kabul etti. Gelen kutusunda teslim ayrıca kontrol edilmedi.
- **Teams kanal mesajları (0.7.2):** bir kanalda Workflows web kancası, adresi G tipi bir SM59 hedefinde (adresin tamamı yol önekine sığdı). `ZCHE_GRAPH_TEAMS` iki ad/değer satırı ve sistem, kullanıcı, zaman bilgisiyle bir `warning` kartı gönderdi: kart kanalda, başlığı uyarı renginde göründü.
- **SAP ile karşılaştırmalar (6 Kasım, 0.8.0):** bir SAP test kullanıcısına (`BWDEVELOPER`, `ZDEVELOPER` rolüyle) Microsoft hesabı kapalı olan paylaşılan posta kutusunun adresi girildi. Deneme sistemindeki diğer kullanıcıların hâlâ adresi yoktu.
  - SAP hesap kontrolü bu kullanıcıyı karşılaştırdı ve *Microsoft hesabı kapalı* bulgusunu verdi.
  - `SAP Test` grubu (tek üye: tenant yöneticisi) ile `ZDEVELOPER` rolü karşılaştırması üç bulgu verdi: üyenin bu adresle bir SAP kullanıcısı yok; `BWDEVELOPER` rolde var ama grupta yok; `DEVELOPER` rolde var ama adresi olmadığı için karşılaştırılmadı.
  - SU01 ile Entra ID karşılaştırması bu kullanıcıyı karşılaştırdı ve önce fark bulmadı: posta kutusunun hesabında ad, soyad, departman ya da unvan yoktu; Entra ID'deki boş bir değer hiçbir zaman öneri olarak gösterilmiyor. Entra yönetim merkezinde ad `Test`, soyad `SAP` ve departman `IT` girildikten sonra aynı çalıştırma üç fark listeledi: ad `Doe` → `Test`, soyad `Jane` → `SAP`, departman boş → `IT` (SU01'deki adlar deneme sisteminin kendi verisi). Entra ID'de hâlâ boş olan unvan önerilmedi.
- **Ayrı Active Directory aracından uyarlanan bazı kontroller (7 Kasım, 0.8.0, commit `e476476`):** geçici, kilitli bir SAP test kullanıcısına `SAP Test` grubundaki üyenin adresi girildi; tenant'ta hiçbir şey değiştirilmedi.
  - `SAP Test` grubu ile `ZDEVELOPER` rolü: üye artık *grupta, SAP kullanıcısı kilitli ya da geçersiz* olarak bildiriliyor. Diğer iki bulgu (`BWDEVELOPER`, `DEVELOPER`) 6 Kasım'daki gibi kaldı.
  - Bu kullanıcı ve `BWDEVELOPER` için "SAP'de kilitli, Entra'da açık" işaretli SAP hesap kontrolü: `BWDEVELOPER` için *Microsoft hesabı kapalı*, test kullanıcısı için *SAP'de kilitli ya da geçersiz, Microsoft hesabı açık*. Kutu işaretli değilken yalnız `BWDEVELOPER` bildirildi.
  - SU01 ile Entra ID karşılaştırması 6 Kasım'daki üç farkı aynen listeledi.
  - "Kullanıcıyı göster" üyenin iş telefonunu Graph'tan okuyup gösterdi.
  - `S_USER_GRP` yetkisi olmayan bir test kullanıcısıyla arka plan işinde çalıştırılan hesap kontrolü *Dışarıda bırakılan SAP kullanıcısı: görüntüleme yetkisi yok: 1* yazdı.
  - Test kullanıcısı sonra silindi. `ZCHE_GRAPH_USERS`'ın 42 birim testi geçiyor.

Tenant'ta bulunup 0.5.1'de düzeltilenler:

- **İndirme:** SharePoint, `$select` ile sorulunca `@microsoft.graph.downloadUrl` alanını döndürmüyor. Modül artık Microsoft'un [indirme sayfasındaki](https://learn.microsoft.com/en-us/graph/api/driveitem-get-content) gibi `select` ile soruyor.
- **Excel:** `00789` hücreye 789 olarak yazılıyordu, çünkü Excel metni elle yazılmış bir giriş gibi yorumluyor. Metinler artık başlarında kesme işaretiyle gidiyor.

  ![0.5.1 sonrası E2'de 00789](docs/img/excel-leading-zero.png)
- **`ZCHE_GRAPH_CHECK`:** "Token'daki izinler:" sonrasındaki boşluk eksikti.

Kod incelemesinde bulunup 0.7.1'de düzeltilenler:

- UTF-8 olmayan bir cevap (proxy'nin hata sayfası) kısa dump veriyordu; artık normal hata veriyor.
- Büyük cevaplar yavaş okunuyordu: JSON okuyucu her metin için metnin bütün kalanında ters bölü arıyordu.
- Arka plan işinde iş günlüğü hatanın yerine ipucu ya da request-id satırını gösteriyordu.
- SAP'nin tanımadığı bir saat dilimi ya da boş saat dilimi yanlış saat üretiyordu; artık bunu söyleyen bir hata veriyor.
- `"Kaya, Derya" <derya@b.com>` virgülden iki alıcıya bölünüyordu.
- Değeri nesne olan liste alanları (bağlantı, konum, tek kişi) kayıtta yer almıyordu.
- Birden çok kişi seçilebilen kişi sütunu tek kişilik sanılıyordu.
- Negatif sayı JSON'a `5-` olarak yazılıyordu.
- Çalışma sayfası ekleme yanlış adrese gidiyordu (`worksheets/add`); tenant'ta denenmedi.

0.7.2'de de:

- Büyük yüklemenin parçaları, diğer PUT istekleri gibi HTTP 429, 503 ya da 504'ten sonra tekrar gönderiliyor. Başarısız bir yükleme oturumunu kapatıyor; başarısız büyük e-posta yarım kalan taslağını siliyor ve bunu söylüyor.
- Son parçadan sonra hâlâ bayt eksikse bu bir hata; boş bir dosyayla "OK Uploaded" ya da eki olmayan bir e-posta değil.
- E-postanın tek isteğe sığıp sığmadığı hesaplanırken yalnız ekler değil, gövde de sayılıyor. HTTP 413 için ipucu var.
- İpuçları "yeniden denendi" sözünü yalnız gerçekten denendiğinde söylüyor; yönlendirme (3xx) hata sayılıyor ve takip edilmiyor.
- Takvimde bir günün listesi artık önceki günün tüm gün etkinliklerini göstermiyor; başka saat diliminde Outlook'ta oluşturulmuş tüm gün etkinlik doğru tarihini alıyor. Kimse verilmeden ya da bitiş başlangıçtan önceyken boş zaman aramak hata veriyor.
- Listeler: `OwnerLookupId`, sütun birden çok değere izin veriyorsa ID listesi yazıyor; kendi adı LookupId ile biten bir sütun kendi türünü koruyor; boş değer evet/hayır ya da tarih alanını temizliyor; `upsert`'te sayı tipindeki anahtar sütun sayı olarak karşılaştırılıyor.
- `#` içeren konuk adresleri e-posta ve takvimde çalışıyor; klasör yolları çözülmüş olarak geliyor; SAP hesap kontrolü 100.000 kullanıcının üstünde hata veriyor; Teams hatası web kancası anahtarını içeren bir cevabı asla göstermiyor.

Tenant'ta bulunan ve 0.7.3'te düzeltilen:

- `ZCHE_GRAPH_TEAMS`'in eklediği "Zaman" satırı, sunucunun saatini kullanıcının saat dilimi adıyla gösteriyordu (test sisteminde UTC saati CET etiketiyle, bir saat farkla). Artık kullanıcının kendi tarih ve saatini gösteriyor. Aynı sebeple `ZCHE_GRAPH_CALENDAR`'ın önerdiği tarih artık sunucunun değil, kullanıcının bugünü.

İkinci bir kod incelemesinde bulunan ve 0.7.4'te düzeltilen:

- **Takvim:** okunup geri yazılan etkinlik metnini kaybediyordu: okuma kısa önizlemeyi alıyor, güncelleme onu tam metnin (ve içindeki Teams katılma bilgilerinin) üzerine yazıyordu. Artık okuma tam metni türüyle (HTML ya da metin) koruyor; önizleme ayrı bir alan.
- **Takvim:** "Bu takvimden sil" katılımcılara haber verilmeyeceğini söylüyordu; düzenleyenin takviminde Microsoft onlara iptal gönderiyor. Program ve açıklama artık bunu söylüyor.
- **Takvim:** en çok etkinlik sayısı verildiğinde önceki günün tüm gün etkinlikleri bu sayıdan yer kaplıyordu; olandan az etkinlik dönüyordu.
- **Listeler:** çoklu seçim sütununda bir seçimin içindeki boşluklar birleşiyordu (`ACME  LTD`, `ACME LTD` oluyordu).
- **E-posta:** e-postanın tek isteğe sığıp sığmadığına artık kaçışlarıyla birlikte isteğin kendisine bakılarak karar veriliyor; metindeki çok sayıda tırnak ya da satır sonu onu 4 MB'ın üstüne çıkarabiliyordu.
- **Ortak yardımcı dosya:** SAP'nin HTTP istemcisine yönlendirmeleri kendisinin takip etmemesi söyleniyor; böylece 3xx her zaman yukarıda anlatılan hataya ulaşıyor.
- **Teams:** yönlendirme (3xx) "OK Sent" olarak bildiriliyordu; artık yalnız 2xx sayılıyor.
- **Excel:** `AAAAAAAA1` ya da `A99999999999` gibi bir başlangıç hücresi programı taşmayla durduruyordu; sayfaya sığmayan blok artık bir hata.

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
- **Ortak yardımcı dosyanın birim testleri:** 16 ABAP Unit testi geçiyor; Microsoft yerine bir test dublörü cevap veriyor. Kapsadıkları:
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
  - `graph.microsoft.com`, ortak yardımcı kodun okuduğu yerde `request-id` bulunan bir `401 InvalidAuthenticationToken` cevabı verdi.

**Henüz doğrulanmadı:**
- **E-postanın Microsoft'ta denenmesi:** HTML e-postalar, ekler (spool'dan olanlar dahil), büyük e-postalar, işaretleme ve taşıma. Posta kutusu sınırlaması (RBAC for Applications) kurulamadı: yeni tenant'ta Exchange Online, `Enable-OrganizationCustomization` adımında kendi iç hatasıyla durdu.
- **Büyük eklerin Microsoft'a yüklenmesi:** yükleme adresinin host'u ve SICF proxy yolu.
- **Kullanıcıların ve takvimin Microsoft'ta denenmesi:** canlı şirket kullanıcılarının tümü üzerinde SAP hesap kontrolü, yönetici ve bağlı çalışanlar (tanımlı değildi), iç içe gruplar, SU01 kontrolünde telefon farkı (yalnız birim testi: tenant'ta telefon değiştirilmedi, test verisine gerçek numara konmadı); katılımcılı etkinlikler ve cevapları, tüm gün etkinlikler, değiştirme ve iptal, aylık seri, yaz saati olan bir saat diliminde seri, şirket dışındaki kişilerin boş zamanı.
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
