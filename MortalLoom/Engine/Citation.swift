import Foundation

// MARK: - Citation Model

/// A single peer-reviewed or authoritative source backing a health claim in the app.
/// Every quantitative recommendation, risk threshold, or reference range shown to the
/// user should trace back to one or more `Citation` entries.
struct Citation: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let authors: String
    let detail: String
    let url: String
}

// MARK: - Citation Library
//
// Single source of truth for every source cited anywhere in the UI. Reference by
// `Citation.ID` (a stable string key) so engines + views can attach citations to
// specific claims without duplicating source metadata.
//
// Adding a new claim to the app? Add the citation here first, then reference its
// `.id` from the engine/view surface that makes the claim.

enum CitationLibrary {

    // MARK: - Life Expectancy Baseline
    static let ssaLifeTable = Citation(
        id: "ssa-life-table-2021",
        title: "SSA Period Life Tables, 2021",
        authors: "U.S. Social Security Administration, Office of the Chief Actuary",
        detail: "Baseline life expectancy by age and sex used for actuarial calculations. Forms the starting point for all MortalLoom longevity estimates before lifestyle, genetic, and environmental adjustments.",
        url: "https://www.ssa.gov/oact/STATS/table4c6.html"
    )

    // MARK: - Sleep & Mortality
    static let cappuccioSleep2010 = Citation(
        id: "cappuccio-2010-sleep",
        title: "Sleep Duration and All-Cause Mortality: A Systematic Review and Meta-Analysis",
        authors: "Cappuccio FP, D'Elia L, Strazzullo P, Miller MA",
        detail: "Sleep. 2010;33(5):585-592. Meta-analysis of 1.3M participants: short sleep (<6h) associated with 12% increased mortality; long sleep (>9h) with 30% increased mortality.",
        url: "https://doi.org/10.1093/sleep/33.5.585"
    )

    static let nsfSleepDuration = Citation(
        id: "nsf-sleep-duration-2015",
        title: "National Sleep Foundation Sleep Duration Recommendations",
        authors: "Hirshkowitz M, Whiton K, Albert SM, et al.",
        detail: "Sleep Health. 2015;1(1):40-43. Adults 26-64: recommended 7-9h; older adults 65+: recommended 7-8h. Foundation of MortalLoom's optimal sleep window.",
        url: "https://doi.org/10.1016/j.sleh.2014.12.010"
    )

    static let youngApnea2008 = Citation(
        id: "young-2008-apnea",
        title: "Sleep Disordered Breathing and Mortality: Eighteen-Year Follow-up of the Wisconsin Sleep Cohort",
        authors: "Young T, Finn L, Peppard PE, et al.",
        detail: "Sleep. 2008;31(8):1071-1078. Severe sleep-disordered breathing (AHI ≥30) associated with ~3x all-cause mortality risk after adjustment. Source for MortalLoom's AHI classification thresholds and apnea longevity impact.",
        url: "https://doi.org/10.1093/sleep/31.8.1071"
    )

    // MARK: - Cardiorespiratory Fitness
    static let acsmGuidelines = Citation(
        id: "acsm-guidelines",
        title: "ACSM's Guidelines for Exercise Testing and Prescription",
        authors: "American College of Sports Medicine",
        detail: "VO2 max fitness classifications by age and sex. Standard clinical reference for cardiorespiratory fitness assessment.",
        url: "https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription"
    )

    static let coleHrr1999 = Citation(
        id: "cole-1999-hrr",
        title: "Heart-Rate Recovery Immediately After Exercise as a Predictor of Mortality",
        authors: "Cole CR, Blackstone EH, Pashkow FJ, Snader CE, Lauer MS",
        detail: "N Engl J Med. 1999;341:1351-1357. Abnormal HR recovery (<12 bpm drop in 1 min) associated with ~4x cardiovascular mortality.",
        url: "https://doi.org/10.1056/NEJM199910283411804"
    )

    static let kodamaFitness2009 = Citation(
        id: "kodama-2009-fitness",
        title: "Cardiorespiratory Fitness as a Quantitative Predictor of All-Cause Mortality",
        authors: "Kodama S, Saito K, Tanaka S, et al.",
        detail: "JAMA. 2009;301(19):2024-2035. Each 1-MET increase in cardiorespiratory fitness associated with ~15% reduction in all-cause mortality.",
        url: "https://doi.org/10.1001/jama.2009.681"
    )

    // MARK: - Gait & Walking Speed
    static let studenskiGait2011 = Citation(
        id: "studenski-2011-gait",
        title: "Gait Speed and Survival in Older Adults",
        authors: "Studenski S, Perera S, Patel K, et al.",
        detail: "JAMA. 2011;305(1):50-58. Each 0.1 m/s increase in gait speed associated with 12% lower mortality. Walking speed is sometimes called 'the 6th vital sign.'",
        url: "https://doi.org/10.1001/jama.2010.1923"
    )

    static let hausdorffFalls2001 = Citation(
        id: "hausdorff-2001-falls",
        title: "Gait Variability and Fall Risk in Community-Living Older Adults",
        authors: "Hausdorff JM, Rios DA, Edelberg HK",
        detail: "Arch Phys Med Rehabil. 2001;82(8):1050-1056. Increased stride-to-stride gait variability is a significant independent predictor of falls in older adults. Foundation for MortalLoom's gait asymmetry / double-support fall-risk score.",
        url: "https://doi.org/10.1053/apmr.2001.24893"
    )

    // MARK: - Alcohol
    static let niaaaLimits = Citation(
        id: "niaaa-limits",
        title: "NIAAA Drinking Levels Defined",
        authors: "National Institute on Alcohol Abuse and Alcoholism",
        detail: "Low-risk drinking limits: women ≤1 drink/day, ≤7/week; men ≤2 drinks/day, ≤14/week. Exceeding these thresholds significantly increases health risk.",
        url: "https://www.niaaa.nih.gov/alcohol-health/overview-alcohol-consumption/moderate-binge-drinking"
    )

    static let gbdAlcohol2018 = Citation(
        id: "gbd-2018-alcohol",
        title: "Alcohol Use and Burden for 195 Countries and Territories, 1990-2016",
        authors: "GBD 2016 Alcohol Collaborators",
        detail: "Lancet. 2018;392(10152):1015-1035. Large-scale analysis supporting that the level of alcohol consumption that minimizes health loss is zero. Used in MortalLoom's high-risk alcohol recommendation.",
        url: "https://doi.org/10.1016/S0140-6736(18)31310-2"
    )

    // MARK: - Smoking
    static let dollSmoking2004 = Citation(
        id: "doll-2004-smoking",
        title: "Mortality in Relation to Smoking: 50 Years' Observations on Male British Doctors",
        authors: "Doll R, Peto R, Boreham J, Sutherland I",
        detail: "BMJ. 2004;328:1519. Lifelong smokers lose ~10 years of life expectancy on average. Quitting before age 40 removes almost all of the excess mortality risk. Primary source for MortalLoom's smoking impact and 'quit smoking' recommendation.",
        url: "https://doi.org/10.1136/bmj.38142.554479.AE"
    )

    static let jhaSmoking2013 = Citation(
        id: "jha-2013-smoking",
        title: "21st-Century Hazards of Smoking and Benefits of Cessation in the United States",
        authors: "Jha P, Ramasundarahettige C, Landsman V, et al.",
        detail: "N Engl J Med. 2013;368:341-350. Confirms ~10 years of lost life expectancy for current smokers and large recovery in former smokers, particularly when cessation occurs before middle age.",
        url: "https://doi.org/10.1056/NEJMsa1211128"
    )

    // MARK: - BMI & Body Composition
    static let whoBmi = Citation(
        id: "who-bmi",
        title: "WHO BMI Classification",
        authors: "World Health Organization",
        detail: "Standard BMI categories: <18.5 underweight, 18.5-24.9 normal, 25-29.9 overweight, ≥30 obese. Used for longevity impact estimation.",
        url: "https://www.who.int/data/gho/data/themes/topics/topic-details/GHO/body-mass-index"
    )

    static let bmiMortality2016 = Citation(
        id: "gbmc-2016-bmi",
        title: "Body-Mass Index and All-Cause Mortality: Individual-Participant-Data Meta-Analysis of 239 Prospective Studies in Four Continents",
        authors: "Global BMI Mortality Collaboration",
        detail: "Lancet. 2016;388(10046):776-786. J-shaped relationship between BMI and mortality. BMI 20.0-25.0 has the lowest risk; severe obesity (≥35) associated with 2-3x all-cause mortality. Source for MortalLoom's BMI longevity impact.",
        url: "https://doi.org/10.1016/S0140-6736(16)30175-1"
    )

    // MARK: - Exercise
    static let whoPhysicalActivity = Citation(
        id: "who-physical-activity-2020",
        title: "WHO Guidelines on Physical Activity and Sedentary Behaviour",
        authors: "World Health Organization",
        detail: "Adults 18-64: at least 150 minutes of moderate-intensity or 75 minutes of vigorous-intensity aerobic activity per week for substantial health benefits.",
        url: "https://www.who.int/publications/i/item/9789240015128"
    )

    static let arem2015Exercise = Citation(
        id: "arem-2015-exercise",
        title: "Leisure Time Physical Activity and Mortality: A Detailed Pooled Analysis of the Dose-Response Relationship",
        authors: "Arem H, Moore SC, Patel A, et al.",
        detail: "JAMA Intern Med. 2015;175(6):959-967. Pooled cohort of 661,000 adults: meeting the 150 min/week guideline associated with ~31% lower mortality; 3-5x the guideline associated with the maximum ~39% reduction.",
        url: "https://doi.org/10.1001/jamainternmed.2015.0533"
    )

    // MARK: - Diet
    static let predimedMedDiet = Citation(
        id: "estruch-2018-predimed",
        title: "Primary Prevention of Cardiovascular Disease with a Mediterranean Diet (PREDIMED)",
        authors: "Estruch R, Ros E, Salas-Salvadó J, et al.",
        detail: "N Engl J Med. 2018;378:e34. Randomized trial of ~7,400 participants: Mediterranean diet supplemented with olive oil or nuts reduced major cardiovascular events by ~30% vs. low-fat control. Primary evidence behind MortalLoom's 'Mediterranean or plant-rich diet' recommendation.",
        url: "https://doi.org/10.1056/NEJMoa1800389"
    )

    static let gbdDiet2019 = Citation(
        id: "gbd-2019-diet",
        title: "Health Effects of Dietary Risks in 195 Countries, 1990-2017",
        authors: "GBD 2017 Diet Collaborators",
        detail: "Lancet. 2019;393(10184):1958-1972. Suboptimal diet responsible for ~1 in 5 deaths globally. Diets high in whole grains, fruits, vegetables, nuts, and seeds while low in sodium and processed meat are associated with the lowest mortality.",
        url: "https://doi.org/10.1016/S0140-6736(19)30041-8"
    )

    // MARK: - Stress & Longevity
    static let epelTelomere2004 = Citation(
        id: "epel-2004-telomere",
        title: "Accelerated Telomere Shortening in Response to Life Stress",
        authors: "Epel ES, Blackburn EH, Lin J, et al.",
        detail: "Proc Natl Acad Sci USA. 2004;101(49):17312-17315. Women reporting higher chronic stress had telomeres equivalent to at least a decade of additional biological aging. Foundation for MortalLoom's 'chronic stress shortens telomeres' claim.",
        url: "https://doi.org/10.1073/pnas.0407162101"
    )

    static let kivimakiStress2018 = Citation(
        id: "kivimaki-2018-stress",
        title: "Work Stress and Risk of Death in Men and Women",
        authors: "Kivimäki M, Pentti J, Ferrie JE, et al.",
        detail: "Lancet Diabetes Endocrinol. 2018;6(9):705-713. Pooled cohort of >100,000 workers: job strain associated with increased all-cause mortality, with the effect most pronounced among men with existing cardiometabolic disease.",
        url: "https://doi.org/10.1016/S2213-8587(18)30140-2"
    )

    // MARK: - Environment
    static let lancetPollution2018 = Citation(
        id: "lancet-pollution-2018",
        title: "The Lancet Commission on Pollution and Health",
        authors: "Landrigan PJ, Fuller R, Acosta NJR, et al.",
        detail: "Lancet. 2018;391(10119):462-512. Each 10 μg/m³ increase in long-term PM2.5 exposure associated with approximately 0.98 year reduction in life expectancy.",
        url: "https://doi.org/10.1016/S0140-6736(17)32345-0"
    )

    static let whoLifeExpectancy = Citation(
        id: "who-life-expectancy-2022",
        title: "WHO Global Health Observatory Life Tables",
        authors: "World Health Organization",
        detail: "2022 data. Country-level life expectancy at birth, used to calculate location-based adjustments relative to the US baseline.",
        url: "https://www.who.int/data/gho/data/themes/mortality-and-global-health-estimates/ghe-life-expectancy-and-healthy-life-expectancy"
    )

    // MARK: - Blood Markers
    static let clinicalLabRanges = Citation(
        id: "clinical-lab-ranges",
        title: "Clinical Laboratory Reference Ranges",
        authors: "Mayo Clinic Laboratories; Quest Diagnostics",
        detail: "Standard clinical laboratory reference ranges for metabolic panels, lipids, CBC, thyroid, and other common blood markers. Ranges may vary slightly between laboratories.",
        url: "https://www.mayocliniclabs.com/test-catalog"
    )

    static let adaHbA1c = Citation(
        id: "ada-hba1c-2024",
        title: "ADA Standards of Care in Diabetes: Glycemic Targets",
        authors: "American Diabetes Association",
        detail: "Diabetes Care. 2024;47(Suppl 1):S111-S125. HbA1c <5.7% normal, 5.7-6.4% prediabetes, ≥6.5% diabetes. Source for MortalLoom's HbA1c reference band.",
        url: "https://diabetesjournals.org/care/issue/47/Supplement_1"
    )

    static let aclAtpIii = Citation(
        id: "ncep-atp-iii",
        title: "NCEP ATP III Lipid Reference Ranges",
        authors: "National Cholesterol Education Program",
        detail: "Optimal LDL <100 mg/dL; desirable HDL ≥40 (men) / ≥50 (women); triglycerides <150 mg/dL; total cholesterol <200 mg/dL. Basis for MortalLoom's lipid panel reference bands.",
        url: "https://www.nhlbi.nih.gov/files/docs/guidelines/atp3full.pdf"
    )

    // MARK: - Genome
    static let clinvar = Citation(
        id: "clinvar",
        title: "ClinVar: Public Archive of Genomic Variation",
        authors: "National Center for Biotechnology Information (NCBI)",
        detail: "Genetic variant pathogenicity classifications and clinical significance. All genome markers in MortalLoom are cross-referenced with ClinVar data.",
        url: "https://www.ncbi.nlm.nih.gov/clinvar/"
    )

    static let deelenApoe2019 = Citation(
        id: "deelen-2019-apoe",
        title: "A Meta-Analysis of Genome-Wide Association Studies Identifies Multiple Longevity Genes",
        authors: "Deelen J, Evans DS, Arking DE, et al.",
        detail: "Nat Commun. 2019;10:3669. APOE variants and all-cause mortality associations across multiple populations. Basis for MortalLoom's APOE ε2/ε3/ε4 lifespan adjustments.",
        url: "https://doi.org/10.1038/s41467-019-11558-2"
    )

    static let farrerApoeAlz1997 = Citation(
        id: "farrer-1997-apoe",
        title: "Effects of Age, Sex, and Ethnicity on the Association Between APOE Genotype and Alzheimer Disease",
        authors: "Farrer LA, Cupples LA, Haines JL, et al.",
        detail: "JAMA. 1997;278(16):1349-1356. Meta-analysis establishing the ~12x Alzheimer's risk for ε4/ε4 homozygotes and ~3x risk for ε3/ε4 heterozygotes. Source for MortalLoom's APOE Alzheimer's risk multipliers.",
        url: "https://doi.org/10.1001/jama.1997.03550160069041"
    )

    // MARK: - Epigenetic Age
    static let horvathClock2013 = Citation(
        id: "horvath-2013",
        title: "DNA Methylation Age of Human Tissues and Cell Types (Horvath Clock)",
        authors: "Horvath S",
        detail: "Genome Biol. 2013;14:R115. Foundational work on DNA methylation-based biological age estimation.",
        url: "https://doi.org/10.1186/gb-2013-14-10-r115"
    )

    static let dunedinPace2022 = Citation(
        id: "belsky-2022-dunedinpace",
        title: "DunedinPACE: A DNA Methylation Biomarker of the Pace of Aging",
        authors: "Belsky DW, Caspi A, Corcoran DL, et al.",
        detail: "eLife. 2022;11:e73420. DunedinPACE measures the pace of biological aging from a single blood draw. Pace of aging <1.0 indicates slower biological aging than chronological age.",
        url: "https://doi.org/10.7554/eLife.73420"
    )

    // MARK: - Collected index for CitationsView
    /// Every citation indexed by ID for O(1) lookup from views.
    static let all: [String: Citation] = [
        ssaLifeTable.id: ssaLifeTable,
        cappuccioSleep2010.id: cappuccioSleep2010,
        nsfSleepDuration.id: nsfSleepDuration,
        youngApnea2008.id: youngApnea2008,
        acsmGuidelines.id: acsmGuidelines,
        coleHrr1999.id: coleHrr1999,
        kodamaFitness2009.id: kodamaFitness2009,
        studenskiGait2011.id: studenskiGait2011,
        hausdorffFalls2001.id: hausdorffFalls2001,
        niaaaLimits.id: niaaaLimits,
        gbdAlcohol2018.id: gbdAlcohol2018,
        dollSmoking2004.id: dollSmoking2004,
        jhaSmoking2013.id: jhaSmoking2013,
        whoBmi.id: whoBmi,
        bmiMortality2016.id: bmiMortality2016,
        whoPhysicalActivity.id: whoPhysicalActivity,
        arem2015Exercise.id: arem2015Exercise,
        predimedMedDiet.id: predimedMedDiet,
        gbdDiet2019.id: gbdDiet2019,
        epelTelomere2004.id: epelTelomere2004,
        kivimakiStress2018.id: kivimakiStress2018,
        lancetPollution2018.id: lancetPollution2018,
        whoLifeExpectancy.id: whoLifeExpectancy,
        clinicalLabRanges.id: clinicalLabRanges,
        adaHbA1c.id: adaHbA1c,
        aclAtpIii.id: aclAtpIii,
        clinvar.id: clinvar,
        deelenApoe2019.id: deelenApoe2019,
        farrerApoeAlz1997.id: farrerApoeAlz1997,
        horvathClock2013.id: horvathClock2013,
        dunedinPace2022.id: dunedinPace2022,
    ]

    /// Resolve an array of citation IDs to their full `Citation` records,
    /// preserving order and skipping any unknown IDs.
    static func resolve(_ ids: [String]) -> [Citation] {
        ids.compactMap { all[$0] }
    }

    // MARK: - Topic Groups (for CitationsView)

    struct Section: Identifiable {
        let id: String
        let title: String
        let icon: String
        let citationIds: [String]
    }

    static let sections: [Section] = [
        Section(
            id: "life-expectancy",
            title: "Life Expectancy Baseline",
            icon: "clock.fill",
            citationIds: [ssaLifeTable.id]
        ),
        Section(
            id: "sleep-mortality",
            title: "Sleep & Mortality",
            icon: "moon.fill",
            citationIds: [cappuccioSleep2010.id, nsfSleepDuration.id, youngApnea2008.id]
        ),
        Section(
            id: "cardio-fitness",
            title: "Cardiovascular Fitness",
            icon: "heart.fill",
            citationIds: [acsmGuidelines.id, coleHrr1999.id, kodamaFitness2009.id]
        ),
        Section(
            id: "gait",
            title: "Gait & Walking Speed",
            icon: "figure.walk",
            citationIds: [studenskiGait2011.id, hausdorffFalls2001.id]
        ),
        Section(
            id: "alcohol",
            title: "Alcohol Risk Thresholds",
            icon: "wineglass.fill",
            citationIds: [niaaaLimits.id, gbdAlcohol2018.id]
        ),
        Section(
            id: "smoking",
            title: "Smoking & Mortality",
            icon: "nosign",
            citationIds: [dollSmoking2004.id, jhaSmoking2013.id]
        ),
        Section(
            id: "bmi",
            title: "BMI & Body Composition",
            icon: "scalemass.fill",
            citationIds: [whoBmi.id, bmiMortality2016.id]
        ),
        Section(
            id: "exercise",
            title: "Exercise Guidelines",
            icon: "figure.run",
            citationIds: [whoPhysicalActivity.id, arem2015Exercise.id]
        ),
        Section(
            id: "diet",
            title: "Diet & Longevity",
            icon: "fork.knife",
            citationIds: [predimedMedDiet.id, gbdDiet2019.id]
        ),
        Section(
            id: "stress",
            title: "Stress & Longevity",
            icon: "brain.head.profile",
            citationIds: [epelTelomere2004.id, kivimakiStress2018.id]
        ),
        Section(
            id: "air-quality",
            title: "Air Quality & Life Expectancy",
            icon: "aqi.medium",
            citationIds: [lancetPollution2018.id]
        ),
        Section(
            id: "country-le",
            title: "Country Life Expectancy",
            icon: "globe",
            citationIds: [whoLifeExpectancy.id]
        ),
        Section(
            id: "blood",
            title: "Blood Test Reference Ranges",
            icon: "drop.fill",
            citationIds: [clinicalLabRanges.id, adaHbA1c.id, aclAtpIii.id]
        ),
        Section(
            id: "genome",
            title: "Genome & Genetic Markers",
            icon: "allergens.fill",
            citationIds: [clinvar.id, deelenApoe2019.id, farrerApoeAlz1997.id]
        ),
        Section(
            id: "epigenetic",
            title: "Epigenetic Age",
            icon: "waveform.path.ecg",
            citationIds: [horvathClock2013.id, dunedinPace2022.id]
        ),
    ]
}
