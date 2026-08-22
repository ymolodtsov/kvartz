import AppKit
import Foundation

struct QueryAttachment: Identifiable, Equatable, Sendable {
    static let maximumCount = 5
    private static let maximumPixelDimension = 2_048
    private static let maximumEncodedBytes = 8 * 1_024 * 1_024

    let id: UUID
    let name: String
    let mediaType: String
    let data: Data

    init(id: UUID = UUID(), name: String, mediaType: String, data: Data) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.data = data
    }

    var dataURL: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }

    var base64: String {
        data.base64EncodedString()
    }

    static func load(from url: URL) throws -> QueryAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard let image = NSImage(contentsOf: url) else {
            throw QueryAttachmentError.unsupportedImage
        }
        return try make(from: image, suggestedName: url.lastPathComponent)
    }

    static func make(from image: NSImage, suggestedName: String = "Pasted image") throws -> QueryAttachment {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw QueryAttachmentError.unsupportedImage
        }

        let scale = min(
            1,
            CGFloat(maximumPixelDimension) / CGFloat(max(source.width, source.height))
        )
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw QueryAttachmentError.unsupportedImage
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage() else {
            throw QueryAttachmentError.unsupportedImage
        }

        let representation = NSBitmapImageRep(cgImage: rendered)
        if let png = representation.representation(using: .png, properties: [:]),
           png.count <= maximumEncodedBytes {
            return QueryAttachment(
                name: normalizedName(suggestedName, extension: "png"),
                mediaType: "image/png",
                data: png
            )
        }
        if let jpeg = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.82]),
           jpeg.count <= maximumEncodedBytes {
            return QueryAttachment(
                name: normalizedName(suggestedName, extension: "jpg"),
                mediaType: "image/jpeg",
                data: jpeg
            )
        }
        throw QueryAttachmentError.imageTooLarge
    }

    private static func normalizedName(_ suggestedName: String, extension fileExtension: String) -> String {
        let stem = (suggestedName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(stem.isEmpty ? "Image" : stem).\(fileExtension)"
    }
}

enum QueryAttachmentError: LocalizedError {
    case unsupportedImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "Kvartz could not read that image."
        case .imageTooLarge:
            "That image is too large to attach."
        }
    }
}

final class QueryAttachmentImageCache: @unchecked Sendable {
    static let shared = QueryAttachmentImageCache()

    private let cache = NSCache<NSUUID, NSImage>()

    private init() {
        cache.countLimit = QueryAttachment.maximumCount * 4
    }

    func image(for attachment: QueryAttachment) -> NSImage? {
        let key = attachment.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: attachment.data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
