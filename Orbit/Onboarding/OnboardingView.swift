import SwiftUI

/// Heading at the top, the liquid bubble stage in the middle, the call to action at the bottom.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @State private var isLeaving = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = OnboardingStep.all
    private var step: OnboardingStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 6)
            header
                .padding(.horizontal, 24)
                .padding(.top, 28)
            BubbleStage(scene: isLeaving ? .collapse : step.scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .background(Theme.background)
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.selection, trigger: index)
    }

    // MARK: Sections

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .glassBackground(in: Circle())
            }
            .opacity(index > 0 ? 1 : 0)
            .disabled(index == 0)
            .accessibilityLabel("Back")

            StoryProgress(count: steps.count, index: index)

            Button("Skip", action: skip)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
        }
        .frame(height: 34)
        .opacity(isLeaving ? 0 : 1)
    }

    private var header: some View {
        ZStack(alignment: .top) {
            // Every page's copy, invisible, so the header is always as tall as the tallest page
            // and the stage below it never jumps when the copy changes.
            ForEach(steps) { headerText(for: $0).hidden() }
            headerText(for: step)
                .id(index)
                .transition(.blurReplace)
        }
        .opacity(isLeaving ? 0 : 1)
    }

    private func headerText(for step: OnboardingStep) -> some View {
        VStack(spacing: 12) {
            Text(step.styledTitle)
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
            Text(step.subtitle)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: 300)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            PrimaryButton(title: isLast ? "Create my orbit" : "Continue", action: advance)
            Button("I already have an account", action: finish)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .frame(height: 44)
        }
        .opacity(isLeaving ? 0 : 1)
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
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 1.2))
            onFinish()
        }
    }
}

#Preview {
    OnboardingView {}
}
