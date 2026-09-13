import Foundation
import Testing
@testable import DICOMKit

/// `DICOMPrivateDictionary` is a caller-supplied table of vendor-specific
/// private attribute VRs. DICOMKit intentionally ships none of its own: see
/// the type's documentation for why.
struct DICOMPrivateDictionaryTests {
    @Test func resolvesRegisteredEntry() throws {
        let dictionary = try DICOMPrivateDictionary([
            DICOMPrivateTagEntry(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01, vr: .DS, name: "Acme Value")
        ])

        #expect(dictionary.vr(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01) == .DS)
        #expect(dictionary.name(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01) == "Acme Value")
    }

    @Test func returnsNilForUnregisteredLookup() throws {
        let dictionary = try DICOMPrivateDictionary([
            DICOMPrivateTagEntry(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01, vr: .DS, name: nil)
        ])

        #expect(dictionary.vr(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x02) == nil)
        #expect(dictionary.vr(privateCreator: "OTHER", group: 0x0009, elementLowByte: 0x01) == nil)
        #expect(dictionary.vr(privateCreator: "ACME", group: 0x000B, elementLowByte: 0x01) == nil)
        #expect(dictionary.name(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01) == nil)
    }

    @Test func matchesCreatorWithTrailingWirePaddingAgainstUntrimmedRegisteredCreator() throws {
        let dictionary = try DICOMPrivateDictionary([
            DICOMPrivateTagEntry(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01, vr: .DS, name: nil)
        ])

        // Private Creator values are LO and are space- or NUL-padded to an
        // even length on the wire.
        #expect(dictionary.vr(privateCreator: "ACME ", group: 0x0009, elementLowByte: 0x01) == .DS)
        #expect(dictionary.vr(privateCreator: "ACME\0", group: 0x0009, elementLowByte: 0x01) == .DS)
    }

    @Test func matchesWhenTheRegisteredCreatorItselfCarriesTrailingPadding() throws {
        let dictionary = try DICOMPrivateDictionary([
            DICOMPrivateTagEntry(privateCreator: "ACME ", group: 0x0009, elementLowByte: 0x01, vr: .DS, name: nil)
        ])

        #expect(dictionary.vr(privateCreator: "ACME", group: 0x0009, elementLowByte: 0x01) == .DS)
    }

    @Test func rejectsEntryWithEvenGroup() {
        #expect(throws: DICOMError.invalidPrivateDictionary) {
            _ = try DICOMPrivateDictionary([
                DICOMPrivateTagEntry(privateCreator: "ACME", group: 0x0008, elementLowByte: 0x01, vr: .DS, name: nil)
            ])
        }
    }
}
