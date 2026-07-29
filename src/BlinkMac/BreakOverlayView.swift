import SwiftUI
import Foundation
import BlinkCore

struct BreakOverlayView: View {
    let showsControls: Bool
    @EnvironmentObject private var state: BreakState

    private var contentOpacity: Double {
        BreakVisuals.contentAlpha(progress: state.progress, fadeToBlack: state.fadeToBlack)
    }

    private var isFinishing: Bool { state.secondsLeft <= BreakVisuals.finishingSeconds }

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
            RadialGradient(
                colors: [Color(red: 0.07, green: 0.13, blue: 0.16), .black],
                center: .center, startRadius: 0, endRadius: 900
            )
            .opacity(0.9)

            VStack(spacing: 34) {
                Spacer()

                ZStack {
                    CountdownRing(progress: state.progress)
                        .frame(width: 186, height: 186)
                    VStack(spacing: 2) {
                        Text("\(Int(state.secondsLeft.rounded(.up)))")
                            .font(.system(size: 62, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("seconds")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .tracking(2.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }

                VStack(spacing: 12) {
                    Text(isFinishing ? "Welcome back" : "Look away")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(isFinishing ? "Your eyes just got a full reset." : state.prompt)
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                Spacer()

                if showsControls, !isFinishing {
                    controls
                        .opacity(state.fadeToBlack ? min(1, contentOpacity * 1.6) : 1)
                }
            }
            .padding(48)
            .opacity(contentOpacity)
            .animation(.easeInOut(duration: 0.9), value: contentOpacity)
        }
        .ignoresSafeArea()
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if state.allowsSkip {
                HStack(spacing: 12) {
                    GhostButton(title: "Postpone \(state.postponeMinutes) min",
                                symbol: "clock.arrow.circlepath",
                                enabled: state.armed,
                                highlighted: false) {
                        state.clickPostpone()
                    }
                    GhostButton(title: "Skip", symbol: "forward.end.fill",
                                enabled: state.armed,
                                highlighted: state.confirmingSkip) {
                        state.clickSkip()
                    }
                }
                Text(hint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.22))
            } else {
                Label("Strict mode — this one is not skippable", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.confirmingSkip)
    }

    private var hint: String {
        if state.confirmingSkip { return "press esc again to skip" }
        return state.armed ? "or press esc twice" : ""
    }
}

private struct CountdownRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(
                    AngularGradient(
                        colors: [Color(red: 0.35, green: 0.85, blue: 0.78),
                                 Color(red: 0.42, green: 0.62, blue: 0.95)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
                .shadow(color: Color(red: 0.35, green: 0.85, blue: 0.78).opacity(0.35), radius: 12)
        }
    }
}

struct GhostButton: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let highlighted: Bool
    let action: () -> Void
    @State private var hovering = false

    private var accent: Color { Color(red: 0.35, green: 0.85, blue: 0.78) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(highlighted ? accent.opacity(0.22)
                                           : Color.white.opacity(hovering && enabled ? 0.16 : 0.08))
            )
            .overlay(Capsule().stroke(highlighted ? accent.opacity(0.5)
                                                  : Color.white.opacity(0.12), lineWidth: 1))
            .foregroundStyle(.white.opacity(enabled ? (hovering || highlighted ? 0.95 : 0.7) : 0.3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}
