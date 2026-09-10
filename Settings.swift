import Foundation
import Darwin

enum DockSide: String, Codable {
    case float, left, right
}

struct BucketSettings: Codable, Equatable {
    var dock: DockSide = .right
    var holdDelay: Double = 0.8
    var autoShow = true
    var onlyFiles = true
    var keepOpen = false
}

struct SettingsStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("settings.json") }
    private var lockFile: URL { directory.appendingPathComponent("manifest.lock") }

    func load() -> BucketSettings {
        (try? locked {
            try JSONDecoder().decode(BucketSettings.self, from: Data(contentsOf: file))
        }) ?? BucketSettings()
    }

    @discardableResult
    func update(_ mutation: (inout BucketSettings) -> Void) -> BucketSettings {
        (try? locked {
            var settings = (try? JSONDecoder().decode(BucketSettings.self, from: Data(contentsOf: file))) ?? BucketSettings()
            mutation(&settings)
            try JSONEncoder().encode(settings).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return settings
        }) ?? BucketSettings()
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(lockFile.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return try body()
    }
}
