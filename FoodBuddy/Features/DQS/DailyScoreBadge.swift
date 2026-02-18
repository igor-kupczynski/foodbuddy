import SwiftUI

struct DailyScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("DQS Score")
            .accessibilityValue("\(score)")
    }

    private var color: Color {
        switch score {
        case 21...:
            return .green
        case 11...20:
            return .yellow
        case 1...10:
            return .orange
        default:
            return .red
        }
    }
}
