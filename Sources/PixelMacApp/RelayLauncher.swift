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
    /// **Sprint 48 (v0.2.76):** İlk launch'ta `npm install` çalışıyor mu?
    /// Settings UI ProgressView için. ~30sn'lik network operation.
    @Published private(set) var isInstallingDependencies: Bool = false

    private var process: Process?
    private var restartCount: Int = 0
    private let maxRestarts: Int = 3
    private var watchdogTask: Task<Void, Never>?

    /// **Sprint 47:** Production'da `.app/Contents/Resources/relay/`, dev
    /// build'de repo'nun `relay/` dizini. **Sprint 48 (v0.2.76):** writable
    /// kopya kaynağı.
    private let relayDirectory: URL?

    init(relayDirectory: URL? = nil) {
        self.relayDirectory = relayDirectory ?? Self.defaultRelayDirectory()
    }

    /// **Sprint 48 (v0.2.76):** Bundle Resources/relay (read-only) yerine
    /// kullanılan writable kopya. `~/Library/Application Support/PixelAgent/
    /// relay/`. node_modules burada install edilir.
    static var writableRelayDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("pixel-agent", isDirectory: true)
            .appendingPathComponent("relay", isDirectory: true)
    }

    /// **Sprint 47:** UserDefaults nil-safe.
    /// **Sprint 49 (v0.2.77):** Default **false** — production Cloudflare URL
    /// artık var (`RelayURLResolver.productionURL`), lokal wrangler subprocess
    /// opsiyonel. Kullanıcı offline/dev için manuel açabilir. Explicit set'li
    /// kullanıcılar (Sprint 47-48'de true/false yapanlar) etkilenmez.
    static func isAutoStartEnabled(defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: autoStartEnabledDefaultsKey) as? Bool {
            return stored
        }
        return false  // Sprint 49: default OFF (production URL handles iOS connection)
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

    /// **Sprint 47-48:** Wrangler subprocess başlat. Idempotent.
    /// **Sprint 48:** Bundle Resources/relay → writable Application Support
    /// copy + lazy npm install + wrangler dev chain.
    func start() {
        guard Self.isAutoStartEnabled() else {
            lastError = nil
            return
        }
        guard !isRunning, !isInstallingDependencies else { return }
        guard let sourceDir = relayDirectory else {
            lastError = "relay/ kaynak dizini bulunamadı (bundle Resources veya dev repo)"
            return
        }

        let npxPath = locateNpx()
        guard let npxPath else {
            lastError = "Node.js bulunamadı. `brew install node` ile kurun veya production Cloudflare URL kullanın."
            return
        }

        // Sprint 48 (v0.2.76): Writable copy + lazy npm install
        let runtimeDir = Self.writableRelayDirectory
        do {
            try Self.ensureWritableCopy(from: sourceDir, to: runtimeDir)
        } catch {
            lastError = "Relay kopyalanamadı: \(error.localizedDescription)"
            return
        }

        let nodeModulesPath = runtimeDir.appendingPathComponent("node_modules")
        if !FileManager.default.fileExists(atPath: nodeModulesPath.path) {
            // Lazy npm install — async, sonra wrangler launch
            Task { [weak self] in
                guard let self else { return }
                await self.runNpmInstall(in: runtimeDir, npxPath: npxPath)
                // npm install bittiyse ve hata yoksa wrangler launch
                let installError = await self.lastError
                if installError == nil {
                    await MainActor.run { self.launchWranglerProcess(at: runtimeDir, npxPath: npxPath) }
                }
            }
            return
        }

        launchWranglerProcess(at: runtimeDir, npxPath: npxPath)
    }

    /// **Sprint 48 (v0.2.76):** Wrangler subprocess'i `runtimeDir`'de spawn et.
    /// `start()` ya doğrudan ya da `npm install` bittikten sonra çağırır.
    private func launchWranglerProcess(at runtimeDir: URL, npxPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: npxPath)
        proc.arguments = ["wrangler", "dev", "--ip", "0.0.0.0", "--port", "8787"]
        proc.currentDirectoryURL = runtimeDir
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

    // MARK: - Sprint 48 (v0.2.76) — Writable copy + npm install

    /// **Sprint 48:** Bundle Resources/relay → Application Support/relay
    /// kopyala (idempotent). Kaynak değişmişse (package-lock fark) destinasyonu
    /// güncelle; node_modules dokunulmaz (separate state).
    static func ensureWritableCopy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: destination.path) {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
            return
        }

        // package-lock.json fark var mı? Yoksa kopya gerek değil.
        let srcLock = source.appendingPathComponent("package-lock.json")
        let dstLock = destination.appendingPathComponent("package-lock.json")
        if let srcData = try? Data(contentsOf: srcLock),
           let dstData = try? Data(contentsOf: dstLock),
           srcData == dstData {
            return
        }

        // Diff var → src + config dosyalarını üzerine kopyala (node_modules
        // dokunulmaz).
        for item in ["wrangler.toml", "package.json", "package-lock.json", "src", "README.md"] {
            let srcURL = source.appendingPathComponent(item)
            let dstURL = destination.appendingPathComponent(item)
            guard fm.fileExists(atPath: srcURL.path) else { continue }
            if fm.fileExists(atPath: dstURL.path) {
                try fm.removeItem(at: dstURL)
            }
            try fm.copyItem(at: srcURL, to: dstURL)
        }
    }

    /// **Sprint 48:** `npm install` çalıştır. UI binding için
    /// `isInstallingDependencies` true. ~30sn network operation. Hata
    /// olursa lastError'a yansıt.
    private func runNpmInstall(in directory: URL, npxPath: String) async {
        await MainActor.run { self.isInstallingDependencies = true }
        defer {
            Task { @MainActor in self.isInstallingDependencies = false }
        }

        // npm path — npx'in yanında durur (Homebrew layout)
        let npmPath = npxPath.replacingOccurrences(of: "/npx", with: "/npm")
        guard FileManager.default.fileExists(atPath: npmPath) else {
            await MainActor.run {
                self.lastError = "npm bulunamadı (\(npmPath)). `brew install node` ile kurun."
            }
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: npmPath)
        proc.arguments = ["install", "--no-audit", "--no-fund", "--prefer-offline"]
        proc.currentDirectoryURL = directory
        proc.environment = EnvironmentBuilder.augmentedEnvironment()

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
        } catch {
            await MainActor.run {
                self.lastError = "npm install başlatılamadı: \(error.localizedDescription)"
            }
            return
        }

        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            await MainActor.run {
                self.lastError = "npm install başarısız (exit \(proc.terminationStatus)). İnternet bağlantınızı kontrol edin veya production Cloudflare URL kullanın."
            }
        }
    }
}
