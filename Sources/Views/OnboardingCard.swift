import SwiftUI

/// One-time onboarding overlay explaining driver setup.
/// Shown on first launch until dismissed; persists dismissal in UserDefaults.
struct OnboardingCard: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var engine: EngineManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { }  // swallow taps so user must use the button

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("WELCOME TO")
                        .font(.etherMono(9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundColor(.etherTextTertiary)
                    Text("ETHER")
                        .font(.etherVariant(EtherType.xxl))
                        .tracking(3.0)
                        .foregroundColor(.etherAccent)
                }

                Text("Ether routes your system audio through a lossless 10-band parametric EQ before sending it to your speakers. Here's how to set it up:")
                    .font(.etherMono(11))
                    .foregroundColor(.etherTextSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    step(1, title: "Install the Ether driver", body: "Ether ships its own virtual audio driver — system audio routes through it for processing.",
                         hint: "Run install-driver.sh from the project")
                    step(2, title: "Select your speakers in Ether", body: "Pick your real output device from the Output dropdown at the top of the window.")
                    step(3, title: "Press Start", body: "Ether will route system audio through its virtual driver, process through the EQ, and play through your speakers.")
                    step(4, title: "Tune your sound", body: "Drag the EQ handles, or use the Character knobs (Bass, Warmth, Clarity, Presence, Air) for quick sculpting. Save profiles for later.")
                }

                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                        UserDefaults.standard.set(true, forKey: "audio.ether.hasSeenOnboarding")
                    } label: {
                        Text("Let's go")
                            .font(.etherMono(11, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.etherAccent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.etherAccent.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.7), radius: 30, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func step(_ number: Int, title: String, body: String, hint: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.etherMono(13, weight: .bold))
                .foregroundColor(.etherAccent)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.etherAccent.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.etherMono(11, weight: .semibold))
                    .foregroundColor(.etherTextPrimary)
                Text(body)
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = hint {
                    Text(hint)
                        .font(.etherMono(10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.4))
                        )
                        .foregroundColor(.etherAccent)
                        .padding(.top, 2)
                }
            }
        }
    }
}
