import Foundation

struct CorrelationDataPoint: Sendable {
    let testDate: Date
    let avgDailySteps: Double
    let avgDailyDistance: Double?
    let avgExerciseMinutes: Double?
    let avgHRV: Double?
    let avgSleepHours: Double?
    let avgDeepSleepPct: Double?
    let avgStandMinutes: Double?
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

            var totalSteps = 0.0, totalDist = 0.0, totalExercise = 0.0
            var totalHRV = 0.0, totalSleep = 0.0, totalDeepPct = 0.0, totalStand = 0.0
            var count = 0.0
            var distCount = 0.0, exerciseCount = 0.0, hrvCount = 0.0
            var sleepCount = 0.0, deepCount = 0.0, standCount = 0.0

            for dayOffset in 1...windowDays {
                guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: testDate) else { continue }
                let dayStr = DateFormatting.dateString(day)
                guard let metrics = metricsByDate[dayStr]?.first else { continue }

                totalSteps += metrics.steps ?? 0
                count += 1

                if let d = metrics.walkingDistance { totalDist += d; distCount += 1 }
                if let e = metrics.exerciseMinutes { totalExercise += e; exerciseCount += 1 }
                if let h = metrics.hrv { totalHRV += h; hrvCount += 1 }
                if let s = metrics.sleepHours { totalSleep += s; sleepCount += 1 }
                if let deep = metrics.sleepDeepHours, let total = metrics.sleepHours, total > 0 {
                    totalDeepPct += (deep / total) * 100
                    deepCount += 1
                }
                if let st = metrics.standMinutes { totalStand += st; standCount += 1 }
            }

            guard count > 0 else { return nil }

            return CorrelationDataPoint(
                testDate: testDate,
                avgDailySteps: totalSteps / count,
                avgDailyDistance: distCount > 0 ? totalDist / distCount : nil,
                avgExerciseMinutes: exerciseCount > 0 ? totalExercise / exerciseCount : nil,
                avgHRV: hrvCount > 0 ? totalHRV / hrvCount : nil,
                avgSleepHours: sleepCount > 0 ? totalSleep / sleepCount : nil,
                avgDeepSleepPct: deepCount > 0 ? totalDeepPct / deepCount : nil,
                avgStandMinutes: standCount > 0 ? totalStand / standCount : nil,
                markers: test.markers
            )
        }
    }
}
