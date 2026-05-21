import CoreImage.CIFilterBuiltins
import PixelRemote
import SwiftUI

struct PairingView: View {
    let relayURL: String
    @State private var code: String = PairingCode.generate()
    @Environment(\.dismiss) private var dismiss

    private var qrPayload: String {
        "pixel-agent-pair://?code=\(code)&relay=\(relayURL)"
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

            Text(code)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .tracking(6)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.quaternary, in: Capsule())

            Text(relayURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button("Yeni kod") {
                    code = PairingCode.generate()
                }
                Button("Kapat") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 360)
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
