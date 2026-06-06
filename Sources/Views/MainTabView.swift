import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    
    // Maintain state for selected tab
    @State private var sitterTab: Int = 0
    @State private var ownerTab: Int = 3 // Owner defaults to messages
    
    var body: some View {
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
            .accentColor(.orange)
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
            .accentColor(.blue)
        }
    }
}
