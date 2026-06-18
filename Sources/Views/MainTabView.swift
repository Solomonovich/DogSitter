import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    // Maintain state for selected tab
    @State private var sitterTab: Int = 0
    @State private var ownerTab: Int = 3 // Owner defaults to messages
    
    var body: some View {
        Group {
        if appState.currentUserRole == .sitter {
            TabView(selection: $sitterTab) {
                BrowsePostsView()
                    .tabItem {
                        Label("פוסטים", systemImage: "magnifyingglass")
                    }
                    .tag(0)
                
                ChatsListView()
                    .tabItem {
                        Label("הודעות", systemImage: "message")
                    }
                    .tag(1)
                
                ProfileView()
                    .tabItem {
                        Label("פרופיל", systemImage: "person")
                    }
                    .tag(2)
            }
            .tint(theme.color.accent)
        } else {
            TabView(selection: $ownerTab) {
                OwnerProfileView()
                    .tabItem {
                        Label("פרופיל", systemImage: "person")
                    }
                    .tag(0)
                
                AddPetView()
                    .tabItem {
                        Label("חיות", systemImage: "pawprint")
                    }
                    .tag(1)
                
                OwnerCreatePostView(selectedTab: $ownerTab)
                    .tabItem {
                        Label("פוסטים", systemImage: "plus.square")
                    }
                    .tag(2)
                
                ChatsListView()
                    .tabItem {
                        Label("הודעות", systemImage: "message")
                    }
                    .tag(3)
            }
            .tint(theme.color.accent)
        }
        }
        // F-18: one central prompt for the email-verification gate; the action
        // buttons stay visually unchanged and only trigger this when unverified.
        .alert("אימות אימייל נדרש", isPresented: $appState.showEmailVerificationPrompt) {
            Button("שלח קישור אימות") { Task { await appState.resendVerificationEmail() } }
            Button("סגור", role: .cancel) {}
        } message: {
            Text("כדי לבצע פעולה זו יש לאמת את כתובת האימייל שלך. נשלח אליך קישור אימות.")
        }
        .task { await appState.refreshEmailVerification() }
    }
}
