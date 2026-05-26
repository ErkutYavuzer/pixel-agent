import Foundation
import PixelBackends

/// **Sprint 47 (v0.2.75):** Mac app launch'ta `npx wrangler dev` subprocess'i
/// otomatik başlatan actor. Kullanıcı manuel `cd relay && npx wrangler dev`
/// yapmak zorunda kalmaz — app ile birlikte gelir, app kapanırken kill olur.
///
/// **Lifecycle:**
/// 1. `start()` — `npx` PATH'te ara (augmentedPATH), `relay/` dizininde process spawn
/// 2. Process stderr/stdout pipe → log buffer (debug için Settings'te göster)
/// 3. App `NSApplication.willTerminateNotification` → `stop()`
/// 4. `stop()` — `process.terminate()` (SIGTERM); graceful exit
///
/// **Fallback'ler:**
/// - `npx` bulunamadı → `lastError = "Node.js kurulu değil"` (user `brew install node`)
/// - `relay/` dizini bulunamadı → `lastError = "relay/ klasörü yok"` (dev build only)
/// - Production binary'de `relay/` Resources/ altında bundled (build-app.sh'a eklenecek)
/// - Subprocess crash → 5s sonra otomatik restart (3 tekrar sonra vazgeç)
///
/// **`@MainActor` ObservableObject** — Settings UI bu state'i okur ve göster.
@MainActor
final class RelayLauncher: ObservableObject {
    /// **Sprint 47:** UserDefaults toggle — auto-start enabled mı?
    /// nil → default true. Kullanıcı production URL kullanıyorsa kapatır.
    static let autoStartEnabledDefaultsKey = "pixel.relay.autoStartEnabled"

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var didStartOnce: Bool = false

    private var process: Process?
    private var restartCount: Int = 0
    private let maxRestarts: Int = 3
    private var watchdogTask: Task<Void, Never>?

    /// **Sprint 47:** Production'da `.app/Contents/Resources/relay/`, dev
    /// build'de repo'nun `relay/` dizini.
    private let relayDirectory: URL?

    init(relayDirectory: URL? = nil) {
        self.relayDirectory = relayDirectory ?? Self.defaultRelayDirectory()
    }

    /// **Sprint 47:** UserDefaults nil-safe.
    static func isAutoStartEnabled(defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: autoStartEnabledDefaultsKey) as? Bool {
            return stored
        }
        return true  // default ON
    }

    /// **Sprint 47:** Production app bundle Resources/relay/ veya dev repo
    /// pixel-agent/relay/. nil ise launcher start() no-op.
    static func defaultRelayDirectory() -> URL? {
        // 1. App bundle Resources/relay (production)
        if let bundled = Bundle.main.url(forResource: "relay", withExtension: nil) {
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("wrangler.toml").path) {
                return bundled
            }
        }
        // 2. Dev repo path (build from source)
        let devPath = URL(fileURLWithPath: "/Users/erkut/Projects/pixel-agent/relay")
        if FileManager.default.fileExists(atPath: devPath.appendingPathComponent("wrangler.toml").path) {
            return devPath
        }
        return nil
    }

    /// **Sprint 47:** Wrangler subprocess başlat. Idempotent. UserDefaults
    /// toggle kapalıysa no-op.
    func start() {
        guard Self.isAutoStartEnabled() else {
            lastError = nil
            return
        }
        guard !isRunning else { return }
        guard let relayDir = relayDirectory else {
            lastError = "relay/ dizini bulunamadı (production bundle Resources/relay altında olmalı)"
            return
        }

        let npxPath = locateNpx()
        guard let npxPath else {
            lastError = "Node.js bulunamadı. `brew install node` ile kurun veya production Cloudflare URL kullanın."
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: npxPath)
        proc.arguments = ["wrangler", "dev", "--ip", "0.0.0.0", "--port", "8787"]
        proc.currentDirectoryURL = relayDir
        proc.environment = EnvironmentBuilder.augmentedEnvironment()

        // Pipe stderr/stdout, log'lara yansıt
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            self.process = proc
            self.isRunning = true
            self.lastError = nil
            self.didStartOnce = true

            // Watchdog: process exit'i izle, beklenmedik exit'te restart
            watchdogTask = Task { [weak self] in
                proc.waitUntilExit()
                await self?.handleProcessExit(code: proc.terminationStatus)
            }
        } catch {
            lastError = "Wrangler başlatılamadı: \(error.localizedDescription)"
            self.process = nil
            self.isRunning = false
        }
    }

    /// **Sprint 47:** Subprocess'i durdur. App quit notification handler.
    func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
            // Force-kill fallback (1s grace)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak proc] in
                if let proc, proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        process = nil
        isRunning = false
    }

    /// **Sprint 47:** Subprocess exit handler. Beklenmedik exit (manuel
    /// stop() çağrılmadan) → restart loop (max 3 kez).
    private func handleProcessExit(code: Int32) {
        guard isRunning else { return }  // stop() ile bitirildi
        isRunning = false
        if restartCount < maxRestarts {
            restartCount += 1
            lastError = "Wrangler beklenmedik kapandı (exit \(code)) — otomatik tekrar deniyor (\(restartCount)/\(maxRestarts))"
            // 5 saniye bekle + restart
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                start()
            }
        } else {
            lastError = "Wrangler \(maxRestarts) kez başarısız oldu. Settings → Bağlantı → 'Yeniden Başlat' veya manuel kontrol gerek."
        }
    }

    /// **Sprint 47:** `npx` binary'sini PATH'te ara. EnvironmentBuilder.augmentedPATH
    /// homebrew vs. paths içerir.
    private func locateNpx() -> String? {
        let candidates = [
            "/opt/homebrew/bin/npx",       // Apple Silicon Homebrew
            "/usr/local/bin/npx",          // Intel Homebrew
            "/usr/bin/npx",                // Sistem
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// **Sprint 47:** Restart counter reset (kullanıcı manuel "Yeniden Başlat"
    /// dediğinde Settings UI'dan).
    func manualRestart() {
        restartCount = 0
        stop()
        // 500ms grace + restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }
}
