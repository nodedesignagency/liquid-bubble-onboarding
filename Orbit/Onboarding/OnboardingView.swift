import SwiftUI

/// Heading at the top, the liquid bubbles in the middle, one sentence and the arrow at the bottom.
/// Everything except the bubbles stays quiet, like the reference.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @State private var isLeaving = false
    @State private var stageSlot: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = OnboardingStep.all
    private var step: OnboardingStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        ZStack {
            // Drawn full screen behind the text, but laid out in the slot between heading and footer,
            // so bubbles pushed aside slide off the real edge of the screen.
            BubbleStage(scene: isLeaving ? .collapse : step.scene, slot: stageSlot)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { slot in
                        stageSlot = slot
                    }
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .opacity(isLeaving ? 0 : 1)
        }
        .background(Theme.background)
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.selection, trigger: index)
    }

    // MARK: Sections

    private var topBar: some View {
        ZStack {
            Text(step.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .id(index)
                .transition(.blurReplace)
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                }
                .opacity(index > 0 ? 1 : 0)
                .disabled(index == 0)
                .accessibilityLabel("Back")
                Spacer()
                Button(action: skip) {
                    Text("Skip")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(height: 44)
                        .padding(.horizontal, 12)
                }
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
            }
        }
        .frame(height: 52)
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                // Every page's sentence, invisible, so the footer never changes height between pages.
                ForEach(steps) { bodyText(for: $0).hidden() }
                bodyText(for: step)
                    .id(index)
                    .transition(.blurReplace)
            }
            Spacer(minLength: 0)
            NextButton(progress: Double(index + 1) / Double(steps.count), isLast: isLast, action: advance)
        }
    }

    private func bodyText(for step: OnboardingStep) -> some View {
        Text(step.body)
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .foregroundStyle(Theme.ink)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 270, alignment: .leading)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height), abs(dx) > 60 else { return }
                if dx < 0 {
                    advance()
                } else {
                    goBack()
                }
            }
    }

    // MARK: Navigation

    private func advance() {
        guard !isLeaving else { return }
        if isLast {
            finish()
        } else {
            withAnimation(.smooth(duration: 0.5)) { index += 1 }
        }
    }

    private func goBack() {
        guard !isLeaving, index > 0 else { return }
        withAnimation(.smooth(duration: 0.5)) { index -= 1 }
    }

    private func skip() {
        guard !isLeaving else { return }
        withAnimation(.smooth(duration: 0.5)) { index = steps.count - 1 }
    }

    /// Melt every bubble back into Earth, then hand over to the app.
    private func finish() {
        guard !isLeaving else { return }
        withAnimation(.smooth(duration: 0.4)) { isLeaving = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 1.3))
            onFinish()
        }
    }
}

#Preview {
    OnboardingView {}
}
