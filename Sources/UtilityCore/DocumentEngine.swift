import Foundation
import PDFKit
import ZIPFoundation

public enum DocumentEngine {
    public static func markdown(from url: URL,progress:(Double)->Void={_ in}) throws -> String {
        try Task.checkCancellation()
        switch AssetKind(url: url) {
        case .image:return try OCREngine.markdown(image:url)
        case .pdf:
            guard let pdf = PDFDocument(url: url) else { throw UtilityError.message("Could not open the PDF") }
            guard !pdf.isLocked else { throw UtilityError.message("This PDF is password protected") }
            guard pdf.pageCount <= 500 else { throw UtilityError.message("PDF exceeds the draft's 500-page limit") }
            var blocks: [String] = []
            for i in 0..<pdf.pageCount {
                try Task.checkCancellation()
                var text = pdf.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty,let page=pdf.page(at:i) {text=try autoreleasepool {try OCREngine.recognize(page:page)}}
                guard !text.isEmpty else {throw UtilityError.message("No readable text on page \(i+1)")}
                blocks.append("## Page \(i + 1)\n\n" + text)
                progress(Double(i+1)/Double(pdf.pageCount))
            }
            guard !blocks.isEmpty else { throw UtilityError.message("This PDF has no pages") }
            return blocks.joined(separator: "\n\n") + "\n"
        case .word: return try word(OfficePackage(url))
        case .presentation: return try presentation(OfficePackage(url))
        case .text, .markdown:
            guard FileServices.bytes(url) <= 50_000_000 else { throw UtilityError.message("Text document exceeds the draft’s 50 MB limit") }
            return try String(contentsOf: url, encoding: .utf8)
        default: throw UtilityError.message("Supported document inputs are PDF, DOCX, PPTX, and UTF-8 text")
        }
    }

    private static func word(_ package: OfficePackage) throws -> String {
        guard let body = try package.xml("word/document.xml").rootElement()?.child("body") else { throw UtilityError.message("The Word document has no body") }
        var headings: [String: Int] = [:]
        if let styles = try? package.xml("word/styles.xml").rootElement() {
            for style in styles.elements("style") {
                let id = style.attr("styleId") ?? ""
                let name = style.child("name")?.attr("val")?.lowercased() ?? id.lowercased()
                if let outline = style.child("pPr")?.child("outlineLvl")?.attr("val").flatMap(Int.init), outline < 6 { headings[id] = outline + 1 }
                else if name.hasPrefix("heading"), let n = name.last?.wholeNumberValue { headings[id] = min(6, max(1,n)) }
                else if name == "title" { headings[id] = 1 }
            }
        }
        var numbering: [String: [String: String]] = [:]
        if let nums = try? package.xml("word/numbering.xml").rootElement() {
            var abstracts: [String: [String: String]] = [:]
            for a in nums.elements("abstractNum") {
                var levels: [String: String] = [:]
                for level in a.elements("lvl") { levels[level.attr("ilvl") ?? "0"] = level.child("numFmt")?.attr("val") ?? "bullet" }
                abstracts[a.attr("abstractNumId") ?? ""] = levels
            }
            for n in nums.elements("num") { numbering[n.attr("numId") ?? ""] = abstracts[n.child("abstractNumId")?.attr("val") ?? ""] }
        }
        let links = try package.relationships("word/_rels/document.xml.rels")
        var blocks: [String] = []
        for element in body.elementChildren {
            try Task.checkCancellation()
            if element.local == "tbl" { blocks.append(table(element)) }
            else if element.local == "p" {
                let text = inline(element, links: links).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let ppr = element.child("pPr")
                let style = ppr?.child("pStyle")?.attr("val") ?? ""
                if let level = headings[style] { blocks.append(String(repeating: "#", count: level) + " " + text) }
                else if let num = ppr?.child("numPr"), let id = num.child("numId")?.attr("val"), id != "0" {
                    let level = num.child("ilvl")?.attr("val") ?? "0"
                    let indent = String(repeating: "  ", count: min(8, Int(level) ?? 0))
                    let marker = numbering[id]?[level] == "bullet" ? "- " : "1. "
                    blocks.append(indent + marker + text)
                } else { blocks.append(text) }
            }
        }
        guard !blocks.isEmpty else { throw UtilityError.message("No supported text was found in the Word document") }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func inline(_ node: XMLElement, links: [String: String] = [:]) -> String {
        switch node.local {
        case "t": return escape(node.stringValue ?? "")
        case "tab": return "\t"
        case "br", "cr": return "\n"
        case "r":
            var value = node.elementChildren.filter { $0.local != "rPr" }.map { inline($0, links: links) }.joined()
            let props = node.child("rPr")
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let b = props?.child("b"), !["0", "false", "off"].contains(b.attr("val") ?? "true") { value = "**" + value + "**" }
                if let i = props?.child("i"), !["0", "false", "off"].contains(i.attr("val") ?? "true") { value = "*" + value + "*" }
            }
            return value
        case "hyperlink":
            let text = node.elementChildren.map { inline($0, links: links) }.joined()
            if let dest = links[node.attr("r:id") ?? ""], let u = URL(string: dest), ["http", "https", "mailto"].contains(u.scheme ?? "") { return "[\(text)](\(dest.replacingOccurrences(of: " ", with: "%20")))" }
            return text
        case "pPr", "rPr", "drawing", "object": return ""
        default: return node.elementChildren.map { inline($0, links: links) }.joined()
        }
    }

    private static func presentation(_ package: OfficePackage) throws -> String {
        guard let root = try package.xml("ppt/presentation.xml").rootElement(), let ids = root.child("sldIdLst") else { throw UtilityError.message("This presentation has no slide list") }
        let rels = try package.relationships("ppt/_rels/presentation.xml.rels")
        var blocks: [String] = []
        for (index, slideID) in ids.elements("sldId").enumerated() {
            try Task.checkCancellation()
            guard let target = rels[slideID.attr("r:id") ?? ""] else { throw UtilityError.message("A presentation slide relationship is missing") }
            let path = try OfficePackage.resolve(target, relativeTo: "ppt/presentation.xml")
            guard let tree = try package.xml(path).rootElement()?.descendants("spTree").first else { continue }
            var title: String?
            var content: [String] = []
            func readShapes(_ container: XMLElement) {
                for shape in container.elementChildren {
                    if shape.local == "grpSp" { readShapes(shape); continue }
                    if shape.local == "graphicFrame", let tbl = shape.descendants("tbl").first { content.append(table(tbl)); continue }
                    guard shape.local == "sp", let tx = shape.child("txBody") else { continue }
                    let isTitle = shape.descendants("ph").contains { ["title", "ctrTitle"].contains($0.attr("type") ?? "") }
                    for paragraph in tx.elements("p") {
                        let text = paragraph.descendants("t").compactMap(\.stringValue).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        if isTitle && title == nil { title = text; continue }
                        let pp = paragraph.child("pPr")
                        let level = min(8, pp?.attr("lvl").flatMap(Int.init) ?? 0)
                        let bullet = pp?.child("buChar") != nil || pp?.child("buAutoNum") != nil
                        content.append((bullet ? String(repeating: "  ", count: level) + "- " : "") + escape(text))
                    }
                }
            }
            readShapes(tree)
            let header = "## Slide \(index + 1)" + (title.map { ": " + escape($0) } ?? "")
            blocks.append(([header] + content).joined(separator: "\n\n"))
        }
        guard !blocks.isEmpty else { throw UtilityError.message("No slides could be read") }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func table(_ node: XMLElement) -> String {
        let rows = node.elements("tr").map { row in row.elements("tc").map { cell in
            cell.descendants("t").compactMap(\.stringValue).joined(separator: " ").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
        } }
        let count = rows.map(\.count).max() ?? 0
        guard count > 0 else { return "" }
        func line(_ cells: [String]) -> String { "| " + (cells + Array(repeating: "", count: max(0, count - cells.count))).joined(separator: " | ") + " |" }
        return ([line(rows[0]), line(Array(repeating: "---", count: count))] + rows.dropFirst().map(line)).joined(separator: "\n")
    }
    private static func escape(_ text: String) -> String {
        var s = text
        for char in ["\\", "*", "_", "[", "]", "<", ">", "#"] { s = s.replacingOccurrences(of: char, with: "\\" + char) }
        return s
    }
}

final class OfficePackage {
    let archive: Archive
    init(_ url: URL) throws {
        guard FileServices.bytes(url) <= 100_000_000 else { throw UtilityError.message("Office file exceeds the draft's 100 MB limit") }
        archive = try Archive(url: url, accessMode: .read)
        var count = 0; var total: UInt64 = 0
        for entry in archive {
            count += 1
            guard count <= 20000, entry.uncompressedSize <= 300_000_000, total <= 300_000_000 - entry.uncompressedSize else { throw UtilityError.message("Office archive expands beyond the draft's limit") }
            total += entry.uncompressedSize
        }
    }
    func xml(_ path: String) throws -> XMLDocument {
        guard let entry = archive[path], entry.uncompressedSize <= 20_000_000 else { throw UtilityError.message("Missing or oversized Office XML: \(path)") }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= 20_000_000 else { throw UtilityError.message("Office XML is too large") }
            data.append(chunk)
        }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let xml = String(data: data, encoding: encoding), xml.range(of: "<!DOCTYPE", options: .caseInsensitive) != nil { throw UtilityError.message("XML document type declarations are not supported") }
        }
        return try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
    }
    func relationships(_ path: String) throws -> [String: String] {
        guard archive[path] != nil else { return [:] }
        var result: [String: String] = [:]
        for r in try xml(path).rootElement()?.elements("Relationship") ?? [] {
            if let id = r.attr("Id"), let target = r.attr("Target") { result[id] = target }
        }
        return result
    }
    static func resolve(_ target: String, relativeTo source: String) throws -> String {
        guard !target.contains(":") else { throw UtilityError.message("External slide links are not supported") }
        let path = target.hasPrefix("/") ? target : (source as NSString).deletingLastPathComponent + "/" + target
        var parts: [String] = []
        for p in path.split(separator: "/") {
            if p == "." { continue }
            if p == ".." { guard !parts.isEmpty else { throw UtilityError.message("Invalid Office relationship path") }; parts.removeLast() }
            else { parts.append(String(p)) }
        }
        return parts.joined(separator: "/")
    }
}

extension XMLElement {
    var local: String { localName ?? name?.components(separatedBy: ":").last ?? "" }
    var elementChildren: [XMLElement] { (children ?? []).compactMap { $0 as? XMLElement } }
    func child(_ name: String) -> XMLElement? { elementChildren.first { $0.local == name } }
    func elements(_ name: String) -> [XMLElement] { elementChildren.filter { $0.local == name } }
    func descendants(_ name: String) -> [XMLElement] { elementChildren.flatMap { ($0.local == name ? [$0] : []) + $0.descendants(name) } }
    func attr(_ name: String) -> String? { attribute(forName: name)?.stringValue ?? (name.contains(":") ? nil : attributes?.first { $0.localName == name }?.stringValue) }
}
