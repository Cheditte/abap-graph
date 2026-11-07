# abap-graph

> [English](README.md) | **Türkçe**

![abap-graph: SAP ve Microsoft logolarıyla Microsoft 365 entegrasyonu; e-posta, dosya ve takvim simgeleri](docs/visuals/abap-graph-cover.png)

**SAP’den Microsoft 365 ile e-posta, dosya ve takvim işlemleri.**

Bu projeyi, SAP ile Microsoft 365 arasında çalışırken aynı bağlantı ve işlem kodlarını tekrar yazma ihtiyacını azaltmak için geliştirdim. Hazır programları ve gerekli dosyaları, kendi sisteminizde kullanıp uyarlayabilmeniz için bir araya getirdim.

**Yalnız ihtiyacınız olan bölümü kurun.** Örneğin Teams’e bildirim göndermek için e-posta veya Excel bölümünü kurmanız gerekmez. Hazır ekranlarda işlem yapabilir; bir ABAP geliştiricisiyle bunları kendi iş süreçlerinize bağlayabilirsiniz.

**[Görselli kurulum ve kullanım yol haritası →](WALKTHROUGH.tr.md)**

## Ne yapmak istiyorsunuz?

![SAP ve Microsoft logolarıyla kullanım alanları: Microsoft Graph üzerinden e-posta, takvim, dosyalar, listeler, kullanıcılar ve gruplar; Excel hücreleri deneysel. Teams bildirimleri ayrı Workflows bağlantısını kullanır.](docs/visuals/integration-map-tr.png)

*Açıklayıcı çizimdir; test ekranı değildir. Teams bildirimleri ayrı Workflows yolunu kullanır. Excel hücre işlemlerinde [destek sınırını](docs/guides/excel.tr.md) okuyun.*

| İhtiyacınız | Başlayacağınız bölüm |
| --- | --- |
| SAP’den bir Teams kanalına bildirim göndermek | [Teams bildirimi](docs/guides/teams.tr.md) |
| Teams toplantı bağlantısı oluşturmak veya takvimi okumak | [Takvim ve toplantılar](docs/guides/calendar.tr.md) |
| Bir posta kutusundan e-posta göndermek veya gelenleri okumak | [E-posta](docs/guides/mail.tr.md) |
| SharePoint / OneDrive’a dosya yüklemek veya dosya indirmek | [Dosyalar](docs/guides/files.tr.md) |
| Var olan Excel dosyasının hücrelerini okumak veya değiştirmek | [Excel — destek sınırını okuyun](docs/guides/excel.tr.md) |
| SharePoint listesindeki kayıtlarla çalışmak | [Listeler](docs/guides/lists.tr.md) |
| Microsoft kullanıcılarını ve grup üyelerini listelemek | [Kullanıcılar ve gruplar](docs/guides/users.tr.md) |

## Başlamak için üç hazırlık

1. **İşleminizi seçin.** Kullanacağınız posta kutusunu, dosyayı, siteyi veya Teams kanalını belirleyin.
2. **Erişimi hazırlayın.** Microsoft tarafında gerekli izinleri, SAP tarafında bağlantıyı tanımlayın. Yetkiler başka bir ekipteyse ilgili rehberi o ekiple paylaşın.
3. **Gereken dosyaları SAP’ye ekleyin.** Ortak yardımcı dosyayı ve seçtiğiniz bölümün dosyalarını kurun; ilk işlemi test ortamında deneyin.

Microsoft Graph, programların Microsoft 365 hizmetlerine erişmesini sağlayan arayüzdür. Bilgisayarınıza ayrıca Graph kurmazsınız. Teams kanal bildirimi ayrı bir İş Akışı bağlantısı kullanır; hangi hazırlıkların gerektiği her rehberde belirtilmiştir.

## Durum ve uyumluluk

| Konu | Durum |
| --- | --- |
| Kaynak sürümü | 0.8.0; henüz yayımlanmamış geliştirme sürümü |
| Denenen ortam | A4H/001, SAP_BASIS 816 ve Microsoft 365 test ortamı; kapsam sürüm ve işleme göre değişir |
| Eski SAP sistemleri | Klasik ABAP 7.00 sözdizimi hedeflenir; ECC 6.0’da henüz denenmedi |
| Excel hücre işlemleri | Kullanılan giriş yöntemi için Microsoft’un destek sınırlaması var; hazır `.xlsx` dosyalarını taşımak için Dosyalar bölümünü kullanabilirsiniz |

[Deneme sonuçları ve açık kalanlar →](VALIDATION.tr.md)

## Ayrıntılara geçmek isterseniz

- **Kurulum ve ilk kullanım:** [ekran görüntülü yol haritası](WALKTHROUGH.tr.md)
- **Alanlar, izinler ve kendi ABAP kodunuzda kullanım:** [teknik başvuru](TECHNICAL.tr.md)
- **Kaynak dosyalar:** [src klasörü](src)

---

[MIT lisansı](LICENSE) · [Hata bildirimi ve geri bildirim](https://github.com/Cheditte/abap-graph/issues)
