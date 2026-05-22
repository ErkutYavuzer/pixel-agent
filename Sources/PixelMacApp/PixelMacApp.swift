import Darwin
import PixelBackends
import PixelCore
import PixelLAN
import PixelMemory
import PixelRemote
import PixelTools
import SwiftUI

@main
struct PixelMacApp: App {
    var body: some Scene {
        WindowGroup("pixel-agent") {
            RootView()
                .frame(minWidth: 520, minHeight: 400)
        }
    }
}

struct RootView: View {
    @State private var backends: [CLIKind: CLIBackend]
    @State private var conversationStore: ConversationStore?
    @State private var initErrorMessage: String?

    init() {
        _backends = State(initialValue: Self.resolveBackends())
        do {
            let store = try ConversationStore()
            _conversationStore = State(initialValue: store)
            _initErrorMessage = State(initialValue: nil)
        } catch {
            _conversationStore = State(initialValue: nil)
            _initErrorMessage = State(initialValue: "Mesaj deposu açılamadı: \(error.localizedDescription)")
        }
    }

    var body: some View {
        Group {
            if let errorMessage = initErrorMessage {
                ErrorView(message: errorMessage, onRetry: retryStore)
            } else if backends.isEmpty {
                ErrorView(
                    message: BackendError.noBackendAvailable.errorDescription ?? "",
                    onRetry: rescan
                )
            } else if let store = conversationStore {
                ChatHost(backends: backends, conversationStore: store)
            } else {
                ErrorView(message: "Bilinmeyen başlatma hatası", onRetry: retryStore)
            }
        }
        .task {
            _ = await SystemNotifications.requestAuthorization()
            await Self.startControlBridge()
        }
    }

    /// MCP server'ın bundle-bağımlı tool isteklerini dinleyen Unix socket
    /// sunucusunu (`ControlSocketServer`) açılışta başlatır. Hata olursa
    /// sessizce yutulur — MCP server'ın saf-data tool'ları yine çalışır.
    private static func startControlBridge() async {
        do {
            try await Self.controlServer.start()
        } catch {
            // Hata olursa stderr'e bas; UI'ı bloke etmesin.
            FileHandle.standardError.write(
                Data("[pixel-agent] Control bridge başlatılamadı: \(error.localizedDescription)\n".utf8)
            )
        }
    }

    /// App lifetime boyunca tek instance — `WindowGroup` yeniden yaratılırsa
    /// `start()` idempotent (`running` flag).
    static let controlServer = ControlSocketServer()

    private func rescan() {
        backends = Self.resolveBackends()
    }

    private func retryStore() {
        do {
            conversationStore = try ConversationStore()
            initErrorMessage = nil
        } catch {
            conversationStore = nil
            initErrorMessage = "Mesaj deposu açılamadı: \(error.localizedDescription)"
        }
    }

    private static func resolveBackends() -> [CLIKind: CLIBackend] {
        var resolved: [CLIKind: CLIBackend] = [:]
        let detector = CLIDetector()
        for (kind, path) in detector.available() {
            resolved[kind] = CLIBackend(kind: kind, executablePath: path)
        }
        return resolved
    }
}

enum ChatMode: String, CaseIterable {
    case single
    case dual

    var displayName: String {
        switch self {
        case .single: return "Tek"
        case .dual: return "Çift"
        }
    }
}

struct ChatHost: View {
    let backends: [CLIKind: CLIBackend]
    let conversationStore: ConversationStore
    @State private var selectedKind: CLIKind
    @State private var secondaryKind: CLIKind
    @State private var mode: ChatMode = .single
    @State private var showPairing: Bool = false
    @State private var showAbout: Bool = false
    @State private var incomingFromRemote: String?
    @State private var planMode: Bool = false
    @StateObject private var remoteHost: RemoteHost

    /// `PIXEL_RELAY_URL` env var varsa onu kullan; yoksa LAN IP (en0/en1) ile WebSocket URL üret;
    /// hiçbiri yoksa `ws://localhost:8787` (sadece Mac-local test için).
    static var defaultRelayURL: String {
        if let envURL = ProcessInfo.processInfo.environment["PIXEL_RELAY_URL"], !envURL.isEmpty {
            return envURL
        }
        if let lanIP = detectLANIPv4() {
            return "ws://\(lanIP):8787"
        }
        return "ws://localhost:8787"
    }

    private static func detectLANIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if !ip.isEmpty, ip != "127.0.0.1" {
                address = ip
                break
            }
        }
        return address
    }

    init(backends: [CLIKind: CLIBackend], conversationStore: ConversationStore) {
        self.backends = backends
        self.conversationStore = conversationStore
        let primary = CLIKind.allCases.first(where: { backends[$0] != nil }) ?? .gemini
        let secondary = CLIKind.allCases.first(where: { backends[$0] != nil && $0 != primary }) ?? primary
        _selectedKind = State(initialValue: primary)
        _secondaryKind = State(initialValue: secondary)
        // Mac LAN advertise + relay paralel — iOS hangisinden gelirse alırız.
        // Builder closure pairingCode/publicKey'i RemoteHost'tan alır (ADR-0023).
        let relayURL = Self.defaultRelayURL
        _remoteHost = StateObject(
            wrappedValue: RemoteHost(
                relayURL: relayURL,
                transportBuilder: { code, _ in
                    let lan = LANServerTransport(configuration: .init(serviceName: nil))
                    if let url = URL(string: relayURL) {
                        let relay = RelayTransport(relayURL: url, pairingCode: code, role: .mac)
                        return MergeTransport(transports: [lan, relay])
                    } else {
                        return MergeTransport(transports: [lan])
                    }
                }
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Mod", selection: $mode) {
                    ForEach(ChatMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 110)

                Picker(mode == .single ? "Backend" : "Sol", selection: $selectedKind) {
                    ForEach(CLIKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                if mode == .dual {
                    Picker("Sağ", selection: $secondaryKind) {
                        ForEach(CLIKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                Spacer()

                Toggle(isOn: $planMode) {
                    Label("Plan", systemImage: "list.bullet.clipboard")
                        .labelStyle(.titleAndIcon)
                }
                .toggleStyle(.button)
                .help(
                    selectedKind == .claude
                        ? "Plan modu — sadece okuma/araştırma tool'ları (Claude --permission-mode plan)"
                        : "Plan modu yalnızca Claude için aktif; \(selectedKind.displayName) bu bayrağı yoksayar"
                )

                if remoteHost.isConnected {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .help("iOS bağlı")
                }

                Button { showAbout = true } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Hakkında")

                Button { showPairing = true } label: {
                    Image(systemName: "qrcode")
                }
                .buttonStyle(.borderless)
                .help("Telefonla eşle (QR kod)")
                .disabled(mode == .dual)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            switch mode {
            case .single:
                if let backend = backends[selectedKind] {
                    ChatView(
                        backend: backend,
                        conversationStore: conversationStore,
                        incomingRemoteText: $incomingFromRemote,
                        planMode: planMode,
                        onAssistantComplete: { text in
                            Task { await remoteHost.sendAssistantMessage(text) }
                        }
                    )
                    // Backend değişiminde ChatViewModel @StateObject sıfırlansın diye
                    // .id'yi backend kind'ına bağla. Aksi halde picker değiştiğinde
                    // view yeniden init olur ama ViewModel eski backend'i tutar.
                    .id(selectedKind)
                } else {
                    MissingBackendView(kind: selectedKind)
                }

            case .dual:
                if let leftBackend = backends[selectedKind], let rightBackend = backends[secondaryKind] {
                    DualChatHost(
                        leftBackend: leftBackend,
                        rightBackend: rightBackend,
                        leftTitle: selectedKind.displayName,
                        rightTitle: secondaryKind.displayName,
                        leftStoreFileName: "conversation-\(selectedKind.rawValue).jsonl",
                        rightStoreFileName: "conversation-\(secondaryKind.rawValue).jsonl",
                        planMode: planMode
                    )
                    .id("\(selectedKind.rawValue)-\(secondaryKind.rawValue)")
                } else {
                    MissingBackendView(kind: backends[selectedKind] == nil ? selectedKind : secondaryKind)
                }
            }
        }
        .sheet(isPresented: $showPairing) {
            PairingView(remoteHost: remoteHost)
        }
        .sheet(isPresented: $showAbout) {
            AboutView(relayURL: remoteHost.relayURL)
        }
        .task {
            for await text in remoteHost.inboundTexts {
                incomingFromRemote = text
            }
        }
    }
}

struct MissingBackendView: View {
    let kind: CLIKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("\(kind.displayName) CLI yüklü değil")
                .font(.headline)
            Text("\(kind.executableName) PATH'te veya bilinen yollarda bulunamadı.\nYükleyip uygulamayı yeniden başlatın.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Başlatılamadı")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Tekrar dene", action: onRetry)
                .keyboardShortcut(.return)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
