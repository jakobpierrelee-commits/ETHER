import SwiftUI

/// Floating overlay listing every keyboard shortcut. Toggled with `?`.
struct ShortcutCheatsheet: View {
    @Binding var isPresented: Bool

    private let sections: [(String, [(String, String)])] = [
        ("Transport", [
            ("Space",            "Start / Stop Ether"),
            ("⌘ B",              "Bypass all bands"),
            ("⌘ 0",              "Reset to flat")
        ]),
        ("Editing", [
            ("⌘ Z",              "Undo"),
            ("⇧ ⌘ Z",            "Redo"),
            ("Drag handle",      "Adjust Freq + Gain"),
            ("⇧ + drag",         "Axis lock + snap to ISO"),
            ("⌘ / ⌥ + drag",    "Fine adjustment"),
            ("Scroll on handle", "Adjust Q"),
            ("⇧ + scroll",       "Fine Q"),
            ("Double-click",     "Reset that band"),
            ("Right-click",      "Filter type / bypass")
        ]),
        ("Knobs", [
            ("Drag knob",        "±12 dB"),
            ("Scroll on knob",   "Adjust"),
            ("Double-click",     "Reset to 0")
        ]),
        ("Profiles", [
            ("X",                "Toggle A/B slot"),
        ]),
        ("App", [
            ("⌘ ,",              "Preferences"),
            ("⌘ W",              "Close window (stays in menu bar)"),
            ("⌘ Q",              "Quit"),
            ("?",                "Show / hide this sheet")
        ])
    ]

    var body: some View {
        ZStack {
            // Dim background — click to dismiss
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("KEYBOARD SHORTCUTS")
                        .font(.etherMono(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundColor(.etherAccent)
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.etherTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                Divider().opacity(0.25)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(sections, id: \.0) { title, rows in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title.uppercased())
                                .font(.etherMono(9, weight: .semibold))
                                .tracking(1.0)
                                .foregroundColor(.etherTextTertiary)
                            ForEach(rows, id: \.0) { key, description in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(key)
                                        .font(.etherMono(10, weight: .medium))
                                        .foregroundColor(.etherAccent)
                                        .frame(width: 110, alignment: .leading)
                                    Text(description)
                                        .font(.etherMono(10))
                                        .foregroundColor(.etherTextSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 620)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.etherAccent.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
        }
        .transition(.opacity)
    }
}
