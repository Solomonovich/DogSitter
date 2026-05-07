import re

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"
with open(file_path, "r") as f:
    content = f.read()

# Fix 1: PostCardBanner VStack alignment
content = content.replace("VStack(spacing: 10) {", "VStack(alignment: .trailing, spacing: 10) {")

# Fix 2: Owner name texts
old_names = """                    Text(firstName).font(.system(size: 17, weight: .bold)).foregroundColor(Color(white: 0.1))
                    if !lastName.isEmpty {
                        Text(lastName).font(.system(size: 17, weight: .bold)).foregroundColor(Color(white: 0.1))
                    }"""
new_names = """                    Text(firstName).font(.system(size: 17, weight: .bold)).foregroundColor(Color(white: 0.1))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if !lastName.isEmpty {
                        Text(lastName).font(.system(size: 17, weight: .bold)).foregroundColor(Color(white: 0.1))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }"""
content = content.replace(old_names, new_names)

# Fix 3: Second Row text alignments
old_second_row = """            // SECOND ROW
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
            .frame(maxWidth: .infinity, alignment: .trailing)"""
new_second_row = """            // SECOND ROW
            VStack(alignment: .trailing, spacing: 4) {
                Text(post.address.components(separatedBy: ",").first ?? post.address)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text("חיות: \\(post.petIds.count)")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text(dateString)
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.1))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)"""
content = content.replace(old_second_row, new_second_row)

# Fix 4: Price Bubble HStack alignment
# Replace "HStack { Spacer(); ..." with just using frame
old_price = """            // PRICE BUBBLE
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
            }"""
new_price = """            // PRICE BUBBLE
            VStack(alignment: .trailing) {
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
            .frame(maxWidth: .infinity, alignment: .trailing)"""
content = content.replace(old_price, new_price)

# Fix 5: PostDetailSheetView Dog Card tap
old_sheet = """    @State private var isSubmitting = false
    @State private var loadedPets: [Pet] = []
    
    var body: some View {"""
new_sheet = """    @State private var isSubmitting = false
    @State private var loadedPets: [Pet] = []
    @State private var selectedPet: Pet? = nil
    
    var body: some View {"""
content = content.replace(old_sheet, new_sheet)

old_dog_cards = """                        // SECTION 2 - DOG CARDS
                        ForEach(loadedPets) { pet in
                            DogCardView(pet: pet, post: post)
                                .padding(.horizontal, 16)
                        }"""
new_dog_cards = """                        // SECTION 2 - DOG CARDS
                        ForEach(loadedPets) { pet in
                            DogCardView(pet: pet, post: post)
                                .padding(.horizontal, 16)
                                .onTapGesture {
                                    selectedPet = pet
                                }
                        }"""
content = content.replace(old_dog_cards, new_dog_cards)

old_sheet_end = """        .task {
            loadedPets = await appState.fetchPets(for: post.petIds)
        }
    }
}"""
new_sheet_end = """        .task {
            loadedPets = await appState.fetchPets(for: post.petIds)
        }
        .sheet(item: $selectedPet) { pet in
            PetDetailOverlayView(pet: pet)
        }
    }
}

struct PetDetailOverlayView: View {
    let pet: Pet
    @Environment(\\.presentationMode) var presentationMode
    
    var ageString: String {
        if pet.ageMonths > 0 {
            return "\\(pet.ageYears) שנים ו-\\(pet.ageMonths) חודשים"
        }
        return "\\(pet.ageYears) שנים"
    }
    
    var body: some View {
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
            .environment(\\.layoutDirection, .leftToRight) // Force X on left
            
            ScrollView {
                VStack(spacing: 20) {
                    if let urls = pet.photoURLs, !urls.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(urls, id: \\.self) { urlString in
                                    if let url = URL(string: urlString) {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image {
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            }
                                        }
                                        .frame(width: 250, height: 250)
                                        .cornerRadius(16)
                                        .clipped()
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .environment(\\.layoutDirection, .rightToLeft)
                    }
                    
                    VStack(alignment: .trailing, spacing: 16) {
                        // Basic Info
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(pet.name).font(.title2.bold())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(pet.breed.joined(separator: ", ")).foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Divider()
                            HStack(spacing: 12) {
                                Text(ageString).font(.body)
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                            HStack(spacing: 12) {
                                Text("\\(pet.weight) ק״ג").font(.body)
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                            HStack(spacing: 12) {
                                Text(pet.sex).font(.body)
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 5)
                        
                        // Medical
                        Text("מידע רפואי").font(.headline.bold()).padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 12) {
                                Text(pet.isMicrochipped ? "יש שבב ✅" : "אין שבב ❌").font(.body)
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                            HStack(spacing: 12) {
                                Text(pet.isNeutered ? "מסורס ✅" : "לא מסורס ❌").font(.body)
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 5)
                        
                        // Behavior
                        Text("התנהגות").font(.headline.bold()).padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack {
                                Spacer()
                                Text(pet.friendlyWithChildren)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(pet.friendlyWithChildren == "כן מאוד" ? Color.green.opacity(0.2) : (pet.friendlyWithChildren == "לפעמים" ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)))
                                    .cornerRadius(8)
                                Text("ידידותי לילדים")
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                            HStack {
                                Spacer()
                                Text(pet.friendlyWithDogs)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(pet.friendlyWithDogs == "כן מאוד" ? Color.green.opacity(0.2) : (pet.friendlyWithDogs == "לפעמים" ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)))
                                    .cornerRadius(8)
                                Text("ידידותי לכלבים")
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                            HStack {
                                Spacer()
                                Text(pet.friendlyWithCats)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(pet.friendlyWithCats == "כן מאוד" ? Color.green.opacity(0.2) : (pet.friendlyWithCats == "לפעמים" ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)))
                                    .cornerRadius(8)
                                Text("ידידותי לחתולים")
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 5)
                        
                        if !pet.additionalInfo.isEmpty {
                            Text("מידע נוסף").font(.headline.bold()).padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(pet.additionalInfo)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .background(Color(.systemGray6))
                                .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    .environment(\\.layoutDirection, .rightToLeft)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}
"""
content = content.replace(old_sheet_end, new_sheet_end)

with open(file_path, "w") as f:
    f.write(content)
print("Fixes applied successfully")
