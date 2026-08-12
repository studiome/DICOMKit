import Foundation

/// Annotation Units values shared by the Graphic and Text Object modules.
public enum DICOMAnnotationUnits: String, Sendable, Equatable {
    case pixel = "PIXEL"
    case display = "DISPLAY"
    case matrix = "MATRIX"
}

/// Graphic Type values (PS3.3 C.10.5) naming how a graphic object's points
/// are drawn.
public enum DICOMGraphicType: String, Sendable, Equatable {
    case point = "POINT"
    case polyline = "POLYLINE"
    case interpolated = "INTERPOLATED"
    case circle = "CIRCLE"
    case ellipse = "ELLIPSE"
}

/// One item of a Referenced Series/Image Sequence: an image (or one of its
/// frames) a presentation state applies to.
public struct DICOMPresentationStateReference: Sendable, Equatable {
    public let seriesInstanceUID: String?
    public let sopClassUID: String?
    public let sopInstanceUID: String
    /// Referenced Frame Number `(0008,1160)`. `nil` means every frame.
    public let frameNumbers: [Int]?

    public init(seriesInstanceUID: String? = nil, sopClassUID: String? = nil, sopInstanceUID: String, frameNumbers: [Int]? = nil) {
        self.seriesInstanceUID = seriesInstanceUID
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.frameNumbers = frameNumbers
    }
}

/// One item of Softcopy VOI LUT Sequence `(0028,3110)`: the window presets
/// and/or VOI LUTs to use for a set of referenced images.
public struct DICOMSoftcopyVOI: Sendable, Equatable {
    /// The images this item applies to. Empty means it applies to every
    /// image the presentation state references.
    public let referencedSOPInstanceUIDs: [String]
    public let windowPresets: [DICOMWindowPreset]
    public let voiLUTs: [DICOMVOILUT]

    public init(referencedSOPInstanceUIDs: [String] = [], windowPresets: [DICOMWindowPreset] = [], voiLUTs: [DICOMVOILUT] = []) {
        self.referencedSOPInstanceUIDs = referencedSOPInstanceUIDs
        self.windowPresets = windowPresets
        self.voiLUTs = voiLUTs
    }
}

/// One item of Displayed Area Selection Sequence `(0070,005A)`: the region
/// of an image to display and how to scale it.
public struct DICOMDisplayedArea: Sendable, Equatable {
    /// The images this item applies to. Empty means it applies to every
    /// image the presentation state references.
    public let referencedSOPInstanceUIDs: [String]
    public let topLeftColumn: Int?
    public let topLeftRow: Int?
    public let bottomRightColumn: Int?
    public let bottomRightRow: Int?
    public let presentationSizeMode: String?
    public let presentationPixelSpacing: [Double]?
    public let presentationPixelAspectRatio: [Int]?
    public let presentationPixelMagnificationRatio: Double?

    public init(
        referencedSOPInstanceUIDs: [String] = [],
        topLeftColumn: Int? = nil,
        topLeftRow: Int? = nil,
        bottomRightColumn: Int? = nil,
        bottomRightRow: Int? = nil,
        presentationSizeMode: String? = nil,
        presentationPixelSpacing: [Double]? = nil,
        presentationPixelAspectRatio: [Int]? = nil,
        presentationPixelMagnificationRatio: Double? = nil
    ) {
        self.referencedSOPInstanceUIDs = referencedSOPInstanceUIDs
        self.topLeftColumn = topLeftColumn
        self.topLeftRow = topLeftRow
        self.bottomRightColumn = bottomRightColumn
        self.bottomRightRow = bottomRightRow
        self.presentationSizeMode = presentationSizeMode
        self.presentationPixelSpacing = presentationPixelSpacing
        self.presentationPixelAspectRatio = presentationPixelAspectRatio
        self.presentationPixelMagnificationRatio = presentationPixelMagnificationRatio
    }
}

/// One item of Graphic Layer Sequence `(0070,0060)`.
public struct DICOMGraphicLayer: Sendable, Equatable {
    public let name: String
    public let order: Int
    public let recommendedDisplayGrayscaleValue: UInt16?
    public let description: String?

    public init(name: String, order: Int, recommendedDisplayGrayscaleValue: UInt16? = nil, description: String? = nil) {
        self.name = name
        self.order = order
        self.recommendedDisplayGrayscaleValue = recommendedDisplayGrayscaleValue
        self.description = description
    }
}

/// One item of Text Object Sequence `(0070,0008)`.
public struct DICOMTextObject: Sendable, Equatable {
    public let text: String
    public let boundingBoxTopLeft: [Double]?
    public let boundingBoxBottomRight: [Double]?
    public let anchorPoint: [Double]?
    public let boundingBoxUnits: DICOMAnnotationUnits?
    public let anchorPointUnits: DICOMAnnotationUnits?
    public let anchorPointVisible: Bool

    public init(
        text: String,
        boundingBoxTopLeft: [Double]? = nil,
        boundingBoxBottomRight: [Double]? = nil,
        anchorPoint: [Double]? = nil,
        boundingBoxUnits: DICOMAnnotationUnits? = nil,
        anchorPointUnits: DICOMAnnotationUnits? = nil,
        anchorPointVisible: Bool = false
    ) {
        self.text = text
        self.boundingBoxTopLeft = boundingBoxTopLeft
        self.boundingBoxBottomRight = boundingBoxBottomRight
        self.anchorPoint = anchorPoint
        self.boundingBoxUnits = boundingBoxUnits
        self.anchorPointUnits = anchorPointUnits
        self.anchorPointVisible = anchorPointVisible
    }
}

/// One item of Graphic Object Sequence `(0070,0009)`.
public struct DICOMGraphicObject: Sendable, Equatable {
    public let units: DICOMAnnotationUnits?
    public let dimensions: Int
    public let pointCount: Int
    public let points: [Double]
    public let type: DICOMGraphicType
    public let filled: Bool

    public init(units: DICOMAnnotationUnits? = nil, dimensions: Int, pointCount: Int, points: [Double], type: DICOMGraphicType, filled: Bool = false) {
        self.units = units
        self.dimensions = dimensions
        self.pointCount = pointCount
        self.points = points
        self.type = type
        self.filled = filled
    }
}

/// One item of Graphic Annotation Sequence `(0070,0001)`.
public struct DICOMGraphicAnnotation: Sendable, Equatable {
    public let layer: String?
    /// The images this item applies to. Empty means it applies to every
    /// image the presentation state references.
    public let referencedSOPInstanceUIDs: [String]
    public let textObjects: [DICOMTextObject]
    public let graphicObjects: [DICOMGraphicObject]

    public init(layer: String? = nil, referencedSOPInstanceUIDs: [String] = [], textObjects: [DICOMTextObject] = [], graphicObjects: [DICOMGraphicObject] = []) {
        self.layer = layer
        self.referencedSOPInstanceUIDs = referencedSOPInstanceUIDs
        self.textObjects = textObjects
        self.graphicObjects = graphicObjects
    }
}

/// A Grayscale Softcopy Presentation State (PS3.3 A.33.2, SOP Class
/// `1.2.840.10008.5.1.4.1.1.11.1`): how the sender intends a set of
/// referenced images to be displayed, independently of the images
/// themselves.
public struct DICOMPresentationState: Sendable, Equatable {
    public let sopInstanceUID: String?
    public let contentLabel: String?
    public let contentDescription: String?
    public let referencedImages: [DICOMPresentationStateReference]
    /// Image Rotation `(0070,0042)`, in degrees clockwise: `0`, `90`, `180`,
    /// or `270`.
    ///
    /// DICOMKit does not bake ``rotation`` or ``horizontalFlip`` into
    /// rendered pixels. Apply them as a display transform instead — for
    /// example as a `CGAffineTransform` — because rotating the pixel buffer
    /// itself would swap rows and columns and invalidate the pixel-spacing
    /// metadata alongside it.
    public let rotation: Int
    /// Image Horizontal Flip `(0070,0041)`. See ``rotation`` for why this
    /// isn't applied to pixel data directly.
    public let horizontalFlip: Bool
    public let presentationLUTShape: DICOMPresentationLUTShape?
    public let displayShutter: DICOMDisplayShutter?
    public let softcopyVOI: [DICOMSoftcopyVOI]
    public let displayedAreas: [DICOMDisplayedArea]
    public let graphicLayers: [DICOMGraphicLayer]
    public let graphicAnnotations: [DICOMGraphicAnnotation]

    public init(
        sopInstanceUID: String? = nil,
        contentLabel: String? = nil,
        contentDescription: String? = nil,
        referencedImages: [DICOMPresentationStateReference] = [],
        rotation: Int = 0,
        horizontalFlip: Bool = false,
        presentationLUTShape: DICOMPresentationLUTShape? = nil,
        displayShutter: DICOMDisplayShutter? = nil,
        softcopyVOI: [DICOMSoftcopyVOI] = [],
        displayedAreas: [DICOMDisplayedArea] = [],
        graphicLayers: [DICOMGraphicLayer] = [],
        graphicAnnotations: [DICOMGraphicAnnotation] = []
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.contentLabel = contentLabel
        self.contentDescription = contentDescription
        self.referencedImages = referencedImages
        self.rotation = rotation
        self.horizontalFlip = horizontalFlip
        self.presentationLUTShape = presentationLUTShape
        self.displayShutter = displayShutter
        self.softcopyVOI = softcopyVOI
        self.displayedAreas = displayedAreas
        self.graphicLayers = graphicLayers
        self.graphicAnnotations = graphicAnnotations
    }

    /// Parses a Grayscale Softcopy Presentation State from a file's dataset.
    ///
    /// - Throws: ``DICOMError/invalidPresentationState`` when SOP Class UID
    ///   `(0008,0016)` is present but isn't
    ///   ``DICOMSOPClass/grayscaleSoftcopyPresentationStateStorage``. A
    ///   dataset with no SOP Class UID at all still parses, so hand-built
    ///   fixtures that omit File Meta Information stay convenient.
    public init(file: DICOMFile) throws {
        let dataset = file.dataset
        if let sopClassUID = dataset[.sopClassUID]?.stringValue,
           sopClassUID != DICOMSOPClass.grayscaleSoftcopyPresentationStateStorage {
            throw DICOMError.invalidPresentationState
        }

        sopInstanceUID = dataset[.sopInstanceUID]?.stringValue
        contentLabel = dataset[DICOMTag(group: 0x0070, element: 0x0080)]?.stringValue
        contentDescription = dataset[DICOMTag(group: 0x0070, element: 0x0081)]?.stringValue

        var references: [DICOMPresentationStateReference] = []
        for seriesItem in dataset[DICOMTag(group: 0x0008, element: 0x1115)]?.sequenceItems ?? [] {
            let seriesInstanceUID = seriesItem[.seriesInstanceUID]?.stringValue
            for imageItem in seriesItem[DICOMTag(group: 0x0008, element: 0x1140)]?.sequenceItems ?? [] {
                guard let sopInstanceUID = imageItem[.referencedSOPInstanceUID]?.stringValue else { continue }
                references.append(DICOMPresentationStateReference(
                    seriesInstanceUID: seriesInstanceUID,
                    sopClassUID: imageItem[.referencedSOPClassUID]?.stringValue,
                    sopInstanceUID: sopInstanceUID,
                    frameNumbers: imageItem[DICOMTag(group: 0x0008, element: 0x1160)]?.stringValues?.compactMap(Int.init)
                ))
            }
        }
        referencedImages = references

        switch dataset[DICOMTag(group: 0x0070, element: 0x0042)]?.uint16Value {
        case 90: rotation = 90
        case 180: rotation = 180
        case 270: rotation = 270
        default: rotation = 0
        }
        horizontalFlip = dataset[DICOMTag(group: 0x0070, element: 0x0041)]?.stringValue?.uppercased() == "Y"

        presentationLUTShape = dataset.presentationLUTShape
        displayShutter = dataset.displayShutter

        softcopyVOI = (dataset[DICOMTag(group: 0x0028, element: 0x3110)]?.sequenceItems ?? []).map { item in
            DICOMSoftcopyVOI(
                referencedSOPInstanceUIDs: Self.referencedSOPInstanceUIDs(in: item),
                windowPresets: item.makeWindowPresets(),
                voiLUTs: item.makeVOILUTs()
            )
        }

        displayedAreas = (dataset[DICOMTag(group: 0x0070, element: 0x005A)]?.sequenceItems ?? []).map { item in
            // (0070,0052)/(0070,0053) are `SL` with column, row order — the
            // opposite of the shutter module's row, column order, which is
            // why the four values are named individually here.
            let topLeft = item[DICOMTag(group: 0x0070, element: 0x0052)]?.int32Values
            let bottomRight = item[DICOMTag(group: 0x0070, element: 0x0053)]?.int32Values
            let aspectRatioStrings = item[DICOMTag(group: 0x0070, element: 0x0102)]?.stringValues
            let aspectRatio = aspectRatioStrings.flatMap { strings -> [Int]? in
                let parsed = strings.compactMap(Int.init)
                return parsed.count == strings.count ? parsed : nil
            }
            return DICOMDisplayedArea(
                referencedSOPInstanceUIDs: Self.referencedSOPInstanceUIDs(in: item),
                topLeftColumn: topLeft?.count == 2 ? Int(topLeft![0]) : nil,
                topLeftRow: topLeft?.count == 2 ? Int(topLeft![1]) : nil,
                bottomRightColumn: bottomRight?.count == 2 ? Int(bottomRight![0]) : nil,
                bottomRightRow: bottomRight?.count == 2 ? Int(bottomRight![1]) : nil,
                presentationSizeMode: item[DICOMTag(group: 0x0070, element: 0x0100)]?.stringValue,
                presentationPixelSpacing: item[DICOMTag(group: 0x0070, element: 0x0101)]?.doubleValues,
                presentationPixelAspectRatio: aspectRatio,
                presentationPixelMagnificationRatio: item[DICOMTag(group: 0x0070, element: 0x0103)]?.float32Values?.first.map(Double.init)
            )
        }

        graphicLayers = (dataset[DICOMTag(group: 0x0070, element: 0x0060)]?.sequenceItems ?? []).compactMap { item in
            guard let name = item[DICOMTag(group: 0x0070, element: 0x0002)]?.stringValue,
                  let order = item[DICOMTag(group: 0x0070, element: 0x0062)]?.stringValue.flatMap(Int.init) else { return nil }
            return DICOMGraphicLayer(
                name: name,
                order: order,
                recommendedDisplayGrayscaleValue: item[DICOMTag(group: 0x0070, element: 0x0066)]?.uint16Value,
                description: item[DICOMTag(group: 0x0070, element: 0x0068)]?.stringValue
            )
        }

        graphicAnnotations = (dataset[DICOMTag(group: 0x0070, element: 0x0001)]?.sequenceItems ?? []).map { item in
            DICOMGraphicAnnotation(
                layer: item[DICOMTag(group: 0x0070, element: 0x0002)]?.stringValue,
                referencedSOPInstanceUIDs: Self.referencedSOPInstanceUIDs(in: item),
                textObjects: (item[DICOMTag(group: 0x0070, element: 0x0008)]?.sequenceItems ?? []).compactMap { textItem in
                    guard let text = textItem[DICOMTag(group: 0x0070, element: 0x0006)]?.stringValue else { return nil }
                    return DICOMTextObject(
                        text: text,
                        boundingBoxTopLeft: textItem[DICOMTag(group: 0x0070, element: 0x0010)]?.float32Values?.map(Double.init),
                        boundingBoxBottomRight: textItem[DICOMTag(group: 0x0070, element: 0x0011)]?.float32Values?.map(Double.init),
                        anchorPoint: textItem[DICOMTag(group: 0x0070, element: 0x0014)]?.float32Values?.map(Double.init),
                        boundingBoxUnits: textItem[DICOMTag(group: 0x0070, element: 0x0003)]?.stringValue.flatMap(DICOMAnnotationUnits.init(rawValue:)),
                        anchorPointUnits: textItem[DICOMTag(group: 0x0070, element: 0x0004)]?.stringValue.flatMap(DICOMAnnotationUnits.init(rawValue:)),
                        anchorPointVisible: textItem[DICOMTag(group: 0x0070, element: 0x0015)]?.stringValue?.uppercased() == "Y"
                    )
                },
                graphicObjects: (item[DICOMTag(group: 0x0070, element: 0x0009)]?.sequenceItems ?? []).compactMap { graphicItem in
                    guard let dimensions = graphicItem[DICOMTag(group: 0x0070, element: 0x0020)]?.uint16Value,
                          let pointCount = graphicItem[DICOMTag(group: 0x0070, element: 0x0021)]?.uint16Value,
                          let points = graphicItem[DICOMTag(group: 0x0070, element: 0x0022)]?.float32Values?.map(Double.init),
                          let type = graphicItem[DICOMTag(group: 0x0070, element: 0x0023)]?.stringValue.flatMap(DICOMGraphicType.init(rawValue:)) else { return nil }
                    return DICOMGraphicObject(
                        units: graphicItem[DICOMTag(group: 0x0070, element: 0x0005)]?.stringValue.flatMap(DICOMAnnotationUnits.init(rawValue:)),
                        dimensions: Int(dimensions),
                        pointCount: Int(pointCount),
                        points: points,
                        type: type,
                        filled: graphicItem[DICOMTag(group: 0x0070, element: 0x0024)]?.stringValue?.uppercased() == "Y"
                    )
                }
            )
        }
    }

    /// Referenced SOP Instance UIDs from a Referenced Image Sequence
    /// `(0008,1140)` nested in `item`. Shared by every module (Softcopy VOI,
    /// Displayed Area, Graphic Annotation) that scopes itself to a subset of
    /// referenced images.
    private static func referencedSOPInstanceUIDs(in item: DICOMDataset) -> [String] {
        (item[DICOMTag(group: 0x0008, element: 0x1140)]?.sequenceItems ?? []).compactMap { $0[.referencedSOPInstanceUID]?.stringValue }
    }

    /// Whether this presentation state references the given image.
    public func appliesTo(sopInstanceUID: String) -> Bool {
        referencedImages.contains { $0.sopInstanceUID == sopInstanceUID }
    }

    /// The Softcopy VOI item for `sopInstanceUID`.
    ///
    /// An item whose ``DICOMSoftcopyVOI/referencedSOPInstanceUIDs`` is empty
    /// applies to every referenced image, so this prefers an item that names
    /// `sopInstanceUID` explicitly and falls back to the first item that
    /// names nothing.
    public func softcopyVOI(for sopInstanceUID: String) -> DICOMSoftcopyVOI? {
        Self.select(from: softcopyVOI, referencedSOPInstanceUIDs: \.referencedSOPInstanceUIDs, matching: sopInstanceUID)
    }

    /// The Displayed Area item for `sopInstanceUID`.
    ///
    /// An item whose ``DICOMDisplayedArea/referencedSOPInstanceUIDs`` is
    /// empty applies to every referenced image, so this prefers an item that
    /// names `sopInstanceUID` explicitly and falls back to the first item
    /// that names nothing.
    public func displayedArea(for sopInstanceUID: String) -> DICOMDisplayedArea? {
        Self.select(from: displayedAreas, referencedSOPInstanceUIDs: \.referencedSOPInstanceUIDs, matching: sopInstanceUID)
    }

    /// Every Graphic Annotation item that applies to `sopInstanceUID`:
    /// items that name it explicitly, plus items whose
    /// ``DICOMGraphicAnnotation/referencedSOPInstanceUIDs`` is empty and so
    /// apply to every referenced image.
    public func graphicAnnotations(for sopInstanceUID: String) -> [DICOMGraphicAnnotation] {
        graphicAnnotations.filter { $0.referencedSOPInstanceUIDs.isEmpty || $0.referencedSOPInstanceUIDs.contains(sopInstanceUID) }
    }

    private static func select<T>(from items: [T], referencedSOPInstanceUIDs: (T) -> [String], matching sopInstanceUID: String) -> T? {
        items.first { referencedSOPInstanceUIDs($0).contains(sopInstanceUID) }
            ?? items.first { referencedSOPInstanceUIDs($0).isEmpty }
    }
}
