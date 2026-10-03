import SwiftUI
import AppKit
import PDFKit
import DiaryCore

@MainActor final class DiaryStore: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var selection: UUID?
    @Published var query = ""
    @Published var filter = "全部日记"
    @Published var message: String?
    @Published var savedAt: Date?
    @Published var isDirty = false
    @Published var storageUnavailable = false
    @Published var editorFocused = false
    @Published var lastEdit = Date.distantPast
    let repository: DiaryRepository
    private var pendingSave: DispatchWorkItem?
    private var tick = Date()
    private var timer: Timer?
    var editor: NSTextView?
    var current: Entry? { entries.first { $0.id == selection } }
    var visible: [Entry] {
        entries.filter { e in
            (filter != "收藏" || e.favorite) && (filter != "今天" || Calendar.current.isDateInToday(e.date)) &&
            (query.isEmpty || (e.title + e.text + e.tags).localizedCaseInsensitiveContains(query))
        }.sorted { $0.date > $1.date }
    }
    init(directory: URL? = nil) {
        let base: URL
        if let directory { base = directory }
        else if let custom = ProcessInfo.processInfo.environment["DAYFOLIO_DATA_DIR"] { base = URL(fileURLWithPath: custom) }
        else { base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dayfolio") }
        repository = DiaryRepository(url: base.appendingPathComponent("journal.json"))
        do { entries = try repository.load() }
        catch { storageUnavailable = true; message = "读取日记失败，已暂停写入以保护原文件。请从数据目录检查 journal.json 和 journal.json.previous。\n\(error.localizedDescription)" }
        if entries.isEmpty && !storageUnavailable { entries = [Entry()]; saveNow() }
        selection = entries.sorted { $0.date > $1.date }.first?.id
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordTime() }
        }
    }
    func recordTime() {
        let now = Date(), elapsed = now.timeIntervalSince(tick); tick = now
        guard elapsed > 0, elapsed < 3, NSApp?.isActive == true, editorFocused, now.timeIntervalSince(lastEdit) < 30,
              !storageUnavailable, let i = entries.firstIndex(where: { $0.id == selection }) else { return }
        entries[i].writingSeconds += elapsed
        isDirty = true
        if Int(entries[i].writingSeconds) % 10 == 0 { saveNow() }
    }
    func update(_ mutation: (inout Entry) -> Void, writing: Bool = false) {
        guard !storageUnavailable, let i = entries.firstIndex(where: { $0.id == selection }) else { return }
        mutation(&entries[i]); entries[i].modifiedAt = Date()
        isDirty = true
        if writing { lastEdit = Date() }
        scheduleSave()
    }
    func editText(_ value: NSAttributedString) {
        do {
            let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            update({ $0.text = value.string; $0.richText = data }, writing: true)
        } catch { message = "无法保存本次富文本更改，请撤销后重试。\n\(error.localizedDescription)" }
    }
    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }; pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
    @discardableResult func saveNow() -> Bool {
        pendingSave?.cancel(); pendingSave = nil
        guard !storageUnavailable else { return !isDirty }
        do { try repository.save(entries); savedAt = Date(); isDirty = false; return true }
        catch { message = "保存失败，当前内容仍保留在内存中。请立即导出完整备份。\n\(error.localizedDescription)"; return false }
    }
    func select(_ id: UUID?) { saveNow(); lastEdit = .distantPast; selection = id }
    func newEntry() {
        guard !storageUnavailable else { return }
        saveNow(); let e = Entry(); entries.append(e); query = ""; filter = "全部日记"; selection = e.id; lastEdit = .distantPast; saveNow()
    }
    func deleteCurrent() {
        guard let current, !storageUnavailable else { return }
        let alert = NSAlert(); alert.messageText = "删除「\(current.displayTitle)」？"; alert.informativeText = "日记及其素材将被移除。删除前可以先导出备份。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "删除")
        if alert.runModal() == .alertSecondButtonReturn { entries.removeAll { $0.id == current.id }; selection = visible.first?.id; saveNow() }
    }
    func revealStorage() { NSWorkspace.shared.open(repository.url.deletingLastPathComponent()) }
    func importFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.message = "导入文档为日记；图片、音频、视频和其他文件作为当前日记的素材。"
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        guard !storageUnavailable else { return }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let ext = url.pathExtension.lowercased()
                let limit = ["dayfolio", "json"].contains(ext) ? 1024 * 1024 * 1024 : 50 * 1024 * 1024
                guard size <= limit else { throw NSError(domain: "Dayfolio", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件过大：素材上限 50 MB，归档上限 1 GB。\(url.lastPathComponent)"]) }
                let data = try Data(contentsOf: url)
                if ["dayfolio", "json"].contains(ext) {
                    let imported = try Archive.decode(data).entries
                    entries = DiaryRepository.merge(imported, into: entries); selection = entries.last?.id
                } else if ["txt", "md", "markdown", "rtf", "docx", "html", "htm"].contains(ext) {
                    var e = Entry(title: url.deletingPathExtension().lastPathComponent)
                    if ["txt", "md", "markdown"].contains(ext) {
                        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw NSError(domain: "Dayfolio", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法识别文本编码：\(url.lastPathComponent)"]) }
                        e.text = text
                    } else {
                        let type: NSAttributedString.DocumentType = ext == "rtf" ? .rtf : (ext == "docx" ? .officeOpenXML : .html)
                        let rich = try NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil)
                        e.text = rich.string; e.richText = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
                    }
                    entries.append(e); selection = e.id
                } else if ext == "pdf" {
                    var e = Entry(title: url.deletingPathExtension().lastPathComponent, text: PDFDocument(data: data)?.string ?? "")
                    e.materials = [Material(name: url.lastPathComponent, data: data)]; entries.append(e); selection = e.id
                } else {
                    if current == nil { newEntry() }
                    guard let current, current.materials.reduce(0, { $0 + $1.data.count }) + data.count <= 300 * 1024 * 1024 else {
                        throw NSError(domain: "Dayfolio", code: 3, userInfo: [NSLocalizedDescriptionKey: "每篇日记的素材总量最多 300 MB。"])
                    }
                    update { $0.materials.append(Material(name: url.lastPathComponent, data: data)) }
                }
            } catch { message = "导入 \(url.lastPathComponent) 失败：\(error.localizedDescription)" }
        }
        saveNow()
    }
    func exportBackup() {
        saveNow(); let panel = NSSavePanel(); panel.nameFieldStringValue = "Dayfolio-完整备份.dayfolio"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Archive(entries: entries).encoded().write(to: url, options: .atomic) } catch { message = error.localizedDescription }
        }
    }
    func openMaterial(_ material: DiaryCore.Material) {
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dayfolio-Preview/\(material.id.uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safeName = (material.name as NSString).lastPathComponent
            let url = dir.appendingPathComponent(safeName.isEmpty ? "附件" : safeName)
            try material.data.write(to: url, options: .atomic); NSWorkspace.shared.open(url)
        } catch { message = error.localizedDescription }
    }
}
