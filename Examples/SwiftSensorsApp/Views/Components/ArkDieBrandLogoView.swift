import SwiftUI

/// Official ArkDieHuD typographic wordmark paired with the Silicon Die Precision icon mark.
struct ArkDieBrandLogoView: View {
    enum Style {
        case header
        case compact
    }

    let style: Style

    private var iconSize: CGFloat {
        self.style == .header ? 44 : 26
    }

    private var cornerRadius: CGFloat {
        self.style == .header ? 10 : 6
    }

    private var wordSize: CGFloat {
        self.style == .header ? 28 : 17
    }

    private var badgeSize: CGFloat {
        self.style == .header ? 17 : 11
    }

    var body: some View {
        HStack(spacing: self.style == .header ? 12 : 8) {
            Image("ArkDieMark")
                .resizable()
                .scaledToFill()
                .frame(width: self.iconSize, height: self.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: self.style == .header ? 2 : 0) {
                HStack(alignment: .center, spacing: 6) {
                    Text("ArkDie")
                        .font(.system(size: self.wordSize, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)

                    Text("HuD")
                        .font(.system(size: self.badgeSize, weight: .heavy, design: .monospaced))
                        .tracking(0.6)
                        .padding(.horizontal, self.style == .header ? 8 : 5)
                        .padding(.vertical, self.style == .header ? 3 : 1.5)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.83, blue: 0.93),
                                    Color(red: 0.20, green: 0.83, blue: 0.60),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ).opacity(0.18),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    Color(red: 0.13, green: 0.83, blue: 0.93).opacity(0.45),
                                    lineWidth: 0.8
                                )
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.10, green: 0.72, blue: 0.85),
                                    Color(red: 0.14, green: 0.72, blue: 0.50),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                if self.style == .header {
                    Text(L10n.tr("SILICON & NETWORK TELEMETRY"))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ArkDieHuD")
    }
}
