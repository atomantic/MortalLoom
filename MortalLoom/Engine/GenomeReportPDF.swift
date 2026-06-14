import CoreGraphics
import CoreText
import Foundation

// MARK: - Report content model
//
// The Genome visit report is built in two pure passes. First a `GenomeReport`
// builder turns the app's ranked findings / ClinVar hits / captured notes into a
// framework-free `GenomeReportContent` value (title, meta lines, sections of
// blocks). Then `GenomeReport.pdfData(for:)` lays that value out into PDF bytes
// with Core Graphics + Core Text — no UIKit/AppKit, so the same code paginates
// identically on iOS and macOS and the content model is unit-testable in
// isolation (the renderer just draws what the builder returns).

struct GenomeReportContent: Equatable {
    let title: String
    let meta: [String]
    let sections: [Section]

    struct Section: Equatable {
        let title: String
        let blocks: [ReportBlock]
    }
}

/// A single laid-out element. The renderer maps each case to a typographic
/// treatment; the builder decides which cases appear and in what order.
enum ReportBlock: Equatable {
    case findingHeader(title: String, status: String, genotype: String?)
    case body(String)
    case bullet(String)
    case talkingPoint(String)
    case note(finding: String, date: String, provider: String?, body: String, followUp: String?)
}

// MARK: - Builder

enum GenomeReport {

    /// Privacy-first footer line — reinforces the brand promise and that this is
    /// an educational summary, not a clinical diagnosis.
    static let disclaimer = "Private to you — generated on your device. An educational summary, not a medical diagnosis."

    /// Suggested export filename, e.g. `MortalLoom-VisitPrep-2026-06-13.pdf`.
    static func filename(prefix: String, date: Date) -> String {
        "MortalLoom-\(prefix)-\(DateFormatting.dateString(date)).pdf"
    }

    // MARK: Pre-visit prep

    /// Pre-visit prep: the top priority findings (each with its curated actions),
    /// drug-response variants for the pharmacist, and a deduped list of doctor
    /// talking points. Empty sections are dropped.
    static func previsit(priorities: [PriorityFinding],
                         clinvarHits: [ClinVarHit],
                         date: Date) -> GenomeReportContent {
        // Bucket the action library once and thread it through, rather than
        // re-bucketing the whole library on every per-finding lookup.
        let buckets = GenomePriorityEngine.bucketActions()
        let sections = [
            section("Top Priorities", priorities.flatMap { priorityBlocks(for: $0, buckets: buckets) }),
            section("Drug-Response Variants", drugResponseBlocks(clinvarHits)),
            section("Questions for Your Doctor", talkingPointBlocks(priorities, buckets: buckets)),
        ].compactMap { $0 }

        return GenomeReportContent(
            title: "Doctor Visit Prep",
            meta: ["Prepared \(DateFormatting.displayDate(DateFormatting.dateString(date)))", disclaimer],
            sections: sections
        )
    }

    // MARK: Post-visit summary

    /// Post-visit summary: the findings reviewed, the notes captured during the
    /// appointment (with follow-ups), and the drug-response variants. `findings`
    /// is the snapshot Visit Mode walked through; `notes` are the notes to
    /// include — the caller passes the ones saved this visit.
    static func postvisit(findings: [PriorityFindingSource],
                          clinvarHits: [ClinVarHit],
                          notes: [VisitNote],
                          date: Date,
                          provider: String?) -> GenomeReportContent {
        let reviewed: [ReportBlock] = findings.map {
            .findingHeader(title: $0.title, status: $0.statusLabel, genotype: $0.displayGenotype)
        }

        // Map a note's findingKey back to a human title where the finding is in
        // the visited set; fall back to the raw key otherwise.
        let titlesByKey = Dictionary(findings.map { ($0.findingKey, $0.title) },
                                     uniquingKeysWith: { first, _ in first })
        let noteBlocks: [ReportBlock] = notes
            .sorted { $0.date < $1.date }
            .map { note in
                .note(
                    finding: titlesByKey[note.findingKey] ?? note.findingKey,
                    date: DateFormatting.displayDate(note.date),
                    provider: note.providerLabel,
                    body: note.body,
                    followUp: note.followUp
                )
            }

        let sections = [
            section("Findings Reviewed", reviewed),
            section("Visit Notes", noteBlocks),
            section("Drug-Response Variants", drugResponseBlocks(clinvarHits)),
        ].compactMap { $0 }

        var meta = ["Visit \(DateFormatting.displayDate(DateFormatting.dateString(date)))"]
        if let provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            meta.append("Provider: \(provider)")
        }
        meta.append(disclaimer)

        return GenomeReportContent(title: "Doctor Visit Summary", meta: meta, sections: sections)
    }

    // MARK: Block builders

    /// Wrap blocks into a section, or `nil` when there's nothing to show — lets
    /// callers assemble a section list with `.compactMap` instead of repeating
    /// the empty-check + append boilerplate.
    private static func section(_ title: String, _ blocks: [ReportBlock]) -> GenomeReportContent.Section? {
        blocks.isEmpty ? nil : .init(title: title, blocks: blocks)
    }

    /// Header for one priority finding plus up to four of its curated actions as
    /// bullets. Caps the action list so a finding with many actions doesn't bury
    /// the rest of the report.
    private static func priorityBlocks(for finding: PriorityFinding,
                                       buckets: GenomePriorityEngine.ActionBuckets) -> [ReportBlock] {
        var blocks: [ReportBlock] = [
            .findingHeader(title: finding.title,
                           status: finding.statusLabel,
                           genotype: finding.source.displayGenotype)
        ]
        for action in GenomePriorityEngine.actions(for: finding.source, bucketed: buckets).prefix(4) {
            blocks.append(.bullet("\(action.kind.label): \(action.title)"))
        }
        return blocks
    }

    /// Drug-response ClinVar hits — surfaced separately because they matter at
    /// the pharmacy counter regardless of whether they made the priority cap.
    private static func drugResponseBlocks(_ hits: [ClinVarHit]) -> [ReportBlock] {
        let drug = hits.filter { $0.entry.severity == "drug_response" }
        guard !drug.isEmpty else { return [] }

        var blocks: [ReportBlock] = [
            .body("Share these with your pharmacist before any new prescription — they affect how you metabolize specific medications.")
        ]
        for hit in drug {
            let gene = hit.entry.gene.isEmpty ? hit.rsid : hit.entry.gene
            blocks.append(.findingHeader(title: "\(gene) (\(hit.rsid))",
                                         status: "Drug Response",
                                         genotype: hit.genotype))
            let conditions = hit.entry.conditions.filter { !$0.isEmpty }.joined(separator: ", ")
            if !conditions.isEmpty { blocks.append(.body(conditions)) }
        }
        return blocks
    }

    /// Deduped doctor talking points drawn from every priority's curated actions,
    /// preserving priority order.
    private static func talkingPointBlocks(_ priorities: [PriorityFinding],
                                           buckets: GenomePriorityEngine.ActionBuckets) -> [ReportBlock] {
        var seen: Set<String> = []
        var blocks: [ReportBlock] = []
        for finding in priorities {
            for action in GenomePriorityEngine.actions(for: finding.source, bucketed: buckets) {
                guard let point = action.doctorTalkingPoint?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !point.isEmpty, !seen.contains(point) else { continue }
                seen.insert(point)
                blocks.append(.talkingPoint(point))
            }
        }
        return blocks
    }
}

// MARK: - PDF renderer

extension GenomeReport {

    private enum Page {
        static let size = CGSize(width: 612, height: 792) // US Letter
        static let margin: CGFloat = 54
        static var contentWidth: CGFloat { size.width - margin * 2 }
    }

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    private static let ink = makeColor(0.11, 0.12, 0.15)
    private static let muted = makeColor(0.45, 0.47, 0.52)
    private static let accent = makeColor(0.30, 0.55, 0.96)
    private static let rule = makeColor(0.82, 0.84, 0.88)

    /// Render a report into PDF bytes. Returns empty `Data` only if the CG PDF
    /// context can't be created (never expected for an in-memory consumer).
    static func pdfData(for content: GenomeReportContent) -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: Page.size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        var pageOpen = false
        var yFromTop = Page.margin

        func beginPage() { ctx.beginPDFPage(nil); pageOpen = true; yFromTop = Page.margin }
        func endPage() { if pageOpen { ctx.endPDFPage(); pageOpen = false } }

        /// Force a page break when `needed` points won't fit below the cursor —
        /// used to keep a section heading attached to its first lines.
        func ensureSpace(_ needed: CGFloat) {
            if yFromTop + needed > Page.size.height - Page.margin { endPage(); beginPage() }
        }

        /// Draw an attributed string, paginating across pages for long runs.
        /// Advances `yFromTop` by the consumed height plus `spacingAfter`.
        func draw(_ attr: NSAttributedString, indent: CGFloat = 0, spacingAfter: CGFloat = 6) {
            if attr.length == 0 { yFromTop += spacingAfter; return }
            let x = Page.margin + indent
            let width = Page.contentWidth - indent
            let framesetter = CTFramesetterCreateWithAttributedString(attr)
            var start = 0
            let total = attr.length

            while start < total {
                if !pageOpen { beginPage() }
                // Too little room for even one line — break to a fresh page.
                if Page.size.height - Page.margin - yFromTop < 18 { endPage(); beginPage(); continue }

                let rect = CGRect(x: x, y: Page.margin,
                                  width: width,
                                  height: Page.size.height - Page.margin - yFromTop)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: start, length: total - start),
                    CGPath(rect: rect, transform: nil),
                    nil
                )
                CTFrameDraw(frame, ctx)

                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { endPage(); beginPage(); continue }

                let consumed = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter,
                    CFRange(location: start, length: visible.length),
                    nil,
                    CGSize(width: width, height: .greatestFiniteMagnitude),
                    nil
                )
                yFromTop += consumed.height
                start += visible.length
                if start < total { endPage(); beginPage() } // continued overleaf
            }
            yFromTop += spacingAfter
        }

        func sectionHeading(_ text: String) {
            // Thin rule above the heading (Core Graphics is y-up in a PDF context).
            ctx.saveGState()
            ctx.setStrokeColor(rule)
            ctx.setLineWidth(0.5)
            let lineY = Page.size.height - yFromTop
            ctx.move(to: CGPoint(x: Page.margin, y: lineY))
            ctx.addLine(to: CGPoint(x: Page.size.width - Page.margin, y: lineY))
            ctx.strokePath()
            ctx.restoreGState()
            yFromTop += 10
            draw(string(text, font: font("Helvetica-Bold", 14), color: ink), spacingAfter: 7)
        }

        func render(_ block: ReportBlock) {
            switch block {
            case let .findingHeader(title, status, genotype):
                ensureSpace(34)
                let m = NSMutableAttributedString()
                m.append(string(title, font: font("Helvetica-Bold", 11.5), color: ink))
                var trailing = "   \(status)"
                if let genotype, !genotype.isEmpty { trailing += " · \(genotype)" }
                m.append(string(trailing, font: font("Helvetica", 9.5), color: muted))
                draw(m, spacingAfter: 3)

            case let .body(text):
                draw(string(text, font: font("Helvetica", 10.5), color: ink), spacingAfter: 5)

            case let .bullet(text):
                draw(string("•  \(text)", font: font("Helvetica", 10.5), color: ink),
                     indent: 12, spacingAfter: 3)

            case let .talkingPoint(text):
                ensureSpace(30)
                let m = NSMutableAttributedString()
                m.append(string("Ask: ", font: font("Helvetica-Bold", 9.5), color: accent))
                m.append(string(text, font: font("Helvetica-Oblique", 10.5), color: ink))
                draw(m, spacingAfter: 7)

            case let .note(finding, date, provider, body, followUp):
                ensureSpace(40)
                draw(string(finding, font: font("Helvetica-Bold", 11), color: ink), spacingAfter: 1)
                var metaLine = date
                if let provider, !provider.isEmpty { metaLine += " · \(provider)" }
                draw(string(metaLine, font: font("Helvetica", 9.5), color: muted), spacingAfter: 2)
                draw(string(body, font: font("Helvetica", 10.5), color: ink), spacingAfter: 2)
                if let followUp, !followUp.isEmpty {
                    let m = NSMutableAttributedString()
                    m.append(string("Follow-up: ", font: font("Helvetica-Bold", 9.5), color: accent))
                    m.append(string(followUp, font: font("Helvetica", 10.5), color: ink))
                    draw(m, spacingAfter: 8)
                } else {
                    yFromTop += 6
                }
            }
        }

        beginPage()
        draw(string(content.title, font: font("Helvetica-Bold", 22), color: ink), spacingAfter: 4)
        for line in content.meta {
            draw(string(line, font: font("Helvetica", 9.5), color: muted), spacingAfter: 1)
        }
        yFromTop += 10

        for section in content.sections {
            ensureSpace(46)
            sectionHeading(section.title)
            for block in section.blocks { render(block) }
            yFromTop += 8
        }

        endPage()
        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: Typography helpers

    private static func font(_ name: String, _ size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    private static func makeColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        // deviceRGB + 4 components always constructs — the fallback never runs.
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, 1])
            ?? CGColor(colorSpace: CGColorSpaceCreateDeviceGray(), components: [0, 1])!
    }

    private static func string(_ text: String, font: CTFont, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [fontKey: font, colorKey: color])
    }
}
