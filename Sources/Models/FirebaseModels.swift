import Foundation
import FirebaseFirestore
import CoreLocation

// MARK: - Enums

enum UserRole: String, Codable {
    case sitter = "sitter"
    case owner = "owner"
    case none = "none"
    case needsRole = "needsRole"
    
    // UI Localizations (optional extension, but raw value must be english as requested in prompt: "sitter" or "owner")
    var displayName: String {
        switch self {
        case .sitter: return "מטפל"
        case .owner: return "בעל כלב"
        default: return ""
        }
    }
}

enum SittingType: String, CaseIterable, Identifiable, Codable {
    case overnight = "לינה"
    case dropIn = "ביקורים"
    case daySitting = "יום"
    case walk = "הליכות"
    
    var id: String { self.rawValue }
}

enum PostStatus: String, Codable {
    case open = "open"
    case approved = "approved"
}

enum MessageType: String, Codable {
    case text = "text"
    case photo = "photo"
    case walk = "walk"
    case payment = "payment"
}

enum WalkStatus: String, Codable {
    case active = "active"
    case completed = "completed"
}

// Ensure CLLocationCoordinate2D can be parsed cleanly if needed manually, though we shouldn't mix it directly with pure Firestore primitives,
// but the prompt specifies arrays of maps. Let's make a Codable Coordinate helper.
struct GeoCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Timestamp?
}

struct WalkCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Timestamp
}

// MARK: - Collections

struct User: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var email: String
    var username: String
    var role: String // "sitter" or "owner"
    var address: String?
    var photoURL: String?
    var age: Int? // sitters only
    var phone: String? // sitters only
    var averageRating: Double?
    var totalReviews: Int?
    @ServerTimestamp var createdAt: Timestamp?
    
    // Convenience wrapper since prompt explicitly said role is "sitter" or "owner"
    var userRole: UserRole {
        UserRole(rawValue: role) ?? .none
    }
}

struct Pet: Identifiable, Codable {
    @DocumentID var id: String?
    var ownerId: String
    var name: String
    var ageYears: Int
    var ageMonths: Int
    var weight: Double
    var sex: String
    var breed: [String]
    var isMicrochipped: Bool
    var isNeutered: Bool
    var friendlyWithChildren: String
    var friendlyWithDogs: String
    var friendlyWithCats: String
    var additionalInfo: String
    var photoURL: String?
    var photoURLs: [String]?
    var mainPhotoURL: String?
    var pendingDeletion: [String]?
    @ServerTimestamp var createdAt: Timestamp?
}

struct Post: Identifiable, Codable {
    @DocumentID var id: String?
    var ownerId: String
    var ownerName: String
    var ownerPhotoURL: String?
    var petIds: [String]
    var address: String
    var latitude: Double?
    var longitude: Double?
    var startDate: Timestamp
    var endDate: Timestamp
    var sittingType: String
    var description: String?
    var foodProvided: Bool
    var foodSchedule: String?
    var walksPerDay: Int?
    var walkDuration: Int?
    var aloneTime: [String: String]? // Map: petId -> String
    var medication: Bool
    var medicationInfo: String?
    var payAmount: Double
    var payPer: String // "hour" or "day"
    var payTiming: String // "perDay" or "endOfStay"
    var pickupType: String? // "dropOff" or "pickUp"
    var pickupAddress: String?
    var interestedCount: Int
    var status: String // "open" or "approved"
    @ServerTimestamp var createdAt: Timestamp?
    
    // Helper to extract enum safely
    var mappedSittingType: SittingType {
        SittingType(rawValue: sittingType) ?? .dropIn
    }
}

struct PostInterestedSitter: Identifiable, Codable {
    @DocumentID var id: String? // usually the sitterUid
    var sitterId: String
    var sitterName: String
    var sitterPhotoURL: String?
    @ServerTimestamp var createdAt: Timestamp?
}

struct Chat: Identifiable, Codable {
    @DocumentID var id: String?
    var postId: String
    var ownerId: String
    var sitterId: String
    var ownerName: String
    var sitterName: String
    var sitterCity: String?
    var ownerPhotoURL: String?
    var sitterPhotoURL: String?
    var approved: Bool
    var archived: Bool
    @ServerTimestamp var createdAt: Timestamp?
    var lastMessage: String?
    var lastMessageTime: Timestamp?
    /// Who sent the last message — lets unread tracking ignore your own outgoing messages.
    /// Optional so existing chat docs decode.
    var lastMessageSenderId: String?
}

struct ChatWrapper: Identifiable {
    var id: String { chat.id ?? UUID().uuidString }
    var chat: Chat
    var otherUser: User?
    var post: Post?
    var pets: [Pet] = []
}

struct OwnerChatGroup: Identifiable {
    var id: String { postId }
    let postId: String
    var post: Post?
    var pets: [Pet]
    var chats: [ChatWrapper]
    var isApproved: Bool { chats.contains(where: { $0.chat.approved }) }
    var isActive: Bool { post?.status == "open" || isApproved }
    var lastMessageTime: Date {
        chats.compactMap { $0.chat.lastMessageTime?.dateValue() }.max() ?? Date.distantPast
    }
}

struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var senderId: String
    var senderName: String
    var sitterCity: String?
    var text: String
    var type: String // "text", "photo", "walk", "payment"
    var photoURL: String?
    var walkId: String?
    
    // Walk specific fields
    var status: String? // "active" or "completed"
    var startTime: Timestamp?
    var endTime: Timestamp?
    var distance: Double?
    var duration: Double?
    var startAddress: String?
    var coordinates: [WalkCoordinate]?
    var photoURLs: [String]?
    
    @ServerTimestamp var createdAt: Timestamp?
}

struct Review: Identifiable, Codable {
    @DocumentID var id: String?
    var sitterId: String
    var ownerId: String
    var ownerName: String
    var ownerPhotoURL: String?
    var postId: String
    var rating: Int // 1-5
    var text: String
    @ServerTimestamp var createdAt: Timestamp?
}

struct Walk: Identifiable, Codable {
    @DocumentID var id: String?
    var chatId: String
    var postId: String
    var sitterId: String
    var ownerId: String
    var status: String // "active" or "completed"
    var startTime: Timestamp
    var endTime: Timestamp?
    var distance: Double // kilometers
    var duration: Double // minutes
    var startAddress: String
    var coordinates: [WalkCoordinate]
    var photoURLs: [String]
    var messageId: String
    /// Optional so existing docs decode. Lives on the walk doc (chat messages are
    /// immutable) — never encode this as a `status` change.
    var isPaused: Bool? = nil
}
