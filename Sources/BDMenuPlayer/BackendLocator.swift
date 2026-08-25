import Foundation
import Darwin

enum BackendLocator {
    static let makeMKVLibraryCandidates = [
        URL(fileURLWithPath: "/Applications/MakeMKV.app/Contents/lib/libmmbd_new.dylib"),
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Applications/MakeMKV.app/Contents/lib/libmmbd_new.dylib")
    ]

    static var makeMKVLibrary: URL? {
        makeMKVLibraryCandidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

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
