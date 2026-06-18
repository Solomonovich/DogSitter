import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import SecurityKit

final class ImageHostPolicyTests: XCTestCase {
    func testAllowsCloudinaryHttps() {
        XCTAssertTrue(ImageHostPolicy.isAllowed("https://res.cloudinary.com/dns0htaph/image/upload/x.jpg"))
    }

    func testRejectsAttackerHost() {
        XCTAssertFalse(ImageHostPolicy.isAllowed("https://attacker.example/track.png?u=victim"))
    }

    func testRejectsNonHttpsAndJunk() {
        XCTAssertFalse(ImageHostPolicy.isAllowed("http://res.cloudinary.com/x.jpg")) // not https
        XCTAssertFalse(ImageHostPolicy.isAllowed("tel://+972500000000"))
        XCTAssertFalse(ImageHostPolicy.isAllowed(nil))
        XCTAssertFalse(ImageHostPolicy.isAllowed(""))
    }

    func testRejectsLookalikeHost() {
        XCTAssertFalse(ImageHostPolicy.isAllowed("https://res.cloudinary.com.evil.com/x.jpg"))
    }
}

final class ProfileFieldsTests: XCTestCase {
    func testNeverIncludesPrivilegedFields() {
        let payload = ProfileFields.updatePayload(
            name: "Dana", username: "@dana", address: "TLV", phone: "050", isSitter: true
        )
        let keys = Set(payload.keys)
        XCTAssertTrue(keys.isSubset(of: ProfileFields.editableKeys))
        for forbidden in ["role", "email", "averageRating", "totalReviews", "id"] {
            XCTAssertNil(payload[forbidden], "payload must never contain \(forbidden)")
        }
    }

    func testOwnerHasNoPhoneField() {
        let payload = ProfileFields.updatePayload(
            name: "Owen", username: "@owen", address: "Haifa", phone: "050", isSitter: false
        )
        XCTAssertNil(payload["phone"], "phone is sitter-only")
        XCTAssertEqual(payload["name"] as? String, "Owen")
    }
}

final class AuthErrorMapperTests: XCTestCase {
    func testCollapsesUserNotFoundAndWrongPassword() {
        XCTAssertEqual(
            AuthErrorMapper.classify(code: AuthErrorMapper.codeUserNotFound),
            AuthErrorMapper.classify(code: AuthErrorMapper.codeWrongPassword)
        )
        XCTAssertEqual(
            AuthErrorMapper.userFacing(code: AuthErrorMapper.codeUserNotFound),
            AuthErrorMapper.userFacing(code: AuthErrorMapper.codeWrongPassword)
        )
    }

    func testUnknownCodeIsGenericWithNoInterpolation() {
        let msg = AuthErrorMapper.userFacing(code: -99999)
        XCTAssertEqual(msg, AuthErrorMapper.message(for: .unknown))
        XCTAssertFalse(msg.contains("Error"))
        XCTAssertFalse(msg.contains("99999"))
    }
}

final class CloudinaryPublicIDTests: XCTestCase {
    func testPreservesPrefixAndIsUnique() {
        let a = CloudinaryPublicID.make(prefix: "pet123")
        let b = CloudinaryPublicID.make(prefix: "pet123")
        XCTAssertTrue(a.hasPrefix("pet123_"))
        XCTAssertNotEqual(a, b, "two ids for the same prefix must differ (unguessable)")
    }
}

final class ImageMetadataTests: XCTestCase {
    /// Build a tiny JPEG that carries a GPS dictionary.
    private func makeJPEGWithGPS() -> Data {
        let size = 4
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let cg = ctx.makeImage()!

        let out = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        let dest = CGImageDestinationCreateWithData(out as CFMutableData, type, 1, nil)!
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 32.0853,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 34.7818,
            kCGImagePropertyGPSLongitudeRef: "E"
        ]
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func hasGPS(in data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return false }
        return props[kCGImagePropertyGPSDictionary] != nil
    }

    func testStripsGPSMetadata() {
        let withGPS = makeJPEGWithGPS()
        XCTAssertTrue(hasGPS(in: withGPS), "sanity: fixture should contain GPS")

        let stripped = ImageMetadata.stripped(from: withGPS)
        XCTAssertFalse(hasGPS(in: stripped), "GPS metadata must be removed after stripping")
        XCTAssertFalse(stripped.isEmpty, "stripped image data must still be a valid image")
    }

    func testReturnsOriginalForNonImageData() {
        let junk = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertEqual(ImageMetadata.stripped(from: junk), junk)
    }
}
