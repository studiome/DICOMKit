import Foundation
import Testing
@testable import DICOMKit

/// The Cine module (PS3.3 C.7.6.5), which gives multi-frame Pixel Data a
/// playback timebase.
struct DICOMCineAttributesTests {
    @Test func frameRateDerivesFromFrameTimeWhenNoOtherRateIsPresent() {
        let attributes = DICOMCineAttributes(frameTime: 40)

        #expect(attributes.frameRate == 25) // 1000 / 40 ms
        #expect(attributes.frameDuration(at: 0) == 40)
        #expect(attributes.frameDuration(at: 9) == 40)
    }

    @Test func recommendedDisplayFrameRateWinsOverCineRateWinsOverFrameTime() {
        #expect(DICOMCineAttributes(frameTime: 40, cineRate: 10, recommendedDisplayFrameRate: 30).frameRate == 30)
        #expect(DICOMCineAttributes(frameTime: 40, cineRate: 10).frameRate == 10)
        #expect(DICOMCineAttributes(frameTime: 40).frameRate == 25)
    }

    @Test func frameTimeVectorReturnsPerIndexDurationsAndFallsBackPastItsEnd() {
        let attributes = DICOMCineAttributes(frameTime: 50, frameTimeVector: [0, 33.3, 33.3])

        #expect(attributes.frameDuration(at: 0) == 0)
        #expect(attributes.frameDuration(at: 1) == 33.3)
        #expect(attributes.frameDuration(at: 2) == 33.3)
        #expect(attributes.frameDuration(at: 3) == 50) // falls back to frameTime past the vector's end
    }

    @Test func frameTimeOfZeroDoesNotProduceInfiniteOrNaNFrameRate() {
        let attributes = DICOMCineAttributes(frameTime: 0)

        #expect(attributes.frameRate == nil)
    }

    @Test func absentAttributesProduceNilFrameRateAndFrameDuration() {
        let attributes = DICOMCineAttributes()

        #expect(attributes.frameRate == nil)
        #expect(attributes.frameDuration(at: 0) == nil)
    }

    // MARK: - Dataset parsing

    @Test func frameTimeOnlyDatasetExposesCineAttributesAndDerivedFrameRate() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1063), vr: .DS, value: Data("40".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.cineAttributes?.frameTime == 40)
        #expect(file.cineAttributes?.frameRate == 25)
    }

    @Test func datasetPriorityOrderMatchesRecommendedThenCineThenFrameTime() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1063), vr: .DS, value: Data("40".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x0040), vr: .IS, value: Data("10".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x2144), vr: .IS, value: Data("30".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.cineAttributes?.frameRate == 30)
    }

    @Test func datasetFrameTimeVectorParsesBackslashSeparatedMillisecondIncrements() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1065), vr: .DS, value: Data("0\\33.3\\33.3".utf8))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.cineAttributes?.frameTimeVector == [0, 33.3, 33.3])
        #expect(file.cineAttributes?.frameDuration(at: 1) == 33.3)
        #expect(file.cineAttributes?.frameDuration(at: 5) == nil) // past the vector, no frameTime to fall back to
    }

    @Test func datasetParsesTrimAndPlaybackAttributes() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x2142), vr: .IS, value: Data("1".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0008, element: 0x2143), vr: .IS, value: Data("20".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1242), vr: .IS, value: Data("40".utf8)),
            DICOMElement(tag: DICOMTag(group: 0x0018, element: 0x1244), vr: .US, value: uint16(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.cineAttributes?.startTrim == 1)
        #expect(file.cineAttributes?.stopTrim == 20)
        #expect(file.cineAttributes?.actualFrameDuration == 40)
        #expect(file.cineAttributes?.preferredPlaybackSequencing == 1)
    }

    @Test func datasetWithNoCineAttributesYieldsNil() throws {
        let dataset = DICOMDataset(elements: [
            DICOMElement(tag: .rows, vr: .US, value: uint16(1))
        ])
        let file = try DICOMFile(data: DICOMWriter.write(dataset: dataset))

        #expect(file.cineAttributes == nil)
    }
}
