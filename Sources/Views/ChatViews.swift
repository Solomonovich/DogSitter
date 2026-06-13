import SwiftUI
import FirebaseFirestore
import MapKit

struct ChatsListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                if appState.currentUserRole == .owner {
                    OwnerChatListView()
                } else {
                    SitterChatListView()
                }
            }
            .navigationTitle("הודעות")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

// MARK: - Owner Chat Views
struct OwnerChatListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if appState.ownerChatGroups.isEmpty {
            VStack {
                Spacer()
                Text("אין צ'אטים עדיין. פרסם פוסט כדי להתחיל!")
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(appState.ownerChatGroups) { group in
                        OwnerChatGroupView(group: group)
                    }
                }
                .padding(.top)
            }
        }
    }
}

struct OwnerChatGroupView: View {
    @EnvironmentObject var appState: AppState
    let group: OwnerChatGroup
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                if !group.isApproved {
                    withAnimation(.spring()) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack {
                    if group.isApproved {
                        Image(systemName: "chevron.down").foregroundColor(.clear) // Spacer
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.left")
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        HStack {
                            Text(group.pets.map { $0.name }.joined(separator: ", "))
                                .font(.headline)
                                .foregroundColor(group.isActive ? Color(white: 0.1) : .gray)
                            
                            Circle()
                                .fill(group.isActive ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                        if let post = group.post {
                            Text("\(post.startDate.dateValue().formatted(date: .numeric, time: .omitted)) - \(post.endDate.dateValue().formatted(date: .numeric, time: .omitted))")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal)
                .frame(height: 44)
                .background(group.isActive ? Color.green.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded || group.isApproved {
                ForEach(group.chats) { wrapper in
                    NavigationLink(destination: ChatDetailView(chatWrapper: wrapper)) {
                        OwnerChatRowView(wrapper: wrapper, isApproved: wrapper.chat.approved)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .swipeActions(edge: .leading) {
                        Button("ארכיון") {
                            if let id = wrapper.chat.id {
                                Task { await appState.archiveChat(chatId: id) }
                            }
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .onAppear {
            if group.isApproved {
                isExpanded = true
            }
        }
    }
}

struct OwnerChatRowView: View {
    @EnvironmentObject var appState: AppState
    let wrapper: ChatWrapper
    let isApproved: Bool
    @State private var showingApproveAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                if let t = wrapper.chat.lastMessageTime?.dateValue() {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                if isApproved {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                } else {
                    Button(action: { showingApproveAlert = true }) {
                        Text("אשר")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(wrapper.chat.sitterName)
                    .font(.system(size: 16, weight: .bold))
                
                Text(wrapper.chat.lastMessage ?? "...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            AsyncImage(url: URL(string: wrapper.chat.sitterPhotoURL ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        }
        .padding()
        .frame(height: 72)
        .background(isApproved ? Color.yellow.opacity(0.2) : Color(.systemBackground))
        .alert("אישור מטפל", isPresented: $showingApproveAlert) {
            Button("ביטול", role: .cancel) { }
            Button("אשר") {
                if let cid = wrapper.chat.id {
                    Task { await appState.approveChat(chatId: cid, postId: wrapper.chat.postId) }
                }
            }
        } message: {
            Text("האם אתה בטוח שברצונך לאשר את המטפל?")
        }
    }
}

// MARK: - Sitter Chat Views
struct SitterChatListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if appState.sitterChats.isEmpty {
            VStack {
                Spacer()
                Text("אין צ'אטים עדיין. חפש פוסטים והתחל!")
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                ForEach(appState.sitterChats) { wrapper in
                    NavigationLink(destination: ChatDetailView(chatWrapper: wrapper)) {
                        SitterChatRowView(wrapper: wrapper)
                    }
                    .listRowInsets(EdgeInsets())
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .listStyle(PlainListStyle())
        }
    }
}

struct SitterChatRowView: View {
    let wrapper: ChatWrapper
    
    var isActive: Bool {
        wrapper.post?.status == "open" || wrapper.chat.approved
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                if let t = wrapper.chat.lastMessageTime?.dateValue() {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                    if wrapper.chat.approved {
                        Text("✓ אושרת")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                    Circle()
                        .fill(isActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(wrapper.chat.ownerName)
                    .font(.system(size: 16, weight: .bold))
                
                Text(wrapper.pets.map { $0.name }.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                
                Text(wrapper.chat.lastMessage ?? "...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            AsyncImage(url: URL(string: wrapper.chat.ownerPhotoURL ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        }
        .padding()
        .frame(height: 72)
        .background(wrapper.chat.approved ? Color.yellow.opacity(0.2) : Color(.systemBackground))
    }
}

// MARK: - Chat Detail
struct ChatDetailView: View {
    @EnvironmentObject var appState: AppState
    let chatWrapper: ChatWrapper
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var listener: ListenerRegistration?
    
    enum ActiveSheet: Identifiable {
        case userProfile
        case imagePicker(UIImagePickerController.SourceType)
        
        var id: String {
            switch self {
            case .userProfile: return "userProfile"
            case .imagePicker(let source): 
                return source == .camera ? "camera" : "gallery"
            }
        }
    }
    
    @State private var activeSheet: ActiveSheet? = nil
    @State private var showingSourceDialog = false
    
    @State private var showAttachmentMenu = false
    @State private var isUploadingPhoto = false
    @State private var selectedLightboxURL: String? = nil
    
    @State private var otherUserFullProfile: User?
    
    @State private var showDeleteAlert = false
    @State private var messageToDelete: ChatMessage? = nil
    @State private var hasInitialScrolled = false
    
    struct WalkIdentifier: Identifiable {
        let id: String
    }
    
    @State private var showingPreWalk = false
    @State private var walkToOpen: WalkIdentifier? = nil
    
    var otherName: String {
        appState.currentUserRole == .owner ? chatWrapper.chat.sitterName : chatWrapper.chat.ownerName
    }
    
    var hasActiveWalk: Bool {
        messages.contains { $0.type == "walk" && $0.status == "active" }
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubbleView(msg: msg, currentUserId: appState.currentUser?.id, selectedLightboxURL: $selectedLightboxURL) { walkId in
                                    self.walkToOpen = WalkIdentifier(id: walkId)
                                }
                                    .contextMenu {
                                        if msg.senderId == appState.currentUser?.id {
                                            Button(role: .destructive) {
                                                messageToDelete = msg
                                                showDeleteAlert = true
                                            } label: {
                                                Label("מחק הודעה", systemImage: "trash")
                                            }
                                        }
                                    }
                                    .id(msg.id ?? "")
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .onChange(of: messages.count) { _, newCount in
                        guard let last = messages.last?.id else { return }
                        if !hasInitialScrolled && newCount > 0 {
                            hasInitialScrolled = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        } else {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                    .onAppear {
                        if !messages.isEmpty && !hasInitialScrolled {
                            hasInitialScrolled = true
                            if let lastId = messages.last?.id {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .overlay {
                    if showAttachmentMenu {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showAttachmentMenu = false
                                }
                            }
                    }
                }
                
                // Input Bar
                VStack(spacing: 0) {
                    Divider()
                        
                        if isUploadingPhoto {
                            HStack {
                                ProgressView()
                                    .padding(.horizontal)
                                Text("מעלה תמונה...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 8)
                        }
                        
                        HStack(alignment: .bottom, spacing: 12) {
                            // Send Button
                            Button(action: {
                                if !inputText.isEmpty {
                                    let txt = inputText
                                    inputText = ""
                                    if let cid = chatWrapper.chat.id {
                                        Task { await appState.sendMessage(chatId: cid, text: txt) }
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(inputText.isEmpty ? Color.gray : Color.blue)
                                    .clipShape(Circle())
                            }
                            .disabled(inputText.isEmpty)
                            
                            // Text Field
                            TextField("הודעה...", text: $inputText, axis: .vertical)
                                .lineLimit(1...5)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(20)
                                .multilineTextAlignment(.trailing)
                            
                            // Plus Button
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showAttachmentMenu.toggle()
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.blue)
                                    .frame(width: 32, height: 32)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.blue, lineWidth: 1.5))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showAttachmentMenu {
                            VStack(spacing: 12) {
                                if appState.currentUserRole == .sitter && !hasActiveWalk && chatWrapper.chat.approved {
                                    Button(action: {
                                        showAttachmentMenu = false
                                        showingPreWalk = true
                                    }) {
                                        HStack {
                                            Text("הוסף הליכה")
                                                .foregroundColor(Color(white: 0.1))
                                            Image(systemName: "pawprint.fill")
                                                .foregroundColor(Color(white: 0.1))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(20)
                                        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                                    }
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            
                            Button(action: {
                                showAttachmentMenu = false
                                showingSourceDialog = true
                            }) {
                                HStack {
                                    Text("הוסף תמונה")
                                        .foregroundColor(Color(white: 0.1))
                                    Image(systemName: "photo")
                                        .foregroundColor(Color(white: 0.1))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(.systemBackground))
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .padding(.bottom, 60)
                        .padding(.trailing, 16)
                        }
                    }
                    }
            
            if let urlString = selectedLightboxURL,
               let url = URL(string: urlString) {
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture { selectedLightboxURL = nil }
                    
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding()
                        }
                    }
                    
                    VStack {
                        HStack {
                            Button(action: { selectedLightboxURL = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .padding()
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .zIndex(999)
                .transition(.opacity)
            }
        }
        .confirmationDialog(
            "בחר תמונה",
            isPresented: $showingSourceDialog,
            titleVisibility: .visible
        ) {
            Button("צלם תמונה") {
                activeSheet = .imagePicker(.camera)
            }
            Button("בחר מגלריה") {
                activeSheet = .imagePicker(.photoLibrary)
            }
            Button("ביטול", role: .cancel) {}
        }
        .sheet(item: $activeSheet) { sheet in
            let _ = print("DEBUG: sheet opening with \(sheet.id)")
            switch sheet {
            case .userProfile:
                ChatUserProfileView(
                    otherUserId: appState.currentUserRole == .owner ? chatWrapper.chat.sitterId : chatWrapper.chat.ownerId,
                    chatId: chatWrapper.id,
                    isApproved: chatWrapper.chat.approved
                )
            case .imagePicker(let sourceType):
                ChatImagePicker(
                    sourceType: sourceType,
                    onImageSelected: { image in
                        activeSheet = nil
                        Task {
                            await sendPhotoMessage(image: image)
                        }
                    }
                )
            }
        }
        .alert("מחק הודעה", isPresented: $showDeleteAlert) {
            Button("מחק", role: .destructive) {
                if let msg = messageToDelete,
                   let msgId = msg.id,
                   let chatId = chatWrapper.chat.id {
                    Task {
                        try? await appState.db
                            .collection("chats")
                            .document(chatId)
                            .collection("messages")
                            .document(msgId)
                            .delete()
                            
                        if msgId == messages.last?.id {
                            try? await appState.db
                                .collection("chats")
                                .document(chatId)
                                .updateData([
                                    "lastMessage": "ההודעה נמחקה"
                                ])
                        }
                    }
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("האם אתה בטוח שברצונך למחוק את ההודעה?")
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle(otherName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    activeSheet = .userProfile
                }) {
                    AsyncImage(url: URL(string: appState.currentUserRole == .owner ? (chatWrapper.chat.sitterPhotoURL ?? "") : (chatWrapper.chat.ownerPhotoURL ?? ""))) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                }
            }
        }
        .onAppear {
            setupMessageListener()
            fetchOtherUser()
        }
        .fullScreenCover(isPresented: $showingPreWalk) {
            PreWalkView(chat: chatWrapper.chat)
        }
        .fullScreenCover(item: $walkToOpen) { walkIdentifier in
            if let cid = chatWrapper.chat.id {
                WalkFullView(walkId: walkIdentifier.id, chatId: cid, isSitter: appState.currentUserRole == .sitter)
            }
        }
        .onDisappear {
            listener?.remove()
        }
    }
    
    func fetchOtherUser() {
        Task {
            let id = appState.currentUserRole == .owner ? chatWrapper.chat.sitterId : chatWrapper.chat.ownerId
            if let user = try? await appState.db.collection("users").document(id).getDocument(as: User.self) {
                await MainActor.run {
                    otherUserFullProfile = user
                }
            }
        }
    }
    
    func setupMessageListener() {
        guard let id = chatWrapper.chat.id else { return }
        listener = appState.db.collection("chats").document(id).collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self.messages = docs.compactMap { try? $0.data(as: ChatMessage.self) }
            }
    }
    
    func sendPhotoMessage(image: UIImage) async {
        guard let chatId = chatWrapper.chat.id,
              let userId = appState.currentUser?.id 
        else { return }
        
        await MainActor.run { isUploadingPhoto = true }
        
        let messageId = UUID().uuidString
        
        do {
            let url = try await CloudinaryHelper.uploadPhoto(
                image: image,
                userId: userId,
                petId: "chats/\(chatId)",
                index: messageId.hashValue
            )
            
            let messageData: [String: Any] = [
                "senderId": userId,
                "senderName": appState.currentUser?.name ?? "",
                "text": "",
                "type": "photo",
                "photoURL": url,
                "createdAt": Timestamp()
            ]
            
            try await appState.db
                .collection("chats")
                .document(chatId)
                .collection("messages")
                .document(messageId)
                .setData(messageData)
            
            try await appState.db
                .collection("chats")
                .document(chatId)
                .updateData([
                    "lastMessage": "📷 תמונה",
                    "lastMessageTime": Timestamp()
                ])
                
        } catch {
            print("Photo upload error: \(error)")
        }
        
        await MainActor.run { isUploadingPhoto = false }
    }
}

// MARK: - Bubble Views
struct ChatBubbleView: View {
    let msg: ChatMessage
    let currentUserId: String?
    @Binding var selectedLightboxURL: String?
    var onTapWalk: ((String) -> Void)? = nil
    
    var isMine: Bool {
        msg.senderId == currentUserId
    }
    
    var body: some View {
        if msg.type == "payment" {
            Text(msg.text)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(16)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if msg.type == "walk" {
            WalkBubbleContent(msg: msg, isMine: isMine, onTap: {
                if let wid = msg.walkId {
                    onTapWalk?(wid)
                }
            })
        } else if msg.type == "photo", let photoURL = msg.photoURL, let url = URL(string: photoURL) {
            HStack {
                if isMine { Spacer() }
                
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 200, height: 200)
                            .clipped()
                            .cornerRadius(16)
                    } else if phase.error != nil {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 200, height: 200)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 200, height: 200)
                            .overlay(ProgressView())
                    }
                }
                .onTapGesture {
                    selectedLightboxURL = photoURL
                }
                
                if !isMine { Spacer() }
            }
        } else {
            // Text Message
            HStack(alignment: .bottom) {
                if isMine { Spacer() }
                
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    Text(msg.text)
                        .padding(12)
                        .background(isMine ? Color.blue : Color(.secondarySystemGroupedBackground))
                        .foregroundColor(isMine ? .white : Color(white: 0.1))
                        .clipShape(RoundedCorner(radius: 16, corners: isMine ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]))
                    
                    if let d = msg.createdAt?.dateValue() {
                        Text(d.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                if !isMine { Spacer() }
            }
        }
    }
}

// MARK: - Chat User Profile View
struct ChatUserProfileView: View {
    @EnvironmentObject var appState: AppState
    let otherUserId: String
    let chatId: String
    let isApproved: Bool
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var user: User? = nil
    @State private var isLoading = true
    
    @State private var photos: [ChatMessage] = []
    @State private var lastDoc: DocumentSnapshot?
    @State private var isLoadingMore = false
    @State private var hasMorePhotos = true
    
    @State private var showingLightbox = false
    @State private var selectedPhotoURL: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                if isLoading {
                    ProgressView()
                } else if let user = user {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("View is rendering")
                                .foregroundColor(.red)
                                .font(.headline)
                            
                            // Header Section
                        VStack(spacing: 8) {
                            AsyncImage(url: URL(string: user.photoURL ?? "")) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            
                            Text(user.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Color(white: 0.1))
                            
                            if isApproved {
                                if let address = user.address, !address.isEmpty {
                                    Text(address)
                                        .font(.system(size: 15))
                                        .foregroundColor(Color(white: 0.4))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                
                                if let phone = user.phone, !phone.isEmpty {
                                    Button(action: {
                                        if let url = URL(string: "tel://\(phone)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "phone.fill")
                                                .font(.system(size: 13))
                                            Text(phone)
                                                .font(.system(size: 15))
                                        }
                                        .foregroundColor(Color(red: 74/255, green: 144/255, blue: 217/255))
                                    }
                                }
                            } else {
                                Text("פרטי יצירת קשר יוצגו לאחר אישור הבקינג")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(16)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top, 20)
                        
                        Divider()
                        
                        // Shared Photos Section
                        VStack(alignment: .trailing, spacing: 12) {
                            Text("תמונות משותפות")
                                .font(.headline.bold())
                                .foregroundColor(Color(white: 0.1))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.horizontal)
                            
                            if photos.isEmpty && !isLoadingMore {
                                Text("אין תמונות משותפות עדיין")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(white: 0.5))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                                    ForEach(photos) { msg in
                                        if let url = msg.photoURL {
                                            Button(action: {
                                                selectedPhotoURL = url
                                                withAnimation { showingLightbox = true }
                                            }) {
                                                AsyncImage(url: URL(string: url)) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().aspectRatio(contentMode: .fill)
                                                    } else {
                                                        ProgressView()
                                                    }
                                                }
                                                .frame(maxWidth: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipped()
                                            }
                                        }
                                    }
                                }
                                
                                if hasMorePhotos {
                                    Button(action: loadMorePhotos) {
                                        if isLoadingMore {
                                            ProgressView()
                                        } else {
                                            Text("טען עוד")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.blue)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical)
                                }
                            }
                        }
                    }
                }
                }
                
                // Lightbox
                if showingLightbox, let url = selectedPhotoURL {
                    ZStack {
                        Color.black.opacity(0.85).edgesIgnoringSafeArea(.all)
                            .onTapGesture { withAnimation { showingLightbox = false } }
                        
                        VStack {
                            HStack {
                                Button(action: { withAnimation { showingLightbox = false } }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.white)
                                }
                                .padding()
                                Spacer()
                            }
                            Spacer()
                            AsyncImage(url: URL(string: url)) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fit)
                                }
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(user?.name ?? "").font(.headline)
                }
            }
            .onAppear {
                loadInitialPhotos()
            }
            .task {
                if let doc = try? await appState.db.collection("users").document(otherUserId).getDocument(as: User.self) {
                    await MainActor.run {
                        self.user = doc
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    func loadInitialPhotos() {
        isLoadingMore = true
        appState.db.collection("chats")
            .document(chatId)
            .collection("messages")
            .whereField("type", isEqualTo: "photo")
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .getDocuments { snapshot, error in
                isLoadingMore = false
                guard let docs = snapshot?.documents else { return }
                self.photos = docs.compactMap { try? $0.data(as: ChatMessage.self) }
                self.lastDoc = docs.last
                self.hasMorePhotos = docs.count == 5
            }
    }
    
    func loadMorePhotos() {
        guard let last = lastDoc else { return }
        isLoadingMore = true
        appState.db.collection("chats")
            .document(chatId)
            .collection("messages")
            .whereField("type", isEqualTo: "photo")
            .order(by: "createdAt", descending: true)
            .start(afterDocument: last)
            .limit(to: 5)
            .getDocuments { snapshot, error in
                isLoadingMore = false
                guard let docs = snapshot?.documents else { return }
                let newPhotos = docs.compactMap { try? $0.data(as: ChatMessage.self) }
                self.photos.append(contentsOf: newPhotos)
                self.lastDoc = docs.last
                self.hasMorePhotos = docs.count == 5
            }
    }
}

// MARK: - Chat Image Picker
struct ChatImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImageSelected: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageSelected: (UIImage) -> Void
        
        init(onImageSelected: @escaping (UIImage) -> Void) {
            self.onImageSelected = onImageSelected
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageSelected(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Walk Bubble Content
struct WalkBubbleContent: View {
    let msg: ChatMessage
    let isMine: Bool
    var onTap: () -> Void
    
    // Live update state
    @State private var liveWalk: Walk?
    @EnvironmentObject var appState: AppState
    
    @State private var walkListener: ListenerRegistration? = nil
    @State private var snapshotImage: UIImage? = nil
    
    @ObservedObject private var tracker = LocationTracker.shared
    
    var activeDuration: Double {
        if tracker.isTracking {
            return Double(tracker.elapsedSeconds) / 60.0
        } else {
            let start = liveWalk?.startTime.dateValue() ?? msg.startTime?.dateValue() ?? Date()
            return Date().timeIntervalSince(start) / 60.0
        }
    }
    
    var body: some View {
        let status = liveWalk?.status ?? msg.status ?? "active"
        let distance = liveWalk?.distance ?? msg.distance ?? 0.0
        let startTime = liveWalk?.startTime.dateValue() ?? msg.startTime?.dateValue() ?? Date()
        let startAddress = liveWalk?.startAddress ?? msg.startAddress ?? ""
        
        Button(action: onTap) {
            if status == "completed" {
                // SCREEN 4 — FINISHED WALK CHAT BUBBLE
                VStack(spacing: 0) {
                    if let img = snapshotImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(hex: "#E0E0E0"))
                            .frame(height: 150)
                            .overlay(ProgressView())
                    }
                    
                    HStack {
                        let totalDuration = liveWalk?.duration ?? msg.duration ?? 0.0
                        Text("זמן - \(formatElapsedTime(Int(totalDuration * 60)))")
                            .font(.caption)
                        Spacer()
                        Divider()
                        Spacer()
                        Text(String(format: "מרחק - %.2f", distance))
                            .font(.caption)
                    }
                    .padding()
                    .background(Color(hex: "#9E9E9E").opacity(0.3))
                }
                .frame(width: 280)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#4A90D9"), lineWidth: 2))
                .padding(.vertical, 4)
                .onAppear {
                    if snapshotImage == nil {
                        generateSnapshot()
                    }
                }
                .onChange(of: liveWalk?.coordinates) { _ in
                    generateSnapshot()
                }
            } else if isMine {
                // SCREEN 2 — ACTIVE WALK CHAT BUBBLE (Sitter)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(formatElapsedTime(Int(activeDuration * 60)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("הותחל ב- \(startTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Button(action: onTap) {
                        Text("סיים ההליכה")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                    }
                }
                .padding()
                .frame(width: 260)
                .background(Color(hex: "#4A90D9"))
                .cornerRadius(16)
            } else {
                // SCREEN 3 — ACTIVE WALK CHAT BUBBLE (Owner)
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(formatElapsedTime(Int(activeDuration * 60)))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(Color(hex: "#4A90D9"))
                        
                        HStack {
                            Text(startAddress)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    
                    HStack {
                        Text("\(startTime.formatted(date: .omitted, time: .shortened)) -הותחל ב")
                            .font(.caption)
                        Spacer()
                        Divider()
                        Spacer()
                        Text(String(format: "מרחק %.2f ק״מ", distance))
                            .font(.caption)
                    }
                    .padding()
                    .background(Color(hex: "#9E9E9E").opacity(0.3))
                }
                .frame(width: 260)
                .background(Color(hex: "#E3F2FD"))
                .cornerRadius(16)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if let walkId = msg.walkId {
                walkListener = appState.db.collection("walks").document(walkId).addSnapshotListener { snapshot, _ in
                    if let doc = try? snapshot?.data(as: Walk.self) {
                        liveWalk = doc
                    }
                }
            }
        }
        .onDisappear {
            walkListener?.remove()
        }
    }
    
    private func generateSnapshot() {
        var coords: [CLLocationCoordinate2D] = []
        if let walkCoords = liveWalk?.coordinates, !walkCoords.isEmpty {
            coords = walkCoords.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        } else if let msgCoords = msg.coordinates, !msgCoords.isEmpty {
            coords = msgCoords.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        
        guard coords.count > 1 else { return }
        
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        
        var mapRect = polyline.boundingMapRect
        mapRect = mapRect.insetBy(dx: -mapRect.width * 0.2, dy: -mapRect.height * 0.2)
        
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(mapRect)
        options.size = CGSize(width: 280, height: 160)
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot, error == nil else {
                print("Snapshot error: \(String(describing: error))")
                return
            }
            
            let image = snapshot.image
            UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
            image.draw(at: .zero)
            
            if let context = UIGraphicsGetCurrentContext() {
                context.setLineWidth(4.0)
                context.setStrokeColor(UIColor(red: 74/255, green: 144/255, blue: 217/255, alpha: 1.0).cgColor)
                
                let points = coords.map { snapshot.point(for: $0) }
                if let first = points.first {
                    context.move(to: first)
                    for point in points.dropFirst() {
                        context.addLine(to: point)
                    }
                    context.strokePath()
                }
            }
            
            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            DispatchQueue.main.async {
                self.snapshotImage = finalImage
            }
        }
    }
    
    private func formatElapsedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
