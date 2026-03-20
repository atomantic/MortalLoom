import Foundation

struct BloodTest: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var date: String // "YYYY-MM-DD"
    var markers: [String: Double] // marker key -> value

    init(id: UUID = UUID(), date: String, markers: [String: Double] = [:]) {
        self.id = id; self.date = date; self.markers = markers
    }
}

struct BloodMarkerRef: Sendable {
    let key: String
    let label: String
    let unit: String
    let min: Double
    let max: Double

    var range: ClosedRange<Double> { min...max }

    func status(for value: Double) -> MarkerStatus {
        if value < min { return .low }
        if value > max { return .high }
        return .normal
    }
}

enum MarkerStatus: String, Sendable {
    case normal, low, high, unknown
}

// All reference ranges from PortOS constants.js
enum BloodMarkers {
    static let all: [BloodMarkerRef] = [
        // Metabolic Panel
        BloodMarkerRef(key: "apoB", label: "ApoB", unit: "mg/dL", min: 40, max: 100),
        BloodMarkerRef(key: "bun", label: "BUN", unit: "mg/dL", min: 7, max: 20),
        BloodMarkerRef(key: "creatinine", label: "Creatinine", unit: "mg/dL", min: 0.7, max: 1.3),
        BloodMarkerRef(key: "egfr", label: "eGFR", unit: "mL/min", min: 90, max: 120),
        BloodMarkerRef(key: "glucose", label: "Glucose", unit: "mg/dL", min: 70, max: 99),
        // Lipids
        BloodMarkerRef(key: "cholesterol", label: "Total Cholesterol", unit: "mg/dL", min: 0, max: 200),
        BloodMarkerRef(key: "hdl", label: "HDL", unit: "mg/dL", min: 40, max: 100),
        BloodMarkerRef(key: "ldl", label: "LDL", unit: "mg/dL", min: 0, max: 100),
        BloodMarkerRef(key: "triglycerides", label: "Triglycerides", unit: "mg/dL", min: 0, max: 150),
        // CBC
        BloodMarkerRef(key: "wbc", label: "WBC", unit: "K/uL", min: 4.5, max: 11.0),
        BloodMarkerRef(key: "rbc", label: "RBC", unit: "M/uL", min: 4.5, max: 5.5),
        BloodMarkerRef(key: "hemoglobin", label: "Hemoglobin", unit: "g/dL", min: 13.5, max: 17.5),
        BloodMarkerRef(key: "hematocrit", label: "Hematocrit", unit: "%", min: 38.3, max: 48.6),
        BloodMarkerRef(key: "platelets", label: "Platelets", unit: "K/uL", min: 150, max: 400),
        // Thyroid
        BloodMarkerRef(key: "tsh", label: "TSH", unit: "mIU/L", min: 0.4, max: 4.0),
        // Extended metabolic
        BloodMarkerRef(key: "na", label: "Sodium", unit: "mmol/L", min: 136, max: 144),
        BloodMarkerRef(key: "k", label: "Potassium", unit: "mmol/L", min: 3.5, max: 5.2),
        BloodMarkerRef(key: "ci", label: "Chloride", unit: "mmol/L", min: 98, max: 106),
        BloodMarkerRef(key: "co2", label: "CO2", unit: "mmol/L", min: 22, max: 32),
        BloodMarkerRef(key: "calcium", label: "Calcium", unit: "mg/dL", min: 8.6, max: 10.3),
        BloodMarkerRef(key: "protein", label: "Total Protein", unit: "g/dL", min: 6.0, max: 8.3),
        BloodMarkerRef(key: "albumin", label: "Albumin", unit: "g/dL", min: 3.5, max: 5.5),
        BloodMarkerRef(key: "globulin", label: "Globulin", unit: "g/dL", min: 1.5, max: 4.5),
        BloodMarkerRef(key: "a_g_ratio", label: "A/G Ratio", unit: "", min: 1.0, max: 2.5),
        BloodMarkerRef(key: "bilirubin", label: "Bilirubin", unit: "mg/dL", min: 0.1, max: 1.2),
        BloodMarkerRef(key: "bili_direct", label: "Bilirubin Direct", unit: "mg/dL", min: 0.0, max: 0.5),
        BloodMarkerRef(key: "alk_phos", label: "Alkaline Phosphatase", unit: "U/L", min: 36, max: 130),
        BloodMarkerRef(key: "sgot_ast", label: "AST (SGOT)", unit: "U/L", min: 10, max: 40),
        BloodMarkerRef(key: "alt", label: "ALT (SGPT)", unit: "U/L", min: 7, max: 56),
        BloodMarkerRef(key: "hba1c", label: "HbA1c", unit: "%", min: 4.0, max: 5.6),
        BloodMarkerRef(key: "anion_gap", label: "Anion Gap", unit: "mmol/L", min: 3, max: 12),
        // Extended Lipids
        BloodMarkerRef(key: "chol_hdl_ratio", label: "Chol/HDL Ratio", unit: "", min: 0, max: 5.0),
        BloodMarkerRef(key: "non_hdl_col", label: "Non-HDL Cholesterol", unit: "mg/dL", min: 0, max: 130),
        // Extended CBC
        BloodMarkerRef(key: "mcv", label: "MCV", unit: "fL", min: 80, max: 100),
        BloodMarkerRef(key: "mch", label: "MCH", unit: "pg", min: 27, max: 33),
        BloodMarkerRef(key: "mchc", label: "MCHC", unit: "g/dL", min: 32, max: 36),
        BloodMarkerRef(key: "rdw", label: "RDW", unit: "%", min: 11.0, max: 15.0),
        BloodMarkerRef(key: "mpv", label: "MPV", unit: "fL", min: 7.5, max: 12.5),
        // Other
        BloodMarkerRef(key: "homocysteine", label: "Homocysteine", unit: "umol/L", min: 5, max: 15),
    ]

    static let byKey: [String: BloodMarkerRef] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    }()

    // Group markers by category for display
    static let categories: [(name: String, keys: [String])] = [
        ("Metabolic Panel", ["glucose", "bun", "creatinine", "egfr", "na", "k", "ci", "co2", "calcium", "protein", "albumin", "globulin", "a_g_ratio", "bilirubin", "bili_direct", "alk_phos", "sgot_ast", "alt", "hba1c", "anion_gap"]),
        ("Lipids", ["cholesterol", "hdl", "ldl", "triglycerides", "apoB", "chol_hdl_ratio", "non_hdl_col"]),
        ("CBC", ["wbc", "rbc", "hemoglobin", "hematocrit", "platelets", "mcv", "mch", "mchc", "rdw", "mpv"]),
        ("Thyroid", ["tsh"]),
        ("Other", ["homocysteine"]),
    ]
}
