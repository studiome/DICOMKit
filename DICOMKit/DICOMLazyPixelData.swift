import Foundation

/// Defers Pixel Data frame decoding until it is explicitly requested.
///
/// Obtain an instance from ``DICOMFile/makeLazyPixelData()`` and retain it for
/// as long as its decoded frames are needed. The first call to
/// ``loadFrames()`` performs decoding; later calls return the cached result.
/// Parsing a `DICOMFile` still validates and retains its encoded dataset, so
/// this API defers decoder work rather than providing streaming file I/O.
public final class DICOMLazyPixelData: @unchecked Sendable {
    private enum State {
        case unloaded
        case loaded([DICOMPixelData]?)
    }

    private let loader: @Sendable () -> [DICOMPixelData]?
    private let lock = NSLock()
    private var state: State = .unloaded

    init(loader: @escaping @Sendable () -> [DICOMPixelData]?) {
        self.loader = loader
    }

    /// Whether decoding has already been attempted.
    public var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .loaded = state { return true }
        return false
    }

    /// Decodes all frames once, then returns the cached result.
    public func loadFrames() -> [DICOMPixelData]? {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .loaded(let frames):
            return frames
        case .unloaded:
            let frames = loader()
            state = .loaded(frames)
            return frames
        }
    }

    /// Decodes frames if necessary and returns the first decoded frame.
    public func loadFirstFrame() -> DICOMPixelData? {
        loadFrames()?.first
    }
}
