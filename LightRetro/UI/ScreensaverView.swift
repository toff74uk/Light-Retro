import SwiftUI

struct ScreensaverView: View {
    let onWake: () -> Void

    var body: some View {
        Button(action: onWake) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 30) {
                    Image("Brand").resizable().scaledToFit().frame(width: 240, height: 100)
                    Text(context.date, style: .time)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                    Text("Tap or press a button to return").font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .accessibilityLabel("Dismiss screensaver")
        .accessibilityIdentifier("dismiss-screensaver")
    }
}
