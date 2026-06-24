import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import MapKit

// F-24: keep diagnostic logging out of release builds. Error objects and asset
// URLs can carry PII, so they are only printed in DEBUG.
private func dbg(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUserRole: UserRole = .none
    @Published var currentUser: User? = nil

    // F-18: email-verification state. Defaults true so verified accounts and
    // Google/Apple logins (which carry a verified email) are never gated.
    @Published var isEmailVerified: Bool = true
    @Published var showEmailVerificationPrompt: Bool = false

    // UI Notification Wrapper
    @Published var activeError: String? = nil
    @Published var isLoadingTarget: Bool = false
    
    // Remote Global Feed State
    @Published var users: [User] = []
    @Published var pets: [Pet] = []
    @Published var posts: [Post] = []
    @Published var reviews: [Review] = []
    @Published var chats: [Chat] = []
    
    // Chat System Models
    @Published var ownerChatGroups: [OwnerChatGroup] = []
    @Published var sitterChats: [ChatWrapper] = []
    @Published var myActivePosts: [Post] = []

    // Sitter tab + deep-link navigation. Lets non-tab UI (e.g. a post card whose
    // owner the sitter is already chatting with) jump straight into the existing
    // chat: switch to the messages tab and push that chat.
    @Published var sitterSelectedTab: Int = 0
    @Published var pendingChatId: String? = nil
    
    let db = Firestore.firestore()
    
    // Listener registrations
    private var postsListener: ListenerRegistration?
    private var chatsListener: ListenerRegistration?
    private var myPostsListener: ListenerRegistration?
    
    init() {
        // Route Live Activity button taps (Pause/Resume/End). A LiveActivityIntent's
        // perform() runs in this app process, so the handler can reach LocationTracker +
        // self directly. Registered once here so it survives a background relaunch.
        WalkActivityActionCenter.shared.handler = { [weak self] command in
            await self?.handleWalkCommand(command)
        }

        // Tie into Auth System
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            Task { @MainActor in
                self.isAuthenticated = (user != nil)
                if let uid = user?.uid {
                    self.isEmailVerified = user?.isEmailVerified ?? true
                    await self.fetchCurrentProfile(uid: uid)
                } else {
                    self.resetState()
                }
            }
        }
    }
    
    deinit {
        postsListener?.remove()
        chatsListener?.remove()
        myPostsListener?.remove()
    }
    
    private func resetState() {
        self.currentUserRole = .none
        self.currentUser = nil
        self.pets = []
        self.posts = []
        self.chats = []
        self.reviews = []
        self.myActivePosts = []
        self.sitterChats = []
        self.ownerChatGroups = []
        self.sitterSelectedTab = 0
        self.pendingChatId = nil
        postsListener?.remove()
        chatsListener?.remove()
        myPostsListener?.remove()
        // F-23: clear the shared location tracker so a finished walk's GPS trace
        // does not linger in memory after sign-out / account switch.
        LocationTracker.shared.resetTracking()
        // End any in-flight Live Activity so it doesn't linger past sign-out.
        WalkLiveActivityManager.shared.end()
    }

    // MARK: - Email Verification (F-18)

    /// Gate for the sensitive actions (post / express interest / start walk). Returns
    /// true if allowed; otherwise raises the verification prompt and returns false.
    /// Mirrors the server-side `email_verified` rule so the user gets a helpful prompt
    /// instead of a raw permission-denied.
    func requireVerifiedEmail() -> Bool {
        if isEmailVerified { return true }
        showEmailVerificationPrompt = true
        return false
    }

    /// Re-checks verification status from the server (call on launch / foreground so
    /// the state updates after the user clicks the verification link).
    func refreshEmailVerification() async {
        do {
            try await Auth.auth().currentUser?.reload()
            self.isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
        } catch {
            dbg("Email verification refresh failed: \(error)")
        }
    }

    /// Re-sends the verification email to the signed-in user.
    func resendVerificationEmail() async {
        do {
            try await Auth.auth().currentUser?.sendEmailVerification()
        } catch {
            dbg("Resend verification email failed: \(error)")
        }
    }

    // MARK: - Abuse Controls (F-22)

    /// File a moderation report against another user.
    func reportUser(_ otherUserId: String, reason: String = "") async {
        guard let uid = currentUser?.id else { return }
        let data: [String: Any] = [
            "reporterId": uid,
            "reportedId": otherUserId,
            "reason": reason,
            "createdAt": FieldValue.serverTimestamp()
        ]
        do { _ = try await db.collection("reports").addDocument(data: data) }
        catch { dbg("Report failed: \(error)") }
    }

    /// Block another user (recorded under the current user's own subcollection).
    func blockUser(_ otherUserId: String) async {
        guard let uid = currentUser?.id else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("blocked").document(otherUserId)
                .setData(["createdAt": FieldValue.serverTimestamp()])
        } catch { dbg("Block failed: \(error)") }
    }

    // MARK: - Account Deletion (F-27)

    /// Deletes the signed-in account. Returns nil on success, or a user-facing
    /// message. If Firebase requires a recent login, the user is asked to re-auth.
    /// Firestore user-document cleanup is handled server-side by a Cloud Function.
    func deleteAccount() async -> String? {
        guard let user = Auth.auth().currentUser else { return "אינך מחובר." }
        do {
            try await user.delete()
            return nil // auth state listener resets local state
        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                return "מטעמי אבטחה יש להתחבר מחדש ואז למחוק את החשבון."
            }
            return "מחיקת החשבון נכשלה. אנא נסה שוב."
        }
    }
    
    // MARK: - Core Profile & Booting
    
    func fetchCurrentProfile(uid: String) async {
        do {
            let document = try await db.collection("users").document(uid).getDocument()
            
            guard document.exists, let data = document.data(), let _ = data["role"] as? String else {
                // FALLBACK: Auto-create document if missing
                let authUser = Auth.auth().currentUser
                let email = authUser?.email ?? ""
                let name = authUser?.displayName ?? "משתמש חדש"
                let username = "@" + (email.split(separator: "@").first.map(String.init) ?? "user")
                
                let newUser = User(
                    id: uid,
                    name: name,
                    email: email,
                    username: username,
                    role: UserRole.needsRole.rawValue,
                    createdAt: Timestamp()
                )
                
                // Save it synchronously without throwing error in a way that blocks UI if it fails
                do {
                    try db.collection("users").document(uid).setData(from: newUser)
                    self.currentUser = newUser
                    self.currentUserRole = .needsRole
                } catch {
                    self.activeError = "שגיאה ביצירת הפרופיל הראשוני."
                    self.currentUserRole = .none
                }
                return
            }
            
            let decodedUser = try document.data(as: User.self)
            self.currentUser = decodedUser
            
            if decodedUser.userRole == .none {
                self.currentUserRole = .needsRole
            } else {
                self.currentUserRole = decodedUser.userRole
            }
            
            // Once profile is validated, pull downstream elements (pets, feed, chats)
            if self.currentUserRole == .owner {
                await fetchPets(for: uid)
                setupMyActivePostsListener(uid: uid)
            }
            setupChatsListener(uid: uid)
            setupPostsListener()
            
        } catch {
            self.activeError = "שגיאה בטעינת הרשת. מציג נתונים שמורים."
            self.currentUserRole = .none
        }
    }
    
    // MARK: - Pets API
    
    func fetchPets(for uid: String) async {
        do {
            let snap = try await db.collection("pets").whereField("ownerId", isEqualTo: uid).getDocuments()
            self.pets = snap.documents.compactMap { try? $0.data(as: Pet.self) }
        } catch {
            self.activeError = "חלה שגיאה בטעינת בעלי החיים."
        }
    }
    
    // MARK: - Posts Live Synchronizer
    
    func setupPostsListener() {
        postsListener?.remove()
        
        // Listen to all Open posts, feed builds in memory natively
        let query = db.collection("posts")
            .whereField("status", isEqualTo: PostStatus.open.rawValue)
            .order(by: "createdAt", descending: true)
        
        postsListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if error != nil {
                self.activeError = "שגיאה בטעינת פוסטים בזמן אמת."
                return
            }
            
            guard let documents = snapshot?.documents else { return }
            var updatedPosts = documents.compactMap { try? $0.data(as: Post.self) }
            
            // App-level secondary sort algorithm: deprioritize posts with higher interestedCount natively.
            // Using stability sort logic since Firestore cannot combine inequality limits arbitrarily across unknown index maps
            updatedPosts.sort { (p1, p2) -> Bool in
                if p1.interestedCount != p2.interestedCount {
                    return p1.interestedCount < p2.interestedCount
                }
                
                let t1 = p1.createdAt?.dateValue() ?? Date.distantPast
                let t2 = p2.createdAt?.dateValue() ?? Date.distantPast
                return t1 > t2
            }
            
            self.posts = updatedPosts
        }
    }
    
    func setupMyActivePostsListener(uid: String) {
        myPostsListener?.remove()
        
        let query = db.collection("posts")
            .whereField("ownerId", isEqualTo: uid)
            .whereField("status", isEqualTo: PostStatus.open.rawValue)
            .order(by: "createdAt", descending: true)
        
        myPostsListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let err = error {
                dbg("Error loading my active posts: \(err.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else { 
                dbg("No snapshot documents found for my active posts")
                return 
            }
            dbg("myActivePosts listener fetched \(documents.count) posts.")
            self.myActivePosts = documents.compactMap { try? $0.data(as: Post.self) }
        }
    }
    
    // MARK: - Chats Live Synchronizer
    
    func setupChatsListener(uid: String) {
        if currentUserRole == .owner {
            loadOwnerChats(uid: uid)
        } else {
            loadSitterChats(uid: uid)
        }
    }
    
    func loadOwnerChats(uid: String) {
        chatsListener?.remove()
        chatsListener = db.collection("chats")
            .whereField("ownerId", isEqualTo: uid)
            .whereField("archived", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self, let docs = snapshot?.documents else { return }
                let parsedChats = docs.compactMap { try? $0.data(as: Chat.self) }
                
                Task {
                    var newGroups: [String: OwnerChatGroup] = [:]
                    for chat in parsedChats {
                        if newGroups[chat.postId] == nil {
                            let post = try? await self.db.collection("posts").document(chat.postId).getDocument(as: Post.self)
                            let pets = await self.fetchPets(for: post?.petIds ?? [])
                            newGroups[chat.postId] = OwnerChatGroup(postId: chat.postId, post: post, pets: pets, chats: [])
                        }
                        
                        var wrapper = ChatWrapper(chat: chat)
                        if let sitter = try? await self.db.collection("users").document(chat.sitterId).getDocument(as: User.self) {
                            wrapper.otherUser = sitter
                        }
                        newGroups[chat.postId]?.chats.append(wrapper)
                    }
                    
                    let sortedGroups = newGroups.values.sorted { $0.lastMessageTime > $1.lastMessageTime }
                    await MainActor.run {
                        self.ownerChatGroups = sortedGroups
                    }
                }
            }
    }

    func loadSitterChats(uid: String) {
        chatsListener?.remove()
        chatsListener = db.collection("chats")
            .whereField("sitterId", isEqualTo: uid)
            .whereField("archived", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self, let docs = snapshot?.documents else { return }
                let parsedChats = docs.compactMap { try? $0.data(as: Chat.self) }
                
                Task {
                    var wrappers: [ChatWrapper] = []
                    for chat in parsedChats {
                        var wrapper = ChatWrapper(chat: chat)
                        wrapper.post = try? await self.db.collection("posts").document(chat.postId).getDocument(as: Post.self)
                        wrapper.pets = await self.fetchPets(for: wrapper.post?.petIds ?? [])
                        if let owner = try? await self.db.collection("users").document(chat.ownerId).getDocument(as: User.self) {
                            wrapper.otherUser = owner
                        }
                        wrappers.append(wrapper)
                    }
                    
                    let sortedWrappers = wrappers.sorted { 
                        ($0.chat.lastMessageTime?.dateValue() ?? Date.distantPast) > ($1.chat.lastMessageTime?.dateValue() ?? Date.distantPast) 
                    }
                    await MainActor.run {
                        self.sitterChats = sortedWrappers
                    }
                }
            }
    }

    func sendMessage(chatId: String, text: String) async {
        guard let user = currentUser, let uid = user.id else { return }
        let msg = ChatMessage(senderId: uid, senderName: user.name, text: text, type: "text")
        do {
            let _ = try db.collection("chats").document(chatId).collection("messages").addDocument(from: msg)
            try await db.collection("chats").document(chatId).updateData([
                "lastMessage": text,
                "lastMessageTime": FieldValue.serverTimestamp(),
                "lastMessageSenderId": uid
            ])
        } catch { dbg("Error sending message: \(error)") }
    }

    func sendPhotoMessage(chatId: String, image: UIImage) async {
        guard let user = currentUser, let uid = user.id else { return }
        let msgId = db.collection("chats").document(chatId).collection("messages").document().documentID
        let path = "dogsitter/chats/\(chatId)"
        do {
            let url = try await CloudinaryHelper.uploadImage(image, folder: path, publicId: msgId)
            var msg = ChatMessage(id: msgId, senderId: uid, senderName: user.name, text: "", type: "photo")
            msg.photoURL = url
            try db.collection("chats").document(chatId).collection("messages").document(msgId).setData(from: msg)
            try await db.collection("chats").document(chatId).updateData([
                "lastMessage": "📷 תמונה",
                "lastMessageTime": FieldValue.serverTimestamp(),
                "lastMessageSenderId": uid
            ])
        } catch { dbg("Error sending photo: \(error)") }
    }
    
    func sendWalkMessage(chatId: String) async {
        guard let user = currentUser, let uid = user.id else { return }
        let text = "🐾 הליכה תתחיל בקרוב"
        let msg = ChatMessage(senderId: uid, senderName: user.name, text: text, type: "walk")
        do {
            let _ = try db.collection("chats").document(chatId).collection("messages").addDocument(from: msg)
            try await db.collection("chats").document(chatId).updateData([
                "lastMessage": text,
                "lastMessageTime": FieldValue.serverTimestamp(),
                "lastMessageSenderId": uid
            ])
        } catch { dbg("Error sending walk message: \(error)") }
    }

    func approveChat(chatId: String, postId: String) async {
        // Only the post owner approves; derive identity from the authenticated user.
        guard let owner = currentUser, let ownerUid = owner.id else { return }
        do {
            // Resolve the sitter from the chat document rather than a fragile chatId
            // string-split (the old `approvedSitterId` parse was spoofable).
            let chat = try? await db.collection("chats").document(chatId).getDocument(as: Chat.self)
            let sitterId = chat?.sitterId ?? ""

            try await db.collection("chats").document(chatId).updateData(["approved": true])
            try await db.collection("posts").document(postId).updateData([
                "status": "approved",
                "approvedSitterId": sitterId
            ])

            // Approval just confirms the booking now — it no longer fakes a payment.
            // Real `payment` messages are written only by the trusted backend, per
            // completed walk (see PaymentService / the charge-walk Edge Function).
            let sysMsg = ChatMessage(senderId: ownerUid, senderName: owner.name, text: "ההזמנה אושרה ✓", type: "text")
            let _ = try db.collection("chats").document(chatId).collection("messages").addDocument(from: sysMsg)
        } catch { dbg("Error approving chat: \(error)") }
    }

    func archiveChat(chatId: String) async {
        do {
            try await db.collection("chats").document(chatId).updateData(["archived": true])
        } catch { dbg("Error archiving chat: \(error)") }
    }
    
    // MARK: - Pets Write Operations
    func savePet(_ pet: Pet) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var petToSave = pet
        petToSave.ownerId = uid
        
        // If it lacks an ID, Firestore will generate one by saving locally.
        let collection = db.collection("pets")
        if let id = petToSave.id {
            try collection.document(id).setData(from: petToSave)
        } else {
            let _ = try collection.addDocument(from: petToSave)
        }
        
        // Re-fetch pets dynamically
        await fetchPets(for: uid)
    }
    
    // MARK: - Post Pet Fetching
    
    func fetchPets(for petIds: [String]) async -> [Pet] {
        guard !petIds.isEmpty else { return [] }
        var fetched: [Pet] = []
        let db = Firestore.firestore()
        
        // Firestore 'in' queries support max 10 elements
        for chunk in stride(from: 0, to: petIds.count, by: 10) {
            let endIndex = min(chunk + 10, petIds.count)
            let slice = Array(petIds[chunk..<endIndex])
            do {
                let snap = try await db.collection("pets").whereField(FieldPath.documentID(), in: slice).getDocuments()
                let chunkPets = snap.documents.compactMap { try? $0.data(as: Pet.self) }
                fetched.append(contentsOf: chunkPets)
            } catch {
                dbg("Error fetching pets chunk: \(error)")
            }
        }
        return fetched
    }
    
    // MARK: - Posts Create Operations
    func createPost(_ post: Post) async throws {
        let newRef = db.collection("posts").document()
        var postToSave = post
        postToSave.id = newRef.documentID // Explicitly set ID
        
        await MainActor.run {
            self.posts.insert(postToSave, at: 0)
            self.myActivePosts.insert(postToSave, at: 0)
        }
        
        let encodedData = try Firestore.Encoder().encode(postToSave)
        try await newRef.setData(encodedData, merge: true)
    }
    
    func updatePost(_ post: Post) async throws {
        guard let id = post.id else { return }
        let encodedData = try Firestore.Encoder().encode(post)
        try await db.collection("posts").document(id).setData(encodedData, merge: true)
    }
    
    func deletePost(_ postId: String) async throws {
        await MainActor.run {
            self.posts.removeAll { $0.id == postId }
            self.myActivePosts.removeAll { $0.id == postId }
        }
        try await db.collection("posts").document(postId).delete()
    }
    
    /// The current sitter's existing chat for a post, if one already exists.
    /// Drives the "already in contact" badge and the "go to chat" teleport so a
    /// sitter can never open a second chat for the same post.
    func existingSitterChat(forPostId postId: String) -> ChatWrapper? {
        sitterChats.first { $0.chat.postId == postId }
    }

    /// Teleport the sitter to an existing chat: switch to the messages tab and
    /// push that chat. The push is deferred one runloop so the messages tab's
    /// navigation stack is mounted before the programmatic link activates.
    func openChat(_ chatId: String) {
        sitterSelectedTab = 1
        DispatchQueue.main.async { [weak self] in
            self?.pendingChatId = chatId
        }
    }

    /// Deep-link target (`dogsitter://walk/{walkId}`): open the chat that owns the walk.
    func openWalk(byId walkId: String) {
        Task {
            if let walk = await fetchWalk(walkId) {
                openChat(walk.chatId)
            }
        }
    }

    func expressInterest(in post: Post) async throws {
        guard let postId = post.id, let user = currentUser, let uid = user.id else { return }

        // Idempotency: a sitter may express interest in a given post only once.
        // Guard against repeated taps (locally and across reopens before the chats
        // listener catches up) creating duplicate chats and over-counting interest.
        if existingSitterChat(forPostId: postId) != nil { return }
        if let existing = try? await db.collection("chats")
            .whereField("sitterId", isEqualTo: uid)
            .whereField("postId", isEqualTo: postId)
            .whereField("archived", isEqualTo: false)
            .limit(to: 1)
            .getDocuments(), !existing.documents.isEmpty {
            return
        }

        let interester = PostInterestedSitter(sitterId: uid, sitterName: user.name, sitterPhotoURL: user.photoURL)

        // Add subcollection doc
        try db.collection("posts").document(postId).collection("interested").document(uid).setData(from: interester)
        // Increment global interestedCount
        try await db.collection("posts").document(postId).updateData([
            "interestedCount": FieldValue.increment(Int64(1))
        ])
        
        // Extract city from address
        var city: String? = nil
        if let address = user.address, !address.isEmpty {
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(address)
                if let locality = placemarks.first?.locality {
                    city = locality
                }
            } catch {
                dbg("Geocoding failed for city extraction: \(error)")
            }
        }
        
        // Automatically create a chat channel
        let chatRef = db.collection("chats").document()
        var chat = Chat(postId: postId, ownerId: post.ownerId, sitterId: uid, ownerName: post.ownerName, sitterName: user.name, sitterCity: city, ownerPhotoURL: post.ownerPhotoURL, sitterPhotoURL: user.photoURL, approved: false, archived: false)
        chat.id = chatRef.documentID
        try chatRef.setData(from: chat)
        
        // Initial interest message
        let initialMsg = ChatMessage(senderId: uid, senderName: user.name, sitterCity: city, text: "מעוניין לטפל בכלב שלך", type: MessageType.text.rawValue)
        let _ = try chatRef.collection("messages").addDocument(from: initialMsg)
        try await chatRef.updateData([
            "lastMessage": "מעוניין לטפל בכלב שלך",
            "lastMessageTime": FieldValue.serverTimestamp(),
            "lastMessageSenderId": uid
        ])
    }
    
    // MARK: - Walk API
    
    func startWalk(chatId: String, postId: String, startAddress: String) async -> String? {
        guard let user = currentUser, let uid = user.id else { return nil }
        // Determine ownerId by finding the chat.
        var ownerId = ""
        if let chat = try? await db.collection("chats").document(chatId).getDocument(as: Chat.self) {
            ownerId = chat.ownerId
        }
        
        let walkRef = db.collection("walks").document()
        let walkId = walkRef.documentID
        
        let messageRef = db.collection("chats").document(chatId).collection("messages").document()
        let messageId = messageRef.documentID
        
        let newWalk = Walk(
            id: walkId,
            chatId: chatId,
            postId: postId,
            sitterId: uid,
            ownerId: ownerId,
            status: "active",
            startTime: Timestamp(),
            endTime: nil,
            distance: 0.0,
            duration: 0.0,
            startAddress: startAddress,
            coordinates: [],
            photoURLs: [],
            messageId: messageId
        )
        
        let walkMsg = ChatMessage(
            id: messageId,
            senderId: uid,
            senderName: user.name,
            text: "🐾 הליכה התחילה!",
            type: "walk",
            walkId: walkId,
            status: "active",
            startTime: newWalk.startTime,
            distance: 0.0,
            duration: 0.0,
            startAddress: startAddress,
            coordinates: [],
            photoURLs: [],
            createdAt: Timestamp()
        )
        
        do {
            try walkRef.setData(from: newWalk)
            try messageRef.setData(from: walkMsg)
            try await db.collection("chats").document(chatId).updateData([
                "lastMessage": "🐾 הליכה התחילה!",
                "lastMessageTime": FieldValue.serverTimestamp(),
                "lastMessageSenderId": uid
            ])
            return walkId
        } catch {
            dbg("Error starting walk: \(error)")
            return nil
        }
    }
    
    // MARK: - Walk session wiring (background tracker + Live Activity)

    /// Wire the shared tracker so its background sync loop drives Firestore + the Live
    /// Activity regardless of which screen is on. Call when a walk starts or on re-attach.
    func beginWalkSession(walkId: String, dogName: String, isSitter: Bool) {
        let tracker = LocationTracker.shared
        tracker.isSitter = isSitter
        tracker.onSync = { [weak self] coords, distanceKm, durationMin in
            guard let self = self else { return }
            Task { await self.updateWalkCoordinates(walkId: walkId, coordinates: coords, distance: distanceKm, duration: durationMin) }
        }
        tracker.onLiveActivityUpdate = { distanceKm, isPaused, elapsedSeconds in
            WalkLiveActivityManager.shared.update(distanceKm: distanceKm, isPaused: isPaused, elapsedSeconds: elapsedSeconds)
        }
        if isSitter {
            WalkLiveActivityManager.shared.start(dogName: dogName, walkId: walkId, startTime: Date())
        }
    }

    /// Tear down the tracker hooks and end the Live Activity when a walk ends.
    func endWalkSession() {
        let tracker = LocationTracker.shared
        tracker.onSync = nil
        tracker.onLiveActivityUpdate = nil
        WalkLiveActivityManager.shared.end()
    }

    private func fetchWalk(_ walkId: String) async -> Walk? {
        try? await db.collection("walks").document(walkId).getDocument(as: Walk.self)
    }

    /// Executes a Live Activity button action. Runs in-app (LiveActivityIntent), so it can
    /// drive the tracker directly. Intents carry `walkId`, so it works even post-relaunch.
    func handleWalkCommand(_ command: WalkActivityCommand) async {
        let tracker = LocationTracker.shared
        switch command {
        case .togglePause(let walkId):
            let newPaused: Bool
            if tracker.isTracking {
                if tracker.isPaused { tracker.resumeWalk(); newPaused = false }
                else { tracker.pauseWalk(); newPaused = true }
            } else {
                // No live session (relaunched): flip from the doc and refresh the Activity.
                let doc = await fetchWalk(walkId)
                newPaused = !(doc?.isPaused ?? false)
                WalkLiveActivityManager.shared.update(
                    distanceKm: doc?.distance ?? 0,
                    isPaused: newPaused,
                    elapsedSeconds: Int((doc?.duration ?? 0) * 60))
            }
            await setWalkPaused(walkId: walkId, isPaused: newPaused)

        case .end(let walkId):
            let doc = await fetchWalk(walkId)
            let finalDistance = tracker.isTracking ? tracker.totalDistance : (doc?.distance ?? 0)
            let finalDuration = tracker.isTracking ? Double(tracker.elapsedSeconds) / 60.0 : (doc?.duration ?? 0)
            tracker.stopTracking()
            endWalkSession()
            if let doc = doc {
                await stopWalk(walkId: walkId, messageId: doc.messageId, chatId: doc.chatId,
                               finalDistance: finalDistance, finalDuration: finalDuration)
            }
        }
    }

    /// Persist pause state on the walk doc (allowed by rules: sitter while status active).
    func setWalkPaused(walkId: String, isPaused: Bool) async {
        do {
            try await db.collection("walks").document(walkId).updateData(["isPaused": isPaused])
        } catch {
            dbg("Error setting walk paused: \(error)")
        }
    }

    /// Best-effort dog name(s) for a post, used as the Live Activity label.
    func dogName(forPostId postId: String) -> String {
        guard let post = posts.first(where: { $0.id == postId }) else { return "טיול" }
        let names = pets.filter { post.petIds.contains($0.id ?? "") }.map { $0.name }
        return names.isEmpty ? "טיול" : names.joined(separator: ", ")
    }

    func updateWalkCoordinates(walkId: String, coordinates: [CLLocationCoordinate2D], distance: Double, duration: Double) async {
        let walkCoords = coordinates.map { WalkCoordinate(latitude: $0.latitude, longitude: $0.longitude, timestamp: Timestamp()) }
        let walkCoordsDicts = walkCoords.compactMap { try? Firestore.Encoder().encode($0) }
        
        do {
            try await db.collection("walks").document(walkId).updateData([
                "coordinates": walkCoordsDicts,
                "distance": distance,
                "duration": duration
            ])
        } catch {
            dbg("Error updating walk coordinates: \(error)")
        }
    }
    
    func stopWalk(walkId: String, messageId: String, chatId: String, finalDistance: Double, finalDuration: Double) async {
        do {
            let endTime = Timestamp()
            
            try await db.collection("walks").document(walkId).updateData([
                "status": "completed",
                "endTime": endTime,
                "distance": finalDistance,
                "duration": finalDuration
            ])

            // The walk bubble reads live from the walk document (liveWalk overrides
            // msg.*), so the previous duplicate write to the chat message is dropped.
            // Messages are immutable under the new rules; display is unaffected.
            _ = messageId

            // Charge per completed walk. The backend re-verifies the walk against
            // Firestore and is idempotent on walkId, so this is safe to fire-and-forget
            // (and no-ops when payments aren't configured yet).
            Task { await PaymentService.shared.chargeForWalk(walkId: walkId) }
        } catch {
            dbg("Error stopping walk: \(error)")
        }
    }
    
    func addWalkPhoto(walkId: String, imageURL: String) async {
        do {
            try await db.collection("walks").document(walkId).updateData([
                "photoURLs": FieldValue.arrayUnion([imageURL])
            ])
        } catch {
            dbg("Error adding walk photo: \(error)")
        }
    }
    
    func getTotalWalkHoursForChat(chatId: String) async -> String {
        do {
            var query: Query = db.collection("walks")
                .whereField("chatId", isEqualTo: chatId)
                .whereField("status", isEqualTo: "completed")
            // Scope to the caller's own id so the participant-only walk read rule can
            // authorize this list query (Firestore proves list safety from the query
            // filters, not the returned docs).
            if let uid = currentUser?.id {
                query = currentUserRole == .owner
                    ? query.whereField("ownerId", isEqualTo: uid)
                    : query.whereField("sitterId", isEqualTo: uid)
            }
            let snap = try await query.getDocuments()
            
            let totalMinutes = snap.documents.compactMap { doc -> Double? in
                return doc.data()["duration"] as? Double
            }.reduce(0, +)
            
            let hours = Int(totalMinutes) / 60
            let minutes = Int(totalMinutes) % 60
            return String(format: "%02d:%02d", hours, minutes)
        } catch {
            dbg("Error fetching walk hours: \(error)")
            return "00:00"
        }
    }
}
