import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum RichTextCodec {
    static let baseFontSize: CGFloat = 16

    static func attributedString(from rtfData: Data) -> NSAttributedString {
        if let attributed = try? NSAttributedString(
            data: rtfData,
            options: [
                .documentType: NSAttributedString.DocumentType.rtf,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed
        }
        return NSAttributedString(string: "")
    }

    static func rtfData(from attributed: NSAttributedString) -> Data {
        let range = NSRange(location: 0, length: attributed.length)
        return (try? attributed.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
        )) ?? Data()
    }

    static func attributedForDisplay(note: Note) -> AttributedString {
        if !note.rtfData.isEmpty {
            return AttributedString(attributedString(from: note.rtfData))
        }
        return AttributedString(note.plainText)
    }
}
