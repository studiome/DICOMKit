import Foundation

/// Cine module attributes (PS3.3 C.7.6.5) that give multi-frame Pixel Data a
/// playback timebase.
public struct DICOMCineAttributes: Sendable, Equatable {
    /// Frame Time `(0018,1063)`, in milliseconds.
    public let frameTime: Double?
    /// Frame Time Vector `(0018,1065)`, in milliseconds.
    public let frameTimeVector: [Double]?
    /// Cine Rate `(0018,0040)`, in frames per second.
    public let cineRate: Int?
    /// Recommended Display Frame Rate `(0008,2144)`, in frames per second.
    public let recommendedDisplayFrameRate: Int?
    /// Start Trim `(0008,2142)`.
    public let startTrim: Int?
    /// Stop Trim `(0008,2143)`.
    public let stopTrim: Int?
    /// Actual Frame Duration `(0018,1242)`.
    public let actualFrameDuration: Int?
    /// Preferred Playback Sequencing `(0018,1244)`.
    public let preferredPlaybackSequencing: Int?

    public init(
        frameTime: Double? = nil,
        frameTimeVector: [Double]? = nil,
        cineRate: Int? = nil,
        recommendedDisplayFrameRate: Int? = nil,
        startTrim: Int? = nil,
        stopTrim: Int? = nil,
        actualFrameDuration: Int? = nil,
        preferredPlaybackSequencing: Int? = nil
    ) {
        self.frameTime = frameTime
        self.frameTimeVector = frameTimeVector
        self.cineRate = cineRate
        self.recommendedDisplayFrameRate = recommendedDisplayFrameRate
        self.startTrim = startTrim
        self.stopTrim = stopTrim
        self.actualFrameDuration = actualFrameDuration
        self.preferredPlaybackSequencing = preferredPlaybackSequencing
    }

    /// The effective playback frame rate, in frames per second.
    ///
    /// Resolved in this priority order: ``recommendedDisplayFrameRate``,
    /// then ``cineRate``, then `1000 / frameTime` when ``frameTime`` is
    /// greater than `0`. `nil` if none of these yields a usable rate.
    public var frameRate: Double? {
        if let recommendedDisplayFrameRate { return Double(recommendedDisplayFrameRate) }
        if let cineRate { return Double(cineRate) }
        if let frameTime, frameTime > 0 { return 1_000 / frameTime }
        return nil
    }

    /// The millisecond increment preceding the frame at `index`.
    ///
    /// Per PS3.3 C.7.6.5.1.2, ``frameTimeVector`` holds one increment per
    /// frame, and its first entry is conventionally `0` since no time
    /// elapses before the first frame. Returns `frameTimeVector[index]` when
    /// the vector has that index; otherwise falls back to ``frameTime``.
    public func frameDuration(at index: Int) -> Double? {
        if let frameTimeVector, frameTimeVector.indices.contains(index) {
            return frameTimeVector[index]
        }
        return frameTime
    }
}
