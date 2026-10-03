import SwiftUI
import AppKit
import DiaryCore

extension Entry {
    var attributed: NSAttributedString {
        if let richText, let rich = try? NSAttributedString(data: richText, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) { return rich }
        let p = NSMutableParagraphStyle(); p.lineSpacing = 8; p.paragraphSpacing = 12
        return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.labelColor, .paragraphStyle: p])
    }
}

final class DiaryTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool { let r = super.becomeFirstResponder(); if r { focusChanged?(true) }; return r }
    override func resignFirstResponder() -> Bool { let r = super.resignFirstResponder(); if r { focusChanged?(false) }; return r }
}

struct RichEditor: NSViewRepresentable {
    @ObservedObject var store: DiaryStore
    var entry: Entry
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let text = DiaryTextView(); text.delegate = context.coordinator
        text.isRichText = true; text.importsGraphics = true; text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = true; text.isAutomaticSpellingCorrectionEnabled = false
        text.drawsBackground = false; text.textContainerInset = NSSize(width: 40, height: 28)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.minSize = NSSize(width: 0, height: 0); text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.focusChanged = { store.editorFocused = $0 }
        scroll.documentView = text; store.editor = text
        context.coordinator.id = entry.id; text.textStorage?.setAttributedString(entry.attributed)
        text.typingAttributes = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.labelColor]
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? DiaryTextView else { return }
        if context.coordinator.id != entry.id {
            context.coordinator.id = entry.id; text.textStorage?.setAttributedString(entry.attributed)
            text.undoManager?.removeAllActions(); text.setSelectedRange(NSRange(location: 0, length: 0)); scroll.contentView.scroll(to: .zero)
        }
        text.isEditable = !store.storageUnavailable; store.editor = text
    }
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        let store: DiaryStore; var id: UUID?
        init(_ store: DiaryStore) { self.store = store }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView, id == store.selection else { return }
            store.editText(text.attributedString())
        }
    }
}

extension DiaryStore {
    func applyFont(name: String? = nil, size: CGFloat? = nil) {
        guard let editor else { return }
        let range = editor.selectedRange()
        let old = (editor.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 18)
        let font = NSFont(name: name ?? old.fontName, size: size ?? old.pointSize) ?? NSFont.systemFont(ofSize: size ?? 18)
        if range.length > 0 { replaceAttributes(editor, range: range, key: .font, value: font) }
        editor.typingAttributes[.font] = font; editor.window?.makeFirstResponder(editor)
    }
    func applyColor(_ color: Color) {
        guard let editor else { return }
        let range = editor.selectedRange(), ns = NSColor(color)
        if range.length > 0 { replaceAttributes(editor, range: range, key: .foregroundColor, value: ns) }
        editor.typingAttributes[.foregroundColor] = ns; editor.window?.makeFirstResponder(editor)
    }
    func format(_ action: String) {
        guard let editor else { return }; editor.window?.makeFirstResponder(editor)
        switch action {
        case "bold": toggleTrait(.boldFontMask, editor: editor)
        case "italic": toggleTrait(.italicFontMask, editor: editor)
        case "underline": editor.underline(nil)
        case "left": editor.alignLeft(nil)
        case "center": editor.alignCenter(nil)
        default: break
        }
    }
    private func replaceAttributes(_ editor: NSTextView, range: NSRange, key: NSAttributedString.Key, value: Any) {
        let replacement = NSMutableAttributedString(attributedString: editor.attributedString().attributedSubstring(from: range))
        replacement.addAttribute(key, value: value, range: NSRange(location: 0, length: replacement.length))
        editor.insertText(replacement, replacementRange: range); editor.setSelectedRange(range)
    }
    private func toggleTrait(_ trait: NSFontTraitMask, editor: NSTextView) {
        let range = editor.selectedRange(), manager = NSFontManager.shared
        let old = (range.length > 0 ? editor.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont : editor.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 18)
        let remove = manager.traits(of: old).contains(trait)
        if range.length > 0 {
            let replacement = NSMutableAttributedString(attributedString: editor.attributedString().attributedSubstring(from: range))
            replacement.enumerateAttribute(.font, in: NSRange(location: 0, length: replacement.length)) { value, r, _ in
                let font = value as? NSFont ?? old
                replacement.addAttribute(.font, value: remove ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait), range: r)
            }
            editor.insertText(replacement, replacementRange: range); editor.setSelectedRange(range)
        } else { editor.typingAttributes[.font] = remove ? manager.convert(old, toNotHaveTrait: trait) : manager.convert(old, toHaveTrait: trait) }
    }
    func insertImage(_ material: DiaryCore.Material) {
        guard let editor, let image = NSImage(data: material.data) else { return }
        let attachment = NSTextAttachment(); attachment.image = image
        let width = min(520, image.size.width), ratio = width / max(1, image.size.width)
        attachment.bounds = NSRect(x: 0, y: 0, width: width, height: image.size.height * ratio)
        let wrapper = FileWrapper(regularFileWithContents: material.data); wrapper.preferredFilename = (material.name as NSString).lastPathComponent; attachment.fileWrapper = wrapper
        let insert = NSMutableAttributedString(string: "\n"); insert.append(NSAttributedString(attachment: attachment)); insert.append(NSAttributedString(string: "\n"))
        let range = editor.selectedRange()
        editor.insertText(insert, replacementRange: range); editor.window?.makeFirstResponder(editor)
    }
}
