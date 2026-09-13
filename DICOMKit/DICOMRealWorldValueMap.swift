import Foundation

/// One item of the Real World Value Mapping Sequence `(0040,9096)`
/// (PS3.3 C.7.6.16.2.11): converts a stored pixel value to a value in a real
/// physical unit — for example, converting a PET stored value to a
/// Standardized Uptake Value (SUV).
///
/// This is a separate transform from the Modality LUT (``DICOMModalityLUT``):
/// the Modality LUT (or Rescale Slope/Intercept) produces a value in a
/// modality unit that feeds VOI windowing for *display*, while a Real World
/// Value Map produces a value a caller *reports* — an SUV, a temperature,
/// a concentration. A caller using this does not window the result.
public struct DICOMRealWorldValueMap: Sendable, Equatable {
    /// Real World Value First Value Mapped `(0040,9216)`.
    public let firstValueMapped: Int
    /// Real World Value Last Value Mapped `(0040,9211)`.
    public let lastValueMapped: Int
    /// Real World Value Slope `(0040,9225)`. Mutually exclusive with
    /// ``lutData``; used with ``intercept``.
    public let slope: Double?
    /// Real World Value Intercept `(0040,9224)`.
    public let intercept: Double?
    /// Real World Value LUT Data `(0040,9212)`. Mutually exclusive with
    /// ``slope``/``intercept``.
    public let lutData: [Double]?
    /// LUT Label `(0040,9210)`.
    public let label: String?
    /// LUT Explanation `(0028,3003)`.
    public let explanation: String?
    /// Measurement Units Code Sequence `(0040,08EA)`.
    public let measurementUnits: DICOMCodeSequenceItem?

    public init(
        firstValueMapped: Int,
        lastValueMapped: Int,
        slope: Double? = nil,
        intercept: Double? = nil,
        lutData: [Double]? = nil,
        label: String? = nil,
        explanation: String? = nil,
        measurementUnits: DICOMCodeSequenceItem? = nil
    ) {
        self.firstValueMapped = firstValueMapped
        self.lastValueMapped = lastValueMapped
        self.slope = slope
        self.intercept = intercept
        self.lutData = lutData
        self.label = label
        self.explanation = explanation
        self.measurementUnits = measurementUnits
    }

    /// Converts a stored pixel value to its real-world value.
    ///
    /// `nil` when `storedValue` falls outside
    /// `firstValueMapped...lastValueMapped`. Otherwise, when ``lutData`` is
    /// present, the entry at `storedValue - firstValueMapped`; otherwise
    /// `Double(storedValue) * slope + intercept`.
    public func value(for storedValue: Int) -> Double? {
        guard storedValue >= firstValueMapped, storedValue <= lastValueMapped else { return nil }
        if let lutData {
            let offset = storedValue - firstValueMapped
            guard lutData.indices.contains(offset) else { return nil }
            return lutData[offset]
        }
        guard let slope, let intercept else { return nil }
        return Double(storedValue) * slope + intercept
    }
}

extension DICOMDataset {
    /// Parses the Real World Value Mapping Sequence `(0040,9096)` found in
    /// `self`.
    ///
    /// - Parameter isSigned: Whether First/Last Value Mapped should be read
    ///   as `SS` rather than `US`. This depends on the *enclosing dataset's*
    ///   Pixel Representation `(0028,0103)` — the same US/SS rule
    ///   `DICOMFile`'s Modality LUT parsing uses — never on anything the
    ///   mapping item itself carries, so callers parsing a nested functional
    ///   group item must still pass the top-level dataset's answer.
    /// - Parameter parentCharacterSet: The character set LUT Explanation and
    ///   the nested Measurement Units code triplet inherit when this item
    ///   (or the code item) declares none of its own.
    func realWorldValueMaps(isSigned: Bool, characterSet parentCharacterSet: DICOMCharacterSet) -> [DICOMRealWorldValueMap] {
        guard let items = self[DICOMTag(group: 0x0040, element: 0x9096)]?.sequenceItems else { return [] }
        return items.compactMap { item -> DICOMRealWorldValueMap? in
            let firstElement = item[DICOMTag(group: 0x0040, element: 0x9216)]
            let lastElement = item[DICOMTag(group: 0x0040, element: 0x9211)]
            let first: Int?
            let last: Int?
            if isSigned {
                first = firstElement?.int16Value.map(Int.init)
                last = lastElement?.int16Value.map(Int.init)
            } else {
                first = firstElement?.uint16Value.map(Int.init)
                last = lastElement?.uint16Value.map(Int.init)
            }
            guard let first, let last else { return nil }
            let itemCharacterSet = item.characterSet(inheriting: parentCharacterSet)
            let measurementUnitsItem = item[DICOMTag(group: 0x0040, element: 0x08EA)]?.sequenceItems?.first
            return DICOMRealWorldValueMap(
                firstValueMapped: first,
                lastValueMapped: last,
                slope: item[DICOMTag(group: 0x0040, element: 0x9225)]?.float64Values?.first,
                intercept: item[DICOMTag(group: 0x0040, element: 0x9224)]?.float64Values?.first,
                lutData: item[DICOMTag(group: 0x0040, element: 0x9212)]?.float64Values,
                label: item[DICOMTag(group: 0x0040, element: 0x9210)]?.stringValue,
                explanation: item.stringValue(for: .lutExplanation, inheriting: itemCharacterSet),
                measurementUnits: measurementUnitsItem?.codeSequenceItem(inheriting: itemCharacterSet)
            )
        }
    }
}
