import AppKit
import SwiftUI
import ServiceManagement

enum SettingsWindow {
    static func make() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Blink"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        return window
    }
}

struct SettingsView: View {
    var body: some View {
        ScrollView {
            SettingsContent()
                .padding(28)
                .padding(.top, 6)
        }
        .frame(width: 460, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsContent: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header

                section("Rhythm") {
                    stepperRow(
                        title: "Break every",
                        value: $settings.workIntervalMinutes,
                        range: 1...120, step: 1,
                        format: { "\($0) min" }
                    )
                    Divider().opacity(0.4)
                    stepperRow(
                        title: "Break lasts",
                        value: $settings.breakDurationSeconds,
                        range: 5...300, step: 5,
                        format: { $0 >= 60 ? "\($0 / 60)m \($0 % 60)s" : "\($0)s" }
                    )
                    Divider().opacity(0.4)
                    stepperRow(
                        title: "Heads-up before",
                        value: $settings.warningLeadSeconds,
                        range: 0...60, step: 5,
                        format: { $0 == 0 ? "off" : "\($0)s" }
                    )
                    Divider().opacity(0.4)
                    stepperRow(
                        title: "Postpone adds",
                        value: $settings.postponeMinutes,
                        range: 1...30, step: 1,
                        format: { "\($0) min" }
                    )
                }

                section("Behaviour") {
                    toggleRow("Strict mode", "No skipping and no postponing once a break starts.", $settings.strictMode)
                    Divider().opacity(0.4)
                    toggleRow("Fade the screen to black", "Mid-break the overlay dims away, so there is nothing left to look at.", $settings.fadeToBlack)
                    Divider().opacity(0.4)
                    toggleRow("Chime at start and end", "Lets you rest with your eyes shut and still know when it is over.", $settings.playSounds)
                    Divider().opacity(0.4)
                    toggleRow("Time away counts as a break", "If you leave the keyboard for a full break length, the timer resets.", $settings.idleResetEnabled)
                    Divider().opacity(0.4)
                    toggleRow("Show countdown in the menu bar", "Displays minutes until the next break next to the icon.", $settings.showCountdownInMenuBar)
                    Divider().opacity(0.4)
                    toggleRow("Launch at login", loginError ?? "Start Blink automatically when you log in.", Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            loginError = LoginItem.set(newValue)
                        }
                    ))
                }

                HStack {
                    GhostButtonLight(title: "Preview a break") {
                        BreakEngine.shared.takeBreakNow()
                    }
                    Spacer()
                    Text("\(settings.breaksToday) breaks today")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "eye")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color(red: 0.25, green: 0.7, blue: 0.66))
            VStack(alignment: .leading, spacing: 2) {
                Text("Blink").font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Every \(settings.workIntervalMinutes) minutes, look away for \(settings.breakDurationSeconds) seconds.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 11) { content() }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
        }
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int,
                            format: @escaping (Int) -> String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, design: .rounded))
            Spacer()
            Text(format(value.wrappedValue))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct GhostButtonLight: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .controlSize(.regular)
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error string to surface in the UI, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Could not update login item: \(error.localizedDescription)"
        }
    }
}
