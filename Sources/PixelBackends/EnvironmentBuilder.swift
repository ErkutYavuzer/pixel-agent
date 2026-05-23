import Foundation

/// CLI subprocess'lerin Launchpad/Finder'dan açıldığında düzgün çalışması için
/// PATH augment helper'ı.
///
/// **Sorun:** PixelAgent.app Launchpad'den açıldığında parent shell config (`.zshrc`,
/// `.bashrc`) okunmaz → `ProcessInfo.processInfo.environment["PATH"]` minimal gelir
/// (`/usr/bin:/bin:/usr/sbin:/sbin`). Gemini CLI'ın shebang'ı `#!/usr/bin/env node`,
/// `env` node'u PATH'te aradığı için bulamayıp **exit code 127** (`No such file or
/// directory`) döner. Aynı sorun nvm/volta ile yüklenmiş Claude CLI için de geçerli.
///
/// **Çözüm:** Subprocess başlatmadan önce PATH'e bilinen node/CLI lokasyonlarını
/// prepend et. Mevcut PATH değeri (varsa) korunur, prepend edilen dizinler önce
/// gelir.
public enum EnvironmentBuilder {

    /// Parent env'i kopyalar ve PATH'e bilinen CLI dizinlerini prepend eder.
    /// Subprocess başlatılırken `process.environment`'a verilir.
    public static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH(currentPATH: env["PATH"], home: env["HOME"] ?? NSHomeDirectory())
        return env
    }

    /// Saf fonksiyon — `currentPATH` üzerine bilinen dizinleri prepend eder, dup
    /// entry'leri tekilleştirir, sıralamayı korur. Test'lerden direkt çağrılır.
    public static func augmentedPATH(currentPATH: String?, home: String) -> String {
        let prepend = knownBinDirectories(home: home)
        let existing = (currentPATH ?? "").split(separator: ":").map(String.init)

        var seen = Set<String>()
        var ordered: [String] = []
        for dir in prepend + existing {
            if !dir.isEmpty, !seen.contains(dir) {
                seen.insert(dir)
                ordered.append(dir)
            }
        }
        return ordered.joined(separator: ":")
    }

    /// Bilinen CLI dizinleri — node, claude, codex, gemini bunlardan birinde olur.
    /// Sıra önemli: daha güvenilir / sık kullanılanlar önce.
    static func knownBinDirectories(home: String) -> [String] {
        var dirs: [String] = [
            "/opt/homebrew/bin",       // Apple Silicon Homebrew
            "/usr/local/bin",          // Intel Homebrew / manuel install
            "\(home)/.local/bin",      // pipx, user-level
            "\(home)/bin",             // manuel
            "\(home)/.volta/bin",      // Volta
            "\(home)/.asdf/shims",     // asdf
        ]
        // nvm — `~/.nvm/versions/node/v20.10.0/bin` gibi versiyon klasörü.
        // En son yüklenen sürümü (alfabetik son) seç; nvm `use` ile değiştirilebilir
        // ama Launchpad context'inde shell hook'u yok, bu basit yaklaşım yeterli.
        dirs.append(contentsOf: latestNVMNodeBinDirectories(home: home))
        return dirs
    }

    /// `~/.nvm/versions/node/` altındaki tüm versiyon `bin/` dizinlerini döndürür.
    /// En son yüklenenden (alfabetik desc) eskiye sıralı — multi-version setup'ta
    /// en güncel kazansın.
    static func latestNVMNodeBinDirectories(home: String) -> [String] {
        let base = "\(home)/.nvm/versions/node"
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue,
              let contents = try? fm.contentsOfDirectory(atPath: base) else {
            return []
        }
        return contents
            .sorted(by: >)  // v20.10.0 > v18.18.0
            .map { "\(base)/\($0)/bin" }
            .filter {
                var d: ObjCBool = false
                return fm.fileExists(atPath: $0, isDirectory: &d) && d.boolValue
            }
    }
}
