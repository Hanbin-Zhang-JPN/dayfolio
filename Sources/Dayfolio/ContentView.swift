import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DiaryCore

private let green = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedRed: 0.62, green: 0.80, blue: 0.68, alpha: 1)
        : NSColor(calibratedRed: 0.24, green: 0.39, blue: 0.30, alpha: 1)
})
private let paper = Color(nsColor: .textBackgroundColor)

struct ContentView: View {
    @ObservedObject var store: DiaryStore
    @State private var inspector = true
    @State private var font = "PingFang SC"
    @State private var fontSize = 18.0
    @State private var ink = Color.primary
    @AppStorage("paperTone") private var tone = "自然"
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Divider()
            entryList.frame(width: 255)
            Divider()
            VStack(spacing: 0) {
                topbar
                Divider()
                if let entry = store.current {
                    entryHeader(entry)
                    formatBar
                    ZStack(alignment: .topLeading) {
                        RichEditor(store: store, entry: entry)
                        if entry.text.isEmpty {
                            Text("此刻，你想留下什么？\n\n写下一件小事、一个念头，或今天值得记住的瞬间。")
                                .font(.system(size: 18)).foregroundStyle(.tertiary).padding(.horizontal, 45).padding(.top, 32).allowsHitTesting(false)
                        }
                    }.background(canvas)
                    Divider()
                    footer(entry)
                } else {
                    ContentUnavailableView("留下一页生活", systemImage: "book.closed", description: Text("新建一篇日记，开始记录今天。"))
                    Button("新建日记") { store.newEntry() }.buttonStyle(.borderedProminent).padding()
                }
            }.frame(minWidth: 390)
            if inspector, let entry = store.current { Divider(); detail(entry).frame(width: 240) }
        }
        .tint(green)
        .background(paper)
        .preferredColorScheme(tone == "自然" ? nil : .light)
        .alert("Dayfolio", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了") { store.message = nil } } message: { Text(store.message ?? "") }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            for p in providers { _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in store.importURLs([url]) } } } }
            return true
        }
    }
    private var canvas: Color {
        switch tone { case "暖纸": return Color(red: 0.98, green: 0.96, blue: 0.91); case "浅绿": return Color(red: 0.93, green: 0.96, blue: 0.93); default: return paper }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "book.pages.fill").font(.system(size: 27)).foregroundStyle(green)
                VStack(alignment: .leading, spacing: 3) { Text("拾光日记").font(.system(size: 21, weight: .semibold, design: .serif)); Text("D A Y F O L I O").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
            }.padding(.top, 28).padding(.bottom, 35)
            Text("我的日记本").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 13)
            ForEach([("全部日记", "square.stack"), ("今天", "sun.max"), ("收藏", "star")], id: \.0) { name, icon in
                Button { store.filter = name } label: {
                    HStack { Image(systemName: icon).frame(width: 20); Text(name); Spacer(); if name == "全部日记" { Text("\(store.entries.count)").font(.caption) } }
                        .padding(11).background(store.filter == name ? green.opacity(0.12) : .clear).clipShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Divider().padding(.vertical, 22)
            VStack(alignment: .leading, spacing: 11) {
                Text("每一天，都值得被记住。").font(.system(size: 15, design: .serif))
                Text("让日常有迹可循，\n让回忆有处安放。").font(.caption).foregroundStyle(.secondary).lineSpacing(5)
            }
            Spacer()
            HStack { stat("\(store.entries.count)", "篇日记"); Spacer(); stat("\(store.entries.reduce(0) { $0 + $1.stats.charactersWithoutSpaces })", "累计字数") }.padding(.bottom, 24)
            Button { store.exportBackup() } label: { Label("完整备份", systemImage: "externaldrive") }.buttonStyle(.plain).padding(.bottom, 14)
            Button { store.revealStorage() } label: { Label("本机数据目录", systemImage: "folder") }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            Text("本地保存 · 由你掌握").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 15).padding(.bottom, 20)
        }.padding(.horizontal, 20).background(Color(nsColor: .controlBackgroundColor))
    }
    private var entryList: some View {
        VStack(spacing: 0) {
            HStack { Text(store.filter).font(.headline); Spacer(); Button { store.newEntry() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).help("新建日记 ⌘N") }.padding(20)
            TextField("搜索标题、正文、标签", text: $store.query).textFieldStyle(.roundedBorder).padding(.horizontal, 15).padding(.bottom, 15)
            HStack { Text("\(store.visible.count) 篇记录"); Spacer(); Text("按日期排序") }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 19).padding(.bottom, 10)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.visible) { entry in
                        Button { store.select(entry.id) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text(entry.date, format: .dateTime.month().day()).font(.caption); Spacer(); if entry.favorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.orange) }; Text(entry.mood).font(.system(size: 10)) }.foregroundStyle(.secondary)
                                Text(entry.displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text(entry.text.isEmpty ? "等待你的第一行文字…" : entry.text.replacingOccurrences(of: "\u{FFFC}", with: "[图片]")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                HStack { Text("\(entry.stats.charactersWithoutSpaces) 字"); if !entry.materials.isEmpty { Image(systemName: "paperclip"); Text("\(entry.materials.count)") }; Spacer(); Text(entry.date, format: .dateTime.year()) }.font(.system(size: 10)).foregroundStyle(.tertiary)
                            }.padding(15).background(store.selection == entry.id ? green.opacity(0.10) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(store.selection == entry.id ? green.opacity(0.25) : Color(nsColor: .separatorColor).opacity(0.25)))
                        }.buttonStyle(.plain)
                    }
                    if store.visible.isEmpty { Text("没有找到日记").foregroundStyle(.secondary).padding(30) }
                }.padding(.horizontal, 12).padding(.bottom, 15)
            }
            Button { store.newEntry() } label: { Label("写一篇日记", systemImage: "plus").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).padding(15)
        }
    }
    private var topbar: some View {
        HStack(spacing: 16) {
            Label(store.storageUnavailable ? "数据读取异常" : "我的私人书写空间", systemImage: "leaf").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { store.importFiles() } label: { Label("导入", systemImage: "tray.and.arrow.down") }.buttonStyle(.plain)
            Menu { ForEach(ExportKind.allCases, id: \.self) { kind in Button(kind.rawValue) { store.export(kind) } }; Divider(); Button("全部日记备份") { store.exportBackup() } } label: { Label("导出", systemImage: "square.and.arrow.up") }.menuStyle(.borderlessButton).fixedSize()
            Button { inspector.toggle() } label: { Image(systemName: "sidebar.right") }.buttonStyle(.plain).help("显示 / 隐藏日记详情")
        }.padding(.horizontal, 24).frame(height: 58)
    }
    private func entryHeader(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(entry.date, format: .dateTime.year().month().day().weekday()).font(.caption).foregroundStyle(.secondary); Spacer(); Button { store.update { $0.favorite.toggle() } } label: { Image(systemName: entry.favorite ? "star.fill" : "star").foregroundStyle(entry.favorite ? Color.orange : .secondary) }.buttonStyle(.plain) }
            TextField("给今天起个名字", text: Binding(get: { store.current?.title ?? "" }, set: { value in store.update({ $0.title = value }, writing: true) })).textFieldStyle(.plain).font(.system(size: 30, weight: .medium, design: .serif))
            HStack(spacing: 8) { Image(systemName: "tag").foregroundStyle(.tertiary); TextField("添加标签，用逗号分隔", text: Binding(get: { store.current?.tags ?? "" }, set: { value in store.update { $0.tags = value } })).textFieldStyle(.plain).font(.caption) }
        }.padding(.horizontal, 40).padding(.top, 25).padding(.bottom, 24).background(canvas)
    }
    private var formatBar: some View {
        HStack(spacing: 12) {
            Picker("字体", selection: $font) {
                Text("苹方").tag("PingFang SC"); Text("宋体").tag("Songti SC"); Text("系统").tag(".AppleSystemUIFont"); Text("Georgia").tag("Georgia"); Text("等宽").tag("Menlo")
                ForEach(NSFontManager.shared.availableFontFamilies.filter { !["PingFang SC", "Songti SC", "Georgia", "Menlo"].contains($0) }, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 110).onChange(of: font) { _, v in store.applyFont(name: v) }
            Picker("字号", selection: $fontSize) { ForEach([12.0, 14, 16, 18, 20, 24, 28, 32], id: \.self) { Text("\(Int($0))").tag($0) } }.labelsHidden().frame(width: 58).onChange(of: fontSize) { _, v in store.applyFont(size: v) }
            Divider().frame(height: 18)
            tool("bold", "加粗", "bold"); tool("italic", "斜体", "italic"); tool("underline", "下划线", "underline")
            ColorPicker("文字颜色", selection: $ink).labelsHidden().frame(width: 28).onChange(of: ink) { _, v in store.applyColor(v) }
            Spacer(minLength: 0)
            Menu { Button("自然") { tone = "自然" }; Button("暖纸") { tone = "暖纸" }; Button("浅绿") { tone = "浅绿" } } label: { Image(systemName: "paintpalette") }.menuStyle(.borderlessButton).fixedSize().help("纸张背景色")
        }.padding(.horizontal, 22).frame(height: 46).background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }
    private func tool(_ icon: String, _ help: String, _ action: String) -> some View { Button { store.format(action) } label: { Image(systemName: icon).frame(width: 19) }.buttonStyle(.plain).help(help) }
    private func footer(_ entry: Entry) -> some View {
        HStack(spacing: 13) {
            Text("\(entry.stats.charactersWithoutSpaces) 字"); Text("\(entry.stats.paragraphs) 段"); Text("阅读约 \(entry.stats.readingMinutes) 分钟")
            Spacer()
            if store.savedAt != nil { Label(store.isDirty ? "保存中…" : "已保存", systemImage: store.isDirty ? "clock" : "checkmark.circle").foregroundStyle(green) }
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 25).frame(height: 36)
    }
    private func detail(_ entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("日记详情").font(.headline).padding(.top, 24)
                VStack(alignment: .leading, spacing: 12) {
                    caption("记录日期")
                    DatePicker("日期", selection: Binding(get: { store.current?.date ?? Date() }, set: { v in store.update { $0.date = v } }), displayedComponents: [.date, .hourAndMinute]).labelsHidden().datePickerStyle(.field)
                    caption("今天的心情")
                    Picker("心情", selection: Binding(get: { store.current?.mood ?? "平静" }, set: { v in store.update { $0.mood = v } })) { ForEach(["平静", "开心", "感激", "期待", "疲惫", "难过"], id: \.self) { Text($0).tag($0) } }.labelsHidden()
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    caption("写作记录")
                    HStack { Image(systemName: "timer").foregroundStyle(green); Text(duration(entry.writingSeconds)).font(.system(size: 23, weight: .medium, design: .rounded)) }
                    Text("编辑器中输入时计时；停止输入 30 秒后暂停，切换应用或日记也会暂停。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                    meta("创建", entry.createdAt); meta("更新", entry.modifiedAt)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    caption("文字统计")
                    metric("字符（含空格）", "\(entry.stats.characters)"); metric("字符（不含空格）", "\(entry.stats.charactersWithoutSpaces)")
                    metric("字 / 词", "\(entry.stats.words)"); metric("段落", "\(entry.stats.paragraphs)")
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack { caption("素材 · \(entry.materials.count)"); Spacer(); Button { store.importFiles() } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain) }
                    if entry.materials.isEmpty { Text("拖入照片、PDF、音频或文件，\n把回忆放在这一页。\n单文件 ≤ 50 MB").font(.caption).foregroundStyle(.secondary).lineSpacing(5).padding(.vertical, 8) }
                    ForEach(entry.materials) { m in
                        VStack(alignment: .leading, spacing: 7) {
                            if m.isImage, let image = NSImage(data: m.data) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 7)) }
                            HStack { Image(systemName: m.isImage ? "photo" : "doc"); Text(m.name).lineLimit(1).font(.caption); Spacer() }
                            HStack {
                                Button("打开") { store.openMaterial(m) }
                                if m.isImage { Button("插入正文") { store.insertImage(m) } }
                                Spacer(); Button { store.update { $0.materials.removeAll { $0.id == m.id } } } label: { Image(systemName: "xmark") }.help("移除素材，正文已插入的图片仍保留")
                            }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(green)
                        }.padding(10).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                Spacer(minLength: 30)
                Button(role: .destructive) { store.deleteCurrent() } label: { Label("删除这篇日记", systemImage: "trash") }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
    private func caption(_ s: String) -> some View { Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
    private func stat(_ v: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(v).font(.system(size: 23, weight: .medium, design: .rounded)); Text(label).font(.system(size: 10)).foregroundStyle(.secondary) } }
    private func metric(_ label: String, _ v: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(v).monospacedDigit() }.font(.system(size: 11)) }
    private func meta(_ label: String, _ date: Date) -> some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(.system(size: 10)).foregroundStyle(.tertiary); Text(date, format: .dateTime.year().month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary) } }
    private func duration(_ seconds: TimeInterval) -> String { let v = Int(seconds); return String(format: "%02d:%02d:%02d", v / 3600, v / 60 % 60, v % 60) }
}
