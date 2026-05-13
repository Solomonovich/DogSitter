import SwiftUI
import MapKit
import CoreLocation

struct BrowsePostsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedPost: Post?
    @State private var sitterLocation: CLLocationCoordinate2D?
    @State private var hasGeocoded = false
    @State private var selectedSittingType: String = "הכל"
    @State private var selectedPetCount: String = "הכל"
    
    let collapsedHeight: CGFloat = 400
    let expandedHeight: CGFloat = (UIScreen.main.bounds.height - 83) * 0.8
    let fullHeight: CGFloat = UIScreen.main.bounds.height - 100
    
    @State private var isShowingPostDetail: Bool = false
    @State private var sheetHeight: CGFloat = 400
    @State private var previousSheetHeight: CGFloat = 400
    @State private var detailDragOffset: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 400
    
    @State private var selectedPostIndex: Int = 0
    @State private var previousPostIndex: Int = 0
    @State private var mapCenter: CLLocationCoordinate2D?
    
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
    
    var mapAnnotations: [MKPointAnnotation] {
        sortedPosts.compactMap { post in
            guard let lat = post.latitude, let lon = post.longitude else { return nil }
            let ann = MKPointAnnotation()
            ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            ann.title = post.ownerName
            ann.subtitle = post.id
            return ann
        }
    }
    
    var currentSelectedPostID: String? {
        guard !isShowingPostDetail else { 
            return selectedPost?.id 
        }
        guard sheetHeight <= collapsedHeight + 50 else { 
            return nil 
        }
        return sortedPosts.indices.contains(selectedPostIndex) ? sortedPosts[selectedPostIndex].id : nil
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(
                centerCoordinate: $mapCenter,
                annotations: mapAnnotations,
                selectedAnnotationID: currentSelectedPostID,
                onAnnotationTapped: { ann in
                    if let id = ann.subtitle, let post = sortedPosts.first(where: { $0.id == id }) {
                        if let idx = sortedPosts.firstIndex(where: { $0.id == post.id }) {
                            selectedPostIndex = idx
                        }
                    }
                },
                onMapTapped: {
                    if !isShowingPostDetail {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            sheetHeight = collapsedHeight
                        }
                    }
                }
            )
                .ignoresSafeArea()
            
            if !isShowingPostDetail {
                HStack {
                    Spacer()
                    FilterBarView(selectedSittingType: $selectedSittingType, selectedPetCount: $selectedPetCount)
                }
                .padding(.top, 50)
                .zIndex(2)
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    if !isShowingPostDetail {
                        VStack {
                            Capsule()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: 40, height: 5)
                                .padding(.top, 8)
                                .padding(.bottom, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if dragStartHeight == 0 { dragStartHeight = sheetHeight }
                                    sheetHeight = max(collapsedHeight, min(expandedHeight, dragStartHeight - value.translation.height))
                                }
                                .onEnded { value in
                                    dragStartHeight = 0
                                    let velocity = -value.velocity.height
                                    let midpoint = (collapsedHeight + expandedHeight) / 2
                                    
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        if velocity > 300 || sheetHeight > midpoint {
                                            sheetHeight = expandedHeight
                                        } else if velocity < -300 || sheetHeight < midpoint {
                                            sheetHeight = collapsedHeight
                                        } else {
                                            if sheetHeight > midpoint {
                                                sheetHeight = expandedHeight
                                            } else {
                                                sheetHeight = collapsedHeight
                                            }
                                        }
                                    }
                                }
                        )
                        
                        if sheetHeight <= collapsedHeight + 50 {
                            if !sortedPosts.isEmpty {
                                TabView(selection: $selectedPostIndex) {
                                    ForEach(Array(sortedPosts.enumerated()), id: \.element.id) { index, post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                            .padding(.bottom, 16)
                                            .onTapGesture {
                                                openPost(post)
                                            }
                                            .tag(index)
                                    }
                                }
                                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                                .onChange(of: selectedPostIndex) { newIndex in
                                    guard newIndex < sortedPosts.count else { return }
                                    let post = sortedPosts[newIndex]
                                    if let lat = post.latitude, let lon = post.longitude {
                                        mapCenter = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                    }
                                }
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
                                                openPost(post)
                                            }
                                    }
                                }
                                .padding(.bottom, 83)
                            }
                        }
                    } else if let post = selectedPost {
                        PostDetailSheetView(post: post, onClose: {
                            closePost()
                        })
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        detailDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    let velocity = value.velocity.height
                                    if detailDragOffset > 100 || velocity > 300 {
                                        detailDragOffset = 0
                                        closePost()
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            detailDragOffset = 0
                                        }
                                    }
                                }
                        )
                    }
                }
                .frame(height: sheetHeight)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.15), radius: 10, y: -5)
                .offset(y: isShowingPostDetail ? max(0, detailDragOffset) : 0)
            }
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .onAppear {
            if !hasGeocoded {
                hasGeocoded = true
                let geocoder = CLGeocoder()
                if let currentUser = appState.currentUser, let address = currentUser.address {
                    geocoder.geocodeAddressString(address) { placemarks, error in
                        if let loc = placemarks?.first?.location {
                            self.sitterLocation = loc.coordinate
                            self.mapCenter = loc.coordinate
                        }
                    }
                }
            }
        }
    }
    
    func openPost(_ post: Post) {
        previousPostIndex = selectedPostIndex
        if let idx = sortedPosts.firstIndex(where: { $0.id == post.id }) {
            selectedPostIndex = idx
        }
        previousSheetHeight = sheetHeight
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sheetHeight = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowingPostDetail = true
            selectedPost = post
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                sheetHeight = expandedHeight
            }
        }
    }
    
    func closePost() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sheetHeight = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowingPostDetail = false
            selectedPost = nil
            selectedPostIndex = previousPostIndex
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                sheetHeight = previousSheetHeight
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
    @State private var isExpanded: Bool = false
    
    let sittingTypes = ["הכל", "דוגווקינג", "פנסיון", "ביקור בית", "אילוף"]
    let petCounts = ["הכל", "1", "2", "3+"]
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 12) {
                    // Sitting Type
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("סוג שירות")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sittingTypes, id: \.self) { type in
                                    Text(type)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedSittingType == type ? Color.blue : Color(.systemGray6))
                                        .foregroundColor(selectedSittingType == type ? .white : .primary)
                                        .clipShape(Capsule())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedSittingType = type
                                            }
                                        }
                                }
                            }
                        }
                        .environment(\.layoutDirection, .rightToLeft)
                    }
                    
                    // Pet count
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("מספר כלבים")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(petCounts, id: \.self) { count in
                                    Text(count)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedPetCount == count ? Color.blue : Color(.systemGray6))
                                        .foregroundColor(selectedPetCount == count ? .white : .primary)
                                        .clipShape(Capsule())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedPetCount = count
                                            }
                                        }
                                }
                            }
                        }
                        .environment(\.layoutDirection, .rightToLeft)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 20)),
                    removal: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 20))
                ))
            }

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isExpanded ? .white : .gray)
                    .frame(width: 40, height: 40)
                    .background(isExpanded ? Color.blue : Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 16)
        }
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
            return "\(startStr) - \(endStr)"
        } else {
            formatter.dateFormat = "d MMMM"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // TOP ROW
            HStack(alignment: .top) {
                // LEFT - icons
                HStack(spacing: 12) {
                    Button(action: toggleSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 22))
                            .foregroundColor(Color(white: 0.2))
                    }
                    
                    ShareLink(item: "בדוק את המודעה הזו ב-דוגסיטר!\nמאת \(post.ownerName)\nב-\(post.address)") {
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
                
                Spacer()
                
                // RIGHT - name then photo
                HStack(alignment: .top, spacing: 8) {
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
                    
                    if let photo = post.ownerPhotoURL, photo.hasPrefix("http") {
                        AsyncImage(url: URL(string: photo)) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.3))
                                .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
                            .frame(width: 52, height: 52)
                    }
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
                
                Text("חיות: \(post.petIds.count)")
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
                        Text("סה״כ ₪\(Int(total))")
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("₪\(Int(post.payAmount))/\(interval)")
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
        .environment(\.layoutDirection, .leftToRight)
    }
}

enum BehaviorStatus {
    case positive, negative, neutral
}

struct BehaviorPill: View {
    let title: String
    let status: BehaviorStatus
    
    var bgColor: Color {
        switch status {
        case .positive: return Color(red: 232/255, green: 245/255, blue: 233/255)
        case .negative: return Color(red: 255/255, green: 235/255, blue: 238/255)
        case .neutral: return Color(red: 255/255, green: 243/255, blue: 224/255)
        }
    }
    var textColor: Color {
        switch status {
        case .positive: return Color(red: 46/255, green: 125/255, blue: 50/255)
        case .negative: return Color(red: 198/255, green: 40/255, blue: 40/255)
        case .neutral: return Color(red: 230/255, green: 81/255, blue: 0/255)
        }
    }
    var icon: String {
        switch status {
        case .positive: return "✓"
        case .negative: return "✗"
        case .neutral: return "~"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 10, weight: .bold))
            Text(title)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundColor(textColor)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(bgColor)
        .cornerRadius(10)
    }
}

func getBehaviorStatus(for text: String) -> BehaviorStatus {
    if text == "כן מאוד" { return .positive }
    if text == "לא בכלל" { return .negative }
    return .neutral
}

struct DogCardView: View {
    let pet: Pet
    let post: Post
    
    var body: some View {
        VStack(spacing: 12) {
            // TOP ROW
            HStack(alignment: .top) {
                // FAR RIGHT
                Group {
                    if let photoStr = pet.mainPhotoURL, !photoStr.isEmpty, let url = URL(string: photoStr) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else if phase.error != nil {
                                Image(systemName: "pawprint.fill").foregroundColor(.gray)
                            } else {
                                ProgressView()
                            }
                        }
                    } else {
                        Image(systemName: "pawprint.fill").foregroundColor(.gray)
                    }
                }
                .frame(width: 52, height: 52)
                .background(Color(white: 0.9))
                .clipShape(Circle())
                
                // LEFT OF PHOTO
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(pet.ageYears) שנים - \(pet.name)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(white: 0.1))
                    
                    Text(pet.sex)
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.4))
                }
                
                Spacer()
            }
            
            // BEHAVIOR ROW
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BehaviorPill(title: "תרופות", status: post.medication ? .negative : .positive)
                    BehaviorPill(title: "נחמד לילדים", status: getBehaviorStatus(for: pet.friendlyWithChildren))
                    BehaviorPill(title: "נחמד לכלבים", status: getBehaviorStatus(for: pet.friendlyWithDogs))
                    
                    if !pet.friendlyWithCats.isEmpty && pet.friendlyWithCats != "לא רלוונטי" {
                        BehaviorPill(title: "נחמד לחתולים", status: getBehaviorStatus(for: pet.friendlyWithCats))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct PostDetailSheetView: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    var onClose: () -> Void
    
    @State private var isSubmitting = false
    @State private var loadedPets: [Pet] = []
    @State private var selectedPet: Pet? = nil
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // FIXED TOP BANNER
                PostCardBanner(post: post, isDetail: true, onClose: onClose)
                    .background(Color.white.shadow(color: .black.opacity(0.05), radius: 5, y: 5))
                    .zIndex(1)
                
                // SCROLLABLE CONTENT
                ScrollView {
                    VStack(spacing: 12) {
                        // SECTION 1 - USER NOTES
                        if let desc = post.description, !desc.isEmpty {
                            VStack {
                                Text(desc)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(white: 0.33))
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .background(Color(white: 0.94))
                                    .cornerRadius(12)
                            }
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        } else {
                            Spacer().frame(height: 16)
                        }
                        
                        // SECTION 2 - DOG CARDS
                        ForEach(loadedPets) { pet in
                            DogCardView(pet: pet, post: post)
                                .padding(.horizontal, 16)
                                .onTapGesture {
                                    selectedPet = pet
                                }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
                .background(Color(white: 0.96))
                
                // FIXED BOTTOM BUTTON
                Button(action: {
                    Task {
                        isSubmitting = true
                        try? await appState.expressInterest(in: post)
                        isSubmitting = false
                        onClose()
                    }
                }) {
                    if isSubmitting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("אני מעוניין")
                    }
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(red: 74/255, green: 144/255, blue: 217/255))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 83 + 16)
                .padding(.top, 16)
                .background(Color(white: 0.96))
            }
        }
        .task {
            loadedPets = await appState.fetchPets(for: post.petIds)
        }
        .sheet(item: $selectedPet) { pet in
            PetDetailOverlayView(pet: pet, post: post)
        }
    }
}

struct PetDetailOverlayView: View {
    let pet: Pet
    let post: Post
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedImageURL: String? = nil
    
    var ageString: String {
        if pet.ageMonths > 0 {
            return "\(pet.ageYears) שנים ו-\(pet.ageMonths) חודשים"
        }
        return "\(pet.ageYears) שנים"
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(Color(.systemGray3))
                    }
                    Spacer()
                    Text(pet.name)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "xmark.circle.fill").opacity(0)
                }
                .padding()
                .background(Color.white)
                .environment(\.layoutDirection, .leftToRight) // Force X on left
                
                ScrollView {
                    VStack(spacing: 20) {
                        if let urls = pet.photoURLs, !urls.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(urls, id: \.self) { urlString in
                                        if let url = URL(string: urlString) {
                                            AsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                }
                                            }
                                            .frame(width: 250, height: 250)
                                            .cornerRadius(16)
                                            .clipped()
                                            .onTapGesture {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    selectedImageURL = urlString
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .environment(\.layoutDirection, .rightToLeft)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {

                            // 2. Additional Info
                            if !pet.additionalInfo.isEmpty {
                                Text(pet.additionalInfo)
                                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2)) // #333333
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(red: 0.94, green: 0.94, blue: 0.94)) // #F0F0F0
                                    .cornerRadius(16)
                            }
                            
                            // 3. Behavior section
                            Text("התנהגות").font(.headline.bold()).padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("ידידותי לילדים")
                                        .foregroundColor(Color(white: 0.1))
                                    Text(pet.friendlyWithChildren)
                                        .font(.caption.bold())
                                        .foregroundColor(Color(white: 0.1))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(pet.friendlyWithChildren == "כן מאוד" ? Color.green.opacity(0.2) : (pet.friendlyWithChildren == "לפעמים" ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)))
                                        .cornerRadius(8)
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Text("ידידותי לכלבים")
                                        .foregroundColor(Color(white: 0.1))
                                    Text(pet.friendlyWithDogs)
                                        .font(.caption.bold())
                                        .foregroundColor(Color(white: 0.1))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(pet.friendlyWithDogs == "כן מאוד" ? Color.green.opacity(0.2) : (pet.friendlyWithDogs == "לפעמים" ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)))
                                        .cornerRadius(8)
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Text("ידידותי לחתולים")
                                        .foregroundColor(Color(white: 0.1))
                                    Text(pet.friendlyWithCats)
                                        .font(.caption.bold())
                                        .foregroundColor(Color(white: 0.1))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(pet.friendlyWithCats == "כן מאוד" ? Color.green.opacity(0.2) : (pet.friendlyWithCats == "לפעמים" ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)))
                                        .cornerRadius(8)
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 5)
                            
                            // 4. Medical section (LAST)
                            Text("מידע רפואי").font(.headline.bold()).padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(pet.isMicrochipped ? "יש שבב ✅" : "אין שבב ❌")
                                        .foregroundColor(Color(white: 0.1)) // #1A1A1A
                                        .font(.body)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    Text(pet.isNeutered ? "מסורס ✅" : "לא מסורס ❌")
                                        .foregroundColor(Color(white: 0.1)) // #1A1A1A
                                        .font(.body)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    if post.medication {
                                        Text("תרופות: \(post.medicationInfo ?? "")")
                                            .foregroundColor(Color(white: 0.1)) // #1A1A1A
                                            .font(.body)
                                    } else {
                                        Text("ללא תרופות ✅")
                                            .foregroundColor(Color(white: 0.1)) // #1A1A1A
                                            .font(.body)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 5)
                        }
                        .padding(.horizontal)
                        .environment(\.layoutDirection, .rightToLeft)
                    }
                    .padding(.vertical)
                }
                .background(Color(.systemGroupedBackground))
            }
            
            // LIGHTBOX OVERLAY
            if let imageURL = selectedImageURL, let url = URL(string: imageURL) {
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedImageURL = nil
                            }
                        }
                    
                    VStack {
                        HStack {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedImageURL = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding()
                        
                        Spacer()
                        
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ProgressView().tint(.white)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .transition(.opacity)
                .zIndex(100)
                .environment(\.layoutDirection, .leftToRight) // Force X on left
            }
        }
    }
}

