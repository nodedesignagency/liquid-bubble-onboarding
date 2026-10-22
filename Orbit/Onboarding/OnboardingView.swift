import SwiftUI

/// Title and one line at the top, the liquid bubbles in the middle, the button at the bottom.
/// Everything except the bubbles stays quiet.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @State private var isLeaving = false
    @State private var stageSlot: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PhotoStyle.storageKey) private var photoStyle = PhotoStyle.glass.rawValue

    private let steps = OnboardingStep.all
    private var step: OnboardingStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        ZStack {
            // Drawn full screen behind the text, but laid out in the slot between header and footer,
            // so bubbles that wander off slide past the real edge of the screen.
            BubbleStage(scene: isLeaving ? .collapse : step.scene, slot: stageSlot)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 8)
                header
                    .padding(.horizontal, 32)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { slot in
                        stageSlot = slot
                    }
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .opacity(isLeaving ? 0 : 1)
        }
        .background(Theme.background)
        .contentShape(Rectangle())
        .gesture(swipe)
        #if DEBUG
        // For comparing looks while we iterate: triple-tap switches glass orbs and masked photos.
        .onTapGesture(count: 3) {
            photoStyle = photoStyle == PhotoStyle.glass.rawValue ? PhotoStyle.mask.rawValue : PhotoStyle.glass.rawValue
        }
        #endif
        .sensoryFeedback(.selection, trigger: index)
        .sensoryFeedback(.impact(weight: .light), trigger: photoStyle)
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
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

    private var header: some View {
        ZStack(alignment: .top) {
            // Every page's copy, invisible, so the header never changes height between pages.
            ForEach(steps) { headerText(for: $0).hidden() }
            headerText(for: step)
                .id(index)
                .transition(.blurReplace)
        }
    }

    private func headerText(for step: OnboardingStep) -> some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(step.subtitle)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 22) {
            PageDots(count: steps.count, index: index)
            PrimaryButton(title: isLast ? "Get started" : "Continue", action: advance)
        }
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
