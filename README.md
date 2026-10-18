# TV Kumanda (iPhone)

Salondaki Philips Google TV için iPhone kumandası: yön tuşları, OK, Geri, Home, ses, oynatma, güç, Ambilight paneli, uygulama kısayolları ve telefondan yazı yazma.
TV tarafının notları: `~/tv2-debloat/README.md`.

## Derleme ve telefona kurma

```
cd ~/Developer/TVKumanda
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project TVKumanda.xcodeproj -scheme TVKumanda -destination 'generic/platform=iOS' \
  -derivedDataPath .build/xcode-device -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-001A036E3C87801C \
  .build/xcode-device/Build/Products/Debug-iphoneos/TVKumanda.app
```

Telefonun kilidi açık ve Mac ile aynı Wi-Fi'da olmalı; bağlanmazsa birkaç kez tekrar dene ya da kabloyla tak.
Sürüm numarası `TVKumanda.xcodeproj/project.pbxproj` içindeki `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.

## İki bağlantı

| | Philips JointSpace | Android TV kumanda protokolü |
|---|---|---|
| Port | 1926 (HTTPS, digest) | 6467 eşleme, 6466 kumanda |
| Eşleme | Uygulama ilk açılışta, TV'de 4 haneli PIN | Sertifika Mac'ten bir kez eşlendi, uygulamaya gömülü |
| Kullanım | Güç, ses düzeyi, Ambilight; kanal düşerse tuşlar | Tuşlar (basılı tutma dahil), uygulama açma, yazı |

- Gömülü sertifika: `TVKumanda/client.p12` (parola `tvkumanda-remote`), PEM halleri `certs/` (gizli, paylaşma).
  Bunlar ve `tools/jointspace_mac_pairing.json` **git'e girmez**; ayrı yedekte durur. Depodan temiz kurulumda `client.p12` yoksa
  uygulama Android TV kanalına bağlanamaz: yedekten geri koy ya da `tools/atv.py pair` ile yeni sertifika eşleyip p12'ye çevir.
- TV sıfırlanırsa: uygulamada **Ayarlar → Kodla yeniden eşleştir** (TV'de 6 karakter çıkar).

## TV'de doğrulanmış kurallar

- **Uygulama açma:** `market://launch` bu TV'de çalışmıyor. Kısayollar `kutu://launch/<paket>` gönderir, TV'deki Kutu Home açar. Yeni kısayol: `TVKumanda/Model/TVApp.swift`.
- **Yazı:** TV, metin düzenlemesini yalnız şu sayaçlarla kabul ediyor:
  `ime_counter` = odak mesajındaki (20) uygulama bilgisinin sayacı, `field_counter` = son alan durumundaki (20 ya da 22) içerik sayacı.
  Gönderilen metin imlecin yerine **eklenir** (alanı değiştirmez); silme DEL tuşuyla. Harf tuşları bu TV'de yazı olarak alınmıyor.
  Reddedilen düzenlemenin nedeni TV kaydında: `adb logcat | grep AtvRemote.ImeFeature`.
- **Basılı tutma:** tuş başlangıç/bitiş (yön 1/2) gönderilir; TV Bro'nun imleci ancak böyle hareket eder.
- Netflix ve YouTube kendi ekran klavyelerini kullanır; oralara telefondan yazı gitmez.
- JointSpace'in uygulama açma komutu Android 14'ün arka plan engeline takılıyor (kullanılmıyor).

## Test araçları (`tools/`)

```
cd ~/Developer/TVKumanda/tools
python3 atv.py pair                       # Android TV eşlemesi (kodu code.txt dosyasına yaz)
python3 atv.py session "app:kutu://launch/com.phlox.tvwebbrowser" "wait:3"
python3 daemon.py                         # bağlantıyı açık tutar, TV mesajlarını daemon.log'a yazar,
                                          # cmd.txt'ye eklenen komutları çalıştırır (key 22, text merhaba, ctr 8 84 …)
python3 jointspace.py get ambilight/currentconfiguration
```

`jointspace_mac_pairing.json` Mac'in Philips eşleşme bilgisidir (gizli).
