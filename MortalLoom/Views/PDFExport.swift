import SwiftUI
import UniformTypeIdentifiers

/// PDF bytes plus a suggested filename, used to drive the cross-platform export
/// UI. Identifiable so it can present a `.sheet(item:)` / `.fileExporter`.
struct PDFExport: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}

/// A `FileDocument` wrapping raw PDF bytes for the macOS file exporter. Mirrors
/// the JSON/markdown document wrappers used elsewhere in the app.
struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension View {
    /// Cross-platform PDF export. iOS presents the system share sheet — which
    /// offers AirPrint for PDFs — so the user can print or hand the report to
    /// any share target. macOS uses the standard file exporter, matching the
    /// rest of the app's export surfaces (Reports, Settings).
    func pdfExport(_ item: Binding<PDFExport?>) -> some View {
        modifier(PDFExportModifier(item: item))
    }
}

#if os(iOS)
import UIKit

private struct PDFExportModifier: ViewModifier {
    @Binding var item: PDFExport?

    func body(content: Content) -> some View {
        content.sheet(item: $item) { export in
            PDFActivityView(export: export)
                .ignoresSafeArea()
        }
    }
}

/// Wraps `UIActivityViewController` so a PDF can be shared (and AirPrinted). The
/// bytes are written to a temp file first so the share sheet shows a proper
/// filename and the Print activity gets a paginated PDF to render.
private struct PDFActivityView: UIViewControllerRepresentable {
    let export: PDFExport

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.filename)
        if (try? export.data.write(to: url, options: .atomic)) != nil {
            items = [url]
        } else {
            // Temp write failed (rare) — fall back to sharing the raw data so the
            // user still gets a share sheet, just without a filename/print path.
            items = [export.data]
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else

private struct PDFExportModifier: ViewModifier {
    @Binding var item: PDFExport?

    func body(content: Content) -> some View {
        content.fileExporter(
            isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
            document: item.map { PDFFileDocument(data: $0.data) },
            contentType: .pdf,
            defaultFilename: item?.filename ?? "GenomeReport"
        ) { _ in
            item = nil
        }
    }
}
#endif
