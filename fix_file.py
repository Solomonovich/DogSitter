import re

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"

with open(file_path, "r") as f:
    content = f.read()

# Split the content at enum BehaviorStatus
parts = content.split("enum BehaviorStatus {", 1)
bottom_part = "enum BehaviorStatus {" + parts[1]

top_part = """import SwiftUI
import MapKit
import CoreLocation

struct BrowsePostsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedPost: Post?
    @State private var sitterLocation: CLLocationCoordinate2D?
    @State private var hasGeocoded = false
    @State private var selectedSittingType: String = "הכל"
    @State private var selectedPetCount: String = "הכל"
    
    @State private var currentHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    
    @State private var selectedPostIndex: Int = 0
    @State private var mapCenter: CLLocationCoordinate2D?
    
    let minHeight: CGFloat = 220
    let midHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    let maxHeight: CGFloat = UIScreen.main.bounds.height - 120
    
    var sheetPosition: SheetPosition {
        if currentHeight <= minHeight + 50 { return .collapsed }
        if currentHeight >= maxHeight - 50 { return .full }
        return .half
    }
    
    enum SheetPosition {
        case collapsed, half, full
    }
    
    var sortedPosts: [Post] {
        var posts = appState.posts
        
        if selectedSittingType != "הכל" {
            posts = posts.filter { $0.mappedSittingType.rawValue == selectedSittingType }
        }
        if selectedPetCount != "הכל" {
            posts = posts.filter { String($0.petIds.count) == selectedPetCount || (selectedPetCount == "3+" && $0.petIds.count >= 3) }
        }
        
        guard let location = sitterLocation else { return posts }
        
        return posts.sorted { p1, p2 in
            let loc1 = CLLocation(latitude: p1.latitude ?? 0, longitude: p1.longitude ?? 0)
            let loc2 = CLLocation(latitude: p2.latitude ?? 0, longitude: p2.longitude ?? 0)
            let myLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
            
            let dist1 = loc1.distance(from: myLoc)
            let dist2 = loc2.distance(from: myLoc)
            
            let maxDist = 50000.0
            let distScore1 = max(0, 1 - (dist1 / maxDist))
            let distScore2 = max(0, 1 - (dist2 / maxDist))
            
            let maxTime = 30 * 24 * 3600.0
            let t1 = p1.startDate.dateValue().timeIntervalSinceNow
            let t2 = p2.startDate.dateValue().timeIntervalSinceNow
            let timeScore1 = max(0, 1 - (t1 / maxTime))
            let timeScore2 = max(0, 1 - (t2 / maxTime))
            
            let score1 = (distScore1 * 0.6) + (timeScore1 * 0.4)
            let score2 = (distScore2 * 0.6) + (timeScore2 * 0.4)
            
            return score1 > score2
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(posts: sortedPosts, selectedPost: $selectedPost, mapCenter: $mapCenter)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) {
                        currentHeight = minHeight
                    }
                }
            
            FilterBarView(selectedSittingType: $selectedSittingType, selectedPetCount: $selectedPetCount)
                .padding(.top, 50)
            
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.vertical, 10)
                
                if currentHeight <= minHeight + 50 {
                    if !sortedPosts.isEmpty {
                        TabView(selection: $selectedPostIndex) {
                            ForEach(Array(sortedPosts.enumerated()), id: \\.element.id) { index, post in
                                PostCardBanner(post: post)
                                    .padding(.horizontal)
                                    .tag(index)
                                    .onTapGesture {
                                        selectedPost = post
                                    }
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    } else {
                        Text("אין פוסטים שמתאימים לסינון")
                            .foregroundColor(.gray)
                            .padding()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(sortedPosts) { post in
                                PostCardBanner(post: post)
                                    .padding(.horizontal)
                                    .onTapGesture {
                                        selectedPost = post
                                    }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                Spacer()
            }
            .frame(height: currentHeight)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(24, corners: [.topLeft, .topRight])
            .shadow(radius: 10)
            .offset(y: UIScreen.main.bounds.height - currentHeight)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = currentHeight - value.translation.height
                        if newHeight > 100 && newHeight < UIScreen.main.bounds.height {
                            currentHeight = newHeight
                        }
                    }
                    .onEnded { value in
                        let velocity = -value.velocity.height
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if velocity > 500 {
                                currentHeight = maxHeight
                            } else if velocity < -500 {
                                currentHeight = minHeight
                            } else {
                                if currentHeight > midHeight + 100 {
                                    currentHeight = maxHeight
                                } else if currentHeight < midHeight - 100 {
                                    currentHeight = minHeight
                                } else {
                                    currentHeight = midHeight
                                }
                            }
                        }
                    }
            )
        }
        .fullScreenCover(item: $selectedPost) { post in
            PostDetailSheetView(post: post, onClose: {
                selectedPost = nil
            })
        }
        .onAppear {
            if !hasGeocoded {
                hasGeocoded = true
                let geocoder = CLGeocoder()
                if let currentUser = appState.currentUser {
                    geocoder.geocodeAddressString(currentUser.address) { placemarks, error in
                        if let loc = placemarks?.first?.location {
                            self.sitterLocation = loc.coordinate
                            self.mapCenter = loc.coordinate
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct FilterBarView: View {
    @Binding var selectedSittingType: String
    @Binding var selectedPetCount: String
    
    let sittingTypes = ["הכל", "דוגווקינג", "פנסיון", "ביקור בית", "אילוף"]
    let petCounts = ["הכל", "1", "2", "3+"]
    
    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(sittingTypes, id: \\.self) { type in
                        Text(type)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedSittingType == type ? Color.blue : Color(.systemGray6))
                            .foregroundColor(selectedSittingType == type ? .white : .primary)
                            .cornerRadius(20)
                            .onTapGesture {
                                selectedSittingType = type
                            }
                    }
                }
                .padding(.horizontal)
            }
            .environment(\\.layoutDirection, .rightToLeft)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(petCounts, id: \\.self) { count in
                        Text(count)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedPetCount == count ? Color.blue : Color(.systemGray6))
                            .foregroundColor(selectedPetCount == count ? .white : .primary)
                            .cornerRadius(20)
                            .onTapGesture {
                                selectedPetCount = count
                            }
                    }
                }
                .padding(.horizontal)
            }
            .environment(\\.layoutDirection, .rightToLeft)
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.95))
        .cornerRadius(16)
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }
}

struct PostCardBanner: View {
    let post: Post
    var isDetail: Bool = false
    var onClose: (() -> Void)? = nil
    @AppStorage("savedPostIDs") private var savedPostIDsData: String = ""
    
    var savedPostIDs: [String] {
        savedPostIDsData.isEmpty ? [] : savedPostIDsData.components(separatedBy: ",")
    }
    
    var isSaved: Bool {
        savedPostIDs.contains(post.id ?? "")
    }
    
    func toggleSave() {
        var ids = savedPostIDs
        if let id = post.id {
            if ids.contains(id) {
                ids.removeAll { $0 == id }
            } else {
                ids.append(id)
            }
            savedPostIDsData = ids.joined(separator: ",")
        }
    }
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        let start = post.startDate.dateValue()
        let end = post.endDate.dateValue()
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "d MMMM, HH:mm"
            let startStr = formatter.string(from: start)
            formatter.dateFormat = "HH:mm"
            let endStr = formatter.string(from: end)
            return "\\(startStr) - \\(endStr)"
        } else {
            formatter.dateFormat = "d MMMM"
            return "\\(formatter.string(from: start)) - \\(formatter.string(from: end))"
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // TOP ROW
            HStack(alignment: .top) {
                // LEFT SIDE - Icons
                VStack(alignment: .leading) {
                    HStack {
                        Button(action: toggleSave) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 22))
                                .foregroundColor(Color(white: 0.2))
                        }
                        
                        ShareLink(item: "בדוק את המודעה הזו ב-דוגסיטר!\\nמאת \\(post.ownerName)\\nב-\\(post.address)") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 22))
                                .foregroundColor(Color(white: 0.2))
                        }
                        
                        if isDetail {
                            Button(action: { onClose?() }) {
                                Circle()
                                    .fill(Color(white: 0.9))
                                    .frame(width: 30, height: 30)
                                    .overlay(Image(systemName: "xmark").foregroundColor(Color(white: 0.3)).font(.system(size: 14, weight: .bold)))
                            }
                        }
                    }
                }
                
                Spacer()
                
                // RIGHT SIDE - Name + Photo
                HStack(alignment: .top, spacing: 8) {
                    // Name stack to the LEFT of the photo
                    VStack(alignment: .trailing, spacing: 2) {
                        let nameParts = post.ownerName.components(separatedBy: " ")
                        let firstName = nameParts.first ?? ""
                        let lastName = nameParts.count > 1 ? nameParts.dropFirst().joined(separator: " ") : ""
                        
                        Text(firstName)
                            .bold()
                            .font(.system(size: 17))
                            .foregroundColor(Color(white: 0.1))
                            .multilineTextAlignment(.trailing)
                        
                        if !lastName.isEmpty {
                            Text(lastName)
                                .bold()
                                .font(.system(size: 17))
                                .foregroundColor(Color(white: 0.1))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    // Photo on the FAR RIGHT
                    Group {
                        if let photo = post.ownerPhotoURL, photo.hasPrefix("http") {
                            AsyncImage(url: URL(string: photo)) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else if phase.error != nil {
                                    Image(systemName: "person.fill").foregroundColor(.gray)
                                } else {
                                    ProgressView()
                                }
                            }
                        } else {
                            Image(systemName: "person.fill").foregroundColor(.gray)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
                }
            }
            
            // DIVIDER
            Rectangle()
                .fill(Color(red: 224/255, green: 224/255, blue: 224/255))
                .frame(height: 1)
                .padding(.vertical, 10)
            
            // SECOND ROW (all content right-aligned)
            VStack(alignment: .trailing, spacing: 8) {
                Text(post.address.components(separatedBy: ",").first ?? post.address)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text("חיות: \\(post.petIds.count)")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text(dateString)
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.1))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // PRICE BUBBLE - Push to RIGHT with Spacer
                HStack {
                    Spacer()
                    let interval = post.payPer == "day" ? "ללילה" : "לשעה"
                    let daysCount = max(1, post.endDate.dateValue().timeIntervalSince(post.startDate.dateValue()) / (60 * 60 * 24))
                    let total = post.payAmount * (post.payPer == "day" ? daysCount : 1)
                    
                    HStack(spacing: 8) {
                        Text("סה״כ ₪\\(Int(total))")
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("₪\\(Int(post.payAmount))/\\(interval)")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color(red: 74/255, green: 144/255, blue: 217/255))
                    .cornerRadius(20)
                }
            }
            
            // PICKUP ROW
            if let pickup = post.pickupType {
                HStack {
                    Text(pickup == "dropOff" ? "🏠 בעל הכלב יביא" : "🚗 המטפל יאסוף")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 229/255, green: 57/255, blue: 53/255))
                    Spacer()
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(isDetail ? Color.white : Color(red: 242/255, green: 242/255, blue: 247/255))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

"""

new_content = top_part + bottom_part

with open(file_path, "w") as f:
    f.write(new_content)

print("Recovered file and applied banner changes perfectly!")
