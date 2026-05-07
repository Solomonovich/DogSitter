import sys

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"
with open(file_path, "r") as f:
    lines = f.readlines()

# Find where PostCardBanner starts
start_idx = -1
for i, line in enumerate(lines):
    if line.startswith("struct PostCardBanner: View {"):
        start_idx = i
        break

if start_idx != -1:
    new_content = lines[:start_idx]
    
    new_code = """struct PostCardBanner: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    var isDetail: Bool = false
    var onClose: (() -> Void)? = nil
    
    @AppStorage("savedPostsString") private var savedPostsString: String = ""
    
    var isSaved: Bool {
        savedPostsString.components(separatedBy: ",").contains(post.id ?? "")
    }
    
    func toggleSave() {
        var ids = savedPostsString.components(separatedBy: ",").filter { !$0.isEmpty }
        if let id = post.id {
            if ids.contains(id) {
                ids.removeAll { $0 == id }
            } else {
                ids.append(id)
            }
            savedPostsString = ids.joined(separator: ",")
        }
    }
    
    var dateString: String {
        let start = post.startDate.dateValue()
        let end = post.endDate.dateValue()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        
        if Calendar.current.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "d MMMM"
            let dayStr = formatter.string(from: start)
            formatter.dateFormat = "HH:mm"
            return "\\(dayStr), \\(formatter.string(from: start)) - \\(formatter.string(from: end))"
        } else {
            formatter.dateFormat = "d MMMM"
            return "\\(formatter.string(from: start)) - \\(formatter.string(from: end))"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // TOP ROW
            HStack(alignment: .top) {
                // 1. FAR RIGHT - Photo
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
                
                // 2. RIGHT - Names
                VStack(alignment: .trailing, spacing: 2) {
                    let nameParts = post.ownerName.components(separatedBy: " ")
                    let firstName = nameParts.first ?? ""
                    let lastName = nameParts.count > 1 ? nameParts.dropFirst().joined(separator: " ") : ""
                    Text(firstName).font(.system(size: 17, weight: .bold)).foregroundColor(Color(white: 0.1))
                    if !lastName.isEmpty {
                        Text(lastName).font(.system(size: 17, weight: .bold)).foregroundColor(Color(white: 0.1))
                    }
                }
                
                Spacer()
                
                // 3. FAR LEFT - Buttons
                HStack(spacing: 16) {
                    if isDetail {
                        Button(action: { onClose?() }) {
                            Circle()
                                .fill(Color(white: 0.9))
                                .frame(width: 30, height: 30)
                                .overlay(Image(systemName: "xmark").foregroundColor(Color(white: 0.3)).font(.system(size: 14, weight: .bold)))
                        }
                    }
                    
                    ShareLink(item: "בדוק את המודעה הזו ב-דוגסיטר!\\nמאת \\(post.ownerName)\\nב-\\(post.address)") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 22))
                            .foregroundColor(Color(white: 0.2))
                    }
                    
                    Button(action: toggleSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 22))
                            .foregroundColor(Color(white: 0.2))
                    }
                }
            }
            
            // DIVIDER
            Rectangle()
                .fill(Color(red: 224/255, green: 224/255, blue: 224/255))
                .frame(height: 1)
                .padding(.vertical, 10)
            
            // SECOND ROW
            VStack(alignment: .trailing, spacing: 4) {
                Text(post.address.components(separatedBy: ",").first ?? post.address)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                
                Text("חיות: \\(post.petIds.count)")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                
                Text(dateString)
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.1))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            
            // PRICE BUBBLE
            HStack {
                Spacer()
                
                let interval = post.payPer == "day" ? "ללילה" : "לשעה"
                let daysCount = max(1, post.endDate.dateValue().timeIntervalSince(post.startDate.dateValue()) / (60 * 60 * 24))
                let total = post.payAmount * (post.payPer == "day" ? daysCount : 1)
                
                HStack(spacing: 8) {
                    Text("₪\\(Int(post.payAmount))/\\(interval)")
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .bold))
                        .environment(\\.layoutDirection, .leftToRight)
                    Text("סה״כ ₪\\(Int(total))")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color(red: 74/255, green: 144/255, blue: 217/255))
                .cornerRadius(20)
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
        .environment(\\.layoutDirection, .rightToLeft)
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
                    Text("\\(pet.ageYears) שנים - \\(pet.name)")
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
        .environment(\\.layoutDirection, .rightToLeft)
    }
}

struct PostDetailSheetView: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    var onClose: () -> Void
    
    @State private var isSubmitting = false
    @State private var loadedPets: [Pet] = []
    
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
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .environment(\\.layoutDirection, .rightToLeft)
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
                .padding(.bottom, geometry.safeAreaInsets.bottom + 16)
                .padding(.top, 16)
                .background(Color(white: 0.96))
            }
        }
        .task {
            loadedPets = await appState.fetchPets(for: post.petIds)
        }
    }
}
"""
    new_content.append(new_code)
    with open(file_path, "w") as f:
        f.writelines(new_content)
    print("Successfully replaced components")
else:
    print("Could not find PostCardBanner")
