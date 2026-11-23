import SwiftUI

/// Help window: shows a Markdown document that is bundled with the app (README = technical reference, UserGuide = guide for everyone) (simple Markdown: headings, lists, code blocks, bold/code/links inline).
struct ReadmeView: View {
    var resource = "README"
    private struct Block: Identifiable { let id: Int; let kind: Kind; let text: String; var number = ""
        enum Kind { case h1, h2, h3, bullet, numbered, code, paragraph } }

    private static func load(_ resource: String) -> String {
        if let u = Bundle.main.url(forResource: resource, withExtension: "md"), let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        return "# GPX Organizer\n\nThis document is not part of this build. See the project page for the documentation."
    }

    private var blocks: [Block] { ReadmeView.parse(ReadmeView.load(resource)) }

    private static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = [], code: [String] = [], inCode = false
        func flushPara() { if !para.isEmpty { out.append(Block(id: out.count, kind: .paragraph, text: para.joined(separator: " "))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("```") {
                if inCode { out.append(Block(id: out.count, kind: .code, text: code.joined(separator: "\n"))); code = [] } else { flushPara() }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            if line.hasPrefix("### ") { flushPara(); out.append(Block(id: out.count, kind: .h3, text: String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { flushPara(); out.append(Block(id: out.count, kind: .h2, text: String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { flushPara(); out.append(Block(id: out.count, kind: .h1, text: String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") { flushPara(); out.append(Block(id: out.count, kind: .bullet, text: String(line.dropFirst(2)))) }
            else if let r = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                flushPara(); out.append(Block(id: out.count, kind: .numbered, text: String(line[r.upperBound...]), number: String(line[..<r.upperBound]).trimmingCharacters(in: .whitespaces)))
            }
            else if line.hasPrefix("  "), let last = out.last, last.kind == .bullet || last.kind == .numbered, para.isEmpty {       // continuation of a list item
                out[out.count - 1] = Block(id: last.id, kind: last.kind, text: last.text + " " + line.trimmingCharacters(in: .whitespaces), number: last.number)
            }
            else if line.trimmingCharacters(in: .whitespaces).isEmpty { flushPara() }
            else { para.append(line.trimmingCharacters(in: .whitespaces)) }
        }
        flushPara()
        return out
    }

    private func inline(_ raw: String) -> Text {
        let s = raw.replacingOccurrences(of: "<kbd>", with: "`").replacingOccurrences(of: "</kbd>", with: "`")
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(a) }
        return Text(s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { b in
                    switch b.kind {
                    case .h1: inline(b.text).font(.largeTitle).bold().padding(.top, 4)
                    case .h2: inline(b.text).font(.title2).bold().padding(.top, 10)
                    case .h3: inline(b.text).font(.headline).padding(.top, 4)
                    case .bullet:
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); inline(b.text).fixedSize(horizontal: false, vertical: true) }
                            .padding(.leading, 8)
                    case .numbered:
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text(b.number).monospacedDigit(); inline(b.text).fixedSize(horizontal: false, vertical: true) }
                            .padding(.leading, 8)
                    case .code:
                        Text(b.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                    case .paragraph: inline(b.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .textSelection(.enabled)
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}
