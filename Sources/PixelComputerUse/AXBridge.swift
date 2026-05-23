import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(AppKit)
import AppKit
#endif

/// `ApplicationServices` AX C API'sini Swift-friendly Sendable arayüze sarar.
///
/// `AXUIElement` CFType — Sendable değil. Bu actor onu **içinde** tutar; dışarıya
/// yalnızca `UIElement` value-type snapshot'ları döner. Traversal/match mantığı
/// da actor içinde — AXUIElement aktöür sınırını ihlal etmez.
///
/// Tüm AX `AXError` non-success durumları `ComputerUseError.axCallFailed`'e
/// dönüştürülür.
actor AXBridge {

    // MARK: - Public actor-isolated API

    /// `UIQuery`'e uyan tüm element'leri döndürür. Tüm AX işlemleri actor içinde
    /// gerçekleşir; dönen `[UIElement]` Sendable.
    ///
    /// **Faz 3a chained query:** `query.within` set ise her aday element için
    /// `kAXParentAttribute` üzerinden ancestor chain walk yapılır; her constraint
    /// için en az bir ancestor'ın uyması zorunlu (AND).
    func find(_ query: UIQuery) throws -> [UIElement] {
        #if canImport(ApplicationServices) && canImport(AppKit)
        let deadline = Date().addingTimeInterval(query.timeout)

        // Root: bundleID set ise hedef app; yoksa frontmost
        let root: AXUIElement
        let bundleID: String?
        if let bid = query.bundleID {
            guard let app = applicationElement(bundleID: bid) else {
                return []  // app çalışmıyor — noMatch yerine boş array
            }
            root = app
            bundleID = bid
        } else {
            guard let front = frontmostApplicationElement() else {
                return []
            }
            root = front.element
            bundleID = front.bundleID
        }

        // BFS traversal
        var queue: [(element: AXUIElement, depth: Int, path: [String])] = [(root, 0, [])]
        var matches: [UIElement] = []

        while !queue.isEmpty {
            if Date() > deadline {
                throw ComputerUseError.timedOut(after: query.timeout)
            }

            let (element, depth, path) = queue.removeFirst()
            let snapshot = makeSnapshot(element, bundleID: bundleID, path: path)

            if Self.matches(snapshot, query: query) {
                // Chained query — ancestor constraints
                if query.within.isEmpty || checkAncestorConstraints(element, query: query, bundleID: bundleID) {
                    matches.append(snapshot)
                }
            }

            if depth < query.maxDepth {
                for child in children(element) {
                    queue.append((child, depth + 1, snapshot.path))
                }
            }
        }

        return matches
        #else
        throw ComputerUseError.unsupported(reason: "AX yalnızca macOS'ta desteklenir")
        #endif
    }

    #if canImport(ApplicationServices) && canImport(AppKit)

    // MARK: - Roots

    private func applicationElement(bundleID: String) -> AXUIElement? {
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
        guard let pid = running?.processIdentifier else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private func frontmostApplicationElement() -> (element: AXUIElement, bundleID: String?)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return (element, app.bundleIdentifier)
    }

    // MARK: - Attribute readers

    private func string(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard err == .success, let str = value as? String else { return nil }
        return str
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    /// **Faz 3a:** `kAXParentAttribute` üzerinden tek seviye yukarı. Application
    /// element'i için nil döner (root).
    private func parent(_ element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard err == .success, let val = value else { return nil }
        // AXUIElementGetTypeID kontrolü gereksiz — AX parent her zaman AXUIElement.
        return (val as! AXUIElement)
    }

    /// **Faz 3a chained query helper:** `element`'in ancestor zincirini gez,
    /// her constraint için en az bir ancestor'ın eşleştiğini doğrula. Maksimum
    /// 32 seviye walk (loop guard). Constraint listesi boş ise true döner.
    private func checkAncestorConstraints(_ element: AXUIElement, query: UIQuery, bundleID: String?) -> Bool {
        guard !query.within.isEmpty else { return true }

        // Tüm ancestor snapshot'larını topla (root'a kadar veya 32. seviyeye).
        var ancestors: [UIElement] = []
        var current: AXUIElement? = parent(element)
        var safety = 32
        while let p = current, safety > 0 {
            ancestors.append(makeSnapshot(p, bundleID: bundleID, path: []))
            current = parent(p)
            safety -= 1
        }

        // Her constraint için ancestors'ta uyan en az bir element olmalı.
        // `containsText` ve nested `within` ancestors içinde de geçerli (recursive).
        for constraint in query.within {
            let hit = ancestors.contains { Self.matches($0, query: constraint) }
            if !hit { return false }
        }
        return true
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal)
        let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal)
        guard posErr == .success, sizeErr == .success,
              let posV = posVal, let sizeV = sizeVal else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posV as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Snapshot

    private func makeSnapshot(
        _ element: AXUIElement,
        bundleID: String?,
        path: [String]
    ) -> UIElement {
        let role = string(element, kAXRoleAttribute as String) ?? "AXUnknown"
        let title = string(element, kAXTitleAttribute as String)
        let label = string(element, kAXDescriptionAttribute as String)
            ?? string(element, kAXLabelValueAttribute as String)
        let identifier = string(element, kAXIdentifierAttribute as String)
        let frameBox = frame(element).map(CGRectBox.init) ?? .zero
        let fullPath = path + [role]
        let opaqueID = OpaqueID.encode(
            bundleID: bundleID,
            path: fullPath,
            discriminators: path.map { _ in nil } + [identifier ?? title]
        )

        return UIElement(
            role: role,
            title: title,
            label: label,
            identifier: identifier,
            frame: frameBox,
            bundleID: bundleID,
            path: fullPath,
            opaqueID: opaqueID
        )
    }

    // MARK: - Resolve (Faz 3a)

    /// **Faz 3a:** Daha önce alınmış bir `opaqueID`'den canlı element snapshot'ı
    /// üretir. Cache yok — path'i AX tree'de tekrar yürür (deterministic + stale-
    /// safe). Element artık yoksa `nil` döner.
    func resolve(opaqueID: String) throws -> UIElement? {
        #if canImport(ApplicationServices) && canImport(AppKit)
        guard let parsed = OpaqueID.decode(opaqueID) else {
            throw ComputerUseError.invalidOpaqueID(raw: opaqueID)
        }

        // Root: bundleID set ise hedef app; yoksa frontmost
        let root: AXUIElement
        let bundleID: String?
        if let bid = parsed.bundleID {
            guard let app = applicationElement(bundleID: bid) else { return nil }
            root = app
            bundleID = bid
        } else {
            guard let front = frontmostApplicationElement() else { return nil }
            root = front.element
            bundleID = front.bundleID
        }

        // İlk path component application role'ü (AXApplication) genellikle —
        // root'tan başlayıp her seviye için role+discriminator eşleşmesini ara.
        var current: AXUIElement = root
        var walkedPath: [String] = []
        for (i, step) in parsed.path.enumerated() {
            // İlk seviye = root'un kendisi (application), descend etme.
            if i == 0 {
                walkedPath.append(step.role)
                continue
            }
            guard let next = findChild(of: current, matching: step) else {
                return nil
            }
            current = next
            walkedPath.append(step.role)
        }

        return makeSnapshot(current, bundleID: bundleID, path: Array(walkedPath.dropLast()))
        #else
        throw ComputerUseError.unsupported(reason: "AX yalnızca macOS'ta desteklenir")
        #endif
    }

    /// `step` (role + discriminator) ile uyan ilk çocuk.
    private func findChild(of parent: AXUIElement, matching step: OpaqueID.Step) -> AXUIElement? {
        for child in children(parent) {
            let role = string(child, kAXRoleAttribute as String) ?? "AXUnknown"
            guard role == step.role else { continue }
            if let disc = step.discriminator {
                let id = string(child, kAXIdentifierAttribute as String)
                let title = string(child, kAXTitleAttribute as String)
                if id == disc || title == disc {
                    return child
                }
            } else {
                return child  // discriminator yoksa role yeter
            }
        }
        return nil
    }

    #endif

    // MARK: - Match logic (Sendable — value-type input)

    /// `UIElement`'in `UIQuery`'e uyup uymadığını döndürür. AX bağımsız — pure
    /// fonksiyon, value-type girdiler, test'te doğrudan çağrılabilir.
    ///
    /// **Match precedence:**
    /// 1. `identifier` set ise → sadece identifier'a bakılır (kararlı handle).
    /// 2. Aksi halde `role` + `title` + `label` + `containsText` AND'lenir.
    /// 3. `within` constraint'leri AX layer'da (AXBridge.checkAncestorConstraints)
    ///    ayrıca check edilir — bu fonksiyon ancestor walk yapmaz.
    static func matches(_ element: UIElement, query: UIQuery) -> Bool {
        // identifier > diğer alanlar — varsa exact match yeter.
        if let id = query.identifier {
            return element.identifier == id
        }

        // Role
        if let role = query.role, role != .any, element.role != role.rawValue {
            return false
        }

        // Title
        if let title = query.title {
            guard let elementTitle = element.title else { return false }
            if !matchString(elementTitle, against: title, mode: query.matchMode) {
                return false
            }
        }

        // Label
        if let label = query.label {
            guard let elementLabel = element.label else { return false }
            if !matchString(elementLabel, against: label, mode: query.matchMode) {
                return false
            }
        }

        // **Faz 3a:** containsText — title OR label substring (case-insensitive).
        // matchMode'a tabi değil; her zaman .caseInsensitive contains.
        if let needle = query.containsText {
            let titleHit = element.title?.range(of: needle, options: .caseInsensitive) != nil
            let labelHit = element.label?.range(of: needle, options: .caseInsensitive) != nil
            if !titleHit && !labelHit { return false }
        }

        return true
    }

    private static func matchString(_ haystack: String, against needle: String, mode: MatchMode) -> Bool {
        switch mode {
        case .exact:
            return haystack == needle
        case .fuzzy:
            // `localizedCaseInsensitiveContains` `.current` locale kullanır —
            // Türkçe sistem'de "I"/"i" eşleşmez ("ı"/"İ" çiftleri). Locale-
            // independent Unicode default case-folding için `range(of:options:)`
            // kullanılır.
            return haystack.range(of: needle, options: .caseInsensitive) != nil
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: needle, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(haystack.startIndex..., in: haystack)
            return regex.firstMatch(in: haystack, options: [], range: range) != nil
        }
    }
}
