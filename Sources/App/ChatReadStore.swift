import SwiftUI
import FirebaseFirestore

/// Local, per-device unread tracking for chats. No backend / schema changes:
/// we record the timestamp of the newest message the user has seen in each chat,
/// and treat a chat as unread when its `lastMessageTime` is newer than that.
///
/// A first-launch baseline keeps pre-existing chats from all showing as unread the
/// moment this feature ships — only activity newer than the baseline counts until
/// the user opens a given chat and establishes its own last-seen point.
final class ChatReadStore: ObservableObject {
    private let lastSeenKey = "chatLastSeen.v1"
    private let baselineKey = "chatReadBaseline.v1"

    @Published private var lastSeen: [String: Date]
    private let baseline: Date

    init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.dictionary(forKey: lastSeenKey) as? [String: Double] {
            lastSeen = raw.mapValues { Date(timeIntervalSince1970: $0) }
        } else {
            lastSeen = [:]
        }

        let stored = defaults.double(forKey: baselineKey)
        if stored == 0 {
            let now = Date()
            defaults.set(now.timeIntervalSince1970, forKey: baselineKey)
            baseline = now
        } else {
            baseline = Date(timeIntervalSince1970: stored)
        }
    }

    /// True when the chat has a message newer than the user's last-seen point.
    func isUnread(_ chat: Chat) -> Bool {
        guard let id = chat.id, let last = chat.lastMessageTime?.dateValue() else { return false }
        let seen = lastSeen[id] ?? baseline
        return last > seen
    }

    /// Record that the user has seen everything up to `date` in this chat.
    func markRead(_ chatId: String, upTo date: Date) {
        if let existing = lastSeen[chatId], existing >= date { return }
        lastSeen[chatId] = date
        UserDefaults.standard.set(lastSeen.mapValues { $0.timeIntervalSince1970 }, forKey: lastSeenKey)
    }
}
