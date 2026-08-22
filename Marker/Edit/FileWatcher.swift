import Foundation

/// Watches one file for changes made outside the app.
///
/// A `DispatchSource` on an open descriptor rather than `NSFilePresenter`. The app
/// is not sandboxed and has no `NSDocument`-coordinated stack to join, so the
/// presenter machinery would be ceremony around a thing the kernel already tells
/// us directly.
/// Nonisolated: this is plumbing around a kernel event source, and the document
/// that owns it is nonisolated too. Events are delivered on the main queue, so the
/// callback bridges back to the main actor at the point it reaches view code.
nonisolated final class FileWatcher {

    enum Change: Sendable, Equatable {
        /// The contents changed on disk.
        case modified
        /// The file was deleted, or renamed out from under us. Editors that write by
        /// rename, which is most of them, produce this rather than `.modified`.
        case vanished
    }

    private let url: URL
    private let onChange: @Sendable (Change) -> Void

    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var suppressUntil: Date?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping @Sendable (Change) -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        // Cancelling the source is what closes the descriptor, and deinit is
        // nonisolated, so the teardown is done inline rather than through the
        // MainActor-isolated stop().
        pending?.cancel()
        source?.cancel()
    }

    // MARK: Lifecycle

    private func start() {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                self.coalesce(.vanished)
            } else {
                self.coalesce(.modified)
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    private func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Re-arms after a rename. Most editors write by writing a temporary file and
    /// renaming it over the original, which invalidates the descriptor, so a watcher
    /// that does not re-open sees the first external save and then goes deaf.
    func rearm() {
        stop()
        start()
    }

    // MARK: Filtering

    /// Silences the watcher around our own write, so saving does not look like an
    /// external change and prompt the user about their own edit.
    func suppress(for interval: TimeInterval = 1.0) {
        suppressUntil = Date().addingTimeInterval(interval)
    }

    /// A single save can produce several events. Coalescing means one prompt.
    private func coalesce(_ change: Change) {
        if let until = suppressUntil, Date() < until { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange(change)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
