import Foundation

// MARK: - Air Quality Level

enum AirQualityLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case good       = "Good"        // Clean/rural — better than US urban average
    case moderate   = "Moderate"    // Typical US city (baseline — no additional adjustment)
    case unhealthy  = "Unhealthy"   // Heavy urban/industrial (e.g., LA smog days)
    case hazardous  = "Hazardous"   // Severe pollution (e.g., Delhi, Beijing peak days)

    var description: String {
        switch self {
        case .good:      return "Rural, mountain, or clean coastal area"
        case .moderate:  return "Average US or European city"
        case .unhealthy: return "Dense urban, traffic, or industrial area"
        case .hazardous: return "High-pollution city (e.g., Delhi, Beijing)"
        }
    }
}

// MARK: - Location Engine

enum LocationEngine {

    // MARK: Country life expectancy delta vs US average (78.5 yrs)
    // Source: WHO Global Health Observatory 2022 data.
    // Delta = countryLE - 78.5 (US gender-average baseline used in SSA table)
    // Capped at [-8, +6] to reflect that individual lifestyle factors dominate beyond this range.

    static func countryLifeExpectancyDelta(_ countryCode: String) -> Double {
        let delta = countryDeltas[countryCode.uppercased()] ?? 0.0
        return min(6.0, max(-8.0, delta))
    }

    // Sorted display name → ISO code, for picker UI
    static let countriesForPicker: [(name: String, code: String)] = countryDeltas.keys
        .map { code in (name: countryDisplayName(code), code: code) }
        .sorted { $0.name < $1.name }

    static func countryDisplayName(_ code: String) -> String {
        displayNames[code.uppercased()] ?? code
    }

    // MARK: Air quality adjustment (years of LE relative to moderate US baseline)
    // Evidence: each 10 µg/m³ increase in long-term PM2.5 ≈ −0.98 yr LE (Lancet 2017).

    static func airQualityAdjustment(_ level: AirQualityLevel?) -> Double {
        switch level {
        case .good:       return 0.5
        case .moderate:   return 0.0   // baseline (typical US city)
        case .unhealthy:  return -1.5
        case .hazardous:  return -3.0
        case nil:         return 0.0
        }
    }

    // MARK: Region (sub-country) life-expectancy delta
    //
    // Applied ON TOP of the country delta. Represents the gap between a given
    // state/province and the country's own baseline.
    // - US states: CDC 2022 state life tables vs US 78.5 baseline
    // - Canadian provinces: Statistics Canada 2020-2022 vs Canada 81.7
    // - UK nations: ONS 2020-2022 vs UK 81.3
    //
    // Encoded as "CC-REGION" (ISO 3166-2). Example: "US-CA" = California.
    // Capped at ±3.0 to prevent sub-national noise from overwhelming other factors.

    static func regionLifeExpectancyDelta(_ regionCode: String) -> Double {
        let key = regionCode.uppercased()
        guard let delta = regionDeltas[key] else { return 0.0 }
        return min(3.0, max(-3.0, delta))
    }

    /// Display name for a region code (e.g. "US-CA" → "California").
    /// Falls back to the raw code for unknown regions.
    static func regionDisplayName(_ regionCode: String) -> String {
        regionNames[regionCode.uppercased()] ?? regionCode
    }

    /// Reverse-lookup a region code from a full administrative-area name
    /// (e.g. "England" → "GB-ENG"). Returns nil when no known region in the
    /// given country matches. Case-insensitive.
    static func regionCode(countryCode: String, administrativeAreaName name: String) -> String? {
        let prefix = countryCode.uppercased() + "-"
        let needle = name.lowercased()
        return regionNames.first { $0.key.hasPrefix(prefix) && $0.value.lowercased() == needle }?.key
    }

    /// Pickable regions for a country, sorted by display name.
    /// Returns empty for countries with no regional breakdown.
    static func regionsForPicker(countryCode: String) -> [(name: String, code: String)] {
        let prefix = countryCode.uppercased() + "-"
        return regionDeltas.keys
            .filter { $0.hasPrefix(prefix) }
            .map { code in (name: regionDisplayName(code), code: code) }
            .sorted { $0.name < $1.name }
    }

    /// Countries for which region-level data exists.
    static func hasRegionalData(_ countryCode: String) -> Bool {
        let prefix = countryCode.uppercased() + "-"
        return regionDeltas.keys.contains { $0.hasPrefix(prefix) }
    }

    // MARK: Combined location adjustment

    static func locationAdjustment(countryCode: String?, regionCode: String? = nil, airQuality: AirQualityLevel?) -> Double {
        let countryAdj = countryCode.map { countryLifeExpectancyDelta($0) } ?? 0.0
        let regionAdj = regionCode.map { regionLifeExpectancyDelta($0) } ?? 0.0
        let aqAdj = airQualityAdjustment(airQuality)
        let total = countryAdj + regionAdj + aqAdj
        // Clamp combined to avoid over-adjusting on top of lifestyle factors
        return min(8.0, max(-10.0, (total * 10).rounded() / 10))
    }

    // MARK: - Data Tables

    private static let countryDeltas: [String: Double] = [
        // Asia-Pacific
        "JP": 5.8,   // Japan 84.3
        "KR": 4.8,   // South Korea 83.3
        "SG": 4.5,   // Singapore 83.0
        "AU": 4.3,   // Australia 82.8
        "NZ": 3.2,   // New Zealand 81.7
        "HK": 6.0,   // Hong Kong 84.5
        "TW": 4.1,   // Taiwan 82.6
        "CN": -1.1,  // China 77.4
        "TH": -1.4,  // Thailand 77.1
        "VN": -4.8,  // Vietnam 73.7
        "MY": -2.2,  // Malaysia 76.3
        "PH": -7.2,  // Philippines 71.3
        "ID": -6.9,  // Indonesia 71.6
        "IN": -8.0,  // India 70.2 (clamped)
        "BD": -5.7,  // Bangladesh 72.8
        "PK": -8.0,  // Pakistan 67.2 (clamped)
        "NP": -7.0,  // Nepal 71.5 (clamped)
        "LK": -2.6,  // Sri Lanka 75.9
        "MN": -5.5,  // Mongolia 73.0
        "KH": -7.0,  // Cambodia 71.5 (clamped)
        "MM": -7.5,  // Myanmar 71.0 (clamped)
        "KZ": -4.5,  // Kazakhstan 74.0
        "UZ": -6.5,  // Uzbekistan 72.0
        // Europe
        "CH": 4.9,   // Switzerland 83.4
        "IS": 3.8,   // Iceland 82.3
        "ES": 4.3,   // Spain 82.8
        "IT": 4.2,   // Italy 82.7
        "SE": 3.9,   // Sweden 82.4
        "NO": 3.8,   // Norway 82.3
        "FR": 3.8,   // France 82.3
        "LU": 3.8,   // Luxembourg 82.3
        "MT": 4.0,   // Malta 82.5
        "IL": 4.1,   // Israel 82.6
        "IE": 3.0,   // Ireland 81.5
        "NL": 2.9,   // Netherlands 81.4
        "BE": 2.9,   // Belgium 81.4
        "FI": 3.1,   // Finland 81.6
        "AT": 2.6,   // Austria 81.1
        "DE": 2.1,   // Germany 80.6
        "DK": 2.7,   // Denmark 81.2
        "PT": 2.5,   // Portugal 81.0
        "GR": 2.2,   // Greece 80.7
        "GB": 2.8,   // United Kingdom 81.3
        "SI": 2.6,   // Slovenia 81.1
        "CY": 2.8,   // Cyprus 81.3
        "CZ": -0.1,  // Czech Republic 78.4
        "SK": -1.1,  // Slovakia 77.4
        "PL": -1.2,  // Poland 77.3
        "EE": -1.4,  // Estonia 77.1
        "LT": -1.9,  // Lithuania 76.6
        "LV": -3.4,  // Latvia 75.1
        "HU": -2.8,  // Hungary 75.7
        "RO": -3.2,  // Romania 75.3
        "BG": -3.4,  // Bulgaria 75.1
        "HR": 0.1,   // Croatia 78.6
        "RS": -2.5,  // Serbia 76.0
        "BA": -2.5,  // Bosnia 76.0
        "AL": -3.0,  // Albania 75.5
        "MK": -3.0,  // North Macedonia 75.5
        "RU": -5.9,  // Russia 72.6
        "UA": -5.5,  // Ukraine 73.0
        "BY": -5.5,  // Belarus 73.0
        "MD": -5.5,  // Moldova 73.0
        "GE": -4.0,  // Georgia 74.5
        "AM": -4.5,  // Armenia 74.0
        "AZ": -3.5,  // Azerbaijan 75.0
        // Americas
        "US": 0.0,   // USA 78.5 (baseline)
        "CA": 3.2,   // Canada 81.7
        "CL": 1.6,   // Chile 80.1
        "AR": -2.0,  // Argentina 76.5
        "UY": 0.5,   // Uruguay 79.0
        "BR": -3.0,  // Brazil 75.5
        "CO": -1.4,  // Colombia 77.1
        "PE": -2.1,  // Peru 76.4
        "EC": -1.4,  // Ecuador 77.1
        "MX": -3.4,  // Mexico 75.1
        "CU": 0.3,   // Cuba 78.8
        "PA": -0.5,  // Panama 78.0
        "CR": 0.6,   // Costa Rica 79.1
        "BO": -7.6,  // Bolivia 70.9 (clamped)
        "VE": -4.5,  // Venezuela 74.0
        "PY": -3.5,  // Paraguay 75.0
        "GT": -5.5,  // Guatemala 73.0
        "HN": -6.0,  // Honduras 72.5
        "SV": -5.5,  // El Salvador 73.0
        "DO": -2.5,  // Dominican Republic 76.0
        "JM": -3.5,  // Jamaica 75.0
        "TT": -2.0,  // Trinidad and Tobago 76.5
        // Middle East / North Africa
        "AE": 0.2,   // UAE 78.7
        "QA": 0.5,   // Qatar 79.0
        "KW": -0.5,  // Kuwait 78.0
        "BH": 0.0,   // Bahrain 78.5
        "SA": -1.9,  // Saudi Arabia 76.6
        "OM": -1.5,  // Oman 77.0
        "JO": -2.0,  // Jordan 76.5
        "LB": -3.5,  // Lebanon 75.0
        "TR": -0.9,  // Turkey 77.6
        "IR": -2.0,  // Iran 76.5
        "IQ": -6.0,  // Iraq 72.5
        "SY": -7.0,  // Syria (clamped)
        "MA": -4.4,  // Morocco 74.1
        "DZ": -2.1,  // Algeria 76.4
        "TN": -3.0,  // Tunisia 75.5
        "EG": -6.2,  // Egypt 72.3
        "LY": -5.5,  // Libya 73.0
        // Sub-Saharan Africa
        "ZA": -8.0,  // South Africa (clamped)
        "NG": -8.0,  // Nigeria (clamped)
        "ET": -8.0,  // Ethiopia (clamped)
        "KE": -8.0,  // Kenya (clamped)
        "TZ": -8.0,  // Tanzania (clamped)
        "GH": -8.0,  // Ghana (clamped)
        "CI": -8.0,  // Côte d'Ivoire (clamped)
        "CM": -8.0,  // Cameroon (clamped)
        "SN": -8.0,  // Senegal (clamped)
        "UG": -8.0,  // Uganda (clamped)
        "ZW": -8.0,  // Zimbabwe (clamped)
        "ZM": -8.0,  // Zambia (clamped)
        "RW": -8.0,  // Rwanda (clamped)
    ]

    private static let displayNames: [String: String] = [
        "AE": "United Arab Emirates",
        "AL": "Albania",
        "AM": "Armenia",
        "AR": "Argentina",
        "AT": "Austria",
        "AU": "Australia",
        "AZ": "Azerbaijan",
        "BA": "Bosnia & Herzegovina",
        "BD": "Bangladesh",
        "BE": "Belgium",
        "BG": "Bulgaria",
        "BH": "Bahrain",
        "BO": "Bolivia",
        "BR": "Brazil",
        "BY": "Belarus",
        "CA": "Canada",
        "CH": "Switzerland",
        "CI": "Côte d'Ivoire",
        "CL": "Chile",
        "CM": "Cameroon",
        "CN": "China",
        "CO": "Colombia",
        "CR": "Costa Rica",
        "CU": "Cuba",
        "CY": "Cyprus",
        "CZ": "Czech Republic",
        "DE": "Germany",
        "DK": "Denmark",
        "DO": "Dominican Republic",
        "DZ": "Algeria",
        "EC": "Ecuador",
        "EE": "Estonia",
        "EG": "Egypt",
        "ES": "Spain",
        "ET": "Ethiopia",
        "FI": "Finland",
        "FR": "France",
        "GB": "United Kingdom",
        "GE": "Georgia",
        "GH": "Ghana",
        "GR": "Greece",
        "GT": "Guatemala",
        "HK": "Hong Kong",
        "HN": "Honduras",
        "HR": "Croatia",
        "HU": "Hungary",
        "ID": "Indonesia",
        "IE": "Ireland",
        "IL": "Israel",
        "IN": "India",
        "IQ": "Iraq",
        "IR": "Iran",
        "IS": "Iceland",
        "IT": "Italy",
        "JM": "Jamaica",
        "JO": "Jordan",
        "JP": "Japan",
        "KE": "Kenya",
        "KH": "Cambodia",
        "KR": "South Korea",
        "KW": "Kuwait",
        "KZ": "Kazakhstan",
        "LB": "Lebanon",
        "LK": "Sri Lanka",
        "LT": "Lithuania",
        "LU": "Luxembourg",
        "LV": "Latvia",
        "LY": "Libya",
        "MA": "Morocco",
        "MD": "Moldova",
        "MK": "North Macedonia",
        "MM": "Myanmar",
        "MN": "Mongolia",
        "MT": "Malta",
        "MX": "Mexico",
        "MY": "Malaysia",
        "NG": "Nigeria",
        "NL": "Netherlands",
        "MO": "Macau",
        "NP": "Nepal",
        "NO": "Norway",
        "NZ": "New Zealand",
        "OM": "Oman",
        "PA": "Panama",
        "PE": "Peru",
        "PH": "Philippines",
        "PK": "Pakistan",
        "PL": "Poland",
        "PT": "Portugal",
        "PY": "Paraguay",
        "QA": "Qatar",
        "RO": "Romania",
        "RS": "Serbia",
        "RU": "Russia",
        "RW": "Rwanda",
        "SA": "Saudi Arabia",
        "SE": "Sweden",
        "SG": "Singapore",
        "SI": "Slovenia",
        "SK": "Slovakia",
        "SN": "Senegal",
        "SV": "El Salvador",
        "SY": "Syria",
        "TH": "Thailand",
        "TN": "Tunisia",
        "TR": "Turkey",
        "TT": "Trinidad & Tobago",
        "TW": "Taiwan",
        "TZ": "Tanzania",
        "UA": "Ukraine",
        "UG": "Uganda",
        "US": "United States",
        "UY": "Uruguay",
        "UZ": "Uzbekistan",
        "VE": "Venezuela",
        "VN": "Vietnam",
        "ZA": "South Africa",
        "ZM": "Zambia",
        "ZW": "Zimbabwe",
    ]

    // MARK: Region Delta Tables (sub-country life-expectancy gap vs country baseline)
    //
    // Values are delta-from-country in years. US states sourced from CDC NVSR
    // "U.S. State Life Tables, 2021"; Canadian provinces from Statistics Canada
    // Table 13-10-0837-01 (2020-2022); UK nations from ONS National Life Tables
    // 2020-2022; Australian states from AIHW life expectancy 2020-2022.
    // Clamped to ±3.0 in the accessor.

    private static let regionDeltas: [String: Double] = [
        // US states (vs 78.5 baseline). CDC 2021 data.
        "US-HI": 2.3,  "US-CA": 1.5,  "US-MA": 1.7,  "US-CT": 1.9,  "US-MN": 1.4,
        "US-NY": 0.9,  "US-NJ": 1.1,  "US-WA": 0.4,  "US-CO": 0.8,  "US-RI": 1.1,
        "US-NH": 1.0,  "US-VT": 0.9,  "US-OR": 0.2,  "US-UT": 0.7,  "US-ID": 0.0,
        "US-VA": 0.1,  "US-MD": 0.3,  "US-DC": 0.5,  "US-IL": -0.2, "US-WI": 0.0,
        "US-NE": -0.1, "US-IA": -0.3, "US-ND": -0.1, "US-SD": -0.6, "US-MT": -0.4,
        "US-WY": -0.9, "US-AK": -1.2, "US-KS": -0.8, "US-DE": -0.3, "US-ME": 0.4,
        "US-PA": -0.6, "US-AZ": -0.4, "US-FL": -1.0, "US-TX": -2.0, "US-NC": -1.3,
        "US-GA": -1.9, "US-NM": -2.8, "US-NV": -1.5, "US-MI": -1.1, "US-OH": -1.6,
        "US-IN": -1.8, "US-MO": -2.1, "US-SC": -2.4, "US-OK": -3.0, "US-AR": -3.0,
        "US-KY": -3.0, "US-LA": -3.0, "US-TN": -3.0, "US-AL": -3.0, "US-MS": -3.0,
        "US-WV": -3.0,
        // Canadian provinces (vs CA 81.7 baseline). StatCan 2020-2022.
        "CA-BC": 0.7,  "CA-ON": 0.5,  "CA-QC": 0.4,  "CA-AB": -0.3, "CA-MB": -1.1,
        "CA-SK": -1.4, "CA-NS": -0.9, "CA-NB": -0.8, "CA-PE": 0.0,  "CA-NL": -1.3,
        "CA-YT": -2.3, "CA-NT": -3.0, "CA-NU": -3.0,
        // UK nations (vs GB 81.3 baseline). ONS 2020-2022.
        "GB-ENG": 0.1, "GB-WLS": -0.7, "GB-SCT": -1.4, "GB-NIR": -0.6,
        // Australian states (vs AU 82.8 baseline). AIHW 2020-2022.
        "AU-ACT": 0.7, "AU-VIC": 0.3,  "AU-WA": 0.2,   "AU-NSW": 0.1,
        "AU-SA": -0.1, "AU-QLD": -0.1, "AU-TAS": -1.3, "AU-NT": -3.0,
    ]

    private static let regionNames: [String: String] = [
        "US-AL": "Alabama", "US-AK": "Alaska", "US-AZ": "Arizona", "US-AR": "Arkansas",
        "US-CA": "California", "US-CO": "Colorado", "US-CT": "Connecticut", "US-DE": "Delaware",
        "US-DC": "District of Columbia", "US-FL": "Florida", "US-GA": "Georgia", "US-HI": "Hawaii",
        "US-ID": "Idaho", "US-IL": "Illinois", "US-IN": "Indiana", "US-IA": "Iowa",
        "US-KS": "Kansas", "US-KY": "Kentucky", "US-LA": "Louisiana", "US-ME": "Maine",
        "US-MD": "Maryland", "US-MA": "Massachusetts", "US-MI": "Michigan", "US-MN": "Minnesota",
        "US-MS": "Mississippi", "US-MO": "Missouri", "US-MT": "Montana", "US-NE": "Nebraska",
        "US-NV": "Nevada", "US-NH": "New Hampshire", "US-NJ": "New Jersey", "US-NM": "New Mexico",
        "US-NY": "New York", "US-NC": "North Carolina", "US-ND": "North Dakota", "US-OH": "Ohio",
        "US-OK": "Oklahoma", "US-OR": "Oregon", "US-PA": "Pennsylvania", "US-RI": "Rhode Island",
        "US-SC": "South Carolina", "US-SD": "South Dakota", "US-TN": "Tennessee", "US-TX": "Texas",
        "US-UT": "Utah", "US-VT": "Vermont", "US-VA": "Virginia", "US-WA": "Washington",
        "US-WV": "West Virginia", "US-WI": "Wisconsin", "US-WY": "Wyoming",
        "CA-AB": "Alberta", "CA-BC": "British Columbia", "CA-MB": "Manitoba",
        "CA-NB": "New Brunswick", "CA-NL": "Newfoundland and Labrador",
        "CA-NS": "Nova Scotia", "CA-NT": "Northwest Territories", "CA-NU": "Nunavut",
        "CA-ON": "Ontario", "CA-PE": "Prince Edward Island", "CA-QC": "Quebec",
        "CA-SK": "Saskatchewan", "CA-YT": "Yukon",
        "GB-ENG": "England", "GB-WLS": "Wales", "GB-SCT": "Scotland", "GB-NIR": "Northern Ireland",
        "AU-ACT": "Australian Capital Territory", "AU-NSW": "New South Wales",
        "AU-NT": "Northern Territory", "AU-QLD": "Queensland", "AU-SA": "South Australia",
        "AU-TAS": "Tasmania", "AU-VIC": "Victoria", "AU-WA": "Western Australia",
    ]
}
