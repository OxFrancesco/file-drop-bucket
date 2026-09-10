import Foundation
import Darwin

struct BucketStore {
    let directory: URL
    init() {
        directory = ProcessInfo.processInfo.environment["BUCKET_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FileDropBucket")
    }
    func canonical(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw NSError(domain: "Bucket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a regular file: \(path)"])
        }
        return url.path
    }
    func access(_ mutation: ((inout [String]) throws -> Void)? = nil) throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(directory.appendingPathComponent("manifest.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let file = directory.appendingPathComponent("manifest.json")
        var paths = [String]()
        if FileManager.default.fileExists(atPath: file.path) {
            paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: file))
        }
        if let mutation {
            try mutation(&paths)
            try JSONEncoder().encode(paths).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return paths
    }
    func add(_ inputs: [String]) throws {
        let valid = try inputs.map(canonical)
        _ = try access { paths in for path in valid where !paths.contains(path) { paths.append(path) } }
    }
}
