import CoreGraphics
import CoreText
import Foundation

/// The data needed to render a blood panel report. Keeping the input as a value
/// makes PDF generation deterministic and free of storage or UI side effects.
struct BloodReport {
    let generatedAt: Date
    let tests: [BloodTest]
}

enum BloodReportPDF {

    struct Row: Equatable {
        let category: String
        let markerKey: String
        let label: String
        let value: String
        let referenceRange: String
        let status: String
        let delta: String?

        var isFlagged: Bool { status != "Normal" }
    }

    struct Category: Equatable {
        let name: String
        let rows: [Row]
    }

    private enum Page {
        static let size = CGSize(width: 612, height: 792) // US Letter
        static let margin: CGFloat = 48
        static var contentWidth: CGFloat { size.width - margin * 2 }
    }

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    private static let ink = makeColor(0.10, 0.11, 0.13)
    private static let muted = makeColor(0.42, 0.44, 0.48)
    private static let rule = makeColor(0.78, 0.80, 0.84)

    static func filename(date: Date) -> String {
        "MortalLoom-Blood-\(DateFormatting.dateString(date)).pdf"
    }

    /// Builds rows in the same category/marker order used by BloodView. Unknown
    /// marker keys never enter the output because only the canonical catalog is
    /// walked.
    static func categories(for report: BloodReport) -> [Category] {
        let sortedTests = report.tests.sorted { $0.date < $1.date }
        guard let latest = sortedTests.last else { return [] }

        let trendsByKey = Dictionary(
            uniqueKeysWithValues: BloodTrendEngine.analyze(tests: sortedTests).map { ($0.id, $0) }
        )

        return BloodMarkers.categories.compactMap { category in
            let rows = category.keys.compactMap { key -> Row? in
                guard let ref = BloodMarkers.byKey[key], let value = latest.markers[key] else { return nil }
                let markerStatus = ref.status(for: value)
                let delta = markerStatus == .normal
                    ? nil
                    : deltaText(for: key, trend: trendsByKey[key], tests: sortedTests)
                return Row(
                    category: category.name,
                    markerKey: key,
                    label: ref.label,
                    value: valueText(value, unit: ref.unit),
                    referenceRange: rangeText(ref),
                    status: statusText(markerStatus),
                    delta: delta
                )
            }
            return rows.isEmpty ? nil : Category(name: category.name, rows: rows)
        }
    }

    /// Renders a doctor-ready, grayscale-safe US Letter PDF. The function has
    /// no side effects and always emits at least one page, including when there
    /// are no blood tests.
    static func pdfData(for report: BloodReport) -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: Page.size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let categories = categories(for: report)
        let flagged = categories.flatMap(\.rows).filter(\.isFlagged)
        let latestDate = report.tests.map(\.date).max()
        var pageOpen = false
        var yFromTop = Page.margin

        func beginPage() {
            context.beginPDFPage(nil)
            pageOpen = true
            yFromTop = Page.margin
        }

        func endPage() {
            if pageOpen { context.endPDFPage(); pageOpen = false }
        }

        func ensureSpace(_ needed: CGFloat) {
            if yFromTop + needed > Page.size.height - Page.margin {
                endPage()
                beginPage()
            }
        }

        func drawText(_ text: String, font: CTFont, color: CGColor = ink,
                      indent: CGFloat = 0, spacingAfter: CGFloat = 5) {
            let attributed = string(text, font: font, color: color)
            let width = Page.contentWidth - indent
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let height = ceil(CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                nil,
                CGSize(width: width, height: .greatestFiniteMagnitude),
                nil
            ).height)
            ensureSpace(max(height, 14))
            let rect = CGRect(
                x: Page.margin + indent,
                y: Page.size.height - yFromTop - height,
                width: width,
                height: height
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                CGPath(rect: rect, transform: nil),
                nil
            )
            CTFrameDraw(frame, context)
            yFromTop += height + spacingAfter
        }

        func drawRule() {
            context.saveGState()
            context.setStrokeColor(rule)
            context.setLineWidth(0.5)
            let y = Page.size.height - yFromTop
            context.move(to: CGPoint(x: Page.margin, y: y))
            context.addLine(to: CGPoint(x: Page.size.width - Page.margin, y: y))
            context.strokePath()
            context.restoreGState()
            yFromTop += 8
        }

        func sectionHeading(_ title: String) {
            ensureSpace(38)
            drawRule()
            drawText(title, font: font("Helvetica-Bold", 14), spacingAfter: 7)
        }

        func rowText(_ row: Row, includeCategory: Bool) -> String {
            var parts: [String] = []
            if includeCategory { parts.append(row.category) }
            parts.append(row.label)
            parts.append(row.value)
            parts.append("Ref: \(row.referenceRange)")
            let statusWithGlyph = switch row.status {
            case "Low": "↓ Low"
            case "High": "↑ High"
            case "Normal": "✓ Normal"
            default: "? Unknown"
            }
            parts.append(statusWithGlyph)
            if let delta = row.delta { parts.append(delta) }
            return parts.joined(separator: "  |  ")
        }

        func drawRow(_ row: Row, includeCategory: Bool = false) {
            ensureSpace(28)
            drawText(
                rowText(row, includeCategory: includeCategory),
                font: font(row.isFlagged ? "Helvetica-Bold" : "Helvetica", 9.5),
                spacingAfter: 4
            )
            drawRule()
        }

        beginPage()
        drawText("Blood Panel Report", font: font("Helvetica-Bold", 22), spacingAfter: 4)
        drawText(
            "Generated \(DateFormatting.displayDate(DateFormatting.dateString(report.generatedAt)))",
            font: font("Helvetica", 9.5), color: muted, spacingAfter: 1
        )
        if let latestDate {
            drawText("Latest panel \(DateFormatting.displayDate(latestDate))", font: font("Helvetica", 9.5), color: muted)
        }

        if categories.isEmpty {
            sectionHeading("Blood Panel")
            drawText("No blood test results have been recorded yet.", font: font("Helvetica", 10.5))
        } else {
            sectionHeading("Flags First")
            if flagged.isEmpty {
                drawText("No markers in the latest panel are outside their reference ranges.", font: font("Helvetica", 10.5))
            } else {
                flagged.forEach { drawRow($0, includeCategory: true) }
            }

            for category in categories {
                sectionHeading(category.name)
                drawText("Marker  |  Result  |  Reference range  |  Status  |  Change",
                         font: font("Helvetica-Bold", 8.5), color: muted, spacingAfter: 5)
                category.rows.forEach { drawRow($0) }
                yFromTop += 4
            }
        }

        yFromTop += 8
        drawText(
            "Private to you — generated on your device. Reference ranges are informational and do not replace medical advice.",
            font: font("Helvetica-Oblique", 8.5), color: muted
        )
        endPage()
        context.closePDF()
        return output as Data
    }

    private static func deltaText(
        for key: String,
        trend: BloodTrendEngine.MarkerTrend?,
        tests: [BloodTest]
    ) -> String? {
        guard let trend,
              let previousDate = tests.dropLast().reversed().first(where: { $0.markers[key] != nil })?.date else {
            return nil
        }
        let arrow: String = switch trend.direction {
        case .rising: "↑"
        case .falling: "↓"
        case .stable: "→"
        }
        let magnitude = abs(trend.latestValue - trend.previousValue)
        return "\(arrow) \(valueText(magnitude, unit: trend.unit)) vs \(previousDate)"
    }

    private static func statusText(_ status: MarkerStatus) -> String {
        switch status {
        case .normal: "Normal"
        case .low: "Low"
        case .high: "High"
        case .unknown: "Unknown"
        }
    }

    private static func valueText(_ value: Double, unit: String) -> String {
        [DateFormatting.formatMarkerValue(value), unit].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func rangeText(_ ref: BloodMarkerRef) -> String {
        "\(DateFormatting.formatMarkerValue(ref.min))–\(DateFormatting.formatMarkerValue(ref.max))" +
            (ref.unit.isEmpty ? "" : " \(ref.unit)")
    }

    private static func font(_ name: String, _ size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    private static func makeColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, 1])
            ?? CGColor(colorSpace: CGColorSpaceCreateDeviceGray(), components: [0, 1])!
    }

    private static func string(_ text: String, font: CTFont, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [fontKey: font, colorKey: color])
    }
}
