import re

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"
with open(file_path, "r") as f:
    content = f.read()

# Find the start of `var body: some View {` inside `PostCardBanner`
# It starts around line 489. 
# We will replace from `    var body: some View {` to `    }\n}\n\nenum BehaviorStatus {`

pattern = r"(?<=    var body: some View \{).*?(?=^\}\n\nenum BehaviorStatus \{)"
match = re.search(pattern, content, re.DOTALL | re.MULTILINE)

if not match:
    print("Could not find PostCardBanner body")
    import sys
    sys.exit(1)

new_body = """
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
    """

content = content[:match.start()] + new_body + content[match.end():]
with open(file_path, "w") as f:
    f.write(content)

print("Banner successfully updated.")
