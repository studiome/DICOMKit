import CoreGraphics
import Foundation
import Testing

/// The rendered bytes backing a `CGImage`, for comparison against the exact
/// grayscale or RGB values a test expects.
func imageBytes(_ image: CGImage) throws -> Data {
    Data(try #require(image.dataProvider?.data) as Data)
}
