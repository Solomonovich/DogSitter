import SwiftUI
import MapKit
import FirebaseFirestore

// Global Walk Tracker Instance for simplicity in this structure
let sharedWalkTracker = LocationTracker()

struct WalkMessageBubble: View {
    let walkId: String
    var onTap: () -> Void
    
    // In a full implementation, this view would listen to the `/walks/{walkId}` document natively
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Top 2/3: Map Placeholder
                MapContainerView(
                    centerCoordinate: nil,
                    annotations: [],
                    route: [],
                    isFollowingUser: false
                )
                .frame(height: 150)
                .disabled(true)
                
                // Bottom 1/3: Info
                HStack {
                    VStack {
                        Text("זמן הליכה")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("00:00")
                            .font(.caption.bold())
                    }
                    Spacer()
                    VStack {
                        Text("מרחק")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("0.0 ק״מ")
                            .font(.caption.bold())
                    }
                    Spacer()
                    VStack {
                        Text("סטטוס")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("צופה")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(10)
                .background(Color.white)
            }
            .frame(width: 250)
            .cornerRadius(15)
            .shadow(color: .black.opacity(0.1), radius: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PreWalkOverlayView: View {
    @Binding var showPreWalk: Bool
    let chat: Chat
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                MapContainerView(
                    centerCoordinate: sharedWalkTracker.lastLocation?.coordinate,
                    annotations: [],
                    route: [],
                    isFollowingUser: true
                )
                .frame(height: geo.size.height * 0.75)
                .onAppear {
                    sharedWalkTracker.requestAuth()
                }
                
                VStack {
                    Button(action: startWalk) {
                        Text("התחל הליכה")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                    .padding()
                    
                    Button("ביטול") {
                        showPreWalk = false
                    }
                    .foregroundColor(.secondary)
                }
                .frame(height: geo.size.height * 0.25)
                .background(Color.white)
            }
            .edgesIgnoringSafeArea(.all)
        }
        .zIndex(100)
    }
    
    func startWalk() {
        guard let userId = appState.currentUser?.id, let name = appState.currentUser?.name, let chatId = chat.id else { return }
        sharedWalkTracker.startWalk()
        
        let newWalk = Walk(chatId: chatId, postId: chat.postId, sitterId: chat.sitterId, ownerId: chat.ownerId, startTime: Timestamp(date: Date()), endTime: nil, distance: 0, duration: 0, coordinates: [], status: WalkStatus.active.rawValue)
        
        Task {
            do {
                let docRef = try appState.db.collection("walks").addDocument(from: newWalk)
                let walkMsg = ChatMessage(senderId: userId, senderName: name, text: "הליכה החלה", type: MessageType.walk.rawValue, walkId: docRef.documentID)
                let _ = try appState.db.collection("chats").document(chatId).collection("messages").addDocument(from: walkMsg)
                showPreWalk = false
            } catch {
                appState.activeError = "שגיאה ביצירת הליכה."
            }
        }
    }
}

struct ActiveWalkOverlayView: View {
    let chat: Chat
    let activeMsgId: String
    var onClose: () -> Void
    
    @EnvironmentObject var appState: AppState
    @ObservedObject var tracker = sharedWalkTracker
    
    @State private var timeElapsed: Int = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                MapContainerView(
                    centerCoordinate: nil,
                    annotations: [],
                    route: tracker.walkRoute,
                    isFollowingUser: true
                )
                .frame(height: geo.size.height * 0.75)
                
                VStack(spacing: 12) {
                    HStack {
                        VStack {
                            Text("זמן הליכה")
                                .foregroundColor(.secondary)
                            Text(formatTime(timeElapsed))
                                .font(.title.bold())
                        }
                        Spacer()
                        VStack {
                            Text("מרחק שנהלך")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f ק״מ", tracker.walkDistanceKm))
                                .font(.title.bold())
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
                    
                    Button(action: stopWalk) {
                        Text("עצור הליכה")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal)
                }
                .frame(height: geo.size.height * 0.25)
                .background(Color.white)
            }
            .edgesIgnoringSafeArea(.all)
        }
        .onReceive(timer) { _ in
            timeElapsed += 1
            syncLocation()
        }
        .zIndex(100)
    }
    
    func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    
    func syncLocation() {
        // Here we would push Tracker state to Firebase Walk document
    }
    
    func stopWalk() {
        tracker.stopWalk()
        timer.upstream.connect().cancel()
        onClose()
    }
}
