#  ``PixelCore``

pixel-agent'ın ortak protokol ve tip katmanı.

## Overview

`PixelCore`, tüm diğer pixel-agent modüllerinin paylaştığı temel tipleri içerir. Bağımlılık grafiğinin en alt katmanıdır — hiçbir modüle bağımlı değildir, diğer modüller bunu import eder.

Tasarım kararları:

- **TaskLocal context propagation** — agent kimliği task ağacında yayılır (bkz. ADR-0003)
- **Protocol-driven backend abstraction** — `ChatBackend` arayüzü ile provider-agnostic dispatch (bkz. ADR-0004)
- **Codable + Sendable her yer** — Swift 6 strict concurrency uyumlu

## Topics

### Sohbet mesajları

- ``Message``
- ``MessageRole``

### Backend protokolü

- ``ChatBackend``
- ``StreamDelta``

### Agent context

- ``AgentContext``
- ``AgentID``

### Namespace

- ``PixelCore``
