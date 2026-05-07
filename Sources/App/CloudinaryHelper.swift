import Foundation
import UIKit

class CloudinaryHelper {
    static let cloudName = "dns0htaph"
    static let uploadPreset = "dogsitter_uploads"
    
    // Resize image to max 1200x1200 maintaining aspect ratio
    static func compressImage(_ image: UIImage) -> Data? {
        let maxSize: CGFloat = 1200.0
        let size = image.size
        
        var newSize: CGSize
        if size.width > maxSize || size.height > maxSize {
            let ratio = max(size.width / maxSize, size.height / maxSize)
            newSize = CGSize(width: size.width / ratio, height: size.height / ratio)
        } else {
            newSize = size
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage?.jpegData(compressionQuality: 0.8)
    }
    
    static func uploadPhoto(image: UIImage, userId: String, petId: String, index: Int) async throws -> String {
        guard let imageData = compressImage(image) else {
            throw NSError(domain: "Cloudinary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
        }
        
        let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/image/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        let parameters: [String: String] = [
            "upload_preset": uploadPreset,
            "folder": "dogsitter/pets/\(userId)/\(petId)",
            "public_id": "\(petId)_\(index)"
        ]
        
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown upload error"
            throw NSError(domain: "Cloudinary", code: -2, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(errorMsg)"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let secureUrl = json["secure_url"] as? String {
            return secureUrl
        } else {
            throw NSError(domain: "Cloudinary", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse secure_url from response"])
        }
    }
}
