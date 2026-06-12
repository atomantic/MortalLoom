import SwiftUI

/// Chip builders shared between GoalsView, GoalEditSheet, and CheckInSheet so
/// the category/horizon/type badge styling doesn't drift between the list
/// card and the check-in header.
enum GoalsViewHelpers {
    @ViewBuilder
    static func goalTypeBadge(_ goalType: GoalType?) -> some View {
        if let gt = goalType, gt != .standard {
            Image(systemName: gt.icon)
                .font(.caption2)
                .foregroundColor(gt == .apex ? .warning : .accentColor)
        }
    }

    static func categoryChip(_ cat: GoalCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: cat.icon)
                .font(.system(size: 9))
            Text(cat.label)
                .font(.system(size: 10))
        }
        .foregroundColor(cat.swiftUIColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(cat.swiftUIColor.opacity(0.15))
        .cornerRadius(4)
    }

    static func horizonChip(_ hz: GoalHorizon) -> some View {
        Text(hz.label)
            .font(.system(size: 10))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.textSecondary.opacity(0.12))
            .cornerRadius(4)
    }
}
