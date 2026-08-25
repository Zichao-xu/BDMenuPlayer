import CBlurayBridge
import Foundation

struct DiscTechnicalInfo: Hashable, Sendable {
    let displayName: String
    let volumeID: String
    let libblurayVersion: String
    let hasFirstPlay: Bool
    let hasTopMenu: Bool
    let titleCount: Int
    let hdmvTitleCount: Int
    let bdjTitleCount: Int
    let usesBDJ: Bool
    let bdjReady: Bool
    let usesAACS: Bool
    let aacsReady: Bool
    let usesBDPlus: Bool
    let bdplusReady: Bool
    let mainDuration: TimeInterval
    let mainChapterStarts: [TimeInterval]
    let error: String?

    static func inspect(path: URL, fallbackName: String) -> DiscTechnicalInfo {
        let probe = path.path.withCString { bdprobe_create($0) }
        guard let probe else {
            return .failed(name: fallbackName, message: "Unable to allocate libbluray probe")
        }
        defer { bdprobe_destroy(probe) }

        func string(_ pointer: UnsafePointer<CChar>?) -> String? {
            guard let pointer else { return nil }
            let value = String(cString: pointer)
            return value.isEmpty ? nil : value
        }

        let chapterCount = Int(bdprobe_main_chapter_count(probe))
        let chapterStarts = (0..<chapterCount).map {
            TimeInterval(bdprobe_main_chapter_start_90k(probe, UInt32($0))) / 90_000
        }

        return DiscTechnicalInfo(
            displayName: string(bdprobe_disc_name(probe)) ?? fallbackName,
            volumeID: string(bdprobe_volume_id(probe)) ?? fallbackName,
            libblurayVersion: string(bdprobe_libbluray_version(probe)) ?? "Unknown",
            hasFirstPlay: bdprobe_has_first_play(probe) != 0,
            hasTopMenu: bdprobe_has_top_menu(probe) != 0,
            titleCount: Int(bdprobe_title_count(probe)),
            hdmvTitleCount: Int(bdprobe_hdmv_title_count(probe)),
            bdjTitleCount: Int(bdprobe_bdj_title_count(probe)),
            usesBDJ: bdprobe_bdj_detected(probe) != 0,
            bdjReady: bdprobe_bdj_handled(probe) != 0,
            usesAACS: bdprobe_aacs_detected(probe) != 0,
            aacsReady: bdprobe_aacs_handled(probe) != 0,
            usesBDPlus: bdprobe_bdplus_detected(probe) != 0,
            bdplusReady: bdprobe_bdplus_handled(probe) != 0,
            mainDuration: TimeInterval(bdprobe_main_duration_90k(probe)) / 90_000,
            mainChapterStarts: chapterStarts,
            error: string(bdprobe_error(probe))
        )
    }

    static func failed(name: String, message: String) -> DiscTechnicalInfo {
        DiscTechnicalInfo(
            displayName: name,
            volumeID: name,
            libblurayVersion: "Unknown",
            hasFirstPlay: false,
            hasTopMenu: false,
            titleCount: 0,
            hdmvTitleCount: 0,
            bdjTitleCount: 0,
            usesBDJ: false,
            bdjReady: false,
            usesAACS: false,
            aacsReady: false,
            usesBDPlus: false,
            bdplusReady: false,
            mainDuration: 0,
            mainChapterStarts: [],
            error: message
        )
    }
}

struct DiscVolume: Identifiable, Hashable, Sendable {
    let id: URL
    let mountURL: URL
    let volumeName: String
    let info: DiscTechnicalInfo
}
