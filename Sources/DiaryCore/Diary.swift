import Foundation

public struct Material: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var data: Data
    public init(name: String, data: Data, id: UUID = UUID()) { self.id = id; self.name = name; self.data = data }
    public var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    public var isImage: Bool { ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp", "bmp"].contains(fileExtension) }
}

public struct Entry: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var date: Date
    public var createdAt: Date
    public var modifiedAt: Date
    public var text: String
    public var richText: Data?
    public var tags: String = ""
    public var mood: String = "平静"
    public var favorite = false
    public var writingSeconds: TimeInterval = 0
    public var materials: [Material] = []
    public init(title: String = "", date: Date = Date(), text: String = "") {
        self.title = title; self.date = date; self.createdAt = Date(); self.modifiedAt = Date(); self.text = text
    }
    public var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名日记" : title }
    public var stats: TextStats { TextStats(text) }
}

public struct TextStats: Equatable {
    public let characters: Int
    public let charactersWithoutSpaces: Int
    public let words: Int
    public let paragraphs: Int
    public let readingMinutes: Int
    public init(_ text: String) {
        let clean = text.replacingOccurrences(of: "\u{FFFC}", with: "")
        characters = clean.count
        charactersWithoutSpaces = clean.filter { !$0.isWhitespace }.count
        var count = 0, inWord = false
        for ch in clean {
            let isCJK = ch.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
            if isCJK { count += 1; inWord = false }
            else if ch.isLetter || ch.isNumber { if !inWord { count += 1 }; inWord = true }
            else { inWord = false }
        }
        words = count
        paragraphs = clean.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        readingMinutes = count == 0 ? 0 : max(1, Int(ceil(Double(count) / 300)))
    }
}

public struct Archive: Codable {
    public var format = "dayfolio"
    public var version = 1
    public var entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }
    public static func decode(_ data: Data) throws -> Archive {
        let result = try JSONDecoder().decode(Archive.self, from: data)
        guard result.format == "dayfolio", result.version == 1 else { throw DiaryError.invalidArchive }
        guard Set(result.entries.map(\.id)).count == result.entries.count,
              result.entries.allSatisfy({ $0.writingSeconds.isFinite && $0.writingSeconds >= 0 }) else { throw DiaryError.invalidArchive }
        return result
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
public enum DiaryError: Error, LocalizedError {
    case invalidArchive
    public var errorDescription: String? { "文件不是受支持的 Dayfolio 备份，或其中数据无效。" }
}

public final class DiaryRepository {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Archive.decode(Data(contentsOf: url)).entries
    }
    public func save(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Archive(entries: entries).encoded()
        if FileManager.default.fileExists(atPath: url.path) {
            // Keep a recoverable previous save, including all embedded materials.
            try Data(contentsOf: url).write(to: url.appendingPathExtension("previous"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
    public static func merge(_ incoming: [Entry], into existing: [Entry]) -> [Entry] {
        // Import as new entries when an ID already exists; never silently overwrite a diary.
        var result = existing
        var ids = Set(existing.map(\.id))
        for var entry in incoming {
            if ids.contains(entry.id) { entry.id = UUID(); entry.title = entry.displayTitle + "（导入副本）" }
            ids.insert(entry.id); result.append(entry)
        }
        return result
    }
}

public enum PlainExport {
    public static func text(_ entry: Entry) -> String {
        "\(entry.displayTitle)\n日期：\(timestamp(entry.date))\n心情：\(entry.mood)\n标签：\(entry.tags)\n\n\(entry.text.replacingOccurrences(of: "\u{FFFC}", with: "[内嵌图片]"))\n\n写作时长：\(Int(entry.writingSeconds)) 秒\n创建：\(timestamp(entry.createdAt))\n更新：\(timestamp(entry.modifiedAt))\n" + (entry.materials.isEmpty ? "" : "\n附件：\n" + entry.materials.map(\.name).joined(separator: "\n"))
    }
    public static func timestamp(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"; return f.string(from: date)
    }
    public static func markdown(_ entry: Entry) -> String {
        "# \(entry.displayTitle)\n\n日期：\(timestamp(entry.date))\n\n心情：\(entry.mood) · 标签：\(entry.tags)\n\n---\n\n\(entry.text)\n\n---\n写作时长：\(Int(entry.writingSeconds)) 秒\n创建：\(timestamp(entry.createdAt))\n更新：\(timestamp(entry.modifiedAt))\n" + (entry.materials.isEmpty ? "" : "\n附件：\n" + entry.materials.map { "- \($0.name)" }.joined(separator: "\n"))
    }
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    public static func html(_ entry: Entry, body: String? = nil) -> String {
        let images = entry.materials.filter(\.isImage).map { material in
            let mime: String
            switch material.fileExtension { case "jpg", "jpeg": mime = "image/jpeg"; case "heic": mime = "image/heic"; case "tiff": mime = "image/tiff"; default: mime = "image/\(material.fileExtension)" }
            return "<figure><img src=\"data:\(mime);base64,\(material.data.base64EncodedString())\"><figcaption>\(escape(material.name))</figcaption></figure>"
        }.joined()
        let downloads = entry.materials.map { "<li><a download=\"\(escape(($0.name as NSString).lastPathComponent))\" href=\"data:application/octet-stream;base64,\($0.data.base64EncodedString())\">\(escape($0.name))</a></li>" }.joined()
        return """
        <!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>\(escape(entry.displayTitle))</title>
        <style>body{max-width:760px;margin:64px auto;padding:0 32px;background:#fbf8f1;color:#353d37;font:18px/1.9 Georgia,serif}h1{line-height:1.3}small,figcaption{color:#768078}img{max-width:100%;border-radius:12px}article{overflow-wrap:anywhere}footer{margin-top:40px;border-top:1px solid #ddd;padding-top:16px}</style>
        <h1>\(escape(entry.displayTitle))</h1><small>\(escape(timestamp(entry.date))) · \(escape(entry.mood)) · \(escape(entry.tags))</small>
        <article>\(body ?? escape(entry.text).replacingOccurrences(of: "\n", with: "<br>"))</article>\(images)\(downloads.isEmpty ? "" : "<h3>素材下载</h3><ul>\(downloads)</ul>")
        <footer><small>写作 \(Int(entry.writingSeconds)) 秒 · 创建于 \(escape(timestamp(entry.createdAt))) · 最后更新 \(escape(timestamp(entry.modifiedAt)))</small></footer></html>
        """
    }
}
