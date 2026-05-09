import SwiftUI

public enum UsageColor {
    public static func color(for utilization: Double) -> Color {
        if utilization >= 95 { return .red }
        if utilization >= 80 { return .orange }
        if utilization >= 60 { return Color(red: 0.95, green: 0.82, blue: 0.25) }
        return Color(red: 0.45, green: 0.85, blue: 0.55)
    }
}

public struct PillBar: View {
    public let utilization: Double
    public let height: CGFloat

    public init(utilization: Double, height: CGFloat = 6) {
        self.utilization = utilization
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(UsageColor.color(for: utilization))
                    .frame(width: geo.size.width * min(max(utilization / 100.0, 0), 1))
            }
        }
        .frame(height: height)
    }
}
