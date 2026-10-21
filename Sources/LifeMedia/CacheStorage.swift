import Foundation
@preconcurrency import AVFoundation
import ObjectiveC

/// Only these regenerable app-owned files are eligible for cleanup. Required
/// format-conversion intermediates live in Application Support and are excluded.
public struct CacheStorage: Sendable {
    private let rootOverride: URL?
    public init() { rootOverride = nil }
    public static var defaultBudgetBytes: Int64 {
        let value = UserDefaults.standard.object(forKey: "cacheBudgetGB") as? Double ?? 10
        let gigabytes = value.isFinite && (1...100).contains(value) ? value : 10
        return Int64(gigabytes * 1_000_000_000)
    }
    init(root: URL) { rootOverride = root }
    private var ownedDirectories: [URL] {
        guard let rootOverride else { return Self.directories }
        return ["org.lifeeditor.proxy", "org.lifeeditor.retime", "org.lifeeditor.canvas", "org.lifeeditor.audio"].map { rootOverride.appendingPathComponent($0, isDirectory: true) }
    }
    static var directories: [URL] {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ["org.lifeeditor.proxy", "org.lifeeditor.retime", "org.lifeeditor.canvas", "org.lifeeditor.audio"].map { root.appendingPathComponent($0, isDirectory: true) }
    }
    private func files() throws -> [(URL, Int64, Date)] {
        var result: [(URL, Int64, Date)] = []
        for directory in ownedDirectories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                // Only versioned, hashed media artifacts are disposable; never
                // recursively traverse directories or follow links into user files.
                guard ["mp4", "mov", "wav"].contains(url.pathExtension) else { continue }
                let stem = url.deletingPathExtension().lastPathComponent
                let isHash = stem.count == 64 && stem.allSatisfy { $0.isHexDigit }
                guard isHash || url.lastPathComponent == "black-v1.mov" else { continue }
                result.append((url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast))
            }
        }
        return result
    }
    public func usageBytes() throws -> Int64 { try files().reduce(0) { $0 + $1.1 } }
    @discardableResult public func cleanup(budget: Int64 = CacheStorage.defaultBudgetBytes, protectedURLs: Set<URL> = []) throws -> Int64 {
        let entries = try files().sorted { $0.2 < $1.2 }
        let protected = Set((protectedURLs.union(CacheLease.activeURLs)).map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        var remaining = entries.reduce(Int64(0)) { $0 + $1.1 }
        for (url, size, _) in entries where remaining > max(0, budget) {
            guard !protected.contains(url.standardizedFileURL.resolvingSymlinksInPath()) else { continue }
            try FileManager.default.removeItem(at: url); remaining -= size
        }
        return remaining
    }
}

/// Active player items and exports lease their decoded sources so cleanup cannot
/// invalidate a composition that has not opened all of its media files yet.
final class CacheLease: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [URL: Int] = [:]
    let urls: Set<URL>
    init(_ urls: Set<URL>) {
        self.urls = Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        Self.lock.withLock { for url in self.urls { Self.counts[url, default: 0] += 1 } }
    }
    deinit {
        Self.lock.withLock {
            for url in urls {
                let count = (Self.counts[url] ?? 1) - 1
                if count == 0 { Self.counts.removeValue(forKey: url) } else { Self.counts[url] = count }
            }
        }
    }
    static var activeURLs: Set<URL> { lock.withLock { Set(counts.keys) } }
}
nonisolated(unsafe) private var cacheLeaseKey: UInt8 = 0
@MainActor func retainCacheLease(_ lease: CacheLease, on item: AVPlayerItem) {
    objc_setAssociatedObject(item, &cacheLeaseKey, lease, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
