import AppKit
import SwiftUI

final class WarningState: ObservableObject {
    @Published var secondsLeft: Int = 10
    @Published var total: Int = 10
}

/// Small non-intrusive HUD in the top-right corner: "look away in 10, 9, 8…"
/// so a break never lands mid-thought without warning.
final class WarningPanelController {
    private var panel: NSPanel?
    private let state = WarningState()

    func show(totalSeconds: Double) {
        guard panel == nil, let screen = NSScreen.main else { return }
        state.total = Int(totalSeconds)
        state.secondsLeft = Int(totalSeconds)

        let size = CGSize(width: 258, height: 68)
        let origin = CGPoint(x: screen.visibleFrame.maxX - size.width - 18,
                             y: screen.visibleFrame.maxY - size.height - 12)
        let p = NSPanel(contentRect: CGRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.animationBehavior = .none
        p.alphaValue = 0
        p.contentView = NSHostingView(rootView: WarningView().environmentObject(state))
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 1
        }
        panel = p
    }

    func update(secondsLeft: Int) {
        state.secondsLeft = max(0, secondsLeft)
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

struct WarningView: View {
    @EnvironmentObject var state: WarningState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.78))
            VStack(alignment: .leading, spacing: 4) {
                Text("Eye break in \(state.secondsLeft)s")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                ProgressView(value: Double(state.total - state.secondsLeft), total: Double(max(1, state.total)))
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.35, green: 0.85, blue: 0.78))
                    .frame(height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
