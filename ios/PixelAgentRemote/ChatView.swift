import PixelCore
import PixelMascot
import PixelRemote
import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var session: RemoteSession
    @State private var draft: String = ""
    @State private var showAbout: Bool = false
    /// **Sprint 5 (iOS history viewer):** Geçmiş sheet'i için flag.
    @State private var showHistory: Bool = false
    /// **Sprint 5 (iOS connection-lost pulse):** Bağlantı düştüğünde set
    /// edilir; banner'a iletilir → ripple animasyonu tetiklenir. Mac
    /// `ConnectionPillView.pulseTrigger` ile aynı pattern.
    @State private var lastDisconnectAt: Date? = nil

    var body: some View {
        TabView {
            // Tab 1: Sohbet
            VStack(spacing: 0) {
                header

                if !session.isConnected {
                    ConnectionLostBanner(
                        pulseTrigger: lastDisconnectAt,
                        nextReconnectAt: session.nextReconnectAt,
                        onRetry: {
                            if let pairing = session.pairing {
                                Task { await session.connect(pairing: pairing) }
                            }
                        }
                    )
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(session.messages) { msg in
                                MessageRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .containerRelativeFrame(.vertical, alignment: .topLeading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color(.systemGroupedBackground))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                    .onChange(of: session.messages.count) {
                        if let last = session.messages.last {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                if let error = session.lastError {
                    errorBanner(error)
                }

                Divider()
                composerBar
            }
            .tabItem {
                Label("Sohbet", systemImage: "bubble.left.and.bubble.right.fill")
            }

            // Tab 2: Subagent'lar
            VStack(spacing: 0) {
                header
                SubagentsListSection()
            }
            .tabItem {
                Label("Subagent'lar", systemImage: "cpu.fill")
            }

            // Tab 3: Mac Paneli
            VStack(spacing: 0) {
                header
                MacPanelDashboardSection()
            }
            .tabItem {
                Label("Mac Paneli", systemImage: "desktopcomputer")
            }

            // Tab 4: Ayarlar (B8)
            VStack(spacing: 0) {
                header
                SettingsTabView()
            }
            .tabItem {
                Label("Ayarlar", systemImage: "gear")
            }
        }
        .tint(.purple)
        .sheet(isPresented: $showAbout) {
            AboutView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistoryViewIOS()
                .environmentObject(session)
        }
        // Sprint 5: isConnected geçişlerini dinleyip loss event'te
        // lastDisconnectAt'ı yenile — banner pulse'lar.
        .onChange(of: session.isConnected) { wasConnected, isConnected in
            if ConnectionLossDetector.isLossEvent(
                wasConnected: wasConnected, isConnected: isConnected
            ) {
                lastDisconnectAt = Date()
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }


    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
            Text(error)
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    private var composerBar: some View {
        HStack(spacing: 12) {
            TextField("Mesaj...", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
            
            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.purple)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            MascotView(state: session.mascotState, size: 36)
                .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("pixel-agent")
                    .font(.system(.headline, design: .rounded))
                if let label = session.transportLabel {
                    transportBadge(label)
                }
            }
            
            Spacer()
            
            if let code = session.pairing?.code {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Sprint 5 (iOS history viewer): Sohbet geçmişi sheet'i.
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func transportBadge(_ label: String) -> some View {
        let color: Color = label == "LAN" ? .green : (label == "Relay" ? .blue : .gray)
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await session.send(text: text) }
    }
}

struct SubagentsListSection: View {
    @EnvironmentObject var session: RemoteSession
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if session.activeSubagents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Çalışmakta olan subagent bulunmuyor.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(session.activeSubagents, id: \.id) { sub in
                            SubagentCard(sub: sub)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct SubagentCard: View {
    @EnvironmentObject var session: RemoteSession
    let sub: SubagentStatusPayload
    
    var isActive: Bool {
        sub.status == "Bekliyor" || sub.status == "Çalışıyor"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sub.prompt)
                        .font(.system(.subheadline, design: .rounded))
                        .bold()
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        Image(systemName: sub.status == "Bekliyor" ? "hourglass" : (sub.status == "Çalışıyor" ? "circle.dotted" : "checkmark.circle.fill"))
                            .font(.caption2)
                        Text(sub.status)
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(statusColor(sub.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(sub.status).opacity(0.12), in: Capsule())
                }
                
                Spacer()
                
                if isActive {
                    Button(action: {
                        Task { await session.cancelSubagent(id: sub.id) }
                    }) {
                        Text("Durdur")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red, in: Capsule())
                    }
                }
            }
            
            // Console output
            if !sub.partialOutput.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Konsol Çıktısı")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.green)
                    }
                    
                    ScrollView {
                        Text(sub.partialOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Bekliyor": return .orange
        case "Çalışıyor": return .blue
        case "Tamamlandı": return .green
        case "İptal edildi": return .gray
        case "Hata", "Süre aşıldı", "Çıktı aşıldı": return .red
        default: return .gray
        }
    }
}

struct MacPanelDashboardSection: View {
    @EnvironmentObject var session: RemoteSession
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // System metrics gauges
                HStack(spacing: 16) {
                    MetricGauge(title: "CPU", value: session.cpuUsage, color: .blue)
                    MetricGauge(title: "RAM", value: session.ramUsage, color: .orange)
                }
                
                // Active application name
                HStack {
                    Label("Aktif Uygulama", systemImage: "window.template")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(session.activeWindow.isEmpty ? "Yok" : session.activeWindow)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.purple)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                
                // Configuration pickers
                VStack(alignment: .leading, spacing: 14) {
                    Text("Konfigürasyon")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Divider()

                    // Backend picker
                    HStack {
                        Text("Arka Uç (Backend)")
                            .font(.subheadline)
                        Spacer()
                        Picker("Backend", selection: Binding(
                            get: { session.selectedBackend },
                            set: { newBackend in
                                guard !newBackend.isEmpty else { return }
                                let newModel = session.availableModels[newBackend]?.first ?? ""
                                Task {
                                    await session.updateConfig(backend: newBackend, model: newModel, planMode: session.planMode)
                                }
                            }
                        )) {
                            if session.availableBackends.isEmpty {
                                Text(session.selectedBackend.isEmpty ? "Yok" : session.selectedBackend).tag(session.selectedBackend)
                            } else {
                                ForEach(session.availableBackends, id: \.self) { b in
                                    Text(b.capitalized).tag(b)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()

                    // Model picker
                    HStack {
                        Text("Model")
                            .font(.subheadline)
                        Spacer()
                        Picker("Model", selection: Binding(
                            get: { session.selectedModel },
                            set: { newModel in
                                guard !newModel.isEmpty else { return }
                                Task {
                                    await session.updateConfig(backend: session.selectedBackend, model: newModel, planMode: session.planMode)
                                }
                            }
                        )) {
                            let models = session.availableModels[session.selectedBackend] ?? []
                            if models.isEmpty {
                                Text(session.selectedModel.isEmpty ? "Yok" : session.selectedModel).tag(session.selectedModel)
                            } else {
                                ForEach(models, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()

                    // Plan Mode toggle
                    Toggle(isOn: Binding(
                        get: { session.planMode },
                        set: { newPlanMode in
                            Task {
                                await session.updateConfig(backend: session.selectedBackend, model: session.selectedModel, planMode: newPlanMode)
                            }
                        }
                    )) {
                        Label("Plan Modu", systemImage: "list.bullet.clipboard")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                
                // Screen Sharing section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ekran Resmi")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            Task { await session.requestScreenshot() }
                        }) {
                            Label("Resim Al", systemImage: "camera.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple, in: Capsule())
                        }
                    }
                    
                    if let image = session.latestScreenshot {
                        ZoomableImageView(image: image)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Ekran görüntüsü talep edilmedi veya yüklenmedi.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                // C12 (Sprint 3): Tool call feed — Mac MCP bridge'inde tetiklenen
                // son ~30 tool çağrısının yatay-dağıtılmış listesi.
                ToolCallFeedSection()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// C12: iOS Mac Paneli'nde Mac'in son MCP tool aktivitesini gösteren
/// kart. Boşsa "Henüz aktivite yok" placeholder.
struct ToolCallFeedSection: View {
    @EnvironmentObject var session: RemoteSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tool Aktivitesi", systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                Spacer()
                if !session.recentToolCalls.isEmpty {
                    Text("\(session.recentToolCalls.count)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            if session.recentToolCalls.isEmpty {
                Text("Henüz aktivite yok. MCP server bir tool çağırdığında burada görüneceksin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(session.recentToolCalls.prefix(10)) { event in
                        ToolCallRow(event: event)
                    }
                    if session.recentToolCalls.count > 10 {
                        Text("ve \(session.recentToolCalls.count - 10) daha…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ToolCallRow: View {
    let event: ToolCallEventPayload

    private var iconName: String {
        event.status == "success" ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    private var iconColor: Color {
        event.status == "success" ? .green : .red
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: event.timestamp))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.toolName)
                        .font(.caption.monospaced().bold())
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let summary = event.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct MetricGauge: View {
    let title: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Gauge(value: value, in: 0...100) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            } currentValueLabel: {
                Text(String(format: "%.1f%%", value))
                    .font(.system(.footnote, design: .monospaced))
                    .bold()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
            .scaleEffect(1.2)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
        
        scrollView.delegate = context.coordinator
        context.coordinator.imageView = imageView
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
    }
}

// Sprint 5: internal hale getirildi — ConversationHistoryViewIOS de kullanır.
struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(BubbleShape(isUser: true))
                    .shadow(color: .blue.opacity(0.15), radius: 3, x: 0, y: 1)
                    .textSelection(.enabled)
            } else if message.role == .assistant {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .clipShape(BubbleShape(isUser: false))
                        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                        .textSelection(.enabled)
                }
                Spacer()
            } else {
                Spacer()
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                Spacer()
            }
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: radius, height: radius),
            style: .continuous
        )
        return path
    }
}
