import SwiftUI
import FirebaseFirestore

struct ChatsListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            List {
                if appState.chats.isEmpty {
                    Text("אין לך צ'אטים פתוחים עדיין.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.chats) { chat in
                        NavigationLink(destination: ChatDetailView(chat: chat)) {
                            ChatRowView(chat: chat)
                        }
                        .listRowBackground(chat.approved ? Color.yellow.opacity(0.2) : Color.white)
                    }
                }
            }
            .navigationTitle("הודעות")
        }
    }
}

struct ChatRowView: View {
    @EnvironmentObject var appState: AppState
    let chat: Chat
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading) {
                Text(otherName)
                    .font(.headline)
                if appState.currentUserRole == .owner, let city = chat.sitterCity {
                    Text(city)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Text(chat.lastMessage ?? "...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if appState.currentUserRole == .owner && !chat.approved {
                Button("אשר") {
                    approveChat()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                .buttonStyle(PlainButtonStyle())
            }
            
            if chat.approved {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            }
        }
    }
    
    var otherName: String {
        appState.currentUserRole == .owner ? chat.sitterName : chat.ownerName
    }
    
    func approveChat() {
        Task {
            guard let id = chat.id else { return }
            do {
                try await appState.db.collection("chats").document(id).updateData(["approved": true])
                try await appState.db.collection("posts").document(chat.postId).updateData(["status": "approved", "approvedSitterId": chat.sitterId])
                
                // Send synthetic payment approved message
                let sysMsg = ChatMessage(senderId: "system", senderName: "System", text: "התשלום עבר בהצלחה ✓", type: MessageType.payment.rawValue)
                let _ = try appState.db.collection("chats").document(id).collection("messages").addDocument(from: sysMsg)
            } catch {
                appState.activeError = "שגיאה באישור הטיפול."
            }
        }
    }
}

struct ChatDetailView: View {
    @EnvironmentObject var appState: AppState
    let chat: Chat
    
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var listener: ListenerRegistration?
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubbleView(msg: msg, currentUserId: appState.currentUser?.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { oldValue, newValue in
                        if let last = messages.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
                
                // Input Area
                VStack(spacing: 0) {
                    HStack {
                        TextField("הקלד הודעה...", text: $inputText)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                        
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                        .disabled(inputText.isEmpty)
                    }
                    .padding()
                    .background(Color.white)
                }
            }
        }
        .navigationTitle(appState.currentUserRole == .owner ? chat.sitterName : chat.ownerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(appState.currentUserRole == .owner ? chat.sitterName : chat.ownerName)
                        .font(.headline)
                    if appState.currentUserRole == .owner, let city = chat.sitterCity {
                        Text(city)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .onAppear {
            setupMessageListener()
        }
        .onDisappear {
            listener?.remove()
        }
    }
    
    func setupMessageListener() {
        guard let id = chat.id else { return }
        listener = appState.db.collection("chats").document(id).collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self.messages = docs.compactMap { try? $0.data(as: ChatMessage.self) }
            }
    }
    
    func sendMessage() {
        guard !inputText.isEmpty, let userId = appState.currentUser?.id, let name = appState.currentUser?.name, let chatId = chat.id else { return }
        let msg = ChatMessage(senderId: userId, senderName: name, text: inputText, type: MessageType.text.rawValue)
        
        let textToSend = inputText
        inputText = ""
        
        Task {
            do {
                let _ = try appState.db.collection("chats").document(chatId).collection("messages").addDocument(from: msg)
                try await appState.db.collection("chats").document(chatId).updateData([
                    "lastMessage": textToSend,
                    "lastMessageTime": FieldValue.serverTimestamp()
                ])
            } catch {
                appState.activeError = "שגיאה בשליחת ההודעה."
            }
        }
    }
}

struct ChatBubbleView: View {
    let msg: ChatMessage
    let currentUserId: String?
    
    var body: some View {
        if msg.type == MessageType.payment.rawValue {
            Text(msg.text)
                .font(.caption.bold())
                .padding(10)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(10)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if msg.type == MessageType.walk.rawValue {
            Text("📍 מעקב הליכה החל: הצגת מפות בטא")
                .padding()
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(15)
                .frame(maxWidth: .infinity, alignment: msg.senderId == currentUserId ? .trailing : .leading)
        } else {
            HStack(alignment: .top) {
                if msg.senderId == currentUserId { Spacer() }
                else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: msg.senderId == currentUserId ? .trailing : .leading, spacing: 4) {
                    if msg.senderId != currentUserId {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(msg.senderName)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            if let city = msg.sitterCity, msg.text == "מעוניין לטפל בכלב שלך" {
                                Text(city)
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Text(msg.text)
                        .padding(12)
                        .background(msg.senderId == currentUserId ? Color.orange : Color(.systemGray5))
                        .foregroundColor(msg.senderId == currentUserId ? .white : .primary)
                        .cornerRadius(15)
                }
                if msg.senderId != currentUserId { Spacer() }
            }
        }
    }
}
