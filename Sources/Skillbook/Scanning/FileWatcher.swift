import CoreServices
import Foundation

/// Thin FSEvents wrapper. Calls back on the main queue with the changed paths.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let excluded: [String]
    private let handler: ([String]) -> Void

    init(paths: [String], excluding excluded: [String], handler: @escaping ([String]) -> Void) {
        self.paths = paths
        self.excluded = excluded
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(eventPaths, to: NSArray.self)
            let changed = (0..<count).compactMap { array[$0] as? String }
            watcher.handler(changed)
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return }
        if !excluded.isEmpty {
            FSEventStreamSetExclusionPaths(s, Array(excluded.prefix(8)) as CFArray)
        }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }
}
