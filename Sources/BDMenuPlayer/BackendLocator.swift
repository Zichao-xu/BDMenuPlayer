import Foundation
import Darwin

enum BackendLocator {
    static let makeMKVDownloadURL = URL(string: "https://www.makemkv.com/download/")!

    static var makeMKVLibraryCandidates: [URL] {
        let appRoots = [
            URL(fileURLWithPath: "/Applications/MakeMKV.app"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/MakeMKV.app")
        ]
        // MakeMKV has shipped the libaacs-compatible shim under both names.
        return appRoots.flatMap { root in
            ["libmmbd_new.dylib", "libmmbd.dylib"].map {
                root.appending(path: "Contents/lib/\($0)")
            }
        }
    }

    static var makeMKVLibrary: URL? {
        makeMKVLibraryCandidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    /// Points libbluray at a user-installed MakeMKV backend. Safe to call
    /// repeatedly, so a backend installed while the app is running is picked
    /// up on the next disc scan.
    @discardableResult
    static func prepareMakeMKVIntegration() -> Bool {
        guard let source = makeMKVLibrary else { return false }

        // libbluray reads these variables when it opens an encrypted disc.
        // Pointing at the user-installed backend avoids modifying our signed app
        // bundle or copying MakeMKV components into it.
        // libbluray's macOS loader appends `.dylib` itself.
        let path = source.deletingPathExtension().path
        return setenv("LIBAACS_PATH", path, 1) == 0 &&
            setenv("LIBBDPLUS_PATH", path, 1) == 0
    }
}
