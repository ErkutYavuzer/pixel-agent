import CoreImage.CIFilterBuiltins
import PixelRemote
import SwiftUI

struct PairingView: View {
    @ObservedObject var remoteHost: RemoteHost
    @Environment(\.dismiss) private var dismiss

    private var qrPayload: String {
        "pixel-agent-pair://?code=\(remoteHost.pairingCode)&relay=\(remoteHost.relayURL)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Cihazınla eşle")
                .font(.title2.bold())

            Text("Telefonundaki pixel-agent uygulamasından bu QR kodu tara.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            qrImage
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))

            Text(remoteHost.pairingCode)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .tracking(6)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.quaternary, in: Capsule())

            Text(remoteHost.relayURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            statusRow

            if let error = remoteHost.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("Yeni kod") {
                    remoteHost.regenerateCode()
                }
                .disabled(remoteHost.isConnected)

                if remoteHost.isConnected {
                    Button("Bağlantıyı kes") {
                        Task { await remoteHost.disconnect() }
                    }
                } else {
                    Button("Bağlan") {
                        Task { await remoteHost.connect() }
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Button("Kapat") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 380)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(remoteHost.isConnected ? .green : .secondary.opacity(0.6))
                .frame(width: 8, height: 8)
            Text(remoteHost.isConnected ? "Bağlı (relay'i dinliyor)" : "Bağlı değil")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var qrImage: Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(qrPayload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return Image(systemName: "qrcode")
        }

        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let scaled = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return Image(systemName: "qrcode")
        }

        return Image(decorative: cgImage, scale: 1.0)
    }
}
