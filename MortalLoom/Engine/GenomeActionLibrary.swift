import Foundation

/// Curated `GenomeAction` library — declarative, data-only. Grow by appending.
///
/// Action IDs are stable across releases; never rename. Add new actions or
/// supersede with new IDs — old saved state references the old ID.
enum GenomeActionLibrary {

    static let all: [GenomeAction] = [

        // ─────────────────────────────────────────────────────────────
        // APOE
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "apoe-e4-cardio",
            kind: .habit,
            title: "Cardiovascular exercise 150+ min/week",
            detail: "Regular cardio is the most evidence-backed neuroprotective intervention for APOE ε4 carriers. Aim for the WHO target of 150 min/week of moderate intensity (or 75 min vigorous).",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "apoe", genotypes: ["\u{03B5}3/\u{03B5}4", "\u{03B5}4/\u{03B5}4", "\u{03B5}2/\u{03B5}4"])
            ],
            bridge: .habitTemplate(HabitTemplate(
                title: "Cardio 150 min/week",
                detail: "Neuroprotective for APOE ε4 — cumulative weekly minutes of moderate cardio.",
                icon: "figure.run",
                category: .health,
                kind: .positive,
                cadence: HabitCadence(period: .weekly, target: 3)
            )),
            citationIds: [
                CitationLibrary.deelenApoe2019.id,
                CitationLibrary.farrerApoeAlz1997.id,
                CitationLibrary.whoPhysicalActivity.id
            ],
            doctorTalkingPoint: "I have APOE ε4 (one or two copies). I'd like to discuss neuroprotective strategies — cardiovascular exercise, sleep, lipid management, and whether earlier cognitive baselines make sense."
        ),

        GenomeAction(
            id: "apoe-e4-sleep",
            kind: .habit,
            title: "Protect 7–9 hours of sleep nightly",
            detail: "Glymphatic clearance of amyloid happens during deep sleep. Sleep loss compounds APOE ε4 risk. Optimize consistency, environment, and avoid late caffeine.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "apoe", genotypes: ["\u{03B5}3/\u{03B5}4", "\u{03B5}4/\u{03B5}4", "\u{03B5}2/\u{03B5}4"])
            ],
            bridge: .lifestyleField(.sleepHoursPerNight),
            citationIds: [
                CitationLibrary.cappuccioSleep2010.id,
                CitationLibrary.nsfSleepDuration.id
            ],
            doctorTalkingPoint: nil
        ),

        GenomeAction(
            id: "apoe-e4-lipid-panel",
            kind: .bloodTest,
            title: "Annual lipid panel (ApoB, LDL-C, HDL)",
            detail: "ε4 carriers metabolize lipids less efficiently. Track ApoB and LDL-C yearly to catch atherosclerosis-driving trends early.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "apoe", genotypes: ["\u{03B5}3/\u{03B5}4", "\u{03B5}4/\u{03B5}4", "\u{03B5}2/\u{03B5}4"])
            ],
            bridge: .bloodMarkerKey("apoB"),
            citationIds: [CitationLibrary.aclAtpIii.id],
            doctorTalkingPoint: nil
        ),

        GenomeAction(
            id: "apoe-e4e4-genetic-counselor",
            kind: .doctorConsult,
            title: "Discuss with a genetic counselor",
            detail: "Homozygous ε4/ε4 carries the strongest APOE-related Alzheimer's risk (~12× baseline). A genetic counselor can help you and family members make informed decisions about testing and risk-reduction.",
            urgency: .prompt,
            conditions: [
                GenomeActionCondition(rsid: "apoe", genotypes: ["\u{03B5}4/\u{03B5}4"])
            ],
            bridge: nil,
            citationIds: [CitationLibrary.farrerApoeAlz1997.id],
            doctorTalkingPoint: "I have homozygous APOE ε4/ε4. I'd like a referral to a genetic counselor and to discuss aggressive risk-reduction strategy."
        ),

        // ─────────────────────────────────────────────────────────────
        // MTHFR C677T (rs1801133)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "mthfr-c677t-homocysteine-panel",
            kind: .bloodTest,
            title: "Order homocysteine + B12 + folate panel",
            detail: "MTHFR variants reduce folate-cycle efficiency. A baseline homocysteine measurement clarifies whether the genotype is currently affecting you. Target homocysteine <10 μmol/L.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "rs1801133", minStatus: .concern)
            ],
            bridge: .bloodMarkerKey("homocysteine"),
            citationIds: [CitationLibrary.clinicalLabRanges.id],
            doctorTalkingPoint: "I have MTHFR C677T (rs1801133). Could we check homocysteine, B12, and folate to baseline my methylation cycle?"
        ),

        GenomeAction(
            id: "mthfr-c677t-methylfolate",
            kind: .supplement,
            title: "Switch from folic acid to methylfolate",
            detail: "Reduced MTHFR activity means less efficient conversion of folic acid to its active form (5-MTHF). Methylated B-vitamins bypass the bottleneck. Discuss with your doctor before starting.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1801133", minStatus: .concern)
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        ),

        GenomeAction(
            id: "mthfr-c677t-tt-doctor",
            kind: .doctorConsult,
            title: "Discuss elevated cardiovascular risk",
            detail: "T/T homozygous reduces enzyme activity to ~30% and is associated with hyperhomocysteinemia and cardiovascular risk. Worth a focused conversation with your primary care.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "rs1801133", genotypes: ["T/T"])
            ],
            bridge: nil,
            citationIds: [CitationLibrary.clinicalLabRanges.id],
            doctorTalkingPoint: "I'm homozygous for MTHFR C677T (rs1801133, T/T) — ~30% enzyme activity. Could we discuss cardiovascular monitoring and methylation support?"
        ),

        // ─────────────────────────────────────────────────────────────
        // MTHFR A1298C (rs1801131)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "mthfr-a1298c-homocysteine-panel",
            kind: .bloodTest,
            title: "Add homocysteine to next blood panel",
            detail: "A1298C variants — especially compound heterozygous with C677T — can meaningfully affect methylation. Homocysteine is the cleanest functional readout.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1801131", minStatus: .concern)
            ],
            bridge: .bloodMarkerKey("homocysteine"),
            citationIds: [CitationLibrary.clinicalLabRanges.id],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // Factor V Leiden (rs6025)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "f5-leiden-flag-providers",
            kind: .doctorConsult,
            title: "Flag this in your medical record",
            detail: "Factor V Leiden 5–10× venous thrombosis risk requires awareness before surgery, hormonal contraceptives, pregnancy, or long-haul flights. Make sure it's documented in your chart.",
            urgency: .prompt,
            conditions: [
                GenomeActionCondition(rsid: "rs6025", minStatus: .concern)
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: "I'm a Factor V Leiden carrier (rs6025). Please add this to my problem list — relevant for surgery, hormonal contraceptives, pregnancy planning, and immobilization."
        ),

        GenomeAction(
            id: "f5-leiden-tt-anticoag-consult",
            kind: .doctorConsult,
            title: "Hematology consult for anticoagulation strategy",
            detail: "Homozygous Factor V Leiden (~50–100× clotting risk) often warrants ongoing hematology input on anticoagulation thresholds.",
            urgency: .prompt,
            conditions: [
                GenomeActionCondition(rsid: "rs6025", genotypes: ["T/T"])
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: "I'm homozygous for Factor V Leiden (rs6025, T/T). Could you refer me to hematology for anticoagulation planning?"
        ),

        // ─────────────────────────────────────────────────────────────
        // HFE C282Y (rs1800562)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "hfe-c282y-iron-panel",
            kind: .bloodTest,
            title: "Iron panel + ferritin (annually if carrier, more if homozygous)",
            detail: "Hemochromatosis presents silently. Track ferritin, transferrin saturation, serum iron — even heterozygous carriers benefit from a baseline.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "rs1800562", minStatus: .concern)
            ],
            bridge: .bloodMarkerKey("ferritin"),
            citationIds: [CitationLibrary.clinicalLabRanges.id],
            doctorTalkingPoint: "I'm an HFE C282Y carrier (rs1800562). Could we baseline ferritin, transferrin saturation, and iron studies?"
        ),

        GenomeAction(
            id: "hfe-c282y-aa-hematology",
            kind: .doctorConsult,
            title: "Hematology referral for hereditary hemochromatosis",
            detail: "Homozygous C282Y is the primary genotype for hereditary hemochromatosis. Phlebotomy may be indicated if iron loading develops. Specialist input is the standard of care.",
            urgency: .prompt,
            conditions: [
                GenomeActionCondition(rsid: "rs1800562", genotypes: ["A/A"])
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: "I'm homozygous for HFE C282Y (rs1800562, A/A). I'd like to discuss screening for iron overload and a hematology referral."
        ),

        // ─────────────────────────────────────────────────────────────
        // HFE H63D (rs1799945)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "hfe-h63d-ferritin",
            kind: .bloodTest,
            title: "Baseline ferritin",
            detail: "H63D causes mild iron overload — meaningful especially with C282Y compound heterozygosity. A ferritin check is the simplest sanity test.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1799945", minStatus: .concern)
            ],
            bridge: .bloodMarkerKey("ferritin"),
            citationIds: [CitationLibrary.clinicalLabRanges.id],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // 9p21 CAD (rs1333049)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "9p21-cad-cardio",
            kind: .habit,
            title: "Cardio 150+ min/week",
            detail: "9p21 is the strongest common genetic risk locus for coronary artery disease. Modifiable risk factors (exercise, lipids, BP) carry the highest leverage in carriers.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "rs1333049", genotypes: ["C/C"])
            ],
            bridge: .habitTemplate(HabitTemplate(
                title: "Cardio 150 min/week",
                detail: "Reduces CAD risk for 9p21 risk genotype.",
                icon: "figure.run",
                category: .health,
                kind: .positive,
                cadence: HabitCadence(period: .weekly, target: 3)
            )),
            citationIds: [CitationLibrary.whoPhysicalActivity.id, CitationLibrary.arem2015Exercise.id],
            doctorTalkingPoint: nil
        ),

        GenomeAction(
            id: "9p21-cad-lipid-panel",
            kind: .bloodTest,
            title: "Lipid panel + ApoB",
            detail: "Track lipids closely if you carry the 9p21 risk genotype. ApoB is a more accurate atherogenic marker than total LDL.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "rs1333049", genotypes: ["C/C"])
            ],
            bridge: .bloodMarkerKey("apoB"),
            citationIds: [CitationLibrary.aclAtpIii.id],
            doctorTalkingPoint: "I carry the 9p21 (rs1333049 C/C) coronary artery disease risk genotype. Could we check ApoB and discuss aggressive lipid targets?"
        ),

        // ─────────────────────────────────────────────────────────────
        // TP53 (rs1042522) — tumor suppression
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "tp53-pro72-screening",
            kind: .screening,
            title: "Stay current on age-appropriate cancer screening",
            detail: "The Pro72 (C/C) genotype favors DNA repair over apoptosis, which can mean reduced clearance of damaged cells. Standard age-appropriate screening matters more — don't skip it.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1042522", genotypes: ["C/C"])
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // COMT (rs4680) — stress / focus
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "comt-met-stress",
            kind: .habit,
            title: "Daily mindfulness / stress regulation practice",
            detail: "Met/Met (slow COMT) means slower clearance of catecholamines — better focus under calm, but more stress reactivity. A daily regulation practice (breathwork, meditation) compensates well.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs4680", genotypes: ["A/A"])
            ],
            bridge: .habitTemplate(HabitTemplate(
                title: "10 min mindfulness",
                detail: "Daily stress-regulation practice — particularly useful for COMT Met/Met.",
                icon: "leaf.fill",
                category: .wellness,
                kind: .positive,
                cadence: HabitCadence(period: .daily, target: 1)
            )),
            citationIds: [CitationLibrary.epelTelomere2004.id],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // SOD2 (rs4880) — mitochondrial antioxidant
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "sod2-val-antioxidant-diet",
            kind: .lifestyle,
            title: "Antioxidant-rich diet (berries, leafy greens, polyphenols)",
            detail: "Val/Val SOD2 imports less efficiently into mitochondria. Dietary antioxidants — and avoiding excessive iron loading — can help compensate.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs4880", genotypes: ["A/A"])
            ],
            bridge: .lifestyleField(.dietQuality),
            citationIds: [CitationLibrary.predimedMedDiet.id],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // ADA caffeine (rs73598374)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "ada-caffeine-cutoff",
            kind: .lifestyle,
            title: "Cut caffeine after 2pm",
            detail: "Altered adenosine processing means caffeine lingers longer and disrupts deep sleep more than for others. A hard cutoff at midday usually fixes the sleep cost.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs73598374", minStatus: .concern)
            ],
            bridge: .habitTemplate(HabitTemplate(
                title: "No caffeine after 2pm",
                detail: "Genotype-aware caffeine cutoff to protect sleep quality.",
                icon: "cup.and.saucer.fill",
                category: .health,
                kind: .negative,
                cadence: HabitCadence(period: .daily, target: 1)
            )),
            citationIds: [CitationLibrary.cappuccioSleep2010.id],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // IL-6 (rs1800795) — inflammation
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "il6-anti-inflammatory-diet",
            kind: .lifestyle,
            title: "Anti-inflammatory diet (Mediterranean pattern)",
            detail: "Higher baseline IL-6 expression links to elevated cardiovascular and cognitive risk. A Mediterranean-pattern diet has the strongest evidence for reducing systemic inflammation.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1800795", genotypes: ["C/C"])
            ],
            bridge: .lifestyleField(.dietQuality),
            citationIds: [CitationLibrary.predimedMedDiet.id],
            doctorTalkingPoint: nil
        ),

        GenomeAction(
            id: "il6-crp-monitor",
            kind: .bloodTest,
            title: "Track high-sensitivity CRP annually",
            detail: "hs-CRP is the standard functional marker of systemic inflammation — useful to know whether your IL-6 genotype is currently driving elevated baseline inflammation.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1800795", genotypes: ["C/C"])
            ],
            bridge: .bloodMarkerKey("crp"),
            citationIds: [CitationLibrary.clinicalLabRanges.id],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // TNF-alpha (rs1800629)
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "tnf-autoimmune-awareness",
            kind: .doctorConsult,
            title: "Mention autoimmune family history at next visit",
            detail: "Elevated TNF-α expression raises baseline risk for autoimmune conditions. If you have family history (RA, IBD, lupus, psoriasis), worth surfacing it explicitly.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "rs1800629", genotypes: ["A/A"])
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        ),

        // ─────────────────────────────────────────────────────────────
        // Generic ClinVar actions — keyed by pseudo-rsid
        // ─────────────────────────────────────────────────────────────

        GenomeAction(
            id: "clinvar-pathogenic-confirm-clia",
            kind: .doctorConsult,
            title: "Confirm with a CLIA-certified clinical lab",
            detail: "Consumer DTC genetic tests are not diagnostic. Pathogenic ClinVar variants warrant confirmation in a clinical laboratory before acting on them.",
            urgency: .prompt,
            conditions: [
                GenomeActionCondition(rsid: "clinvar:pathogenic")
            ],
            bridge: nil,
            citationIds: [CitationLibrary.clinvar.id],
            doctorTalkingPoint: "My consumer genetic test flagged a ClinVar pathogenic variant. Could we order clinical confirmation testing before making any decisions?"
        ),

        GenomeAction(
            id: "clinvar-pathogenic-genetic-counselor",
            kind: .doctorConsult,
            title: "Genetic counselor referral",
            detail: "Pathogenic findings often have implications for first-degree relatives. A genetic counselor helps you and family understand the actual risk and screening options.",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "clinvar:pathogenic")
            ],
            bridge: nil,
            citationIds: [CitationLibrary.clinvar.id],
            doctorTalkingPoint: nil
        ),

        GenomeAction(
            id: "clinvar-drug-pharmacist-handoff",
            kind: .doctorConsult,
            title: "Share with your pharmacist before next prescription",
            detail: "Drug-response variants affect how you metabolize specific medications. Walk your pharmacist through the list before your next new prescription — many will flag interactions you'd otherwise miss.",
            urgency: .routine,
            conditions: [
                GenomeActionCondition(rsid: "clinvar:drug_response")
            ],
            bridge: nil,
            citationIds: [CitationLibrary.clinvar.id],
            doctorTalkingPoint: "I have a drug-response variant in [gene]. Before prescribing [medication], could we check whether dosing or alternatives are appropriate?"
        ),
    ]
}
