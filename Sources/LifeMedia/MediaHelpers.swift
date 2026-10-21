import Foundation
import CryptoKit
import Darwin
import LifeCore

public enum HelperError: LocalizedError {
    case unavailable, localFilesOnly, failed(String), invalidProbe
    public var errorDescription: String? {
        switch self {
        case .unavailable: "This format needs the bundled media helpers."
        case .localFilesOnly: "Choose a local media file. Network media is unsupported."
        case .failed(let message): "Media conversion failed: \(message)"
        case .invalidProbe: "The file has no supported video or audio stream."
        }
    }
}

/// Only the pinned app helpers, or an explicit source-build test override, are used.
enum MediaHelpers {
    static var directory: URL? {
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL { candidates.append(resource.appendingPathComponent("Helpers")) }
        if let path = ProcessInfo.processInfo.environment["LIFE_HELPER_DIRECTORY"] { candidates.append(URL(fileURLWithPath: path)) }
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("ffmpeg").path) &&
            FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("ffprobe").path)
        }
    }
    static func prepare(_ url: URL, progress: (@MainActor @Sendable (Double) -> Void)?) async throws -> URL {
        guard url.isFileURL else { throw HelperError.localFilesOnly }
        guard let directory else { throw HelperError.unavailable }
        let probe = try await HelperProcess.run(directory.appendingPathComponent("ffprobe"), arguments: [
            "-v", "error", "-max_alloc", "268435456", "-protocol_whitelist", "file,pipe",
            "-show_format", "-show_streams", "-of", "json", url.path])
        guard let json = try JSONSerialization.jsonObject(with: probe) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else { throw HelperError.invalidProbe }
        let video = streams.contains { $0["codec_type"] as? String == "video" && (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0 }
        guard video || streams.contains(where: { $0["codec_type"] as? String == "audio" }) else { throw HelperError.invalidProbe }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Life Editor/Intermediates", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadata = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let identity = "native-v1|\(url.standardizedFileURL.path)|\(metadata.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(metadata.fileSize ?? 0)"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = root.appendingPathComponent(hash + (video ? ".mov" : ".wav"))
        let sidecar = root.appendingPathComponent(hash + ".probe.json")
        if FileManager.default.fileExists(atPath: destination.path) && FileManager.default.fileExists(atPath: sidecar.path) { return destination }
        let temporary = root.appendingPathComponent(".prepare-\(UUID())." + (video ? "mov" : "wav"))
        defer { try? FileManager.default.removeItem(at: temporary) }
        var args = ["-v", "error", "-nostdin", "-n", "-max_alloc", "268435456", "-threads", "2",
                    "-filter_threads", "2", "-filter_complex_threads", "2", "-protocol_whitelist", "file,pipe",
                    "-copyts", "-start_at_zero", "-i", url.path]
        if video {
            args += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le",
                     "-fps_mode", "passthrough", "-c:a", "pcm_s24le"]
        } else { args += ["-map", "0:a:0", "-vn", "-c:a", "pcm_f32le"] }
        args += ["-map_metadata", "0", "-threads", "2", "-progress", "pipe:1", "-nostats", temporary.path]
        let format = json["format"] as? [String: Any]
        let duration = Double(format?["duration"] as? String ?? "") ?? 0
        _ = try await HelperProcess.run(directory.appendingPathComponent("ffmpeg"), arguments: args,
            progressDuration: duration, progress: progress)
        try Task.checkCancellation()
        var inventory = json
        inventory["lifeEditorPreparation"] = ["version": 1, "originalURL": url.absoluteString,
            "videoStream": video ? "first" : "none", "audioStream": "first", "timestampPolicy": "preserve timestamps; normalize origin",
            "orientationPolicy": "FFmpeg autorotate into pixels", "variableFrameRatePolicy": "preserve timestamps; no CFR map generated"] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sidecar, options: .atomic)
        do { try FileManager.default.moveItem(at: temporary, to: destination) }
        catch { if !FileManager.default.fileExists(atPath: destination.path) { throw error } }
        return destination
    }
}

/// Drains both pipes continuously with capped memory. Cancellation has a bounded
/// grace period before killing only this direct helper process.
private final class HelperProcess: @unchecked Sendable {
    private let process = Process()
    private let stdout = Pipe(), stderr = Pipe()
    private let lock = NSLock()
    private var output = Data(), errors = Data()
    private var stopped = false
    private var terminatedAt: Date?
    private var progressTime: Double = 0
    private func append(_ data: Data, error: Bool) {
        lock.withLock {
            if error { errors.append(data); if errors.count > 65536 { errors.removeFirst(errors.count - 65536) } }
            else {
                output.append(data)
                if let text = String(data: data, encoding: .utf8) {
                    for line in text.split(separator: "\n") where line.hasPrefix("out_time_us=") {
                        if let value = Double(line.dropFirst(12)) { progressTime = max(progressTime, value / 1_000_000) }
                    }
                }
                if output.count > 1_048_576 { output.removeFirst(output.count - 1_048_576) }
            }
        }
    }
    private func cancel() {
        lock.withLock {
            stopped = true
            if process.isRunning { process.terminate(); terminatedAt = Date() }
        }
    }
    static func run(_ executable: URL, arguments: [String], progressDuration: Double = 0,
                    progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws -> Data {
        let job = HelperProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            job.process.executableURL = executable; job.process.arguments = arguments
            job.process.standardOutput = job.stdout; job.process.standardError = job.stderr
            job.stdout.fileHandleForReading.readabilityHandler = { handle in job.append(handle.availableData, error: false) }
            job.stderr.fileHandleForReading.readabilityHandler = { handle in job.append(handle.availableData, error: true) }
            defer {
                job.stdout.fileHandleForReading.readabilityHandler = nil
                job.stderr.fileHandleForReading.readabilityHandler = nil
                try? job.stdout.fileHandleForReading.close(); try? job.stderr.fileHandleForReading.close()
            }
            try job.lock.withLock {
                guard !job.stopped else { throw CancellationError() }
                try job.process.run()
            }
            var reported = -1.0
            while job.process.isRunning {
                let state = job.lock.withLock { (job.terminatedAt, job.progressTime) }
                if let date = state.0, Date().timeIntervalSince(date) > 2 { kill(job.process.processIdentifier, SIGKILL) }
                if let progress, progressDuration > 0 {
                    let fraction = min(0.99, state.1 / progressDuration)
                    if fraction - reported > 0.01 { await progress(fraction); reported = fraction }
                }
                // Cancellation must still reap the process and drain its pipes.
                if Task.isCancelled { usleep(20_000) }
                else { try? await Task.sleep(for: .milliseconds(20)) }
            }
            job.stdout.fileHandleForReading.readabilityHandler = nil
            job.stderr.fileHandleForReading.readabilityHandler = nil
            job.append(job.stdout.fileHandleForReading.readDataToEndOfFile(), error: false)
            job.append(job.stderr.fileHandleForReading.readDataToEndOfFile(), error: true)
            try Task.checkCancellation()
            guard job.process.terminationStatus == 0 else {
                throw HelperError.failed(job.lock.withLock { String(data: job.errors.suffix(4096), encoding: .utf8) ?? "Invalid media" })
            }
            if let progress { await progress(1) }
            return job.lock.withLock { job.output }
        } onCancel: { job.cancel() }
    }
}
