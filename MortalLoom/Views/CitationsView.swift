import SwiftUI

struct CitationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sources & Citations")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 4)

                Text("MortalLoom's health calculations and reference ranges are based on peer-reviewed research, government health databases, and established clinical guidelines. This page lists all primary sources used throughout the app.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                citationSection(
                    title: "Life Expectancy Baseline",
                    icon: "clock.fill",
                    citations: [
                        Citation(
                            title: "SSA Period Life Tables, 2021",
                            authors: "U.S. Social Security Administration, Office of the Chief Actuary",
                            detail: "Baseline life expectancy by age and sex used for actuarial calculations.",
                            url: "https://www.ssa.gov/oact/STATS/table4c6.html"
                        ),
                    ]
                )

                citationSection(
                    title: "Sleep & Mortality",
                    icon: "moon.fill",
                    citations: [
                        Citation(
                            title: "Sleep Duration and All-Cause Mortality",
                            authors: "Cappuccio FP, D'Elia L, Strazzullo P, Miller MA",
                            detail: "Sleep. 2010;33(5):585-592. Meta-analysis of 1.3M participants: short sleep (<6h) associated with 12% increased mortality; long sleep (>9h) with 30% increased mortality.",
                            url: "https://doi.org/10.1093/sleep/33.5.585"
                        ),
                        Citation(
                            title: "National Sleep Foundation Sleep Duration Recommendations",
                            authors: "Hirshkowitz M, Whiton K, Albert SM, et al.",
                            detail: "Sleep Health. 2015;1(1):40-43. Adults 26-64: recommended 7-9h; older adults 65+: recommended 7-8h.",
                            url: "https://doi.org/10.1016/j.sleh.2014.12.010"
                        ),
                    ]
                )

                citationSection(
                    title: "Cardiovascular Fitness",
                    icon: "heart.fill",
                    citations: [
                        Citation(
                            title: "ACSM's Guidelines for Exercise Testing and Prescription",
                            authors: "American College of Sports Medicine",
                            detail: "VO2 max fitness classifications by age and sex. Standard clinical reference for cardiorespiratory fitness assessment.",
                            url: "https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription"
                        ),
                        Citation(
                            title: "Heart-Rate Recovery After Exercise as a Predictor of Mortality",
                            authors: "Cole CR, Blackstone EH, Pashkow FJ, Snader CE, Lauer MS",
                            detail: "N Engl J Med. 1999;341:1351-1357. Abnormal HR recovery (<12 bpm drop in 1 min) associated with 4x cardiovascular mortality.",
                            url: "https://doi.org/10.1056/NEJM199910283411804"
                        ),
                        Citation(
                            title: "Cardiorespiratory Fitness and All-Cause Mortality",
                            authors: "Kodama S, Saito K, Tanaka S, et al.",
                            detail: "JAMA. 2009;301(19):2024-2035. Each 1-MET increase in fitness associated with ~15% reduction in all-cause mortality.",
                            url: "https://doi.org/10.1001/jama.2009.681"
                        ),
                    ]
                )

                citationSection(
                    title: "Gait & Walking Speed",
                    icon: "figure.walk",
                    citations: [
                        Citation(
                            title: "Gait Speed and Survival in Older Adults",
                            authors: "Studenski S, Perera S, Patel K, et al.",
                            detail: "JAMA. 2011;305(1):50-58. Each 0.1 m/s increase in gait speed associated with 12% lower mortality. Walking speed is called 'the 6th vital sign.'",
                            url: "https://doi.org/10.1001/jama.2010.1923"
                        ),
                    ]
                )

                citationSection(
                    title: "Alcohol Risk Thresholds",
                    icon: "wineglass.fill",
                    citations: [
                        Citation(
                            title: "NIAAA Drinking Levels Defined",
                            authors: "National Institute on Alcohol Abuse and Alcoholism",
                            detail: "Low-risk drinking limits: women \u{2264}1 drink/day, \u{2264}7/week; men \u{2264}2 drinks/day, \u{2264}14/week. Exceeding these thresholds significantly increases health risk.",
                            url: "https://www.niaaa.nih.gov/alcohol-health/overview-alcohol-consumption/moderate-binge-drinking"
                        ),
                    ]
                )

                citationSection(
                    title: "BMI & Body Composition",
                    icon: "scalemass.fill",
                    citations: [
                        Citation(
                            title: "WHO BMI Classification",
                            authors: "World Health Organization",
                            detail: "Standard BMI categories: <18.5 underweight, 18.5-24.9 normal, 25-29.9 overweight, \u{2265}30 obese. Used for longevity impact estimation.",
                            url: "https://www.who.int/data/gho/data/themes/topics/topic-details/GHO/body-mass-index"
                        ),
                    ]
                )

                citationSection(
                    title: "Exercise Guidelines",
                    icon: "figure.run",
                    citations: [
                        Citation(
                            title: "WHO Guidelines on Physical Activity and Sedentary Behaviour",
                            authors: "World Health Organization",
                            detail: "Adults 18-64: at least 150 min of moderate-intensity or 75 min of vigorous-intensity aerobic activity per week for substantial health benefits.",
                            url: "https://www.who.int/publications/i/item/9789240015128"
                        ),
                    ]
                )

                citationSection(
                    title: "Air Quality & Life Expectancy",
                    icon: "aqi.medium",
                    citations: [
                        Citation(
                            title: "The Lancet Commission on Pollution and Health",
                            authors: "Landrigan PJ, Fuller R, Acosta NJR, et al.",
                            detail: "Lancet. 2018;391(10119):462-512. Each 10 \u{00B5}g/m\u{00B3} increase in long-term PM2.5 exposure associated with approximately 0.98 year reduction in life expectancy.",
                            url: "https://doi.org/10.1016/S0140-6736(17)32345-0"
                        ),
                    ]
                )

                citationSection(
                    title: "Country Life Expectancy",
                    icon: "globe",
                    citations: [
                        Citation(
                            title: "WHO Global Health Observatory Life Tables",
                            authors: "World Health Organization",
                            detail: "2022 data. Country-level life expectancy at birth, used to calculate location-based adjustments relative to the US baseline (78.5 years).",
                            url: "https://www.who.int/data/gho/data/themes/mortality-and-global-health-estimates/ghe-life-expectancy-and-healthy-life-expectancy"
                        ),
                    ]
                )

                citationSection(
                    title: "Blood Test Reference Ranges",
                    icon: "drop.fill",
                    citations: [
                        Citation(
                            title: "Clinical Laboratory Reference Ranges",
                            authors: "Mayo Clinic Laboratories; Quest Diagnostics",
                            detail: "Standard clinical laboratory reference ranges for metabolic panels, lipids, CBC, thyroid, and other common blood markers. Ranges may vary slightly between laboratories.",
                            url: "https://www.mayocliniclabs.com/test-catalog"
                        ),
                    ]
                )

                citationSection(
                    title: "Genome & Genetic Markers",
                    icon: "allergens.fill",
                    citations: [
                        Citation(
                            title: "ClinVar: Public Archive of Genomic Variation",
                            authors: "National Center for Biotechnology Information (NCBI)",
                            detail: "Genetic variant pathogenicity classifications and clinical significance. All genome markers in MortalLoom are cross-referenced with ClinVar data.",
                            url: "https://www.ncbi.nlm.nih.gov/clinvar/"
                        ),
                        Citation(
                            title: "APOE and Longevity",
                            authors: "Deelen J, Evans DS, Arking DE, et al.",
                            detail: "Nat Commun. 2019;10:3669. APOE variants and all-cause mortality associations across multiple populations.",
                            url: "https://doi.org/10.1038/s41467-019-11558-2"
                        ),
                    ]
                )

                citationSection(
                    title: "Epigenetic Age",
                    icon: "waveform.path.ecg",
                    citations: [
                        Citation(
                            title: "An Epigenetic Biomarker of Aging (Horvath Clock)",
                            authors: "Horvath S",
                            detail: "Genome Biol. 2013;14:R115. Foundational work on DNA methylation-based biological age estimation. Pace of aging <1.0 indicates younger biological age.",
                            url: "https://doi.org/10.1186/gb-2013-14-10-r115"
                        ),
                        Citation(
                            title: "DunedinPACE: Pace of Aging",
                            authors: "Belsky DW, Caspi A, Corcoran DL, et al.",
                            detail: "eLife. 2022;11:e73420. DunedinPACE measures the pace of biological aging from a single blood draw.",
                            url: "https://doi.org/10.7554/eLife.73420"
                        ),
                    ]
                )

                // Disclaimer
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(Color.cardBorder)
                    Text("Disclaimer")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    Text("MortalLoom provides informational health estimates based on published research and is not a substitute for professional medical advice, diagnosis, or treatment. Life expectancy calculations are statistical estimates, not individual predictions. Always consult a qualified healthcare provider for medical decisions.")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(Color.bg)
    }

    // MARK: - Components

    private struct Citation: Identifiable {
        let id = UUID()
        let title: String
        let authors: String
        let detail: String
        let url: String
    }

    private func citationSection(title: String, icon: String, citations: [Citation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
            }

            ForEach(citations) { citation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(citation.title)
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                    Text(citation.authors)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    Text(citation.detail)
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    Link(destination: URL(string: citation.url)!) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text("View Source")
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgCard.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
