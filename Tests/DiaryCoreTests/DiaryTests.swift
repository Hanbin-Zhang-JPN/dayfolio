import Foundation
import DiaryCore

struct TestFailure: Error { let message: String }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(message: message) }
}
@main struct DiaryCoreChecks {
    static func main() throws {
        let s = TextStats("今天很好 Hello world!\n第二段 123")
        try require(s.words == 10 && s.paragraphs == 2 && s.charactersWithoutSpaces == 21, "Mixed-language counting")
        try require(TextStats(" \n\u{FFFC}").words == 0 && TextStats("👨‍👩‍👧‍👦").characters == 1, "Empty content and composed Unicode")
        print("PASS mixed-language statistics and Unicode")
        var e = Entry(title: "旅行", date: Date(timeIntervalSince1970: 1234), text: "你好")
        e.richText = Data([1, 2]); e.writingSeconds = 125; e.materials = [Material(name: "照片.png", data: Data([0, 1, 255]))]
        let decoded = try Archive.decode(Archive(entries: [e]).encoded()).entries
        try require(decoded == [e], "Archive round-trip")
        print("PASS dates, rich text, writing time and binary materials round-trip")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let r = DiaryRepository(url: folder.appendingPathComponent("journal.json"))
        let old = Entry(title: "旧内容"), new = Entry(title: "新内容")
        try r.save([old]); try r.save([new])
        try require(r.load() == [new], "Atomic save")
        try require(Archive.decode(Data(contentsOf: r.url.appendingPathExtension("previous"))).entries == [old], "Previous version")
        print("PASS atomic save and previous version recovery")
        var unsupported = Archive(entries: []); unsupported.version = 99
        var invalid = e; invalid.writingSeconds = -1
        for archive in [unsupported, Archive(entries: [e, e]), Archive(entries: [invalid])] {
            let data = try archive.encoded()
            do { _ = try Archive.decode(data); throw TestFailure(message: "Invalid archive accepted") }
            catch is DiaryError { }
        }
        print("PASS reject unsupported versions, duplicate IDs and invalid writing duration")
        let result = DiaryRepository.merge([old], into: [old])
        try require(result.count == 2 && result[0] == old && result[1].id != old.id, "Import overwrites existing ID")
        print("PASS imported duplicates never overwrite originals")
        let html = PlainExport.html(Entry(title: "<script>", text: "<b>&"))
        try require(!html.contains("<script>") && html.contains("&lt;b&gt;&amp;"), "HTML escaping")
        print("PASS HTML escaping")
        try Data("corrupted".utf8).write(to: r.url)
        do { _ = try r.load(); throw TestFailure(message: "Corrupt storage accepted") } catch is DecodingError { }
        try require(Data(contentsOf: r.url) == Data("corrupted".utf8), "Corrupt file modified during read")
        print("PASS corrupt storage stays untouched")
        print("All 7 core checks passed")
    }
}
