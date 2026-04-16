import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("ETHER")
                .font(.etherVariant(28))
                .tracking(4.0)
                .foregroundColor(.etherAccent)

            Text("System Audio Equalizer")
                .font(.etherMono(11))
                .foregroundColor(.etherTextSecondary)

            Text("v\(version) (\(build))")
                .font(.etherMono(10))
                .foregroundColor(.etherTextTertiary)
                .monospacedDigit()

            Divider().opacity(0.3).padding(.vertical, 4)

            VStack(spacing: 6) {
                Text("Built with low-latency AVAudioEngine,")
                Text("Core Audio HAL taps, and vDSP FFT.")
            }
            .font(.etherMono(10))
            .foregroundColor(.etherTextSecondary)
            .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            // BlackHole attribution — MIT license requirement
            VStack(spacing: 4) {
                Text("AUDIO CAPTURE POWERED BY")
                    .font(.etherMono(8, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(.etherTextTertiary)

                Link(destination: URL(string: "https://github.com/ExistentialAudio/BlackHole")!) {
                    HStack(spacing: 4) {
                        Text("BlackHole")
                            .font(.etherMono(11, weight: .medium))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.etherAccent)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(28)
        .frame(width: 360, height: 320)
        .background(Color.etherBackground)
    }
}
