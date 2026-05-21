# Security Policy

## Güvenlik açığı bildirimi

`pixel-agent` erken MVP geliştirme aşamasındadır. Güvenlik açığı bulursanız lütfen **public GitHub issue açmayın**. Bunun yerine doğrudan e-posta gönderin:

**yavuzererkut@gmail.com**

Mesajınızda şunları eklemeniz yararlı olur:
- Açığın açıklaması
- Reproduction adımları
- Etki / risk değerlendirmesi
- Önerilen çözüm (varsa)

Mümkün olan en kısa sürede dönüş yapılacaktır (best-effort, hobi/portfolio projesi).

## Desteklenen sürümler

Bu proje [Semantic Versioning](https://semver.org/) kurallarına uyar. Yalnızca en son minor sürüm güvenlik düzeltmesi alır.

| Sürüm | Destek |
|---|---|
| 0.x (pre-release) | Aktif |
| pixel-agent2 (önceki sürüm) | ❌ Destek yok — bu repoya geçildi |

## Gizli veri uyarısı

Bu proje LLM API'leri ile çalışır. Aşağıdaki tipte verilerin **commit edilmemesi** kritik:

- API anahtarları (Anthropic, OpenAI, Gemini, vb.)
- OAuth token'ları
- Pairing token'ları, ed25519 private key'leri
- Kullanıcı konuşma log'ları (`conversation.jsonl`)

`.gitignore` bu dosya tiplerini kapsar. Pre-commit hook ek bir güvenlik katmanı sunar.
