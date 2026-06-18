import Foundation
import ImageIO

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// F-15: explicitly strip EXIF/GPS/IPTC metadata from image data before upload.
/// Photos taken at home (pet/walk photos) can embed GPS coordinates; the old code
/// relied on an incidental re-encode side effect rather than removing metadata
/// intentionally. This re-encodes the image with the sensitive dictionaries removed.
public enum ImageMetadata {
    /// Returns image data with GPS/EXIF/IPTC metadata removed. If the data cannot be
    /// parsed as an image it is returned unchanged (never throws / never loses the image).
    public static func stripped(from data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source) else { return data }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, uti, 1, nil) else {
            return data
        }

        // Setting a metadata dictionary to kCFNull removes it from the output.
        let stripOptions: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyExifDictionary: kCFNull as Any,
            kCGImagePropertyIPTCDictionary: kCFNull as Any
        ]

        CGImageDestinationAddImageFromSource(destination, source, 0, stripOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }
}
