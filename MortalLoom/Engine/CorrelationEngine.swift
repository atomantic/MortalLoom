import Foundation

struct CorrelationDataPoint: Sendable {
    let testDate: Date
    let avgDailySteps: Double
    let markers: [String: Double]
}

enum CorrelationEngine {

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
}
