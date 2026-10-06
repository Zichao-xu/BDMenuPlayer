import Foundation

/// A line ready for the overlay, with the size and placement its source
/// subtitle asked for.
struct SubtitleLine: Hashable, Sendable {
    enum Placement: Sendable { case top, bottom }

    let text: String
    /// Font size as a fraction of the video height.
    let relativeSize: Double
    let placement: Placement
    /// 1 left, 2 center, 3 right (ASS numpad column).
    let column: Int
}

/// Parses ASS/SSA and SRT into timed lines. Any style is accepted; the
/// overlay reproduces size, top/bottom placement and stacking order, but not
/// fonts, colours or positioned signs.
struct SubtitleTrack: Sendable {
    struct Cue: Sendable {
        let startMilliseconds: Int64
        let endMilliseconds: Int64
        let line: SubtitleLine
        /// Lower values sit closer to the screen edge, like libass collision order.
        let order: Int
    }

    let cues: [Cue]
    /// Width / height of the frame the subtitle was authored for.
    let aspectRatio: Double

    init(url: URL) throws {
        var source = try String(contentsOf: url, encoding: .utf8)
        if source.first == "\u{FEFF}" { source.removeFirst() }
        source = source.replacingOccurrences(of: "\r\n", with: "\n")
        if url.pathExtension.lowercased() == "srt" || !source.contains("Dialogue:") {
            cues = Self.parseSRT(source)
            aspectRatio = 16 / 9
        } else {
            (cues, aspectRatio) = Self.parseASS(source)
        }
    }

    func lines(at milliseconds: Int64) -> [SubtitleLine] {
        cues
            .filter { $0.startMilliseconds <= milliseconds && milliseconds < $0.endMilliseconds }
            .sorted { $0.order < $1.order }
            .prefix(6)
            .map(\.line)
    }

    // MARK: - ASS

    private struct Style {
        var fontSize = 20.0
        var alignment = 2
    }

    private static func parseASS(_ source: String) -> ([Cue], Double) {
        var section = ""
        var playResX = 384.0
        var playResY = 288.0
        var styleFields: [String] = []
        var eventFields = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        var styles: [String: Style] = [:]
        var cues: [Cue] = []

        for raw in source.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.lowercased()
                continue
            }
            if section == "[script info]" {
                if let value = value(of: "PlayResX", in: line), let number = Double(value) { playResX = number }
                if let value = value(of: "PlayResY", in: line), let number = Double(value) { playResY = number }
            } else if section.hasPrefix("[v4") {
                if line.hasPrefix("Format:") {
                    styleFields = fieldNames(line)
                } else if line.hasPrefix("Style:") {
                    let values = split(line, dropping: "Style:", count: max(styleFields.count, 1))
                    var style = Style()
                    if let index = styleFields.firstIndex(of: "fontsize"), index < values.count,
                       let size = Double(values[index]) { style.fontSize = size }
                    if let index = styleFields.firstIndex(of: "alignment"), index < values.count,
                       let alignment = Int(values[index]) {
                        // Legacy SSA alignment: 1-3 bottom, +4 top, +8 middle.
                        style.alignment = section == "[v4 styles]" ? legacyAlignment(alignment) : alignment
                    }
                    if let name = values.first { styles[name] = style }
                }
            } else if section == "[events]" {
                if line.hasPrefix("Format:") {
                    eventFields = fieldNames(line)
                    continue
                }
                guard line.hasPrefix("Dialogue:") else { continue }
                let values = split(line, dropping: "Dialogue:", count: eventFields.count)
                func field(_ name: String) -> String? {
                    eventFields.firstIndex(of: name).flatMap { $0 < values.count ? values[$0] : nil }
                }
                guard
                    let text = field("text"),
                    let start = field("start").flatMap(assTime),
                    let end = field("end").flatMap(assTime),
                    end > start,
                    let cue = makeCue(
                        text: text,
                        style: styles[field("style") ?? ""] ?? Style(),
                        layer: Int(field("layer") ?? "") ?? 0,
                        readOrder: cues.count,
                        playResY: playResY,
                        start: start,
                        end: end
                    )
                else { continue }
                cues.append(cue)
            }
        }
        return (cues, playResX / max(1, playResY))
    }

    private static func makeCue(
        text raw: String,
        style: Style,
        layer: Int,
        readOrder: Int,
        playResY: Double,
        start: Int64,
        end: Int64
    ) -> Cue? {
        let overrides = raw.matches(of: /\{([^}]*)\}/).map { String($0.output.1) }.joined()
        // Vector drawings render as garbage when reduced to text.
        if overrides.contains(/\\p[1-9]/) { return nil }

        var alignment = style.alignment
        if let match = overrides.firstMatch(of: /\\an([1-9])/), let value = Int(match.output.1) {
            alignment = value
        }
        var placement: SubtitleLine.Placement = alignment >= 4 ? .top : .bottom
        // A positioned line belongs to whichever half of the frame it points at.
        if let match = overrides.firstMatch(of: /\\(?:pos|move)\(\s*[-\d.]+\s*,\s*([-\d.]+)/),
           let y = Double(match.output.1) {
            placement = y < playResY / 2 ? .top : .bottom
        }
        var size = style.fontSize
        if let match = overrides.firstMatch(of: /\\fs([\d.]+)/), let value = Double(match.output.1) {
            size = value
        }

        let text = raw
            .replacing(/\{[^}]*\}/, with: "")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: "\u{00A0}")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return Cue(
            startMilliseconds: start,
            endMilliseconds: end,
            line: SubtitleLine(
                text: text,
                relativeSize: min(0.2, max(0.02, size / max(1, playResY))),
                placement: placement,
                column: (alignment - 1) % 3 + 1
            ),
            order: layer * 100_000 + readOrder
        )
    }

    private static func legacyAlignment(_ value: Int) -> Int {
        let column = value & 3
        if value & 4 != 0 { return 6 + column }
        if value & 8 != 0 { return 3 + column }
        return column
    }

    private static func fieldNames(_ line: String) -> [String] {
        line.dropFirst("Format:".count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    /// Splits a Style/Dialogue line; the final field (text) may contain commas.
    private static func split(_ line: String, dropping prefix: String, count: Int) -> [String] {
        line.dropFirst(prefix.count)
            .split(separator: ",", maxSplits: max(0, count - 1), omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func value(of key: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(key.lowercased() + ":") else { return nil }
        return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
    }

    private static func assTime(_ timestamp: String) -> Int64? {
        let pieces = timestamp.split(separator: ":")
        guard pieces.count == 3,
              let hours = Double(pieces[0]),
              let minutes = Double(pieces[1]),
              let seconds = Double(pieces[2]) else { return nil }
        return Int64(((hours * 3600) + (minutes * 60) + seconds) * 1000)
    }

    // MARK: - SRT

    private static func parseSRT(_ source: String) -> [Cue] {
        var cues: [Cue] = []
        for block in source.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[timingIndex].components(separatedBy: "-->")
            guard times.count == 2,
                  let start = srtTime(times[0]),
                  let end = srtTime(times[1]),
                  end > start else { continue }
            let text = lines[(timingIndex + 1)...]
                .joined(separator: "\n")
                .replacing(/<[^>]*>/, with: "")
                .replacing(/\{[^}]*\}/, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(Cue(
                startMilliseconds: start,
                endMilliseconds: end,
                line: SubtitleLine(text: text, relativeSize: 0.055, placement: .bottom, column: 2),
                order: cues.count
            ))
        }
        return cues
    }

    private static func srtTime(_ value: String) -> Int64? {
        // 00:01:02,345 (some files use a period)
        let cleaned = value.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init)?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        return assTime(cleaned)
    }
}
