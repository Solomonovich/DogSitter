import SwiftUI
import FirebaseFirestore

struct ChatsListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(white: 0.98).edgesIgnoringSafeArea(.all)
                
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
                .background(group.isActive ? Color(red: 0.94, green: 1.0, blue: 0.94) : Color(white: 0.96))
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
        .background(Color.white)
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
        .background(isApproved ? Color(red: 1.0, green: 0.95, blue: 0.7) : Color.white)
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
        .background(wrapper.chat.approved ? Color(red: 1.0, green: 0.95, blue: 0.7) : Color.white)
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
    
    var otherName: String {
        appState.currentUserRole == .owner ? chatWrapper.chat.sitterName : chatWrapper.chat.ownerName
    }
    
    var body: some View {
        ZStack {
            Color(white: 0.98).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubbleView(msg: msg, currentUserId: appState.currentUser?.id, selectedLightboxURL: $selectedLightboxURL)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
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
                                .background(Color(white: 0.95))
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
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.blue, lineWidth: 1.5))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.white)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showAttachmentMenu {
                            VStack(spacing: 12) {
                            Button(action: {
                                showAttachmentMenu = false
                                if let cid = chatWrapper.chat.id {
                                    Task { await appState.sendWalkMessage(chatId: cid) }
                                }
                            }) {
                                HStack {
                                    Text("הוסף הליכה")
                                        .foregroundColor(Color(white: 0.1))
                                    Image(systemName: "pawprint.fill")
                                        .foregroundColor(Color(white: 0.1))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            
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
                                .background(Color.white)
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
            
            if showAttachmentMenu {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showAttachmentMenu = false
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
            HStack {
                if isMine { Spacer() }
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text(msg.text).bold()
                        Image(systemName: "pawprint.fill")
                    }
                    Text("פיצ'ר זה יגיע בקרוב")
                        .font(.system(size: 12))
                }
                .padding(16)
                .background(Color(red: 0.8, green: 0.9, blue: 1.0))
                .foregroundColor(Color(white: 0.1))
                .clipShape(RoundedCorner(radius: 16, corners: isMine ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]))
                if !isMine { Spacer() }
            }
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
                        .background(isMine ? Color(red: 0.29, green: 0.56, blue: 0.85) : Color(white: 0.94))
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
                Color(white: 0.98).edgesIgnoringSafeArea(.all)
                
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
                                    .background(Color(white: 0.95))
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

