import Foundation

struct ASSSubtitleTrack: Sendable {
    struct Cue: Sendable {
        let startMilliseconds: Int64
        let endMilliseconds: Int64
        let text: String
    }

    let cues: [Cue]

    init(url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        cues = source.split(whereSeparator: \Character.isNewline).compactMap { line in
            guard line.hasPrefix("Dialogue:") else { return nil }
            let fields = line.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10 else { return nil }

            let style = String(fields[3])
            guard style.hasPrefix("Dial_JP") || style.hasPrefix("Dial_CH") else { return nil }
            guard let start = Self.milliseconds(String(fields[1])),
                  let end = Self.milliseconds(String(fields[2])) else { return nil }

            let cleanText = String(fields[9])
                .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\\N"#, with: "\n")
                .replacingOccurrences(of: #"\\n"#, with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return nil }
            return Cue(startMilliseconds: start, endMilliseconds: end, text: cleanText)
        }
    }

    func lines(at milliseconds: Int64) -> [String] {
        cues.lazy
            .filter { $0.startMilliseconds <= milliseconds && milliseconds < $0.endMilliseconds }
            .prefix(4)
            .map(\.text)
    }

    private static func milliseconds(_ timestamp: String) -> Int64? {
        let pieces = timestamp.split(separator: ":")
        guard pieces.count == 3,
              let hours = Double(pieces[0]),
              let minutes = Double(pieces[1]),
              let seconds = Double(pieces[2]) else { return nil }
        return Int64(((hours * 3600) + (minutes * 60) + seconds) * 1000)
    }
}
