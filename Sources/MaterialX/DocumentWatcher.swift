import Foundation

/// Reloads a `.mtlx` file when it or a file it includes changes.
///
/// Polls modification dates, which also catches editors that save by replacing the file. Files that fail to parse
/// are reported and skipped; the next good save is yielded.
public struct DocumentWatcher: Sendable {
    public enum Event: Sendable {
        case loaded(MaterialXDocument)
        case failed(String)
    }

    public var url: URL
    public var interval: Duration

    public init(url: URL, interval: Duration = .milliseconds(250)) {
        self.url = url
        self.interval = interval
    }

    /// The document now, then again after each change. Ends when the consuming task is cancelled.
    public func events() -> AsyncStream<Event> {
        let url = url
        let interval = interval
        return AsyncStream { continuation in
            let task = Task {
                var stamps: [URL: Date] = [:]
                while !Task.isCancelled {
                    let current = Self.stamps(for: url)
                    if current != stamps {
                        stamps = current
                        do {
                            continuation.yield(.loaded(try MaterialXDocument(url: url)))
                        } catch {
                            continuation.yield(.failed("\(error)"))
                        }
                    }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Modification dates of `url` and the files it includes, found by reading `xi:include` hrefs.
    static func stamps(for url: URL) -> [URL: Date] {
        var stamps: [URL: Date] = [:]
        var pending = [url.standardizedFileURL]
        while let next = pending.popLast() {
            guard stamps[next] == nil else { continue }
            stamps[next] = (try? FileManager.default.attributesOfItem(atPath: next.path)[.modificationDate] as? Date) ?? .distantPast
            if let data = try? Data(contentsOf: next), let root = try? MaterialXElement.parse(data) {
                for include in root.children(tag: "xi:include") {
                    if let href = include["href"] {
                        pending.append(URL(fileURLWithPath: href, relativeTo: next.deletingLastPathComponent()).standardizedFileURL)
                    }
                }
            }
        }
        return stamps
    }
}
