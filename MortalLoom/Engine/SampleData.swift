import Foundation

enum SampleData {

    // MARK: - Profile

    static let profile = HealthProfile(
        birthDate: "1980-03-15",
        biologicalSex: .male,
        lifestyle: LifestyleData(
            smokingStatus: .never,
            exerciseMinutesPerWeek: 180,
            sleepHoursPerNight: 7.5,
            dietQuality: .good,
            stressLevel: .moderate,
            bmi: 23.4
        )
    )

    // MARK: - Date Helpers

    private static func dateStr(daysAgo: Int) -> String {
        DateFormatting.dateString(daysAgo: daysAgo)
    }

    private static func seededRandom(_ seed: Int, min: Double, max: Double) -> Double {
        // Deterministic pseudo-random for reproducible sample data
        let x = sin(Double(seed) * 12.9898) * 43758.5453
        let frac = x - floor(x)
        return min + frac * (max - min)
    }

    // MARK: - Lookup sets for correlation data generation

    private static let alcoholDateSet: Set<String> = {
        Set(alcoholDrinks.filter { $0.abv > 1.0 }.map(\.date))
    }()

    private static let nicotineDateSet: Set<String> = {
        Set(nicotineEntries.map(\.date))
    }()

    // MARK: - Alcohol (90 days, realistic patterns)
    // ~3-4 drinking days per week, mix of beer and cocktails

    static let alcoholDrinks: [AlcoholDrink] = {
        var drinks: [AlcoholDrink] = []
        for day in 0..<90 {
            let date = dateStr(daysAgo: day)
            let dayOfWeek = Calendar.current.component(.weekday, from:
                Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date())

            // Drink more on Fri(6), Sat(7), and some weekdays
            let drinkProbability = seededRandom(day * 7, min: 0, max: 1)
            let isWeekend = dayOfWeek == 6 || dayOfWeek == 7
            let shouldDrink = isWeekend ? drinkProbability < 0.8 : drinkProbability < 0.35

            if shouldDrink {
                // Pick drink type based on seed
                let drinkType = seededRandom(day * 13, min: 0, max: 1)
                if drinkType < 0.4 {
                    // Beer
                    let count: Double = isWeekend ? (seededRandom(day * 17, min: 0, max: 1) < 0.5 ? 2 : 1) : 1
                    drinks.append(AlcoholDrink(name: "Modelo Especial", oz: 12, abv: 4.4, count: count, date: date))
                } else if drinkType < 0.65 {
                    // Guinness
                    drinks.append(AlcoholDrink(name: "Nitro Guinness", oz: 14.9, abv: 4.2, count: 1, date: date))
                } else if drinkType < 0.85 {
                    // Old Fashioned
                    drinks.append(AlcoholDrink(name: "Old Fashioned", oz: 2, abv: 40, count: 1, date: date))
                } else {
                    // N/A beer day
                    drinks.append(AlcoholDrink(name: "Guinness 0", oz: 14.9, abv: 0.4, count: 1, date: date))
                }

                // Sometimes a second different drink on weekends
                if isWeekend && seededRandom(day * 23, min: 0, max: 1) < 0.3 {
                    drinks.append(AlcoholDrink(name: "Old Fashioned", oz: 2, abv: 40, count: 1, date: date))
                }
            }
        }
        return drinks
    }()

    // MARK: - Nicotine (90 days, occasional use)

    static let nicotineEntries: [NicotineEntry] = {
        var entries: [NicotineEntry] = []
        for day in 0..<90 {
            let date = dateStr(daysAgo: day)
            let prob = seededRandom(day * 31, min: 0, max: 1)
            // Use nicotine pouch ~40% of days
            if prob < 0.4 {
                let count = seededRandom(day * 37, min: 0, max: 1) < 0.3 ? 2 : 1
                entries.append(NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: count, date: date))
            } else if prob < 0.5 {
                entries.append(NicotineEntry(product: "Lucy 4mg", mgPerUnit: 4, count: 1, date: date))
            }
        }
        return entries
    }()

    // MARK: - Presets

    static let alcoholPresets = AlcoholPreset.defaults

    static let nicotinePresets: [NicotinePreset] = NicotinePreset.defaults

    // MARK: - Body Entries (90 days of weight, some with body fat)

    static let bodyEntries: [BodyEntry] = {
        var entries: [BodyEntry] = []
        // Weight trend: started at 162, gradually down to ~154 over 90 days
        for day in stride(from: 89, through: 0, by: -1) {
            let date = dateStr(daysAgo: day)
            // Not every day has a measurement — roughly every 2-3 days
            if Int(seededRandom(day * 41, min: 0, max: 10)) % 3 == 0 {
                let progress = Double(89 - day) / 89.0
                let baseWeight = 162.0 - (progress * 8.0) // 162 -> 154
                let noise = seededRandom(day * 43, min: -1.0, max: 1.0)
                let weight = (baseWeight + noise).rounded(to: 1)

                // Body fat measured less frequently
                let bodyFat: Double? = Int(seededRandom(day * 47, min: 0, max: 10)) % 5 == 0
                    ? (17.0 - progress * 2.5 + seededRandom(day * 53, min: -0.5, max: 0.5)).rounded(to: 1)
                    : nil

                entries.append(BodyEntry(date: date, weightLbs: weight, bodyFatPct: bodyFat))
            }
        }
        return entries
    }()

    // MARK: - Health Metrics (90 days — HRV, heart rate, steps, etc.)
    // HRV is lower on drinking days, heart rate is higher on nicotine days

    static let healthMetrics: [HealthMetricEntry] = {
        var metrics: [HealthMetricEntry] = []
        for day in 0..<90 {
            let date = dateStr(daysAgo: day)
            let isDrinkingDay = alcoholDateSet.contains(date)
            let isNicotineDay = nicotineDateSet.contains(date)

            // HRV: baseline ~42ms, lower after drinking (~35ms), higher on clean days (~48ms)
            let hrvBase: Double = isDrinkingDay ? 35.0 : 45.0
            let hrv = (hrvBase + seededRandom(day * 59, min: -5, max: 5)).rounded(to: 1)

            // Heart rate: baseline ~68bpm, higher on nicotine days (~74bpm)
            let hrBase: Double = isNicotineDay ? 74.0 : 68.0
            let hr = (hrBase + seededRandom(day * 61, min: -3, max: 3)).rounded(to: 1)

            // Resting heart rate: baseline ~58bpm, slightly higher with nicotine
            let rhrBase: Double = isNicotineDay ? 61.0 : 57.0
            let rhr = (rhrBase + seededRandom(day * 67, min: -2, max: 2)).rounded(to: 1)

            // Steps: 6000-12000, higher on exercise days
            let stepsBase = seededRandom(day * 71, min: 5000, max: 13000)
            let steps = stepsBase.rounded(to: 0)

            // Active energy: correlated with steps
            let energy = (steps * 0.04 + seededRandom(day * 73, min: -50, max: 50)).rounded(to: 0)

            // Exercise minutes: 0-90, some days more active
            let exercise = seededRandom(day * 79, min: 0, max: 1) < 0.6
                ? seededRandom(day * 83, min: 20, max: 60).rounded(to: 0)
                : seededRandom(day * 87, min: 0, max: 15).rounded(to: 0)

            // Flights climbed: 0-20
            let flights = seededRandom(day * 89, min: 2, max: 18).rounded(to: 0)

            // VO2 Max: measured infrequently, slight upward trend
            let progress = Double(89 - day) / 89.0
            let vo2: Double? = Int(seededRandom(day * 91, min: 0, max: 10)) % 8 == 0
                ? (42.0 + progress * 2.0 + seededRandom(day * 93, min: -1, max: 1)).rounded(to: 1)
                : nil

            // SpO2: mostly 97-99%
            let spo2: Double? = Int(seededRandom(day * 97, min: 0, max: 10)) % 3 == 0
                ? (97.0 + seededRandom(day * 101, min: 0, max: 2)).rounded(to: 1)
                : nil

            // Respiratory rate: 13-18 breaths/min
            let resp: Double? = Int(seededRandom(day * 103, min: 0, max: 10)) % 2 == 0
                ? (15.0 + seededRandom(day * 107, min: -2, max: 2)).rounded(to: 1)
                : nil

            // Sleep: baseline ~7.5h, worse after drinking (~6.5h), better on clean days (~7.8h)
            let sleepBase: Double = isDrinkingDay ? 6.3 : 7.6
            let sleepHrs = (sleepBase + seededRandom(day * 109, min: -0.8, max: 0.8)).rounded(to: 1)

            // Sleep stages: deep ~18%, REM ~22%, core ~60% of total
            let deepPct = isDrinkingDay ? 0.12 : 0.20
            let remPct = isDrinkingDay ? 0.15 : 0.23
            let deepHrs = (sleepHrs * deepPct + seededRandom(day * 111, min: -0.2, max: 0.2)).rounded(to: 2)
            let remHrs = (sleepHrs * remPct + seededRandom(day * 113, min: -0.2, max: 0.2)).rounded(to: 2)
            let coreHrs = (sleepHrs - deepHrs - remHrs).rounded(to: 2)

            // Cardio recovery: ~25 bpm drop, worse with nicotine
            let recoveryBase: Double = isNicotineDay ? 20.0 : 28.0
            let cardioRec: Double? = Int(seededRandom(day * 115, min: 0, max: 10)) % 5 == 0
                ? (recoveryBase + seededRandom(day * 117, min: -5, max: 5)).rounded(to: 1)
                : nil

            // Walking speed: ~1.2 m/s average
            let walkSpd: Double? = Int(seededRandom(day * 119, min: 0, max: 10)) % 2 == 0
                ? (1.2 + seededRandom(day * 121, min: -0.15, max: 0.15)).rounded(to: 2)
                : nil

            // Walking distance: correlated with steps
            let walkDist = (steps * 0.0007 + seededRandom(day * 123, min: -0.3, max: 0.3)).rounded(to: 2)

            // Gait: asymmetry ~3%, double support ~25%
            let walkAsym: Double? = Int(seededRandom(day * 125, min: 0, max: 10)) % 3 == 0
                ? (3.0 + seededRandom(day * 127, min: -1.5, max: 1.5)).rounded(to: 1)
                : nil
            let walkDS: Double? = Int(seededRandom(day * 129, min: 0, max: 10)) % 3 == 0
                ? (25.0 + seededRandom(day * 131, min: -3, max: 3)).rounded(to: 1)
                : nil

            // Stair speeds (m/s)
            let stairUp: Double? = Int(seededRandom(day * 133, min: 0, max: 10)) % 4 == 0
                ? (0.8 + seededRandom(day * 135, min: -0.1, max: 0.1)).rounded(to: 2)
                : nil
            let stairDn: Double? = Int(seededRandom(day * 137, min: 0, max: 10)) % 4 == 0
                ? (0.9 + seededRandom(day * 139, min: -0.1, max: 0.1)).rounded(to: 2)
                : nil

            // Walking HR average
            let walkHR: Double? = Int(seededRandom(day * 141, min: 0, max: 10)) % 2 == 0
                ? (105.0 + seededRandom(day * 143, min: -8, max: 8)).rounded(to: 1)
                : nil

            // Stand time: 30-120 minutes
            let standMins = (seededRandom(day * 145, min: 30, max: 120)).rounded(to: 0)

            // Basal energy: ~1600-1800 kcal
            let basalE = (seededRandom(day * 147, min: 1550, max: 1850)).rounded(to: 0)

            // Breathing disturbances: mostly low (0-5/hr), higher after drinking
            let bdBase: Double = isDrinkingDay ? 6.0 : 2.0
            let bd: Double? = Int(seededRandom(day * 149, min: 0, max: 10)) % 3 == 0
                ? (bdBase + seededRandom(day * 151, min: -1.5, max: 3)).rounded(to: 1)
                : nil

            // Daylight: 15-90 minutes
            let daylight: Double? = Int(seededRandom(day * 153, min: 0, max: 10)) % 2 == 0
                ? (seededRandom(day * 155, min: 10, max: 90)).rounded(to: 0)
                : nil

            metrics.append(HealthMetricEntry(
                date: date,
                heartRate: hr,
                restingHeartRate: rhr,
                hrv: hrv,
                oxygenSaturation: spo2,
                respiratoryRate: resp,
                vo2Max: vo2,
                steps: steps,
                activeEnergy: energy,
                exerciseMinutes: exercise,
                flightsClimbed: flights,
                sleepHours: sleepHrs,
                sleepDeepHours: max(0, deepHrs),
                sleepRemHours: max(0, remHrs),
                sleepCoreHours: max(0, coreHrs),
                cardioRecovery: cardioRec,
                walkingSpeed: walkSpd,
                walkingDistance: max(0, walkDist),
                walkingAsymmetry: walkAsym,
                walkingDoubleSupport: walkDS,
                stairSpeedUp: stairUp,
                stairSpeedDown: stairDn,
                walkingHRAverage: walkHR,
                standMinutes: standMins,
                basalEnergy: basalE,
                breathingDisturbances: bd,
                daylightMinutes: daylight
            ))
        }
        return metrics
    }()

    // MARK: - Blood Tests (3 tests over 6 months)

    static let bloodTests: [BloodTest] = [
        BloodTest(date: dateStr(daysAgo: 180), markers: [
            "glucose": 92, "bun": 14, "creatinine": 1.0, "egfr": 105,
            "cholesterol": 195, "hdl": 52, "ldl": 115, "triglycerides": 140,
            "apoB": 95,
            "wbc": 6.2, "rbc": 4.8, "hemoglobin": 15.2, "hematocrit": 44.5, "platelets": 245,
            "tsh": 2.1,
            "na": 140, "k": 4.2, "ci": 102, "co2": 26,
            "calcium": 9.5, "protein": 7.1, "albumin": 4.3, "globulin": 2.8,
            "a_g_ratio": 1.5, "bilirubin": 0.8, "alk_phos": 65, "sgot_ast": 24, "alt": 28,
            "hba1c": 5.3, "homocysteine": 10.5,
        ]),
        BloodTest(date: dateStr(daysAgo: 90), markers: [
            "glucose": 88, "bun": 13, "creatinine": 0.95, "egfr": 108,
            "cholesterol": 185, "hdl": 55, "ldl": 105, "triglycerides": 125,
            "apoB": 88,
            "wbc": 5.8, "rbc": 4.9, "hemoglobin": 15.5, "hematocrit": 45.0, "platelets": 238,
            "tsh": 1.9,
            "na": 141, "k": 4.0, "ci": 101, "co2": 27,
            "calcium": 9.6, "protein": 7.2, "albumin": 4.4, "globulin": 2.8,
            "a_g_ratio": 1.6, "bilirubin": 0.7, "alk_phos": 62, "sgot_ast": 22, "alt": 25,
            "hba1c": 5.2, "homocysteine": 9.8,
        ]),
        BloodTest(date: dateStr(daysAgo: 14), markers: [
            "glucose": 85, "bun": 12, "creatinine": 0.9, "egfr": 112,
            "cholesterol": 178, "hdl": 58, "ldl": 98, "triglycerides": 110,
            "apoB": 82,
            "wbc": 5.5, "rbc": 5.0, "hemoglobin": 15.8, "hematocrit": 46.2, "platelets": 252,
            "tsh": 1.8,
            "na": 139, "k": 4.1, "ci": 100, "co2": 25,
            "calcium": 9.7, "protein": 7.0, "albumin": 4.5, "globulin": 2.5,
            "a_g_ratio": 1.8, "bilirubin": 0.6, "alk_phos": 58, "sgot_ast": 20, "alt": 22,
            "hba1c": 5.1, "homocysteine": 9.2,
        ]),
    ]

    // MARK: - Blood Donations (mixed products across the past year)

    static let bloodDonations: [BloodDonation] = [
        BloodDonation(donationType: .wholeBlood, volumeML: 500, date: dateStr(daysAgo: 300), location: "Community Blood Drive"),
        BloodDonation(donationType: .plasma, volumeML: 690, date: dateStr(daysAgo: 220), location: "Downtown Donor Center"),
        BloodDonation(donationType: .wholeBlood, volumeML: 500, date: dateStr(daysAgo: 160), location: "Downtown Donor Center"),
        BloodDonation(donationType: .platelets, volumeML: 300, date: dateStr(daysAgo: 95), location: "Downtown Donor Center"),
        BloodDonation(donationType: .wholeBlood, volumeML: 480, date: dateStr(daysAgo: 40), location: "Community Blood Drive"),
    ]

    // MARK: - Eye Exams (2 exams, 1 year apart)

    static let eyeExams: [EyeExam] = [
        EyeExam(date: dateStr(daysAgo: 400),
                leftSphere: -2.25, leftCylinder: -0.75, leftAxis: 170,
                rightSphere: -2.00, rightCylinder: -0.50, rightAxis: 10),
        EyeExam(date: dateStr(daysAgo: 35),
                leftSphere: -2.50, leftCylinder: -0.75, leftAxis: 172,
                rightSphere: -2.25, rightCylinder: -0.50, rightAxis: 8),
    ]

    // MARK: - Epigenetic Tests (2 tests, showing improvement)

    static let epigeneticTests: [EpigeneticTest] = [
        EpigeneticTest(date: dateStr(daysAgo: 365),
                       chronologicalAge: 44.0, biologicalAge: 42.5,
                       paceOfAging: 0.92,
                       organScores: [
                        "Heart": 41.0, "Liver": 43.5, "Kidney": 42.0,
                        "Brain": 44.0, "Immune": 40.5, "Metabolic": 43.0,
                       ]),
        EpigeneticTest(date: dateStr(daysAgo: 30),
                       chronologicalAge: 45.0, biologicalAge: 42.0,
                       paceOfAging: 0.88,
                       organScores: [
                        "Heart": 40.0, "Liver": 42.0, "Kidney": 41.5,
                        "Brain": 43.5, "Immune": 39.0, "Metabolic": 42.0,
                       ]),
    ]

    // MARK: - Goal Hierarchy (post-reframe)
    //
    // After the 2026-04-11 Goal Alignment Reframing, the app's data model is
    // a three-tier tree: North Star (apex) → Life Pillars (sub-apex) → concrete
    // Standard goals. Habits attach to any level. Reflection-shaped check-ins
    // carry alignment ratings, blockers, and commitments.
    //
    // This sample set populates the full hierarchy plus ~6 months of weekly
    // reflections so Reports, Reflections, and the alignment trend chart
    // have realistic-looking content in demo/screenshot builds.

    // Stable IDs so parent/child links don't change across builds.
    static let apexId = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let healthPillarId = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    static let craftPillarId = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
    static let legacyPillarId = UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!

    static let goals: [Goal] = {
        // MARK: - Apex (North Star)

        let apexReflections: [GoalCheckIn] = [
            GoalCheckIn(
                date: dateStr(daysAgo: 168),
                note: "The book is why I get up before the kids wake. The body is what keeps me able to write it.",
                alignmentRating: 6,
                commitments: ["Write 4 mornings this week", "No wine on weeknights"],
                promptAnswered: "Why does this matter to you?"
            ),
            GoalCheckIn(
                date: dateStr(daysAgo: 140),
                note: "Hit every morning writing session. Skipped one run. Commitments matter — these aren't aspirational any more.",
                alignmentRating: 8,
                commitments: ["Keep the morning cadence", "Run 3x this week"],
                promptAnswered: "What's the most important thing you've done this week toward your goals?"
            ),
            GoalCheckIn(
                date: dateStr(daysAgo: 112),
                note: "Sick for half the week, everything slipped. Noticed I'm fine with skipping runs but feel guilty about skipping writing.",
                alignmentRating: 5,
                blockers: ["Flu", "Travel next week"],
                commitments: ["Pack running shoes", "One hour of writing minimum"],
                promptAnswered: "What's holding you back right now?"
            ),
            GoalCheckIn(
                date: dateStr(daysAgo: 84),
                note: "Finished chapter 4 ahead of schedule. Marathon training is landing.",
                alignmentRating: 9,
                commitments: ["Don't coast — start outlining chapter 5"],
                promptAnswered: "What surprised you about your alignment this month?"
            ),
            GoalCheckIn(
                date: dateStr(daysAgo: 56),
                note: "Piano has been stalled for weeks. Accepting it's not an alignment-priority right now.",
                alignmentRating: 7,
                blockers: ["Piano is a distraction — should I archive it?"],
                commitments: ["Decide whether to keep piano active"],
                promptAnswered: "What would you retire from your goals if you could?"
            ),
            GoalCheckIn(
                date: dateStr(daysAgo: 28),
                note: "Book is past the half-way point. Health is the best it's been in years. This is what alignment feels like.",
                alignmentRating: 9,
                commitments: ["Keep the rhythm — don't add new things"],
                promptAnswered: "What's the most important thing you've done this week toward your goals?"
            ),
            GoalCheckIn(
                date: dateStr(daysAgo: 7),
                note: "Still on track. Noticed stress creeping in around book deadline — want to protect sleep.",
                alignmentRating: 8,
                commitments: ["8 hours of sleep 5 nights this week", "One hard run"],
                promptAnswered: "What could you clear from your calendar this week?"
            ),
        ]

        let apex = Goal(
            id: apexId,
            title: "Live healthy long enough to finish the work that matters",
            notes: "Write the books, raise the family, stay strong enough to enjoy it all.",
            createdDate: dateStr(daysAgo: 200),
            checkIns: apexReflections,
            checkInIntervalDays: 14,
            status: .active,
            priority: .high,
            horizon: .lifetime,
            category: .legacy,
            goalType: .apex
        )

        // MARK: - Life Pillars (sub-apex)

        let healthPillar = Goal(
            id: healthPillarId,
            title: "Strong, resilient body",
            notes: "The runway extender. Sleep, movement, substances under control.",
            createdDate: dateStr(daysAgo: 195),
            checkIns: [
                GoalCheckIn(
                    date: dateStr(daysAgo: 120),
                    note: "Sleep is the weakest link. Exercise is solid, diet drifts on travel weeks.",
                    alignmentRating: 6,
                    promptAnswered: "Which life pillar has had the most attention this month?"
                ),
                GoalCheckIn(
                    date: dateStr(daysAgo: 60),
                    note: "Back on 7.5 hours, running 3x/week, almost no alcohol during the week.",
                    alignmentRating: 8
                ),
            ],
            checkInIntervalDays: 14,
            status: .active,
            priority: .high,
            parentId: apexId,
            horizon: .lifetime,
            category: .health,
            goalType: .subApex
        )

        let craftPillar = Goal(
            id: craftPillarId,
            title: "Deep practice at my craft",
            notes: "Writing, thinking, shipping work I'm proud of.",
            createdDate: dateStr(daysAgo: 195),
            checkIns: [
                GoalCheckIn(
                    date: dateStr(daysAgo: 90),
                    note: "Morning writing cadence unlocked everything. Protect it.",
                    alignmentRating: 9
                ),
            ],
            checkInIntervalDays: 14,
            status: .active,
            priority: .high,
            parentId: apexId,
            horizon: .lifetime,
            category: .creative,
            goalType: .subApex
        )

        let legacyPillar = Goal(
            id: legacyPillarId,
            title: "Present for the family",
            notes: "Show up — meals, bedtime, weekend adventures.",
            createdDate: dateStr(daysAgo: 195),
            checkIns: [
                GoalCheckIn(
                    date: dateStr(daysAgo: 45),
                    note: "Work creep is the main threat here. Evenings are sacred.",
                    alignmentRating: 7,
                    blockers: ["Late-day meetings"]
                ),
            ],
            checkInIntervalDays: 14,
            status: .active,
            priority: .medium,
            parentId: apexId,
            horizon: .lifetime,
            category: .family,
            goalType: .subApex
        )

        // MARK: - Standard Goals (concrete, dated, nested under pillars)

        // Book — under craft pillar, on track
        let bookGoal = Goal(
            title: "Publish a book",
            notes: "Technical book on distributed systems",
            createdDate: dateStr(daysAgo: 150),
            targetDate: dateStr(daysAgo: -215), // ~7 months from today
            checkIns: [
                GoalCheckIn(date: dateStr(daysAgo: 140), progressPct: 5, note: "Outlined chapters"),
                GoalCheckIn(date: dateStr(daysAgo: 112), progressPct: 12, note: "First two chapters drafted"),
                GoalCheckIn(date: dateStr(daysAgo: 84), progressPct: 22, note: "Chapters 3-4 complete"),
                GoalCheckIn(date: dateStr(daysAgo: 56), progressPct: 32, note: "Chapter 5 + diagrams"),
                GoalCheckIn(date: dateStr(daysAgo: 28), progressPct: 48, note: "Past the halfway point"),
                GoalCheckIn(date: dateStr(daysAgo: 7), progressPct: 55, note: "Chapter 7 drafted"),
            ],
            milestones: [
                GoalMilestone(title: "Outline complete", completed: true, completedDate: dateStr(daysAgo: 140)),
                GoalMilestone(title: "First draft (10 chapters)", completed: false),
                GoalMilestone(title: "Technical review", completed: false),
                GoalMilestone(title: "Final edits", completed: false),
                GoalMilestone(title: "Submit to publisher", completed: false),
            ],
            checkInIntervalDays: 7,
            priority: .high,
            parentId: craftPillarId,
            horizon: .oneYear,
            category: .creative,
            goalType: .standard
        )

        // Marathon — under health pillar, slightly overdue check-in
        let marathonGoal = Goal(
            title: "Run a marathon",
            notes: "Target: Portland Marathon",
            createdDate: dateStr(daysAgo: 90),
            targetDate: dateStr(daysAgo: -120), // ~4 months out
            checkIns: [
                GoalCheckIn(date: dateStr(daysAgo: 84), progressPct: 10, note: "Started C25K"),
                GoalCheckIn(date: dateStr(daysAgo: 56), progressPct: 25, note: "Can run 10K now"),
                GoalCheckIn(date: dateStr(daysAgo: 28), progressPct: 38, note: "Half marathon distance reached"),
                GoalCheckIn(date: dateStr(daysAgo: 12), progressPct: 45, note: "18 mile long run"),
            ],
            milestones: [
                GoalMilestone(title: "Run 5K", completed: true, completedDate: dateStr(daysAgo: 70)),
                GoalMilestone(title: "Run 10K", completed: true, completedDate: dateStr(daysAgo: 56)),
                GoalMilestone(title: "Run half marathon", completed: true, completedDate: dateStr(daysAgo: 28)),
                GoalMilestone(title: "Run 30K", completed: false),
                GoalMilestone(title: "Complete marathon", completed: false),
            ],
            checkInIntervalDays: 7,
            priority: .high,
            parentId: healthPillarId,
            horizon: .oneYear,
            category: .health,
            goalType: .standard
        )

        // Piano — stalled, surfaces in stagnation signals
        // Bug fix (audit finding): target was -180 (past) paired with
        // createdDate 200, which StagnationEngine reads as "759 days overdue".
        // Keep a stale check-in cadence but set a realistic future target.
        let pianoGoal = Goal(
            title: "Learn Chopin Nocturne Op.9 No.2",
            notes: "A concrete piece I can actually play end-to-end.",
            createdDate: dateStr(daysAgo: 200),
            targetDate: dateStr(daysAgo: -60), // 2 months from today
            checkIns: [
                GoalCheckIn(date: dateStr(daysAgo: 190), progressPct: 5, note: "Bought keyboard, started lessons"),
                GoalCheckIn(date: dateStr(daysAgo: 150), progressPct: 15, note: "Scales and basic chords"),
                GoalCheckIn(date: dateStr(daysAgo: 90), progressPct: 20, note: "First simple piece learned"),
            ],
            milestones: [
                GoalMilestone(title: "Learn scales and chords", completed: true, completedDate: dateStr(daysAgo: 150)),
                GoalMilestone(title: "Play first complete piece", completed: true, completedDate: dateStr(daysAgo: 90)),
                GoalMilestone(title: "Learn Chopin Nocturne Op.9 No.2", completed: false),
                GoalMilestone(title: "Perform for someone", completed: false),
            ],
            checkInIntervalDays: 14,
            priority: .low,
            parentId: craftPillarId,
            horizon: .oneYear,
            category: .creative,
            goalType: .standard
        )

        // Garden — completed, shows recent win
        let gardenGoal = Goal(
            title: "Build a raised garden bed",
            notes: "Cedar 4x8, with drip irrigation",
            createdDate: dateStr(daysAgo: 90),
            completedDate: dateStr(daysAgo: 15),
            checkIns: [
                GoalCheckIn(date: dateStr(daysAgo: 80), progressPct: 20, note: "Materials purchased"),
                GoalCheckIn(date: dateStr(daysAgo: 50), progressPct: 60, note: "Frame built"),
                GoalCheckIn(date: dateStr(daysAgo: 30), progressPct: 80, note: "Soil and irrigation in"),
                GoalCheckIn(date: dateStr(daysAgo: 15), progressPct: 100, note: "Planted first seeds!"),
            ],
            milestones: [
                GoalMilestone(title: "Buy lumber and hardware", completed: true, completedDate: dateStr(daysAgo: 80)),
                GoalMilestone(title: "Build frame", completed: true, completedDate: dateStr(daysAgo: 50)),
                GoalMilestone(title: "Install irrigation", completed: true, completedDate: dateStr(daysAgo: 30)),
                GoalMilestone(title: "Fill with soil and plant", completed: true, completedDate: dateStr(daysAgo: 15)),
            ],
            checkInIntervalDays: 7,
            status: .completed,
            priority: .medium,
            parentId: legacyPillarId,
            horizon: .oneYear,
            category: .family,
            goalType: .standard
        )

        return [apex, healthPillar, craftPillar, legacyPillar, bookGoal, marathonGoal, pianoGoal, gardenGoal]
    }()

    // MARK: - Habits (post-reframe daily loop)

    static let habits: [Habit] = {
        // Morning writing — under craft pillar, strong ~28-day streak
        let writingCompletions: [HabitCompletion] = (0..<84).compactMap { day in
            // Skip weekends and an occasional miss for realism.
            let weekday = Calendar.current.component(.weekday, from:
                Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date())
            let isWeekend = weekday == 1 || weekday == 7
            if isWeekend { return nil }
            // Miss every ~13 days
            if day % 13 == 5 { return nil }
            return HabitCompletion(date: dateStr(daysAgo: day), count: 1, note: "")
        }
        let writingHabit = Habit(
            name: "Morning writing",
            detail: "45 minutes before the kids wake up",
            icon: "pencil.and.scribble",
            colorHex: "#7F5AF0",
            category: .creative,
            kind: .positive,
            cadence: HabitCadence(period: .daily, target: 1),
            parentGoalId: craftPillarId,
            createdDate: dateStr(daysAgo: 90),
            completions: writingCompletions
        )

        // Run — under health pillar, 3x/week
        let runCompletions: [HabitCompletion] = (0..<84).compactMap { day in
            // ~3 days per week: Tue, Thu, Sat
            let weekday = Calendar.current.component(.weekday, from:
                Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date())
            let isRunDay = weekday == 3 || weekday == 5 || weekday == 7
            if !isRunDay { return nil }
            // Miss one every ~10 days
            if day % 23 == 7 { return nil }
            return HabitCompletion(date: dateStr(daysAgo: day), count: 1, note: "")
        }
        let runHabit = Habit(
            name: "Run",
            detail: "30+ minutes, easy pace unless track day",
            icon: "figure.run",
            colorHex: "#22C55E",
            category: .health,
            kind: .positive,
            cadence: HabitCadence(period: .weekly, target: 3),
            parentGoalId: healthPillarId,
            createdDate: dateStr(daysAgo: 90),
            completions: runCompletions
        )

        // Meditate — wellness, daily, recently broken
        let meditateCompletions: [HabitCompletion] = (10..<50).compactMap { day in
            if day % 3 == 0 { return nil } // patchy
            return HabitCompletion(date: dateStr(daysAgo: day), count: 1, note: "")
        }
        let meditateHabit = Habit(
            name: "Meditate",
            detail: "10 minutes, Waking Up app",
            icon: "leaf.fill",
            colorHex: "#06B6D4",
            category: .wellness,
            kind: .positive,
            cadence: HabitCadence(period: .daily, target: 1),
            parentGoalId: healthPillarId,
            createdDate: dateStr(daysAgo: 120),
            completions: meditateCompletions
        )

        // No wine on weeknights — negative/avoid habit, mostly holding
        let noWineCompletions: [HabitCompletion] = (0..<60).compactMap { day in
            let weekday = Calendar.current.component(.weekday, from:
                Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date())
            let isWeeknight = weekday >= 2 && weekday <= 6
            if !isWeeknight { return nil }
            // ~90% success
            if day % 11 == 3 { return nil }
            return HabitCompletion(date: dateStr(daysAgo: day), count: 1, note: "")
        }
        let noWineHabit = Habit(
            name: "No wine on weeknights",
            detail: "Weekdays only — weekends are fair game",
            icon: "wineglass",
            colorHex: "#F59E0B",
            category: .health,
            kind: .negative,
            cadence: HabitCadence(period: .daily, target: 1),
            parentGoalId: healthPillarId,
            createdDate: dateStr(daysAgo: 75),
            completions: noWineCompletions
        )

        return [writingHabit, runHabit, meditateHabit, noWineHabit]
    }()

    // MARK: - Genome Variants (sample 23andMe-format data)

    static let genomeFileContent = """
    # rsid\tchromosome\tposition\tgenotype
    rs12913832\t15\t28365618\tGG
    rs1805007\t16\t89919709\tCC
    rs4988235\t2\t136608646\tAG
    rs1799971\t6\t154360797\tAA
    rs53576\t3\t8804371\tGG
    rs1800497\t11\t113400106\tCT
    rs7294919\t12\t97514060\tAG
    i3003137\t7\t17284577\tAC
    rs429358\t19\t45411941\tTT
    rs7412\t19\t45412079\tCC
    """

    static let genomeVariants: [GenomeVariant] = GenomeParser.parse(genomeFileContent).variants

    // MARK: - Ancestry DNA format sample

    static let ancestryDNAFileContent = """
    #AncestryDNA raw data download
    #rsid,chromosome,position,allele1,allele2
    rs12913832,15,28365618,G,G
    rs1805007,16,89919709,C,C
    rs4988235,2,136608646,A,G
    """

    // MARK: - Full AppData

    static let fullAppData = AppData(
        profile: profile,
        alcoholDrinks: alcoholDrinks,
        alcoholPresets: alcoholPresets,
        nicotineEntries: nicotineEntries,
        nicotinePresets: nicotinePresets,
        bloodTests: bloodTests,
        bloodDonations: bloodDonations,
        eyeExams: eyeExams,
        epigeneticTests: epigeneticTests,
        bodyEntries: bodyEntries,
        healthMetrics: healthMetrics,
        goals: goals,
        habits: habits
    )
}

// MARK: - Double Rounding Helper

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
