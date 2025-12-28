import SwiftUI
import UIKit

enum RichTextCommand {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case increaseFont
    case decreaseFont
    case title
    case heading
    case body
    case bulletedList
    case numberedList
    case checklist
}

struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var command: RichTextCommand?
    @Binding var isFocused: Bool
    @Binding var refreshToken: UUID

    var onChange: (NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: RichTextCodec.baseFontSize)
        textView.backgroundColor = .clear
        textView.allowsEditingTextAttributes = true
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if context.coordinator.lastRefreshToken != refreshToken {
            uiView.attributedText = attributedText
            uiView.selectedRange = NSRange(location: uiView.attributedText.length, length: 0)
            context.coordinator.lastRefreshToken = refreshToken
        } else if !uiView.isFirstResponder, !uiView.attributedText.isEqual(attributedText) {
            uiView.attributedText = attributedText
        }

        if let command {
            context.coordinator.apply(command, to: uiView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: RichTextEditor
        var lastRefreshToken: UUID

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.lastRefreshToken = parent.refreshToken
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.attributedText = textView.attributedText
            parent.onChange(textView.attributedText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.isFirstResponder == false, parent.isFocused {
                textView.becomeFirstResponder()
            }

            let range = textView.selectedRange
            if range.length == 0, textView.attributedText.length > 0 {
                let index = max(range.location - 1, 0)
                let attrs = textView.attributedText.attributes(at: index, effectiveRange: nil)
                textView.typingAttributes = attrs
            }
        }

        func apply(_ command: RichTextCommand, to textView: UITextView) {
            switch command {
            case .toggleBold:
                toggleFontTrait(.traitBold, in: textView)
            case .toggleItalic:
                toggleFontTrait(.traitItalic, in: textView)
            case .toggleUnderline:
                toggleUnderline(in: textView)
            case .increaseFont:
                adjustFontSize(by: 1, in: textView)
            case .decreaseFont:
                adjustFontSize(by: -1, in: textView)
            case .title:
                applyParagraphStyle(size: 28, weight: .bold, in: textView)
            case .heading:
                applyParagraphStyle(size: 22, weight: .semibold, in: textView)
            case .body:
                applyParagraphStyle(size: RichTextCodec.baseFontSize, weight: .regular, in: textView)
            case .bulletedList:
                toggleList(prefix: "- ", in: textView)
            case .numberedList:
                toggleNumberedList(in: textView)
            case .checklist:
                toggleList(prefix: "[ ] ", in: textView)
            }
        }

        private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, in textView: UITextView) {
            let range = textView.selectedRange
            if range.length == 0 {
                var attrs = textView.typingAttributes
                let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: RichTextCodec.baseFontSize)
                attrs[.font] = fontTogglingTrait(font, trait: trait)
                textView.typingAttributes = attrs
                return
            }

            let storage = textView.textStorage
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: RichTextCodec.baseFontSize)
                let updated = fontTogglingTrait(font, trait: trait)
                storage.addAttribute(.font, value: updated, range: subrange)
            }
            storage.endEditing()
            textView.selectedRange = range
            parent.attributedText = storage.copy() as? NSAttributedString ?? textView.attributedText
            parent.onChange(parent.attributedText)
        }

        private func fontTogglingTrait(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) {
                traits.remove(trait)
            } else {
                traits.insert(trait)
            }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: descriptor, size: font.pointSize)
            }
            return font
        }

        private func toggleUnderline(in textView: UITextView) {
            let range = textView.selectedRange
            if range.length == 0 {
                var attrs = textView.typingAttributes
                let current = (attrs[.underlineStyle] as? Int) ?? 0
                attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                textView.typingAttributes = attrs
                return
            }

            let storage = textView.textStorage
            storage.beginEditing()
            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, subrange, _ in
                let current = (value as? Int) ?? 0
                let next = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                storage.addAttribute(.underlineStyle, value: next, range: subrange)
            }
            storage.endEditing()
            textView.selectedRange = range
            parent.attributedText = storage.copy() as? NSAttributedString ?? textView.attributedText
            parent.onChange(parent.attributedText)
        }

        private func adjustFontSize(by delta: CGFloat, in textView: UITextView) {
            let range = textView.selectedRange
            let minSize: CGFloat = 12
            let maxSize: CGFloat = 28

            if range.length == 0 {
                var attrs = textView.typingAttributes
                let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: RichTextCodec.baseFontSize)
                let size = max(min(font.pointSize + delta, maxSize), minSize)
                attrs[.font] = UIFont(descriptor: font.fontDescriptor, size: size)
                textView.typingAttributes = attrs
                return
            }

            let storage = textView.textStorage
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: RichTextCodec.baseFontSize)
                let size = max(min(font.pointSize + delta, maxSize), minSize)
                let updated = UIFont(descriptor: font.fontDescriptor, size: size)
                storage.addAttribute(.font, value: updated, range: subrange)
            }
            storage.endEditing()
            textView.selectedRange = range
            parent.attributedText = storage.copy() as? NSAttributedString ?? textView.attributedText
            parent.onChange(parent.attributedText)
        }

        private func applyParagraphStyle(size: CGFloat, weight: UIFont.Weight, in textView: UITextView) {
            let range = fullParagraphRange(for: textView.selectedRange, in: textView)
            let storage = textView.textStorage
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let baseFont = (value as? UIFont) ?? UIFont.systemFont(ofSize: RichTextCodec.baseFontSize)
                let updated = UIFont.systemFont(ofSize: size, weight: weight)
                let traits = baseFont.fontDescriptor.symbolicTraits
                let withTraits = updated.fontDescriptor.withSymbolicTraits(traits) ?? updated.fontDescriptor
                storage.addAttribute(.font, value: UIFont(descriptor: withTraits, size: size), range: subrange)
            }
            storage.endEditing()
            textView.selectedRange = range
            parent.attributedText = storage.copy() as? NSAttributedString ?? textView.attributedText
            parent.onChange(parent.attributedText)
        }

        private func toggleList(prefix: String, in textView: UITextView) {
            let range = fullParagraphRange(for: textView.selectedRange, in: textView)
            let paragraphs = paragraphRanges(in: range, textView: textView)
            let storage = textView.textStorage
            storage.beginEditing()

            var shouldRemove = true
            for paragraph in paragraphs {
                let text = (storage.string as NSString).substring(with: paragraph)
                if !text.hasPrefix(prefix) {
                    shouldRemove = false
                    break
                }
            }

            for paragraph in paragraphs.reversed() {
                if shouldRemove {
                    let removeRange = NSRange(location: paragraph.location, length: prefix.count)
                    storage.deleteCharacters(in: removeRange)
                } else {
                    let attrs = storage.attributes(at: paragraph.location, effectiveRange: nil)
                    let insert = NSAttributedString(string: prefix, attributes: attrs)
                    storage.insert(insert, at: paragraph.location)
                }
            }

            storage.endEditing()
            textView.selectedRange = adjustedSelection(for: range, prefix: prefix, removed: shouldRemove)
            parent.attributedText = storage.copy() as? NSAttributedString ?? textView.attributedText
            parent.onChange(parent.attributedText)
        }

        private func toggleNumberedList(in textView: UITextView) {
            let range = fullParagraphRange(for: textView.selectedRange, in: textView)
            let paragraphs = paragraphRanges(in: range, textView: textView)
            let storage = textView.textStorage
            storage.beginEditing()

            let hasNumbers = paragraphs.allSatisfy { paragraph in
                let text = (storage.string as NSString).substring(with: paragraph)
                return text.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            }

            for (index, paragraph) in paragraphs.enumerated().reversed() {
                if hasNumbers {
                    let text = (storage.string as NSString).substring(with: paragraph)
                    if let match = text.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        let nsRange = NSRange(match, in: text)
                        let removeRange = NSRange(location: paragraph.location, length: nsRange.length)
                        storage.deleteCharacters(in: removeRange)
                    }
                } else {
                    let attrs = storage.attributes(at: paragraph.location, effectiveRange: nil)
                    let prefix = "\(index + 1). "
                    let insert = NSAttributedString(string: prefix, attributes: attrs)
                    storage.insert(insert, at: paragraph.location)
                }
            }

            storage.endEditing()
            textView.selectedRange = range
            parent.attributedText = storage.copy() as? NSAttributedString ?? textView.attributedText
            parent.onChange(parent.attributedText)
        }

        private func paragraphRanges(in range: NSRange, textView: UITextView) -> [NSRange] {
            let text = textView.textStorage.string as NSString
            var ranges: [NSRange] = []
            var location = range.location
            let end = range.location + range.length
            while location <= end {
                let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
                ranges.append(paragraph)
                location = paragraph.location + paragraph.length
                if paragraph.length == 0 { break }
            }
            return ranges
        }

        private func fullParagraphRange(for range: NSRange, in textView: UITextView) -> NSRange {
            let text = textView.textStorage.string as NSString
            if range.length == 0 {
                return text.paragraphRange(for: range)
            }
            let start = text.paragraphRange(for: NSRange(location: range.location, length: 0))
            let endLocation = range.location + range.length - 1
            let end = text.paragraphRange(for: NSRange(location: endLocation, length: 0))
            let length = (end.location + end.length) - start.location
            return NSRange(location: start.location, length: length)
        }

        private func adjustedSelection(for range: NSRange, prefix: String, removed: Bool) -> NSRange {
            let delta = removed ? -prefix.count : prefix.count
            let newLocation = max(range.location + delta, 0)
            return NSRange(location: newLocation, length: range.length)
        }
    }
}
