# Polish Roadmap — "Demo-Ready" Milestone

> **Mission.** Mac + iOS pixel-agent'ı sürekli daha yetenekli ve "demo-ready" hale getir. Marketing katmanı (README/landing/brew tap/OG image) Faz A'da kuruldu — şu an ürün polish'i öne çıkıyor. Hedef sabit: **her oturum projeyi bir derece daha satılabilir + bir derece daha kullanışlı yapmak**.
>
> **Why this document.** "Binlerce yıldız" iddiası ile mevcut demo-readiness seviyesi arasındaki gap'i objektif tut. Plan agent'ın 23 May 2026'da yaptığı source-level audit (39 spesifik gap) burada listelenir; her item ROI'lendirilmiş, sprint atanmış, durum izlenir.

## Demo-Readiness tanımı

pixel-agent **demo-ready** sayılır eğer:

1. Yeni bir kullanıcı uygulamayı kurduğunda **empty state'te ne yapacağını biliyor** (sample prompt chip'leri).
2. Streaming sırasında **typing indicator** ve markdown render var (kod blokları + copy button).
3. **Plan Mode aktif iken hangi tool'lar bloklandı** kullanıcıya görsel olarak belli.
4. **Keyboard shortcuts** çalışıyor (⌘N yeni sohbet, mod geçiş, vs.).
5. **Subagent dispatch sonucu** ana chat akışına entegre (sadece panel kartında kalmıyor).
6. **iOS dashboard'dan yapılan değişiklikler** Mac'te toast/banner ile feedback veriyor.
7. **CLI auth hatası** durumunda actionable retry/login butonu çıkıyor.
8. **MCP entegrasyon helper** (Claude Code / Cursor / Codex için JSON snippet + bin path + copy button) içinde.
9. **Hata durumlarında** "Tekrar dene" butonu (sessiz fail yok).
10. **Pairing status** günlük kullanımda görünür (sadece sheet açıkken değil).

Bu 10 madde **Sprint 1**'in kapsamı. Tamamlandığında "demo-ready" milestone'u açılır.

## Gap Kategorileri (Plan agent audit, 23 May 2026)

39 madde, 3 kategori. Her madde için dosya referansı, mevcut durum, hedef hal Plan agent çıktısında — özet aşağıda.

### A. UX/Görsel Polish (13 madde)
Markdown rendering, typing indicator, empty state, mascot polish, focus halos, error retry, asymmetric bubble, toolbar gruplama, scroll spring, reconnect countdown — feature çalışıyor ama "hızlı prototip" hissi veriyor.

### B. Eksik Temel Feature (14 madde)
Settings scene yok, conversation history sidebar/search/export yok, drag-drop file context yok, keyboard shortcuts (.commands) yok, per-message actions (copy/regenerate/edit) yok, iOS settings tab yok, MCP setup UI yok, conversation rename/tag yok, paired-devices yönetimi yok.

### C. End-to-End Workflow (12 madde)
Subagent → chat entegrasyonu yok, screenshot chat'e düşmüyor, Set-of-Mark numbered overlay UI'da görünmüyor, Plan Mode tool list panel yok, iOS→Mac config-change toast yok, connection-lost pulse yok, daimi pairing pill yok, MCP entegrasyon helper yok, actionable auth error yok, subagent cap reached transient banner yok, screenshot → "soruna sor" akışı yok, tool-call event'leri envelope'ta yok.

## ROI Tablosu (top-16)

ROI = (Impact × Demo visibility) / Effort. Effort: S=1, M=2, L=3.

| # | Item | Effort | Impact (1-5) | Demo (1-5) | ROI | Sprint |
|---|---|---|---|---|---|---|
| **C8** | MCP entegrasyon helper (JSON + bin + copy) | S | 4 | 5 | **20** | S1 |
| **C4** | Plan Mode tool list panel | S | 4 | 4 | **16** | S1 |
| **A3** | Empty state + sample prompt chips | S | 3 | 5 | **15** | S1 |
| **A1** | Markdown rendering + code block copy | M | 5 | 5 | **12.5** | S1 |
| **B5** | Keyboard shortcuts (.commands) | S | 3 | 4 | **12** | S1 |
| **A2** | Typing indicator (3-dot pulse) | S | 3 | 4 | **12** | S1 |
| **C5** | iOS→Mac config-change toast | S | 3 | 4 | **12** | S1 |
| **A7** | Inline retry banner on error | S | 4 | 3 | **12** | S1 |
| **C9** | Actionable auth error (login deep-link) | S | 4 | 3 | **12** | S1 |
| **C1** | Subagent sonucu chat'e akıt | M | 5 | 4 | **10** | S1 |
| **C7** | Daimi connection pill | S | 3 | 3 | **9** | S2 |
| **B6** | Quick-actions menu (copy last) | S | 3 | 3 | **9** | S2 |
| **B3** | Conversation export (markdown/JSON) | S | 3 | 3 | **9** | S2 |
| **A8** | Composer focus halo + haptic | S | 2 | 4 | **8** | S2 |
| **C10** | Subagent cap-reached banner | S | 2 | 3 | **6** | S2 |
| **C2/C3** | Screenshot in-chat + SoM overlay UI | L | 4 | 5 | **6.7** | S2 |
| **B2** | Conversation history sidebar | L | 5 | 4 | **6.7** | S3 |
| **C12** | Tool-call envelope events (iOS) | M | 3 | 4 | **6** | S3 |
| **B1** | Settings scene (tab'lı) | L | 4 | 3 | **4** | S3 |
| **B8** | iOS settings tab | M | 3 | 3 | **4.5** | S3 |

## Sprint 1 — "Demo-Ready Foundation" (1-2 hafta, 10 item)

| Status | # | Item |
|---|---|---|
| ✅ | C8 | MCP entegrasyon helper |
| ✅ | C4 | Plan Mode tool list panel |
| ✅ | A3 | Empty state + sample prompts |
| ✅ | A1 | Markdown + code block copy |
| ✅ | B5 | Keyboard shortcuts |
| ✅ | A2 | Typing indicator |
| ✅ | C5 | iOS→Mac config toast |
| ✅ | A7 | Inline retry banner |
| ⏳ | C9 | Actionable auth error |
| ⏳ | C1 | Subagent → chat akışı |

Bitince **demo-ready milestone açılır** + demo GIF kaydı + Show HN hazırlığı başlar.

## Sprint 2 — "Power-User Touches" (Sprint 1 sonrası)

C7, B6, B3, A8, C10, C2/C3 + sprint 1 follow-up'lar.

## Sprint 3 — "Persistent State + iOS Parity" (Sprint 2 sonrası)

B2 (conversation history sidebar — büyük), B1 (Settings scene), B8 (iOS settings tab), C12 (tool-call envelope events).

## Demo Senaryosu (Sprint 1 sonrası)

> Kullanıcı pixel-agent'ı açar. `⌘N` ile yeni sohbet. **Empty state'te 4 prompt chip görür** ("Bu klasörü özetle" / "Code review yap" / "Plan modunda araştırma" / "Subagent ile karşılaştır"). "Plan modunda araştırma" chip'ine tıklar. **Plan toggle otomatik açılır**, sağ tarafta **read-only tool list paneli** belirir (Read ✓ / Glob ✓ / Edit ✗ / Bash ✗). Send'e basar. **Typing indicator 3 dot pulse** ile başlar. Claude yanıtı **markdown formatında** stream eder; kod bloğunun sağ üstünde **"Kopyala" butonu**. Kullanıcı subagent panelinden Gemini'ye "PDF özetle" dispatch eder. Subagent panelde çalışırken, **bittiğinde ana chat'e `[subagent gemini] sonuç:` mesajı düşer**. Bu sırada telefonundan iOS dashboard ile backend'i Codex'e değiştirir; **Mac üstte "📱 Telefon: Codex'e geçildi" toast** belirir. Authentication exparit olursa **"Authenticate Claude" butonu**na basıp `claude login` Terminal'i açılır. Sohbet bitince "About" → **"MCP Entegrasyonu"** menüsünden JSON snippet'i kopyalayıp Claude Code config'ine yapıştırır.

## Tracking

Bu dosya kalıcı kayıt; her sprint sonu güncellenir (status değişimleri, yeni eklenen gap'ler, kaldırılan/birleşen item'lar). Plan agent yeniden audit çağrılırsa sonuç bu dosyaya merge edilir.

Audit kaynağı: Plan agent çağrısı, oturum 23 May 2026 (memory: pixel_agent_v3.md madde 34 sonrası).
