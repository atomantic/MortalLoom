import Foundation

struct CorrelationDataPoint: Sendable {
    let testDate: Date
    let avgDailySteps: Double
    let markers: [String: Double]
}

enum CorrelationEngine {

    /// Build correlation data for each blood test by averaging daily activity metrics
    /// from the 30 days preceding each test date.
    static func buildCorrelationData(
        tests: [BloodTest],
        healthMetrics: [HealthMetricEntry],
        windowDays: Int = 30
    ) -> [CorrelationDataPoint] {
        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)

        return tests.compactMap { test -> CorrelationDataPoint? in
            guard let testDate = DateFormatting.dateFromString(test.date) else { return nil }

            var totalSteps = 0.0, count = 0.0
            for dayOffset in 1...windowDays {
                guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: testDate) else { continue }
                let dayStr = DateFormatting.dateString(day)
                if let metrics = metricsByDate[dayStr]?.first {
                    totalSteps += metrics.steps ?? 0
                    count += 1
                }
            }

            guard count > 0 else { return nil }

            return CorrelationDataPoint(
                testDate: testDate,
                avgDailySteps: totalSteps / count,
                markers: test.markers
            )
        }
    }

    /// Convert active goals into week-index markers relative to a birth date.
    /// Returns both target date markers and projected completion markers.
    static func goalMarkers(
        goals: [Goal],
        birthDate: Date,
        deathDate: Date?,
        healthyCognitiveDate: Date?
    ) -> [(title: String, weekIndex: Int, isProjected: Bool, priority: GoalPriority)] {
        var markers: [(title: String, weekIndex: Int, isProjected: Bool, priority: GoalPriority)] = []

        for goal in goals where goal.status == .active {
            if let targetStr = goal.targetDate,
               let targetDate = DateFormatting.dateFromString(targetStr) {
                let days = Calendar.current.dateComponents([.day], from: birthDate, to: targetDate).day ?? 0
                let weekIdx = max(0, days / 7)
                markers.append((title: goal.title, weekIndex: weekIdx, isProjected: false, priority: goal.priority))
            }

            let projection = GoalEngine.project(goal: goal, deathDate: deathDate, healthyCognitiveDate: healthyCognitiveDate)
            if let projDate = projection.projectedCompletionDate {
                let days = Calendar.current.dateComponents([.day], from: birthDate, to: projDate).day ?? 0
                let weekIdx = max(0, days / 7)
                markers.append((title: goal.title, weekIndex: weekIdx, isProjected: true, priority: goal.priority))
            }
        }

        return markers
    }
}
