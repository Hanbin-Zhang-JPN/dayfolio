import Foundation
import AppKit
import CoreText
import DiaryCore

enum ExportKind: String, CaseIterable {
    case txt = "纯文本 TXT", markdown = "Markdown", html = "网页 HTML", rtf = "富文本 RTF", docx = "Word DOCX", pdf = "PDF", json = "JSON（含素材）"
    var suffix: String { switch self { case .markdown: return "md"; case .json: return "json"; default: return String(describing: self) } }
}

@MainActor extension DiaryStore {
    func export(_ kind: ExportKind) {
        guard let entry = current else { return }; saveNow()
        let panel = NSSavePanel()
        let name = entry.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(name).\(kind.suffix)"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Exporter.data(entry, kind: kind).write(to: url, options: .atomic) }
            catch { message = "导出失败：\(error.localizedDescription)" }
        }
    }
}

enum Exporter {
    static func data(_ entry: Entry, kind: ExportKind) throws -> Data {
        switch kind {
        case .txt: return Data(PlainExport.text(entry).utf8)
        case .markdown: return Data(PlainExport.markdown(entry).utf8)
        case .json: return try Archive(entries: [entry]).encoded()
        case .html:
            // AppKit's HTML serializer retains character formatting. Use only its body fragment.
            let rich = NSMutableAttributedString(attributedString: entry.attributed)
            var inlineImages = ""
            rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length), options: .reverse) { value, range, _ in
                if let a = value as? NSTextAttachment {
                    let data = a.fileWrapper?.regularFileContents ?? a.image?.tiffRepresentation
                    if let data, let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                        inlineImages = "<figure><img src=\"data:image/png;base64,\(png.base64EncodedString())\"></figure>" + inlineImages
                    }
                    rich.replaceCharacters(in: range, with: "[图片见文末]")
                }
            }
            let data = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue])
            let source = String(data: data, encoding: .utf8) ?? ""
            let body: String?
            if let start = source.range(of: "<body"), let end = source.range(of: "</body>"), let close = source[start.upperBound...].firstIndex(of: ">") {
                let styles: String
                if let s = source.range(of: "<style"), let e = source.range(of: "</style>") { styles = String(source[s.lowerBound..<e.upperBound]) } else { styles = "" }
                body = styles + String(source[source.index(after: close)..<end.lowerBound]) + inlineImages
            } else { body = nil }
            return Data(PlainExport.html(entry, body: body).utf8)
        case .rtf, .docx:
            let document = richDocument(entry)
            return try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: kind == .rtf ? NSAttributedString.DocumentType.rtf : .officeOpenXML])
        case .pdf: return try pdf(entry)
        }
    }
    static func richDocument(_ entry: Entry) -> NSAttributedString {
        let title = NSAttributedString(string: entry.displayTitle + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.black])
        let doc = NSMutableAttributedString(attributedString: title)
        doc.append(NSAttributedString(string: "\(PlainExport.timestamp(entry.date)) · \(entry.mood) · \(entry.tags)\n\n", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray]))
        doc.append(entry.attributed)
        // Resolve adaptive system colors against a light appearance for portable documents.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            doc.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: doc.length)) { value, range, _ in
                if let c = value as? NSColor, let rgb = c.usingColorSpace(.deviceRGB) { doc.addAttribute(.foregroundColor, value: NSColor(deviceRed: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent), range: range) }
            }
        }
        doc.append(NSAttributedString(string: "\n\n写作时长：\(Int(entry.writingSeconds)) 秒\n创建：\(PlainExport.timestamp(entry.createdAt))\n更新：\(PlainExport.timestamp(entry.modifiedAt))\n" + (entry.materials.isEmpty ? "" : "\n素材：" + entry.materials.map(\.name).joined(separator: "、")), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray]))
        return doc
    }
    static func pdf(_ entry: Entry) throws -> Data {
        let result = NSMutableData()
        guard let consumer = CGDataConsumer(data: result) else { throw DiaryError.invalidArchive }
        var media = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw DiaryError.invalidArchive }
        let doc = richDocument(entry)
        let framesetter = CTFramesetterCreateWithAttributedString(doc)
        var offset = 0, page = 1
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: CGRect(x: 48, y: 60, width: 499, height: 730), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let label = NSAttributedString(string: "Dayfolio · \(page)", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.gray])
            context.textPosition = CGPoint(x: 260, y: 30); CTLineDraw(CTLineCreateWithAttributedString(label), context)
            let count = CTFrameGetVisibleStringRange(frame).length
            guard count > 0 else { context.endPDFPage(); context.closePDF(); throw NSError(domain: "Dayfolio", code: 4, userInfo: [NSLocalizedDescriptionKey: "内容无法分页，请缩小内嵌图片或字体后重试。"]) }
            offset += count; page += 1; context.endPDFPage()
        } while offset < doc.length
        // CoreText does not draw NSTextAttachment images; add each image as a separate fitted page.
        var images: [NSImage] = []
        entry.attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: entry.attributed.length)) { value, _, _ in
            if let a = value as? NSTextAttachment, let image = a.image ?? a.fileWrapper?.regularFileContents.flatMap({ NSImage(data: $0) }) { images.append(image) }
        }
        images.append(contentsOf: entry.materials.filter(\.isImage).compactMap { NSImage(data: $0.data) })
        for image in images {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            context.beginPDFPage(nil)
            let ratio = min(499 / CGFloat(cg.width), 730 / CGFloat(cg.height))
            let w = CGFloat(cg.width) * ratio, h = CGFloat(cg.height) * ratio
            context.draw(cg, in: CGRect(x: (595 - w) / 2, y: (842 - h) / 2, width: w, height: h)); context.endPDFPage()
        }
        context.closePDF(); return result as Data
    }
}
