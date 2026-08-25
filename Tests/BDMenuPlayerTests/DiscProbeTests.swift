import CBlurayBridge
import CVLCBridge
import Darwin
import Foundation
import XCTest
@testable import BDMenuPlayer

final class DiscProbeTests: XCTestCase {
    func testLibblurayRuntimeIsAvailable() {
        let probe = bdprobe_create("")
        XCTAssertNotNil(probe)
        defer { bdprobe_destroy(probe) }
        XCTAssertFalse(String(cString: bdprobe_libbluray_version(probe)).isEmpty)
    }

    func testConfiguredDiscExposesBluRayStructure() throws {
        let discURL = try configuredDiscURL()
        let probe = discURL.path.withCString { bdprobe_create($0) }
        XCTAssertNotNil(probe)
        defer { bdprobe_destroy(probe) }

        XCTAssertEqual(bdprobe_is_bluray(probe), 1)
        XCTAssertGreaterThan(bdprobe_title_count(probe), 0)
        XCTAssertTrue(bdprobe_has_first_play(probe) != 0 || bdprobe_has_top_menu(probe) != 0)
    }

    func testConfiguredDiscMenuReachesPlaybackThroughARM64VLC() throws {
        let discURL = try configuredDiscURL()
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pluginPath = packageRoot.appending(path: "Dependencies/VLC/plugins").path

        guard FileManager.default.fileExists(atPath: pluginPath) else {
            throw XCTSkip("Run scripts/setup-vlc.sh to install the local VLC runtime")
        }

        _ = BackendLocator.prepareMakeMKVIntegration()
        let bridge = pluginPath.withCString { vlcbridge_create($0) }
        XCTAssertNotNil(bridge)
        guard let bridge else { return }
        defer {
            vlcbridge_stop(bridge)
            vlcbridge_destroy(bridge)
        }

        XCTAssertEqual(
            discURL.path.withCString { vlcbridge_play_bluray(bridge, $0, nil) },
            0
        )

        let deadline = Date().addingTimeInterval(30)
        var observedStates: Set<Int32> = []
        while Date() < deadline {
            let state = vlcbridge_player_state(bridge)
            observedStates.insert(state)
            if state == 3 { return }
            if state == 7 {
                XCTFail("LibVLC reported a playback error; states: \(observedStates.sorted())")
                return
            }
            usleep(200_000)
        }
        XCTFail("Blu-ray menu did not reach playback; states: \(observedStates.sorted())")
    }

    func testASSParserReturnsBilingualLines() throws {
        let subtitle = """
        [Script Info]
        Title: Fixture

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Dial_JP,,0,0,0,,こんにちは
        Dialogue: 1,0:00:01.00,0:00:03.00,Dial_CH,,0,0,0,,你好
        """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "BDMenuPlayer-\(UUID().uuidString).ass")
        try subtitle.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let track = try ASSSubtitleTrack(url: url)
        XCTAssertEqual(track.lines(at: 2_000), ["こんにちは", "你好"])
        XCTAssertTrue(track.lines(at: 4_000).isEmpty)
    }

    private func configuredDiscURL() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["BD_MENU_PLAYER_TEST_DISC"],
              FileManager.default.fileExists(atPath: path + "/BDMV/index.bdmv") else {
            throw XCTSkip("Set BD_MENU_PLAYER_TEST_DISC to a mounted Blu-ray volume")
        }
        return URL(fileURLWithPath: path)
    }
}
