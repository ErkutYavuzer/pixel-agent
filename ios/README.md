# pixel-agent iOS

iOS uzak istemci — Mac'teki pixel-agent core'una WebSocket relay üzerinden bağlanır.

## Xcode project kurulumu (tek seferlik, manuel)

Bu klasörde Swift kaynak dosyaları var ama `.xcodeproj` yok. SPM iOS app target'larını sınırlı destekliyor; Xcode IDE / simulator için ayrı project gerek. Setup:

1. **Xcode → File → New → Project**
2. **iOS → App template**, Interface: `SwiftUI`, Language: `Swift`
3. Product Name: `PixelAgentRemote`, Organization Identifier: `dev.erkutyavuzer`
4. Save location: `~/Projects/pixel-agent/ios/` (yani buradaki klasör seçildiğinde Xcode `PixelAgentRemote.xcodeproj` yaratır)
5. Xcode otomatik bir `PixelAgentRemote/` alt-klasör yaratır. Onun yerine **mevcut bu klasördeki** Swift dosyalarını kullanmak için:
   - Xcode'un yarattığı default `ContentView.swift`, `PixelAgentRemoteApp.swift`, `Assets.xcassets` vb. dosyaları sil
   - Bu klasördeki `PixelAgentRemoteApp.swift`, `ContentView.swift`, `RemoteSession.swift`, `PairingScannerView.swift`, `ChatView.swift` dosyalarını Xcode navigator'a sürükle (✅ "Add to target")
   - `Info.plist`: Xcode default'unu üzerine bu klasördeki ile değiştir (`NSCameraUsageDescription` zorunlu)
6. **Add Local Package Dependency:**
   - File → Add Package Dependencies → Add Local
   - Path: `..` (parent — `pixel-agent` monorepo)
   - Products: `PixelCore` + `PixelRemote` ekle (PixelAgentRemote target'ına)
7. **Deployment target:** iOS 17.0+ (SwiftUI `@Observable`, `Image(decorative:scale:)` vb. için)
8. Build & run — iOS Simulator veya gerçek cihaz

## Pairing flow (test)

1. Mac tarafı:
   ```bash
   cd ~/Projects/pixel-agent
   swift run PixelMacApp
   ```
   Üst sağ QR ikonuna tıkla → `PairingView` açılır, QR kod görünür.

2. Cloudflare Worker (lokal dev için):
   ```bash
   cd relay
   npm install
   npm run dev      # ws://localhost:8787
   ```

3. iOS app'i çalıştır (Xcode → ⌘R)
4. Kameraya QR kodu göster → bağlantı kurulur
5. iOS'tan mesaj yaz → Mac'teki ChatView'da görmen lazım (Faz 2'de iki yönlü)

## Sınırlar (MVP)

- iOS'tan gelen mesaj Mac'in chat akışına entegre değil (Hafta 6'da)
- Stream yok; assistant yanıtı tek seferde gelir (Mac stream bitince)
- Reconnect manuel
- Auth sadece pairing code; ed25519 imza yok (v0.2'de)

## Dosyalar

| Dosya | Sorumluluğu |
|---|---|
| `PixelAgentRemoteApp.swift` | `@main` SwiftUI App, `RemoteSession` `@StateObject` |
| `ContentView.swift` | Root view — bağlıysa `ChatView`, değilse `PairingScannerView` |
| `RemoteSession.swift` | `RelayClient` wrap, `ObservableObject`, send/receive flow, `PairingInfo` parse |
| `PairingScannerView.swift` | `AVCaptureSession` + `UIViewControllerRepresentable` QR scan |
| `ChatView.swift` | iOS chat UI (mesaj listesi + composer) |
| `Info.plist` | `NSCameraUsageDescription` (zorunlu) |
