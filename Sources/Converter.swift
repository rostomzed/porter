import Foundation
import AppKit

enum ConversionError: LocalizedError {
    case unsupported(String)
    case engineUnavailable(String)
    case engineFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            return "“.\(ext)” files aren’t supported yet"
        case .engineUnavailable(let msg):
            return msg
        case .engineFailed(let msg):
            return msg
        case .outputMissing:
            return "The conversion finished but no PDF was produced"
        }
    }
}

/// Routes a file to the best available conversion engine.
enum Converter {

    static let wordExtensions: Set<String> = ["doc", "docx", "dot", "dotx", "docm", "rtf", "odt"]
    static let excelExtensions: Set<String> = ["xls", "xlsx", "xlsm", "csv", "ods"]
    static let powerPointExtensions: Set<String> = ["ppt", "pptx", "pptm", "odp"]
    static let pagesExtensions: Set<String> = ["pages"]
    static let numbersExtensions: Set<String> = ["numbers"]
    static let keynoteExtensions: Set<String> = ["key"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp", "jp2"]
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "text", "log"]
    static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]
    static let rtfdExtensions: Set<String> = ["rtfd"]

    /// Google Drive "files" (.gdoc etc.) are not documents — they're tiny JSON
    /// pointers to a document that lives in Google's cloud. No local app can
    /// convert them; they must be downloaded from Google in a real format.
    static let googlePointerExtensions: Set<String> = ["gdoc", "gsheet", "gslides", "gdraw", "gform", "gtable"]

    static var supportedExtensions: Set<String> {
        wordExtensions
            .union(excelExtensions)
            .union(powerPointExtensions)
            .union(pagesExtensions)
            .union(numbersExtensions)
            .union(keynoteExtensions)
            .union(imageExtensions)
            .union(textExtensions)
            .union(htmlExtensions)
            .union(rtfdExtensions)
    }

    /// Convert `input` to a PDF at `output`. Throws on failure.
    /// Runs on a background queue.
    static func convert(input: URL, output: URL) throws {
        let ext = input.pathExtension.lowercased()

        if googlePointerExtensions.contains(ext) {
            throw ConversionError.engineFailed(
                "This is a link to a Google Docs file in the cloud, not the document itself. In Google Docs/Sheets/Slides use File → Download → PDF (or Word/Excel/PowerPoint format), then convert that file.")
        }

        switch ext {
        case _ where wordExtensions.contains(ext) || rtfdExtensions.contains(ext):
            try convertWordFamily(input: input, output: output, ext: ext)

        case _ where excelExtensions.contains(ext):
            try convertExcelFamily(input: input, output: output, ext: ext)

        case _ where powerPointExtensions.contains(ext):
            try convertPowerPointFamily(input: input, output: output)

        case _ where pagesExtensions.contains(ext):
            try OfficeConverter.convertWithIWork(app: .pages, input: input, output: output)

        case _ where numbersExtensions.contains(ext):
            try OfficeConverter.convertWithIWork(app: .numbers, input: input, output: output)

        case _ where keynoteExtensions.contains(ext):
            try OfficeConverter.convertWithIWork(app: .keynote, input: input, output: output)

        case _ where imageExtensions.contains(ext):
            try NativeConverters.convertImage(input: input, output: output)

        case _ where textExtensions.contains(ext):
            try NativeConverters.convertText(input: input, output: output)

        case _ where htmlExtensions.contains(ext):
            try NativeConverters.convertHTML(input: input, output: output)

        default:
            throw ConversionError.unsupported(ext)
        }

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.outputMissing
        }
    }

    // MARK: - Family routing with fallbacks

    private static func convertWordFamily(input: URL, output: URL, ext: String) throws {
        // Microsoft Word gives perfect fidelity, including legacy .doc files.
        if OfficeConverter.isInstalled(.word), ext != "rtfd" {
            try OfficeConverter.convertWithWord(input: input, output: output)
            return
        }
        if LibreOfficeConverter.isInstalled {
            try LibreOfficeConverter.convert(input: input, output: output)
            return
        }
        // Native fallback: decent for simple documents.
        try NativeConverters.convertAttributedDocument(input: input, output: output)
    }

    private static func convertExcelFamily(input: URL, output: URL, ext: String) throws {
        if OfficeConverter.isInstalled(.excel) {
            try OfficeConverter.convertWithExcel(input: input, output: output)
            return
        }
        if LibreOfficeConverter.isInstalled {
            try LibreOfficeConverter.convert(input: input, output: output)
            return
        }
        if ext == "csv" {
            try NativeConverters.convertText(input: input, output: output)
            return
        }
        throw ConversionError.engineUnavailable(
            "Converting spreadsheets requires Microsoft Excel or LibreOffice")
    }

    private static func convertPowerPointFamily(input: URL, output: URL) throws {
        if OfficeConverter.isInstalled(.powerPoint) {
            try OfficeConverter.convertWithPowerPoint(input: input, output: output)
            return
        }
        if LibreOfficeConverter.isInstalled {
            try LibreOfficeConverter.convert(input: input, output: output)
            return
        }
        throw ConversionError.engineUnavailable(
            "Converting presentations requires Microsoft PowerPoint or LibreOffice")
    }
}
