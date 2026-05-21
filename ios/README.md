# pixel-agent iOS

iOS uzak istemci — Mac'teki pixel-agent core'una WebSocket relay üzerinden bağlanır.

## Build

`.xcodeproj` dosyası **gitignored** ve [xcodegen](https://github.com/yonaskolb/XcodeGen) ile her seferinde `project.yml`'den üretilir.

```bash
brew install xcodegen          # tek seferlik
cd ios
xcodegen generate              # → PixelAgentRemote.xcodeproj
```

Simulator build (CLI):

```bash
xcodebuild \
  -project ios/PixelAgentRemote.xcodeproj \
  -scheme PixelAgentRemote \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ios/build \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Veya doğrudan Xcode'da `ios/PixelAgentRemote.xcodeproj` aç → ⌘R.

Gerçek cihaza kurulum için `DEVELOPMENT_TEAM` `project.yml`'de set (varsayılan `LH3Z8J92FX` — sahibinizinkiyle değiştirin) ve:

```bash
xcodebuild ... -allowProvisioningUpdates build && \
  xcrun devicectl device install/launch ...
```

## Asset üretimi

AppIcon ve launch screen mascot logosu `Sources/PixelMascot` ASCII grid'inden türetilir. Mascot değişirse:

```bash
python3 scripts/generate-app-icon.py    # 1024 master + LaunchIcon @1x/@2x/@3x
```

Detay: [ADR-0014](../docs/adr/0014-ios-app-store-assets.md).

## Pairing flow (test)

1. Mac tarafı:
   ```bash
   cd ~/Projects/pixel-agent
   ./scripts/build-app.sh release && open PixelAgent.app
   ```
   Üst sağ QR ikonuna tıkla → `PairingView` açılır, QR kod görünür.

2. Cloudflare Worker (lokal dev için):
   ```bash
   cd relay
   npx wrangler dev --ip 0.0.0.0       # LAN'a 0.0.0.0:8787
   ```

3. iOS app'i çalıştır (Xcode ⌘R veya `xcrun simctl launch ...`)
4. Kameraya QR kodu göster → bağlantı kurulur. UserDefaults'a pairing kaydedilir, sonraki açılışlar otomatik bağlanır.
5. Çift yönlü mesajlaşma çalışır (Hafta 6'da `RemoteHost` ile Mac ChatView'a forward landed).

## Sınırlar (v0.2)

- Stream yok; assistant yanıtı tek seferde gelir (Mac stream bitince forward).
- Reconnect 5s timeout sonra forget.
- Auth sadece pairing code; ed25519 imza v0.3 hedefli.

## Dosyalar

| Dosya | Sorumluluğu |
|---|---|
| `project.yml` | xcodegen project tanımı (bundle ID, team, deployment target, assets) |
| `PixelAgentRemote/PixelAgentRemoteApp.swift` | `@main` SwiftUI App, `RemoteSession` `@StateObject` |
| `PixelAgentRemote/ContentView.swift` | Root view — bağlıysa `ChatView`, değilse `PairingScannerView` |
| `PixelAgentRemote/RemoteSession.swift` | `RelayClient` wrap, `ObservableObject`, send/receive, `PairingInfo` parse + UserDefaults persist |
| `PixelAgentRemote/PairingScannerView.swift` | `AVCaptureSession` + `UIViewControllerRepresentable` QR scan |
| `PixelAgentRemote/ChatView.swift` | iOS chat UI (mesaj listesi + composer) |
| `PixelAgentRemote/AboutView.swift` | "Hakkında" sayfası |
| `PixelAgentRemote/Info.plist` | bundle metadata + `NSCameraUsageDescription` + `UILaunchScreen` dictionary |
| `PixelAgentRemote/PrivacyInfo.xcprivacy` | App Store privacy manifest (UserDefaults reason, no tracking) |
| `PixelAgentRemote/Assets.xcassets/` | AppIcon (1024 master), AccentColor, LaunchBackground, LaunchIcon |
