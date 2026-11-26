import AppKit
import SwiftUI

/// A plain-text editor for SKILL.md with no smart quotes, a find bar, and light Markdown/YAML highlighting.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 22, height: 20)
        tv.drawsBackground = false
        tv.insertionPointColor = .controlAccentColor
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.apply(fontSize: fontSize, to: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let selection = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = selection.filter { $0.rangeValue.upperBound <= (text as NSString).length }
            context.coordinator.highlight(tv)
        }
        if context.coordinator.fontSize != fontSize {
            context.coordinator.apply(fontSize: fontSize, to: tv)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var fontSize: CGFloat = 0

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
        }

        func apply(fontSize: CGFloat, to tv: NSTextView) {
            self.fontSize = fontSize
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            tv.defaultParagraphStyle = style
            tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            tv.typingAttributes = [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                                   .foregroundColor: NSColor.textColor, .paragraphStyle: style]
            highlight(tv)
        }

        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let text = storage.string as NSString
            let full = NSRange(location: 0, length: text.length)
            let base = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
            let style = tv.defaultParagraphStyle ?? NSParagraphStyle.default

            storage.beginEditing()
            storage.setAttributes([.font: base, .foregroundColor: NSColor.textColor, .paragraphStyle: style], range: full)

            var inFrontmatter = false
            var frontmatterDone = false
            var inFence = false
            var lineNumber = 0
            text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                let line = text.substring(with: range)
                let t = line.trimmingCharacters(in: .whitespaces)
                defer { lineNumber += 1 }

                if lineNumber == 0 && t == "---" {
                    inFrontmatter = true
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
                    return
                }
                if inFrontmatter && !frontmatterDone {
                    if t == "---" {
                        frontmatterDone = true
                        inFrontmatter = false
                        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
                        return
                    }
                    if let colon = line.firstIndex(of: ":"), line.first?.isWhitespace == false {
                        let keyLength = line.distance(from: line.startIndex, to: colon)
                        storage.addAttributes([.foregroundColor: NSColor.systemPurple, .font: bold],
                                              range: NSRange(location: range.location, length: keyLength))
                        storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                             range: NSRange(location: range.location + keyLength, length: range.length - keyLength))
                    } else {
                        storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                    }
                    return
                }
                if t.hasPrefix("```") || t.hasPrefix("~~~") {
                    inFence.toggle()
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
                    return
                }
                if inFence {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
                    return
                }
                if t.hasPrefix("#") {
                    storage.addAttributes([.foregroundColor: NSColor.controlAccentColor, .font: bold], range: range)
                } else if t.hasPrefix(">") {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                }
            }
            storage.endEditing()
        }
    }
}
