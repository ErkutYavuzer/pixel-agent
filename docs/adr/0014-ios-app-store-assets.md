# ADR-0014: iOS App Store Asset ve Privacy Manifest

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** ios, app-store, privacy

## Context

`PixelAgentRemote` iOS uygulaması v0.1.0'da yalnızca pairing + chat iskeletiyle gönderildi; App Store yayına hazır değildi: AppIcon yok, default boş `UILaunchScreen`, Privacy manifest yok. Apple 2024 itibarıyla App Store submission'larda `PrivacyInfo.xcprivacy` ve "required reason API" beyanı zorunlu hâle getirdi. Ayrıca v0.1.0'ın bundle versiyonu Mac core'unun çok gerisinde kalmıştı (Mac v0.2.2 ↔ iOS 0.1.0).

## Decision

### AppIcon

- `PixelMascot.idleFrame` (12×12 ASCII grid) tek master 1024×1024 PNG'ye render edilir. sRGB, **alpha kanalı yok** (App Store gereksinimi).
- Tüm boyutlar (60×60@2x, 76×76@2x~ipad vs.) Xcode tarafından master'dan üretilir; manuel boyut listesi tutulmaz.
- Arkaplan koyu mor (`#1C142E`) — squircle mask ile iyi kontrast veriyor.
- Render scripti `scripts/generate-app-icon.py` (Python + Pillow). `IDLE_FRAME` ve `PALETTE` sabitleri `Sources/PixelMascot/PixelMascot.swift` ile bire bir aynı tutulur.
- AppIcon değiştirmek için: ASCII grid'i / palette'i Swift tarafında değiştir → scripti çalıştır → commit.

### Launch screen

- `LaunchScreen.storyboard` **yerine** Info.plist `UILaunchScreen` dictionary kullanılır (iOS 13+):
  - `UIColorName: LaunchBackground` (asset catalog colorset, `#1C142E`)
  - `UIImageName: LaunchIcon` (asset catalog imageset, mascot @1x/@2x/@3x)
  - `UIImageRespectsSafeAreaInsets: true`
- Gerekçe: ayrı storyboard ek dosya, ek dependency, ek Xcode UI değişikliği gerektiriyor. Dictionary yöntemi tamamen text-based, xcodegen ile reproducible.

### Privacy manifest (`PrivacyInfo.xcprivacy`)

Beyan edilen alanlar:
- `NSPrivacyTracking: false` (uygulama hiç track etmiyor)
- `NSPrivacyTrackingDomains: []`
- `NSPrivacyCollectedDataTypes: []` — relay'e gönderilen kullanıcı mesajları **collection** sayılmaz çünkü uygulama veya geliştirici tarafından depolanmıyor; sadece kullanıcının kendi Mac'ine forward ediliyor.
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`: pairing bilgisini aynı uygulamanın içinde tutuyoruz (`pixel-agent.pairing.v1` key, dokümante edilmiş davranış).

Yeni "required reason API" kullanılırsa (file timestamp, system boot time, vb.) manifest'e satır eklenmesi gerekli.

### Asset catalog yapısı

```
ios/PixelAgentRemote/Assets.xcassets/
├── AppIcon.appiconset/
│   ├── Contents.json (universal, ios, 1024x1024 single entry)
│   └── AppIcon-1024.png
├── AccentColor.colorset/       # iOS tint color (mor)
├── LaunchBackground.colorset/  # launch screen arkaplan
└── LaunchIcon.imageset/        # launch screen mascot logosu
    ├── LaunchIcon.png      (240×240)
    ├── LaunchIcon@2x.png   (480×480)
    └── LaunchIcon@3x.png   (720×720)
```

### Bundle versiyon

iOS app v0.1.0 → **v0.2.0** (`CFBundleShortVersionString`), build `2`. Mac core ile aynı major+minor'a hizalanır.

## Consequences

**Olumlu:**
- App Store submission'da privacy compliance hatası alınmaz.
- AppIcon ve launch screen reproducible — repo clone + `xcodegen generate + python3 scripts/generate-app-icon.py` ile bire bir aynı bundle çıkar. Manuel Xcode tıklaması yok.
- Marka tutarlılığı: Mac status bar mascot'u ile iOS app icon aynı ASCII grid'den gelir; tek noktadan değişir.

**Olumsuz:**
- Pillow build dependency eklendi (sadece dev — runtime'da yok).
- Apple "required reason API" listesini değiştirirse manifest manuel güncellenmeli (otomatik tespit yok).

## Alternatives

- **SF Symbols icon olarak**: Apple icon olarak SF Symbol kabul etmiyor — raster PNG zorunlu.
- **Storyboard launch screen**: Daha esnek (ortada metin + icon + version stamp olabilir) ama xcodegen ile yönetilmesi zor; başka bir XML formatı + IB sürümleme. Vazgeçildi.
- **Tüm icon boyutlarını manuel commit**: Xcode 14+ tek master'dan otomatik üretiyor; ekstra dosya tutmanın anlamı yok.

## References

- [Apple — Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [Apple — Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api)
- `scripts/generate-app-icon.py`
- `ios/PixelAgentRemote/PrivacyInfo.xcprivacy`
- `ios/project.yml`
