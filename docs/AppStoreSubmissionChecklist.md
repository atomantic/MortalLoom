# App Store Submission Checklist

Manual steps that live in App Store Connect (not in the codebase) and must be
re-verified for each submission. The on-device `PrivacyInfo.xcprivacy` manifest is
the source of truth for accessed-API reasons; this file tracks the **nutrition
label** declarations that are configured in the ASC web console.

## Privacy Nutrition Labels

MortalLoom is privacy-first: no accounts, no telemetry, no third-party tracking. The
only outbound network calls are to public, keyless, account-less APIs.

| Data type | Collected? | Linked to you? | Used for tracking? | Why |
|---|---|---|---|---|
| Coarse Location | Yes (transient) | **Not Linked to You** | No | A rounded ~1 km coordinate is sent to `air-quality-api.open-meteo.com` for a single AQI lookup. No account/API key/cookie; the coordinate is never persisted (`AirQualityService.fetch` rounds to 0.01°, `LocationService.clearCoordinate()` discards it after use). |

**Verify before each submission:** in App Store Connect → App Privacy, confirm
**Coarse Location** is declared as *collected*, **Not Linked to You**, **not used for
tracking**, with the "App Functionality" purpose. No other data types are collected.

Reference: `MortalLoom/Services/AirQualityService.swift`,
`MortalLoom/Services/LocationService.swift`, `MortalLoom/App/PrivacyInfo.xcprivacy`.
