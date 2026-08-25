import Foundation

enum DiscScanner {
    static func scan() -> [DiscVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsReadOnlyKey]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumes.compactMap { volumeURL in
            let indexURL = volumeURL.appending(path: "BDMV/index.bdmv")
            guard FileManager.default.fileExists(atPath: indexURL.path) else {
                return nil
            }

            let values = try? volumeURL.resourceValues(forKeys: Set(keys))
            let volumeName = values?.volumeName ?? volumeURL.lastPathComponent
            let info = DiscTechnicalInfo.inspect(path: volumeURL, fallbackName: volumeName)
            return DiscVolume(id: volumeURL, mountURL: volumeURL, volumeName: volumeName, info: info)
        }
        .sorted { $0.info.displayName.localizedStandardCompare($1.info.displayName) == .orderedAscending }
    }
}
