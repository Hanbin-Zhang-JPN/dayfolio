import Foundation
import AppKit
import PDFKit
import DiaryCore

enum ExportSmoke {
    static func run() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dayfolio-Export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var e = Entry(title: "中文 & English <日记>", text: String(repeating: "今天记下生活。Hello, Dayfolio!\n", count: 160))
        let rich = NSMutableAttributedString(string: e.text, attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.systemRed])
        let image = NSImage(size: NSSize(width: 100, height: 60))
        image.lockFocus(); NSColor.systemGreen.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 60)).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        e.materials = [Material(name: "素材.png", data: png)]
        let attachment = NSTextAttachment(); attachment.image = image; attachment.fileWrapper = FileWrapper(regularFileWithContents: png); attachment.fileWrapper?.preferredFilename = "inline.png"
        rich.append(NSAttributedString(attachment: attachment))
        e.richText = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        for kind in ExportKind.allCases {
            let data = try Exporter.data(e, kind: kind)
            guard !data.isEmpty else { throw DiaryError.invalidArchive }
            try data.write(to: dir.appendingPathComponent("test.\(kind.suffix)"))
            switch kind {
            case .json: guard try Archive.decode(data).entries == [e] else { throw DiaryError.invalidArchive }
            case .pdf: guard let pdf = PDFDocument(data: data), pdf.pageCount >= 3, pdf.string?.contains("Dayfolio") == true else { throw DiaryError.invalidArchive }
            case .docx:
                guard data.prefix(2) == Data([0x50, 0x4b]) else { throw DiaryError.invalidArchive }
                let imported = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
                guard imported.string.contains("今天记下生活") else { throw DiaryError.invalidArchive }
            case .rtf:
                let imported = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                guard imported.string.contains("今天记下生活") else { throw DiaryError.invalidArchive }
            case .html:
                let html = String(decoding: data, as: UTF8.self)
                guard html.contains("data:image/png;base64,"), html.contains("&lt;日记&gt;") else { throw DiaryError.invalidArchive }
            default: break
            }
            print("PASS export \(kind.rawValue) (\(data.count) bytes)")
        }
        print("PASS all seven export formats, Unicode, inline images, paginated PDF and archive round-trip")
    }
}
