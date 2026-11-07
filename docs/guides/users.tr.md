# Microsoft kullanıcılarını ve grup üyelerini SAP’de listelemek

[Ana rehber](../../WALKTHROUGH.tr.md) · [English](users.md) | **Türkçe**

Bu bölüm, Microsoft 365 kullanıcılarını ve grup üyelerini SAP’de listelemeyi açıklar. İlk kullanımda sınırlı sayıda hesabı okuyun ve Microsoft tarafındaki bilgilerle karşılaştırın. Program yalnız okuma yapar; hesap oluşturmaz, silmez veya kapatmaz.

## 1. Erişimi hazırlayın

[Graph bağlantısını](connection.tr.md) hazırlayın. Microsoft yöneticiniz kullanıcı okuma için `User.Read.All`, grup üyeleri için `GroupMember.Read.All` uygulama izinlerini değerlendirip onaylar. Bunlar kuruluşun kullanıcı/grup bilgilerine erişim sağlar; posta veya dosya izni istemez.

## 2. Dosyaları ekleyin

[SE38 sırası](install.tr.md): `ZCHE_GRAPH_CORE` → `ZCHE_GRAPH_USERS_LIB` → `ZCHE_GRAPH_USERS`.

## 3. İlk listeyi alın

**SE38 → ZCHE_GRAPH_USERS → F8**. Tenant ve SM59 alanlarına kendi bağlantınızı girin:

1. **Find users / Kullanıcı ara** seçin.
2. **Filter / Filtre** alanını boş bırakın; **At most / En çok** değerini `5` yapın.
3. **F8** ile çalıştırın. Gelen adları ve hesap adreslerini Microsoft ortamınızdakilerle karşılaştırın.

![SAP kullanıcı aramasında Find users, boş Filter ve At most 5 alanları.](../img/walkthrough/users-find-input.png)

*A4H/001 giriş örneği. Bu seçim en fazla beş hesabı okur; kendi Tenant ve SM59 bilgilerinizi kullanın.*

![SAP kullanıcı listesinde üç Microsoft hesabı ve hesap durumları.](../img/walkthrough/users-result.png)

*5 Kasım 2026’da A4H/001’de, 0.7.4 kurulu oturumda alınan üç hesaplık sonuç. `disabled`, Microsoft hesabının devre dışı olduğunu belirtir; programın hesabı kapattığı anlamına gelmez.*

Grup üyeleri için **Members of a group / Grubun üyeleri** seçip kendi grubunuzun adını veya ID’sini girin. **Show a user / Kullanıcıyı göster** seçeneği belirli hesabın ayrıntılarını getirir.

<details>
<summary>Ek örnek: grup üyelerini listelemek</summary>

![SAP kullanıcı programında Members of a group seçimi ve SAP Test grup adı.](../img/walkthrough/users-group-input.png)

*Members of a group seçildiğinde Group alanına kendi grubunuzu girin. Bu örnekte `SAP Test` ve en fazla beş üye seçildi; User alanı boş bırakıldı.*

![SAP Test grubunun okuma sonucunda Members 1 ve bir üyenin hesap bilgileri.](../img/walkthrough/users-group-result.png)

*Aynı A4H/001 oturumunda grubun bir üyesi listelendi. Bu işlem grup üyeliğini değiştirmez.*

</details>

Liste geldiğinde adları ve hesap adreslerini kontrol etmek bu ilk deneme için yeterli.

## 4. SAP ile karşılaştırma (isteğe bağlı)

Üç seçenek Microsoft'u SAP kullanıcılarıyla karşılaştırır. Yalnız rapor verirler; hiçbir şey değiştirilmez.

- **SAP kullanıcıları: hesap**: Microsoft hesabı kapalı ya da hiç olmayan aktif SAP kullanıcıları.
- **Grup ile SAP rolü**: bir grup ve bir SAP rolü girin. Liste, grupta olup rolü olmayanları ve rolü olup grupta olmayanları gösterir.
- **SU01 ile Entra ID**: SU01 ile Microsoft arasında farklı olan ad, departman ve unvan.

Kişiler SU01'deki e-posta adresiyle eşleşir. Karşılaştırmalar ek SAP okuma yetkileri ister. [Ayrıntılar](../../TECHNICAL.tr.md#entra-id-kullanıcıları-ve-grupları)

Rol ve SU01 seçenekleri 0.8.0'da eklendi ve henüz SAP'de denenmedi.
