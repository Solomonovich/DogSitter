import SwiftUI

struct SitterHomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var searchService = AddressSearchService()
    
    @State private var addressSearch = ""
    @State private var selectedTypes: Set<PostType> = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header / Search Bubble
                    VStack(alignment: .leading, spacing: 16) {
                        Text("מצא כלבים לשמור עליהם")
                            .font(.title2.bold())
                        
                        // Address Search
                        VStack(alignment: .leading) {
                            TextField("הכנס אזור או כתובת", text: $searchService.searchQuery)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            
                            if !searchService.completions.isEmpty {
                                ScrollView {
                                    VStack(alignment: .leading) {
                                        ForEach(searchService.completions, id: \.title) { comp in
                                            Button(action: {
                                                searchService.searchQuery = comp.title
                                                searchService.completions = []
                                            }) {
                                                VStack(alignment: .leading) {
                                                    Text(comp.title)
                                                        .foregroundColor(.primary)
                                                    Text(comp.subtitle)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.vertical, 4)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 150)
                                .background(Color.white)
                                .cornerRadius(10)
                                .shadow(radius: 2)
                            }
                        }
                        
                        // Sitting Types Multi-select
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(PostType.allCases) { type in
                                    Button(action: {
                                        if selectedTypes.contains(type) {
                                            selectedTypes.remove(type)
                                        } else {
                                            selectedTypes.insert(type)
                                        }
                                    }) {
                                        Label(type.displayName, systemImage: type.iconName)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedTypes.contains(type) ? Color.blue : Color(.systemGray5))
                                            .foregroundColor(selectedTypes.contains(type) ? .white : .primary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                        
                        NavigationLink(destination: BrowsePostsView()) {
                            Text("חפש")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.1), radius: 10)
                    .padding()
                    
                    // Reviews Carousel
                    VStack(alignment: .leading) {
                        Text("ביקורות אחרונות")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(appState.reviews) { review in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: review.ownerPhotoURL ?? "person.crop.circle")
                                                .font(.largeTitle)
                                                .foregroundColor(.gray)
                                            Text(review.ownerName)
                                                .font(.subheadline.bold())
                                        }
                                        Text(review.text)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding()
                                    .frame(width: 250, height: 120)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(15)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Service Cards
                    VStack(alignment: .leading) {
                        Text("השירותים שלנו")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(PostType.allCases) { type in
                                VStack(spacing: 12) {
                                    Label(type.displayName, systemImage: type.iconName)
                                        .font(.headline)
                                        .foregroundStyle(type.chipTint)

                                    NavigationLink(destination: BrowsePostsView()) { // Should pass filter
                                        Text("חפש \(type.displayName)")
                                            .font(.caption.bold())
                                            .padding(8)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding()
                                .frame(height: 100)
                                .background(Color.white)
                                .cornerRadius(15)
                                .shadow(color: Color.black.opacity(0.05), radius: 5)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // About Us Placeholder
                    VStack {
                        Text("אודותינו")
                            .font(.headline)
                        Text("דוגסיטר היא הפלטפורמה המובילה למציאת מטפלים ודוגווקרים מוסמכים בסביבתך. כל המטפלים שלנו עוברים סינון קפדני.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .padding(.top, 20)
                    
                }
            }
            .navigationBarHidden(true)
        }
    }
}
