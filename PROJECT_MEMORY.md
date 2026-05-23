# Project Memory - pixel-agent

Bu dosya projenin tek gerçek kaynağıdır (source of truth). Kronolojik oturum kayıtları, aktif durum, teknik kararlar, iptal edilen özellikler ve sonraki adımları içerir.

## Proje Hakkında
`pixel-agent`; macOS/iOS platformlarında çalışan, pixel-art maskot arayüzüne sahip, arka planda popüler LLM CLI araçlarını (Claude, Codex, Gemini) subprocess olarak tetikleyen agentik bir masaüstü kontrol sistemidir. Model Context Protocol (MCP) sunucusu, Unix domain socket köprüsü ve ed25519 imzalı Mac ↔ iOS iletişim kanalı ile entegre bir biçimde çalışır.

---

## 1. Kronolojik Oturum Kayıtları

### 23 Mayıs 2026 - İlk Detaylı Analiz ve Hafıza Oluşturma
- **Gerçekleştirilen İş:** Projenin tüm modülleri (`PixelCore`, `PixelBackends`, `PixelTools`, `PixelMemory`, `PixelMascot`, `PixelRemote`, `PixelLAN`, `PixelSubagent`, `PixelMCPServer`, `PixelComputerUse`, `PixelMacApp` ve `pixel-mcp-server`) satır satır okundu ve analiz edildi.
- **Bulgular:** 
  - Projenin SPM monorepo mimarisinde 10 kütüphane ve 2 executable target'tan oluştuğu teyit edildi.
  - Sürüm numaraları: `PixelCore`: 0.0.0, `PixelRemote`: 0.2.0, `PixelLAN`: 0.2.9, `PixelBackends`: 0.0.0, `PixelTools`: 0.1.0, `PixelMascot`: 0.1.0, `PixelMemory`: 0.1.0, `PixelSubagent`: 0.2.24, `PixelComputerUse`: 0.2.23, `PixelMCPServer`: 0.2.24.
  - `PROJECT_MEMORY.md` dosyası oluşturuldu.

---

### 23 Mayıs 2026 - Gemini Modeli Güncellemesi ve Chat İzolasyonu
- **Gerçekleştirilen İş:**
  - Gemini varsayılan model ID'si `gemini-3.5-flash`'tan `gemini-2.5-flash`'a çekildi (v0.43.0 CLI uyumluluğu için).
  - `ModelCatalog` içindeki geçersiz `gemini-3.5-flash` ve `gemini-3.1-pro` model ID'leri, CLI/API uyumlu doğru karşılıkları olan `gemini-3-flash-preview`, `gemini-3.1-pro-preview` ve `gemini-3-pro-preview` ile güncellendi.
  - Tekli chat modunda sekmeler arası sohbet geçmişinin karışmasını (spillover) önlemek amacıyla `RootView` ve `ChatHost` güncellenerek her backend için ayrı `ConversationStore` (`conversation-<kind>.jsonl`) kullanımı sağlandı.
  - Kullanıcının yerel tercihlerinde (UserDefaults/AppStorage) kayıtlı kalmış olabilecek eski geçersiz `gemini-3.5-flash` veya `gemini-3.1-pro` modellerini otomatik olarak tespit edip temizleyen ve çalışan varsayılana düşüren mantık `PixelMacApp.swift` içindeki `currentModel(for:)` metoduna eklendi.
  - İlgili birim testleri güncellenerek tüm testler (`swift test`) başarıyla koşturuldu.


---

### 23 Mayıs 2026 - iOS Mobil Uygulama Geliştirmeleri (Streaming & Yeniden Bağlanma)
- **Gerçekleştirilen İş:**
  - Mac ile iOS remote arasındaki veri paketi (`RemoteEnvelope`) genişletilerek `.assistantChunk` enum tipi ve `assistantChunk` factory metodu eklendi.
  - Mac tarafında `RemoteHost` sınıfına kelime kelime (chunk) gönderimini sağlayan `sendAssistantChunk` metodu entegre edildi.
  - `ChatViewModel`, `ChatView` ve `PixelMacApp` güncellenerek LLM yanıt akışı (streaming) anlık olarak iOS remote istemcisine yönlendirildi.
  - iOS mobil uygulamasına (`PixelAgentRemote`) monorepo içindeki `PixelMascot` kütüphanesi entegre edildi, `project.yml` güncellendi ve `xcodegen` ile proje dosyaları yeniden üretildi.
  - `RemoteSession` üzerinde exponential backoff tabanlı otomatik yeniden bağlanma algoritması ve WebSocket chunk okuma mekanizması geliştirildi.
  - iOS tarafında bağlantı kopsa dahi pairing bilgisinin silinip doğrudan kameraya atılması engellendi; chat ekranında kalınarak en üstte "Bağlantı kesildi, yeniden bağlanılıyor..." uyarısı ve "Tekrar Dene" butonu gösterilmesi sağlandı.
  - Sohbet arayüzüne `MascotView` entegre edilerek maskot durumunun anlık mesaj akışıyla senkron çalışması (.thinking, .speaking, .idle, .error) ve modern sağ-sol hizalı sohbet balonları eklendi.
  - **Bağlantı Kararlılığı ve Döngü Düzeltmesi:** `RemoteSession` içindeki yeniden bağlanma döngüsünün `disconnect(forget: false)` çağrısı üzerinden kendi kendini iptal etme (self-cancellation) hatası giderildi; bağlantı temizleme ve başlatma mantığı izole edilerek kararlı bir Bonjour LAN ↔ Cloudflare Relay geçişi ve kesintisiz yeniden bağlanma sağlandı.
  - **Klavye Kapatma Gestures (Keyboard Dismissal):** Sohbet arayüzündeki boşluğa/arka plana tıklandığında klavyeyi otomatik kapatan `onTapGesture` ve kaydırma yapıldığında klavyeyi kapatan `.scrollDismissesKeyboard(.interactively)` modifikatörleri eklenerek iOS mesajlaşma deneyimi iyileştirildi.
  - Birim testleri güncellenerek tüm SPM paket testlerinin (`swift test`) ve iOS simulator/cihaz hedefinin (`xcodebuild`) başarıyla derlendiği doğrulandı.

### 23 Mayıs 2026 - iOS Premium Kontrol & Ayarlar Entegrasyonu ve Bug Düzeltmeleri
- **Gerçekleştirilen İş:**
  - Mac ile iOS remote arasındaki durum ve ekran paylaşımı (`.hostStatus`, `.screenshotPayload`) ile kontrol akışları (`.clientConfig`, `.clientAction`) `RemoteEnvelope` ve `RemoteHost`/`RemoteSession` katmanlarında tamamlandı.
  - iOS remote uygulaması (`PixelAgentRemote`) premium bir kontrol panel dashboard'una (`TabView`) dönüştürüldü:
    - **1. Sohbet Tabı:** Mesaj geçmişi ve touch-dismiss keyboard düzeltmeleri (boşluğa tıklayınca klavyenin kapanmaması sorunu `.contentShape(Rectangle())` ve `onTapGesture` ile çözüldü).
    - **2. Subagent'lar Tabı:** Mac'te paralel çalışan subagent'ları canlı izleyen prompt, durum rozetleri, dark monospaced console çıktı kartları ve asenkron "Durdur" (Cancel) butonları eklendi.
    - **3. Mac Paneli Tabı:** CPU/RAM kullanım dairesel Gauge'ları, aktif pencere adı rozeti, arka uç (CLIKind) & model dinamik picker'ları, Plan Modu switch'i ve pinch-to-zoom (ZoomableImageView) destekli canlı Mac ekran görüntüsü alma paneli entegre edildi.
  - **Derleme ve Test Düzeltmeleri:**
    - Mach task memory sorgusunda `mach_task_self()` makrosunun Swift 6 altındaki uyumsuzluğu `mach_task_self_` global değişkenine geçilerek giderildi.
    - `ScreenshotCapture` ve `capture` metodları `PixelMacApp` tarafından erişilebilmesi için `public` yapıldı.
    - Swift 6 derleyicisinin karmaşık `Codable`/`Equatable` struct'larda (sözlük/dizi içeren) ürettiği synthesized equatable kod optimizasyon hatası (segfault/instruction trap) `EnvelopePayload` ve `RemoteEnvelope` için manuel `Equatable` (`==`) implementasyonu yazılarak ve test assertions'ları property-level karşılaştırmaya çekilerek tamamen çözüldü.
    - Tüm birim testlerinin (`swift test`) ve iOS remote hedefinin (`xcodebuild`) başarıyla derlendiği ve sıfır hata ile tamamlandığı doğrulandı.

---

## 2. Aktif Durum ve Proje Yapısı

### Modül Dağılımı ve Görevleri
1. **PixelCore (v0.0.0):** 
   - `MessageRole` (`system`, `user`, `assistant`) ve `Message` veri modelleri.
   - `StreamDelta` enum'ı (`textChunk`, `done`).
   - `ChatOptions` (planMode bayrağı) ve `AgentContext` (TaskLocal `current` agent/subagent ID takibi).
   - `ChatBackend` protokol tanımı.
   - `ToolArbiter`: Paylaşılan fiziksel kaynakları (pointer, screen, clipboard, mic, speaker, fileWrite) deadlock-free kilitlemek için FIFO sıralı actor.
2. **PixelRemote (v0.2.0):** 
   - `RemoteEnvelope` ve `EnvelopePayload`: Mac ↔ iOS arası yapısal mesaj paketleri.
   - `PairingCode`: 6 haneli Base32/Cihaz eşleştirme kod üretici ve doğrulayıcı.
   - `EnvelopeSigner`: ed25519 (CryptoKit) imzalama ve doğrulama.
   - `KeyStore`: Keychain (`KeychainKeyStore`) veya Bellek-içi (`InMemoryKeyStore`) anahtar saklama.
   - `RelayClient` ve `RelayTransport`: Cloudflare Worker WebSocket relay adaptörü.
   - `RemoteHost`: Mac tarafındaki eşleşme ve bağlantı yöneticisi class'ı.
3. **PixelLAN (v0.2.9):** 
   - Bonjour advertise/browse servisleri (`LANService` ve `LANClient`).
   - `LANFraming`: Satır sonu (`\n`) ayrılmış JSON paket framing.
   - `FallbackTransport`: sequential failover transport composite.
   - `MergeTransport`: Paralel Bonjour LAN + Cloudflare relay transport birleştirici (broadcast / duplicate yutucu).
4. **PixelBackends (v0.0.0):** 
   - `CLIDetector`: claude, codex, gemini binary yollarını bulur.
   - `EnvironmentBuilder`: Launchpad/Finder context'indeki minimal PATH sorununu çözen augment metotları ve dedicated App Support workspacecwd çözümü.
   - `CLIProcessRunner`: Subprocess'i asenkron satır satır okuyan wrapper.
   - `ModelCatalog`: Bilinen LLM model listesi (Claude: Opus/Sonnet/Haiku; Codex: GPT-5/5.5/o1/o3; Gemini: 3.5 Flash/3.1 Pro/2.5/2.0/1.5).
   - `CLIBackend`: LLM CLI araçlarını (claude, codex, gemini) yürüten ve çıktılarını `StreamJSONParser`/`CodexJSONParser` veya text line modunda parse edip `StreamDelta`'ya dönüştüren ana chat backend implementasyonu.
5. **PixelTools (v0.1.0):** 
   - `SoundEffect`: Basso, Glass, Tink seslerini play eder.
   - `DockBadge`: Dock badge etiketini set/clear eder.
   - `SystemNotifications`: Bundled .app context'indeyken UserNotifications post eder.
6. **PixelMascot (v0.1.0):** 
   - `MascotState` (`idle`, `thinking`, `speaking`, `error`).
   - `MascotFrame` (ASCII pixel art matrisi) ve `MascotView` (Canvas ile pixel art animasyon render view'u).
7. **PixelMemory (v0.1.0):** 
   - `ConversationStore`: `.jsonl` (JSON Lines) formatında append-only mesaj deposu. Yeni konuşmada eskileri tarih damgasıyla archive altına taşır.
8. **PixelSubagent (v0.2.24):** 
   - `SubagentResult`: Çalışma sonucunu (`completed`, `budgetExceeded`, `cancelled`, `failed`) yönetir.
   - `Budget`: maxDuration (süre) ve maxOutputBytes (byte) limit ayarları.
   - `SubagentRunner`: withTaskGroup kullanarak worker ile watchdog'u yarıştırarak subagent çalıştıran asenkron runner.
9. **PixelComputerUse (v0.2.23):** 
   - AX-first hibrit desktop kontrol katmanı.
   - `ui_query`, `ui_click`, `ui_type`, `ui_screenshot` (Set-of-Mark ve Window Content Crop destekli), `ui_resolve` implementasyonları.
   - `AXBridge` (C AX API sarmalayıcı), `PointerControl` (CGEvent enjektör), `ScreenshotCapture` (ScreenCaptureKit).
10. **PixelMCPServer (v0.2.24):** 
    - Model Context Protocol (initialize, tools/list, tools/call) JSON-RPC handler'ları.
    - Built-in araçlar (clipboard, time, active app, LAN IP) ve macOS bridge socket arayüzü.
11. **PixelMacApp (Executable):** 
    - SwiftUI tabanlı masaüstü chat arayüzü (Tek/Çift sütun).
    - `ControlSocketServer`: Unix domain socket üzerinden `pixel-mcp-server` isteklerini alan ve `SubagentManager` + `PixelComputerUse` facade'ına dağıtan bridge.
12. **pixel-mcp-server (Executable):** 
    - MCPServer stdio pipe executable'ı.

---

## 3. Teknik Kararlar

- **SPM Monorepo Yapısı:** SPM package yapısıyla modüller izole edilmiş, compile-time bağımlılık döngüleri kesin olarak engellenmiştir (ADR-0001).
- **Subprocess LLM İletişimi:** LLM modelleri API yerine doğrudan yerel CLI subprocess wrapper'ları (`claude`, `codex`, `gemini`) çalıştırılarak çağrılır.
- **Append-Only JSONL Depolama:** Veri tabanı yerine taşınabilirliği ve basitliği artırmak için satır tabanlı JSON Lines dosyaları tercih edilmiştir.
- **Ed25519 İmzalı Remote Kanal:** Mac ile iOS remote arasındaki relay kanalı compromise olsa bile MITM engellenmesi adına her envelope ed25519 ile imzalanır.
- **ToolArbiter:** Paralel çalışan subagent'ların veya dual-agent yapısının aynı anda ekran, klavye, mouse veya clipboard'a erişimini FIFO sırasıyla serialize etmek için global mutex actor tasarımı kullanılmıştır.
- **Set-of-Mark (SoM) & Window Crop:** `ui_screenshot` sırasında vision model'lerin daha kararlı çalışması için element bounding box'larını numaralandırarak çizme (SoM) ve pencerelerin titlebar'larını kırparak (Window Crop) sadece içerik alanını vision model'e gönderme kararı alınmıştır.
- **Plan Modu Koruması (`PIXEL_PLAN_MODE=1`):** Plan modunda destructive tool'ların (`ui_click`, `ui_type`) çalıştırılması MCP server seviyesinde engellenmiştir.

---

## 4. İptal Edilen Özellikler ve Nedenleri
*(Şu an itibariyle iptal edilmiş resmi bir özellik veya karar bulunmamaktadır.)*

---

## 5. Sonraki Adımlar

1. **Dual Mode / Remote Entegrasyonu:** iOS remote forward akışının çift sütun (dual mode) için uyumluluk geliştirmeleri.
2. **Yerel Tool Dispatcher Zinciri:** planned durumundaki dahili `ToolDispatcher` ve `ToolArbiter` entegrasyonunun v0.3+ kapsamında tamamlanması.
3. **Fuzzy/Semantic Query Geliştirmeleri:** UI aramalarında tam ve regex dışındaki fuzzy/semantic arama yeteneklerinin zenginleştirilmesi.
