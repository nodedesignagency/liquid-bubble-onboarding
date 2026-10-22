import SwiftUI

/// v2: one screen, in the style of the Wabi app.
///
/// Earth waits as a big glass dome rising from the bottom edge under one line of copy. Swipe up
/// and it follows the finger; let go high enough and it flies up into a small glass orb, its
/// trailing drop stretching the glass, the copy bending as Earth passes through it. Then your
/// friends bubble out of Earth's surface into a floating cluster of liquid glass, "Meet Orbit."
/// fades in under it, and two glass buttons come up. "Continue" melts everything back into Earth
/// and sinks it to the dome, the first frame, so a screen recording loops.
struct GlassOnboardingView: View {
    var onFinish: () -> Void

    private enum Phase { case gate, revealed, leaving }

    @State private var phase = Phase.gate
    @State private var lift = EarthLift()
    @State private var showGateText = true
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showFooter = false
    @State private var pastThreshold = false
    @State private var hintBob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far up the finger has to lift Earth before letting go reveals.
    private let threshold: CGFloat = 90

    var body: some View {
        ZStack {
            Theme.glassCanvas.ignoresSafeArea()

            GeometryReader { full in
                BubbleStage(
                    scene: phase == .revealed ? .reveal : .gate,
                    look: .v2,
                    lift: lift,
                    backdrop: AnyView(headline(in: full.size))
                )
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                if phase == .gate && showGateText {
                    hint
                        .transition(.opacity)
                }
                if showFooter {
                    footer
                        .transition(.opacity.combined(with: .offset(y: 16)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.selection, trigger: pastThreshold)
        .sensoryFeedback(.impact(weight: .medium), trigger: phase == .revealed)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { hintBob = true }
        }
    }

    // MARK: Copy

    /// Drawn into the glass layer, so Earth bends it on the way up. Laid out on the whole screen.
    private func headline(in size: CGSize) -> some View {
        let scale = min(size.width / StageMetrics.referenceSize.width, size.height / StageMetrics.referenceSize.height,
                        StageMetrics.maxScale)
        // Under the orb Earth becomes (`OrbitChoreography`: centre y -44, radius 30).
        let titleTop = size.height / 2 + (-44 + 30) * scale + 26
        return ZStack {
            Text("Everyone you love,\nin one orbit.")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .opacity(showGateText ? 1 : 0)
                .blur(radius: showGateText ? 0 : 6)
                .position(x: size.width / 2, y: size.height * 0.4)

            VStack(spacing: 2) {
                Text("Meet Orbit.")
                    .foregroundStyle(Theme.ink)
                    .opacity(showTitle ? 1 : 0)
                    .blur(radius: showTitle ? 0 : 6)
                Text("Your friends, always\nwithin reach.")
                    .foregroundStyle(Theme.inkSecondary)
                    .opacity(showSubtitle ? 1 : 0)
                    .blur(radius: showSubtitle ? 0 : 6)
            }
            .font(.system(size: 27, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(1)
            .fixedSize()
            .position(x: size.width / 2, y: titleTop + 52)
        }
        .frame(width: size.width, height: size.height)
    }

    private var hint: some View {
        Button(action: reveal) {
            VStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .offset(y: hintBob && !reduceMotion ? -3 : 1)
                Text("Swipe up to enter")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Sits just above the dome's top.
        .padding(.bottom, 200)
        .accessibilityLabel("Enter")
    }

    private var footer: some View {
        VStack(spacing: 12) {
            GlassButton(title: "Continue with Apple", systemImage: "apple.logo", action: finish)
            GlassButton(title: "Continue with phone number", systemImage: "phone.fill", action: finish)
            Text("By continuing, you agree to our Terms and Privacy Policy.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    // MARK: Gesture

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard phase == .gate else { return }
                lift.move(to: value.translation.height, at: now)
                pastThreshold = -value.translation.height > threshold
            }
            .onEnded { value in
                guard phase == .gate else { return }
                lift.release(at: now)
                let flung = value.predictedEndTranslation.height < -260
                if -value.translation.height > threshold || flung {
                    reveal()
                }
                pastThreshold = false
            }
    }

    private var now: Double { Date.timeIntervalSinceReferenceDate }

    // MARK: Phases

    private func reveal() {
        guard phase == .gate else { return }
        phase = .revealed
        withAnimation(.easeOut(duration: 0.35).delay(0.15)) { showGateText = false }
        withAnimation(.smooth(duration: 0.6).delay(0.55)) { showTitle = true }
        withAnimation(.smooth(duration: 0.6).delay(0.85)) { showSubtitle = true }
        withAnimation(.smooth(duration: 0.6).delay(1.6)) { showFooter = true }
    }

    /// Melt everyone back into Earth and sink it to the dome, then hand over to the app.
    private func finish() {
        guard phase == .revealed else { return }
        phase = .leaving
        withAnimation(.smooth(duration: 0.4)) {
            showFooter = false
            showTitle = false
            showSubtitle = false
        }
        withAnimation(.smooth(duration: 0.6).delay(1.0)) { showGateText = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 2.4))
            onFinish()
        }
    }
}

/// A capsule of glass: Liquid Glass on iOS 26 and later, a frosted material before that.
struct GlassButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassCapsuleStyle())
    }
}

struct GlassCapsuleStyle: ButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular.tint(.white.opacity(0.45)).interactive(), in: Capsule())
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
                .background(Color.white.opacity(0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
        }
    }
}

#Preview {
    GlassOnboardingView {}
}
