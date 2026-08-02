import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Converters that need no external application: images, plain text,
/// Markdown, HTML, and a last-resort renderer for word-processing formats.
enum NativeConverters {

    // MARK: - Images

    static func convertImage(input: URL, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.engineFailed("Couldn’t read the image")
        }

        var mediaBox = CGRect.zero
        guard let context = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else {
            throw ConversionError.engineFailed("Couldn’t create the PDF file")
        }

        // Multi-frame images (multi-page TIFF) become multi-page PDFs.
        let count = CGImageSourceGetCount(source)
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary) else { continue }

            // Respect EXIF orientation by drawing through NSImage when needed.
            var pageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let orientation = imageOrientation(source: source, index: index)
            let swapsAxes = orientation >= 5 // 5–8 are the 90°-rotated orientations
            if swapsAxes {
                pageRect = CGRect(x: 0, y: 0, width: image.height, height: image.width)
            }

            context.beginPage(mediaBox: &pageRect)
            context.saveGState()
            applyOrientationTransform(orientation, context: context,
                                      width: CGFloat(image.width), height: CGFloat(image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.restoreGState()
            context.endPage()
        }
        context.closePDF()
    }

    private static func imageOrientation(source: CGImageSource, index: Int) -> Int {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return props?[kCGImagePropertyOrientation] as? Int ?? 1
    }

    private static func applyOrientationTransform(_ orientation: Int, context: CGContext,
                                                  width: CGFloat, height: CGFloat) {
        switch orientation {
        case 2: // mirrored horizontally
            context.translateBy(x: width, y: 0); context.scaleBy(x: -1, y: 1)
        case 3: // rotated 180°
            context.translateBy(x: width, y: height); context.rotate(by: .pi)
        case 4: // mirrored vertically
            context.translateBy(x: 0, y: height); context.scaleBy(x: 1, y: -1)
        case 5: // mirrored + rotated 90° CCW
            context.rotate(by: .pi / 2); context.scaleBy(x: 1, y: -1)
        case 6: // rotated 90° CW
            context.translateBy(x: height, y: 0); context.rotate(by: .pi / 2)
        case 7: // mirrored + rotated 90° CW
            context.translateBy(x: height, y: width)
            context.rotate(by: -.pi / 2); context.scaleBy(x: 1, y: -1)
        case 8: // rotated 90° CCW
            context.translateBy(x: 0, y: width); context.rotate(by: -.pi / 2)
        default:
            break
        }
    }

    // MARK: - Plain text & Markdown

    static func convertText(input: URL, output: URL) throws {
        let raw = try String(contentsOf: input, encoding: detectEncoding(input))
        let ext = input.pathExtension.lowercased()

        let attributed: NSAttributedString
        if ext == "md" || ext == "markdown" {
            attributed = markdownAttributedString(raw)
        } else {
            attributed = NSAttributedString(string: raw, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.black,
            ])
        }
        try renderPaginated(attributed, to: output)
    }

    private static func detectEncoding(_ url: URL) -> String.Encoding {
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        return .isoLatin1
    }

    private static func markdownAttributedString(_ markdown: String) -> NSAttributedString {
        if let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(allowsExtendedAttributes: true,
                           interpretedSyntax: .full,
                           failurePolicy: .returnPartiallyParsedIfPossible)) {
            let ns = NSMutableAttributedString(parsed)
            // AttributedString(markdown:) produces semantic attributes without
            // concrete fonts — normalize to a readable base font and black text.
            ns.addAttributes([
                .foregroundColor: NSColor.black,
            ], range: NSRange(location: 0, length: ns.length))
            ns.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
                if value == nil {
                    ns.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: range)
                }
            }
            return ns
        }
        return NSAttributedString(string: markdown, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
        ])
    }

    // MARK: - HTML

    static func convertHTML(input: URL, output: URL) throws {
        let data = try Data(contentsOf: input)
        let attributed = try onMainThread { () -> NSAttributedString in
            // The HTML importer is WebKit-based and must run on the main thread.
            guard let attr = NSAttributedString(
                html: data,
                baseURL: input.deletingLastPathComponent(),
                documentAttributes: nil) else {
                throw ConversionError.engineFailed("Couldn’t parse the HTML file")
            }
            return attr
        }
        try renderPaginated(attributed, to: output)
    }

    // MARK: - Word-processing fallback (no Word, no LibreOffice)

    static func convertAttributedDocument(input: URL, output: URL) throws {
        let attributed = try onMainThread { () -> NSAttributedString in
            do {
                return try NSAttributedString(
                    url: input,
                    options: [:],
                    documentAttributes: nil)
            } catch {
                throw ConversionError.engineFailed(
                    "Couldn’t read the document natively — install Microsoft Word or LibreOffice for full support")
            }
        }
        try renderPaginated(attributed, to: output)
    }

    // MARK: - Paginated text rendering (US Letter, 0.75in margins)

    static func renderPaginated(_ attributed: NSAttributedString, to output: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let inset: CGFloat = 54
        let textRect = pageRect.insetBy(dx: inset, dy: inset)

        var mediaBox = pageRect
        guard let context = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else {
            throw ConversionError.engineFailed("Couldn’t create the PDF file")
        }

        let content = attributed.length > 0 ? attributed : NSAttributedString(string: " ")
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        let path = CGPath(rect: textRect, transform: nil)

        var location = 0
        repeat {
            context.beginPage(mediaBox: &mediaBox)
            context.setFillColor(CGColor.white)
            context.fill(pageRect)

            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPage()

            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break } // avoid an infinite loop on unrenderable content
            location += visible.length
        } while location < content.length

        context.closePDF()
    }

    // MARK: - Helpers

    private static func onMainThread<T>(_ work: () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try work()
        }
        return try DispatchQueue.main.sync(execute: work)
    }
}
