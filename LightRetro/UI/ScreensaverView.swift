import SwiftUI

struct ScreensaverView: View {
    let onWake: () -> Void
    @State private var startedAt = ProcessInfo.processInfo.systemUptime

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let size = geometry.size
                let width = min(240, size.width * 0.72, size.height * 1.1)
                let height = width * 0.70
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                    VStack(spacing: 0) {
                        Image("Brand").resizable().scaledToFit()
                            .frame(height: height * 0.66)
                            .accessibilityLabel("Light Retro")
                            .accessibilityIdentifier("screensaver-logo")
                        Text(Date(), style: .time)
                            .font(.system(size: width * 0.18, weight: .light, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: width, height: height)
                    .offset(x: offset(elapsed, speed: 22, travel: size.width - width),
                            y: offset(elapsed, speed: 15, travel: size.height - height))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onWake)

            Button(action: onWake) {
                Text("Tap or press a button to return")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss screensaver")
            .accessibilityIdentifier("dismiss-screensaver")
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    // Reflect at each edge at the same constant speeds as the Android screensaver.
    private func offset(_ elapsed: TimeInterval, speed: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        let distance = (CGFloat(elapsed) * speed + travel * 0.15)
            .truncatingRemainder(dividingBy: 2 * travel)
        return min(distance, 2 * travel - distance)
    }
}
