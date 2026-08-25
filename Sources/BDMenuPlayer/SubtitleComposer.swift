import Foundation

enum SubtitleComposerError: LocalizedError {
    case unsupportedMultipleFiles
    case unreadable(URL)
    case missingEvents(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedMultipleFiles:
            "Multiple-file merging currently supports ASS subtitles only."
        case .unreadable(let url):
            "Unable to read \(url.lastPathComponent)."
        case .missingEvents(let url):
            "No ASS events were found in \(url.lastPathComponent)."
        }
    }
}

enum SubtitleComposer {
    private struct ASSDocument {
        var scriptInfo: [String]
        var styleFormat: String
        var styles: [(name: String, line: String)]
        var eventFormat: String
        var events: [String]
    }

    static func compose(urls: [URL], for disc: DiscTechnicalInfo) throws -> URL {
        let sortedURLs = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard !sortedURLs.isEmpty else { throw SubtitleComposerError.unsupportedMultipleFiles }

        if sortedURLs.count == 1, sortedURLs[0].pathExtension.lowercased() != "ass" {
            return sortedURLs[0]
        }
        guard sortedURLs.allSatisfy({ $0.pathExtension.lowercased() == "ass" }) else {
            throw SubtitleComposerError.unsupportedMultipleFiles
        }

        let documents = try sortedURLs.map(parseASS)
        let offsets = timelineOffsets(fileCount: documents.count, disc: disc)

        var styleNames = Set<String>()
        var mergedStyles: [String] = []
        for document in documents {
            for style in document.styles where styleNames.insert(style.name).inserted {
                mergedStyles.append(style.line)
            }
        }

        var mergedEvents: [String] = []
        for (index, document) in documents.enumerated() {
            mergedEvents.append(contentsOf: document.events.map { shiftEvent($0, by: offsets[index]) })
        }

        let first = documents[0]
        let output = (["\u{FEFF}[Script Info]"] + first.scriptInfo + [
            "",
            "[V4+ Styles]",
            first.styleFormat,
        ] + mergedStyles + [
            "",
            "[Events]",
            first.eventFormat,
        ] + mergedEvents).joined(separator: "\n") + "\n"

        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "BDMenuPlayer/Generated Subtitles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let episodeNames = sortedURLs.compactMap(episodeNumber).joined(separator: "+")
        let suffix = episodeNames.isEmpty ? "merged" : episodeNames
        let outputURL = cacheRoot.appending(path: "BDMenuPlayer \(suffix) bilingual.ass")
        try output.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func timelineOffsets(fileCount: Int, disc: DiscTechnicalInfo) -> [TimeInterval] {
        guard fileCount > 1 else { return [0] }
        let usableChapters = disc.mainChapterStarts.filter { $0 > 1 && $0 < disc.mainDuration - 1 }
        return (0..<fileCount).map { index in
            guard index > 0, disc.mainDuration > 0 else { return 0 }
            let target = disc.mainDuration * Double(index) / Double(fileCount)
            return usableChapters.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
        }
    }

    private static func parseASS(_ url: URL) throws -> ASSDocument {
        guard var text = try? String(contentsOf: url, encoding: .utf8) else {
            throw SubtitleComposerError.unreadable(url)
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var aliases: [String: String] = [:]
        for line in lines where line.hasPrefix("; Font Subset: ") {
            let mapping = String(line.dropFirst("; Font Subset: ".count)).components(separatedBy: " - ")
            if mapping.count == 2 {
                aliases[mapping[0]] = fallbackFont(for: mapping[1])
            }
        }

        var section = ""
        var scriptInfo: [String] = []
        var styleFormat = "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"
        var styles: [(String, String)] = []
        var eventFormat = "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        var events: [String] = []

        for line in lines {
            if line.hasPrefix("[") {
                section = line
                continue
            }
            switch section {
            case "[Script Info]":
                if !line.hasPrefix("; Font Subset:") && !line.hasPrefix("; Processed by AssFontSubset") {
                    scriptInfo.append(line)
                }
            case "[V4+ Styles]":
                if line.hasPrefix("Format:") {
                    styleFormat = line
                } else if line.hasPrefix("Style:") {
                    let normalized = normalizeFonts(in: line, aliases: aliases)
                    let name = normalized.dropFirst("Style:".count).split(separator: ",", maxSplits: 1)[0]
                        .trimmingCharacters(in: .whitespaces)
                    styles.append((name, normalized))
                }
            case "[Events]":
                if line.hasPrefix("Format:") {
                    eventFormat = line
                } else if !line.isEmpty {
                    events.append(normalizeFonts(in: line, aliases: aliases))
                }
            default:
                break
            }
        }
        guard !events.isEmpty else { throw SubtitleComposerError.missingEvents(url) }
        return ASSDocument(
            scriptInfo: scriptInfo,
            styleFormat: styleFormat,
            styles: styles,
            eventFormat: eventFormat,
            events: events
        )
    }

    private static func normalizeFonts(in line: String, aliases: [String: String]) -> String {
        var result = line
        for (alias, fallback) in aliases {
            result = result.replacingOccurrences(of: alias, with: fallback)
        }
        let directFallbacks = [
            "A-OTF UD Shin Go Pr6N DB": "Hiragino Sans",
            "FOT-Seurat ProN B": "Hiragino Sans",
            "HYQiHei 65S": "PingFang TC",
            "HYQiHei 85S": "PingFang TC",
            "HYQiHei 45S": "PingFang TC",
            "FZYaSong-DB-GBK": "Songti TC",
            "FZYaSong-B-GBK": "Songti TC",
            "DFGHSMincho-W7": "Hiragino Mincho ProN",
            "DFHanziPenW5-A": "HanziPen TC",
            "DFHanziPenW3-A": "HanziPen TC",
            "FZLanTingYuan-B-GBK": "Yuanti TC",
            "FZLanTingYuan-EB-GBK": "Yuanti TC",
            "FZLanTingYuan-DB-GBK": "Yuanti TC",
            "FZLanTingYuan-R-GBK": "Yuanti TC",
            "FZXiaoBiaoSong-B05": "Songti TC",
            "FZYingBiKaiShu-S15": "Kaiti TC",
            "DFHannotateW7-A": "Hannotate TC",
            "Zpix": "PingFang TC",
        ]
        for (font, fallback) in directFallbacks {
            result = result.replacingOccurrences(of: font, with: fallback)
        }
        return result
    }

    private static func fallbackFont(for original: String) -> String {
        normalizeFonts(in: original, aliases: [:]) == original ? "PingFang TC" : normalizeFonts(in: original, aliases: [:])
    }

    private static func shiftEvent(_ line: String, by offset: TimeInterval) -> String {
        guard offset != 0 else { return line }
        var fields = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4,
              let start = parseTime(fields[1]),
              let end = parseTime(fields[2]) else { return line }
        fields[1] = formatTime(start + offset)
        fields[2] = formatTime(end + offset)
        return fields.joined(separator: ",")
    }

    private static func parseTime(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3_600 + minutes * 60 + seconds
    }

    private static func formatTime(_ value: TimeInterval) -> String {
        let centiseconds = Int((value * 100).rounded())
        let hours = centiseconds / 360_000
        let minutes = (centiseconds / 6_000) % 60
        let seconds = (centiseconds / 100) % 60
        let fraction = centiseconds % 100
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, fraction)
    }

    private static func episodeNumber(_ url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let match = name.range(of: #"(?<!\d)(\d{2})(?!\d)"#, options: .regularExpression) else {
            return nil
        }
        return String(name[match])
    }
}
