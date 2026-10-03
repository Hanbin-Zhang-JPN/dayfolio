import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: DiaryStore?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store?.saveNow() == false {
            let alert = NSAlert(); alert.messageText = "日记尚未保存"; alert.informativeText = "请先导出完整备份，或修复数据目录的写入问题后再退出。"; alert.addButton(withTitle: "返回应用"); alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}

@main struct DayfolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = DiaryStore()
    init() {
        if CommandLine.arguments.contains("--self-test") {
            do { try ExportSmoke.run(); exit(0) } catch { fputs("Export tests failed: \(error)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup("拾光日记 · Dayfolio") {
            ContentView(store: store).frame(minWidth: 1080, minHeight: 700)
                .onAppear { delegate.store = store }
                .onDisappear { store.saveNow() }
        }.defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建日记") { store.newEntry() }.keyboardShortcut("n")
                Button("导入文档 / 素材…") { store.importFiles() }.keyboardShortcut("i")
                Button("立即保存") { store.saveNow() }.keyboardShortcut("s")
                Divider()
                Button("导出完整备份…") { store.exportBackup() }.keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandMenu("日记") {
                ForEach(ExportKind.allCases, id: \.self) { kind in Button("导出 \(kind.rawValue)…") { store.export(kind) } }
                Divider(); Button("打开数据目录") { store.revealStorage() }
            }
        }
    }
}
