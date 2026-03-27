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
                    let count = isWeekend ? (seededRandom(day * 17, min: 0, max: 1) < 0.5 ? 2 : 1) : 1
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

    static let nicotinePresets: [NicotinePreset] = [
        NicotinePreset(name: "Zyn 6mg", mgPerUnit: 6),
        NicotinePreset(name: "Lucy 4mg", mgPerUnit: 4),
        NicotinePreset(name: "Zyn 3mg", mgPerUnit: 3),
    ]

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
                flightsClimbed: flights
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

    // MARK: - Goals

    static let goals: [Goal] = {
        let today = DateFormatting.todayString()

        // Goal 1: Publish a book — 35% done, on track
        let bookGoal = Goal(
            title: "Publish a book",
            notes: "Technical book on distributed systems",
            createdDate: dateStr(daysAgo: 120),
            targetDate: dateStr(daysAgo: -365), // 1 year from now
            checkIns: [
                GoalCheckIn(date: dateStr(daysAgo: 110), progressPct: 5, note: "Outlined chapters"),
                GoalCheckIn(date: dateStr(daysAgo: 90), progressPct: 12, note: "First two chapters drafted"),
                GoalCheckIn(date: dateStr(daysAgo: 60), progressPct: 22, note: "Chapters 3-4 complete"),
                GoalCheckIn(date: dateStr(daysAgo: 30), progressPct: 30, note: "Hit chapter 5, added diagrams"),
                GoalCheckIn(date: dateStr(daysAgo: 5), progressPct: 35, note: "Chapter 6 draft done"),
            ],
            milestones: [
                GoalMilestone(title: "Outline complete", completed: true, completedDate: dateStr(daysAgo: 110)),
                GoalMilestone(title: "First draft (10 chapters)", completed: false),
                GoalMilestone(title: "Technical review", completed: false),
                GoalMilestone(title: "Final edits", completed: false),
                GoalMilestone(title: "Submit to publisher", completed: false),
            ],
            checkInIntervalDays: 7,
            priority: .high
        )

        // Goal 2: Run a marathon — needs check-in
        let marathonGoal = Goal(
            title: "Run a marathon",
            notes: "Target: Portland Marathon",
            createdDate: dateStr(daysAgo: 60),
            targetDate: dateStr(daysAgo: -200),
            checkIns: [
                GoalCheckIn(date: dateStr(daysAgo: 55), progressPct: 10, note: "Started C25K"),
                GoalCheckIn(date: dateStr(daysAgo: 30), progressPct: 25, note: "Can run 10K now"),
                GoalCheckIn(date: dateStr(daysAgo: 14), progressPct: 35, note: "Half marathon distance reached"),
            ],
            milestones: [
                GoalMilestone(title: "Run 5K", completed: true, completedDate: dateStr(daysAgo: 45)),
                GoalMilestone(title: "Run 10K", completed: true, completedDate: dateStr(daysAgo: 30)),
                GoalMilestone(title: "Run half marathon", completed: true, completedDate: dateStr(daysAgo: 14)),
                GoalMilestone(title: "Run 30K", completed: false),
                GoalMilestone(title: "Complete marathon", completed: false),
            ],
            checkInIntervalDays: 7,
            priority: .medium
        )

        // Goal 3: Learn piano — stalled, slipping
        let pianoGoal = Goal(
            title: "Learn to play piano",
            notes: "Classical repertoire — start with Chopin nocturnes",
            createdDate: dateStr(daysAgo: 200),
            targetDate: dateStr(daysAgo: -180),
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
            priority: .low
        )

        // Goal 4: Completed goal
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
            priority: .medium
        )

        return [bookGoal, marathonGoal, pianoGoal, gardenGoal]
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
        eyeExams: eyeExams,
        epigeneticTests: epigeneticTests,
        bodyEntries: bodyEntries,
        healthMetrics: healthMetrics,
        goals: goals
    )
}

// MARK: - Double Rounding Helper

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
