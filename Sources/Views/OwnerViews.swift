import SwiftUI
import FirebaseAuth
import GoogleSignIn

struct OwnerProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let user = appState.currentUser {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: user.photoURL ?? "person.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .padding()
                                        .foregroundColor(.gray)
                                )
                            Text(user.name)
                                .font(.title)
                                .bold()
                            Text(user.username)
                                .foregroundColor(.secondary)
                            Text(user.address ?? "")
                                .font(.subheadline)
                                
                            NavigationLink(destination: EditProfileView()) {
                                Text("ערוך פרופיל")
                                    .font(.subheadline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(20)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top)
                        
                        Divider()
                        
                        VStack(alignment: .leading) {
                            Text("החיות שלי")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(appState.pets) { pet in
                                        PetSquareCard(pet: pet)
                                    }
                                    
                                    NavigationLink(destination: AddPetView()) {
                                        VStack {
                                            Image(systemName: "plus")
                                                .font(.largeTitle)
                                                .foregroundColor(.blue)
                                            Text("הוסף לחיה")
                                                .font(.headline)
                                                .foregroundColor(.blue)
                                        }
                                        .frame(width: 120, height: 120)
                                        .background(
                                            RoundedRectangle(cornerRadius: 15)
                                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                                .foregroundColor(.blue)
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical)
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("פוסטים פעילים")
                                    .font(.headline)
                                Spacer()
                                Text("פוסטים: \(appState.myActivePosts.count)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal)
                            
                            if appState.myActivePosts.isEmpty {
                                Text("אין פוסטים פעילים")
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(appState.myActivePosts) { post in
                                            PostSquareCard(post: post)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        Spacer(minLength: 40)
                        
                        Button("התנתק") {
                            do {
                                GIDSignIn.sharedInstance.signOut()
                                try Auth.auth().signOut()
                            } catch {
                                print("Error signing out: \(error)")
                            }
                        }
                        .padding()
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("הפרופיל שלי")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ThemeToggleView()
                        .scaleEffect(0.6)
                        .frame(width: 84, height: 36)
                }
            }
        }
    }
}

struct PetSquareCard: View {
    let pet: Pet
    
    private func getValidURL(from urlString: String) -> URL? {
        if urlString.hasPrefix("pawprint") { return nil }
        
        var finalString = urlString
        
        if finalString.contains("dogsitter/pets/") {
            let components = finalString.components(separatedBy: "dogsitter/pets/")
            if components.count > 1 {
                let publicIdPath = "dogsitter/pets/" + components[1]
                finalString = "https://res.cloudinary.com/dns0htaph/image/upload/\(publicIdPath)"
                
                if !finalString.lowercased().hasSuffix(".jpg") && !finalString.lowercased().hasSuffix(".png") {
                    finalString += ".jpg"
                }
            }
        }
        
        return URL(string: finalString)
    }
    
    var body: some View {
        NavigationLink(destination: AddPetView(petToEdit: pet)) {
            ZStack(alignment: .bottom) {
                if let urlString = pet.mainPhotoURL ?? pet.photoURL, let url = getValidURL(from: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if let error = phase.error {
                            let _ = print("Failed to load: \(url.absoluteString) - Error: \(error)")
                            VStack {
                                Spacer()
                                Image(systemName: "pawprint.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(20)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            .frame(width: 120, height: 120)
                            .background(Color(.systemGray6))
                        } else {
                            LottieProgressView(size: 36)
                                .frame(width: 120, height: 120)
                                .background(Color(.systemGray6))
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipped()
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "pawprint.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .frame(width: 120, height: 120)
                    .background(Color(.systemGray6))
                }
                
                Text(pet.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
            }
            .frame(width: 120, height: 120)
            .cornerRadius(15)
        }
    }
}

struct PostSquareCard: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    
    var body: some View {
        NavigationLink(destination: EditPostView(postToEdit: post)) {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .foregroundColor(.blue)
                
                let dogNames = appState.pets.filter { post.petIds.contains($0.id ?? "") }.map { $0.name }.joined(separator: ", ")
                Text(dogNames.isEmpty ? "כלבים" : dogNames)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("₪\(Int(post.payAmount))")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .bold()
            }
            .frame(width: 120, height: 120)
            .background(Color(.systemGray6))
            .cornerRadius(15)
        }
    }
}

struct AddPetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    var petToEdit: Pet?
    
    @State private var name = ""
    @State private var ageYears = ""
    @State private var ageMonths = ""
    @State private var weight = ""
    @State private var sex = "זכר"
    @State private var selectedBreed = "מעורב"
    @State private var isMicrochipped = false
    @State private var isNeutered = false
    @State private var kidsFriendly = "לפעמים"
    @State private var dogsFriendly = "לפעמים"
    @State private var catsFriendly = "לפעמים"
    @State private var additionalInfo = ""
    @State private var hasLoadedInitialData = false
    
    // Photo states
    @State private var localPhotos: [UIImage] = []
    @State private var remotePhotoURLs: [String] = []
    @State private var pendingDeletions: [String] = []
    @State private var mainPhotoIndex: Int = 0
    @State private var tappedSlotIndex: Int = 0
    
    @State private var showActionSheet = false
    @State private var showImagePicker = false
    @State private var imageSourceType: ImagePickerSourceType = .photoLibrary
    @State private var pickedImages: [UIImage] = []
    
    @State private var isUploading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    
    let friendlyOptions = ["כן מאוד", "לפעמים", "לא בכלל"]
    let totalSlots = 6
    
    var body: some View {
        Form {
            Section(header: Text("תמונות של החיה (עד 6)")) {
                let currentTotal = localPhotos.count + remotePhotoURLs.count
                let totalVisibleSlots = min(currentTotal + 1, totalSlots)
                let slotSize = (UIScreen.main.bounds.width - 60) / 3
                let rowCount = totalVisibleSlots <= 3 ? 1 : 2
                let gridHeight = CGFloat(rowCount) * slotSize + (rowCount == 2 ? 10 : 0)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(0..<totalVisibleSlots, id: \.self) { index in
                        if index < remotePhotoURLs.count {
                            // Remote Photo
                            PhotoSlotView(imageURL: remotePhotoURLs[index], image: nil, isMain: index == mainPhotoIndex, size: slotSize) {
                                let removedURL = remotePhotoURLs[index]
                                remotePhotoURLs.remove(at: index)
                                pendingDeletions.append(extractPublicId(from: removedURL))
                                adjustMainIndexAfterRemoval(removedIndex: index)
                            }
                            .onLongPressGesture {
                                mainPhotoIndex = index
                            }
                        } else if index < currentTotal {
                            // Local Photo
                            let localIdx = index - remotePhotoURLs.count
                            PhotoSlotView(imageURL: nil, image: localPhotos[localIdx], isMain: index == mainPhotoIndex, size: slotSize) {
                                localPhotos.remove(at: localIdx)
                                adjustMainIndexAfterRemoval(removedIndex: index)
                            }
                            .onLongPressGesture {
                                mainPhotoIndex = index
                            }
                        } else if index == currentTotal {
                            // Empty Slot to add
                            Button(action: {
                                tappedSlotIndex = index
                                showActionSheet = true
                            }) {
                                VStack {
                                    Image(systemName: "plus")
                                        .font(.title)
                                    Text("הוסף תמונה")
                                        .font(.caption)
                                }
                                .frame(width: slotSize, height: slotSize)
                                .background(Color(.systemGray6))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .frame(height: gridHeight, alignment: .top)
                .animation(.easeInOut, value: currentTotal)
                .padding(.vertical, 8)
                
                if currentTotal > 0 {
                    Text("לחיצה ארוכה על תמונה תגדיר אותה כתמונה ראשית ⭐")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("פרטי החיה")) {
                TextField("שם הכלב *", text: $name)
                HStack {
                    TextField("שנים *", text: $ageYears).keyboardType(.numberPad)
                    Text("שנים")
                    TextField("חודשים *", text: $ageMonths).keyboardType(.numberPad)
                    Text("חודשים")
                }
                HStack {
                    TextField("משקל (ק״ג)", text: $weight).keyboardType(.decimalPad)
                    Text("ק״ג")
                }
                Picker("מין *", selection: $sex) {
                    Text("זכר").tag("זכר")
                    Text("נקבה").tag("נקבה")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Picker("גזע *", selection: $selectedBreed) {
                    Text("מעורב").tag("מעורב")
                    Text("פודל").tag("פודל")
                    Text("גולדן רטריבר").tag("גולדן רטריבר")
                    Text("לברדור").tag("לברדור")
                }
            }
            
            Section(header: Text("רפואי")) {
                Toggle("יש שבב?", isOn: $isMicrochipped)
                Toggle("מסורס / מעוקרת?", isOn: $isNeutered)
            }
            
            Section(header: Text("התנהגות")) {
                Picker("ידידותי לילדים *", selection: $kidsFriendly) {
                    ForEach(friendlyOptions, id: \.self) { Text($0) }
                }
                Picker("ידידותי לכלבים *", selection: $dogsFriendly) {
                    ForEach(friendlyOptions, id: \.self) { Text($0) }
                }
                Picker("ידידותי לחתולים *", selection: $catsFriendly) {
                    ForEach(friendlyOptions, id: \.self) { Text($0) }
                }
            }
            
            Section(header: Text("מידע נוסף")) {
                TextEditor(text: $additionalInfo)
                    .frame(height: 80)
            }
            
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            if let succ = successMessage {
                Text(succ)
                    .foregroundColor(.green)
                    .bold()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Button(action: savePet) {
                if isUploading {
                    LottieProgressView(size: 80)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("שמור")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(name.isEmpty || ageYears.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(8)
                }
            }
            .disabled(name.isEmpty || ageYears.isEmpty || isUploading)
        }
        .navigationTitle(petToEdit == nil ? "חיה חדשה" : "ערוך חיה")
        .actionSheet(isPresented: $showActionSheet) {
            ActionSheet(title: Text("הוסף תמונה"), buttons: [
                .default(Text("צלם תמונה")) {
                    imageSourceType = .camera
                    showImagePicker = true
                },
                .default(Text("בחר מהגלריה")) {
                    imageSourceType = .photoLibrary
                    showImagePicker = true
                },
                .cancel(Text("ביטול"))
            ])
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: imageSourceType, selectionLimit: totalSlots - (localPhotos.count + remotePhotoURLs.count), selectedImages: $pickedImages)
        }
        .onChange(of: pickedImages) { newImages in
            for img in newImages {
                if (localPhotos.count + remotePhotoURLs.count) < totalSlots {
                    let localIdx = tappedSlotIndex - remotePhotoURLs.count
                    if localIdx >= 0 && localIdx <= localPhotos.count {
                        localPhotos.insert(img, at: localIdx)
                    } else {
                        localPhotos.append(img)
                    }
                }
            }
            pickedImages.removeAll() // reset
        }
        .onAppear {
            guard !hasLoadedInitialData, let p = petToEdit else { return }
            hasLoadedInitialData = true
            
            name = p.name
            ageYears = String(p.ageYears)
            ageMonths = String(p.ageMonths)
            weight = String(p.weight)
            sex = p.sex
            selectedBreed = p.breed.first ?? "מעורב"
            isMicrochipped = p.isMicrochipped
            isNeutered = p.isNeutered
            kidsFriendly = p.friendlyWithChildren
            dogsFriendly = p.friendlyWithDogs
            catsFriendly = p.friendlyWithCats
            additionalInfo = p.additionalInfo
            
            remotePhotoURLs = p.photoURLs ?? []
            if let mainUrl = p.mainPhotoURL, let mainIdx = remotePhotoURLs.firstIndex(of: mainUrl) {
                mainPhotoIndex = mainIdx
            }
        }
    }
    
    private func adjustMainIndexAfterRemoval(removedIndex: Int) {
        if mainPhotoIndex == removedIndex {
            mainPhotoIndex = 0
        } else if mainPhotoIndex > removedIndex {
            mainPhotoIndex -= 1
        }
    }
    
    private func extractPublicId(from url: String) -> String {
        if let range = url.range(of: "dogsitter/pets/") {
            let path = String(url[range.lowerBound...])
            if let dotIndex = path.lastIndex(of: ".") {
                return String(path[..<dotIndex])
            }
            return path
        }
        return url
    }
    
    func savePet() {
        guard let userId = appState.currentUser?.id else { return }
        
        isUploading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                // Determine Pet ID
                let finalPetId = petToEdit?.id ?? appState.db.collection("pets").document().documentID
                var finalPhotoURLs = remotePhotoURLs
                
                // Upload Local Photos Sequentially
                for (idx, image) in localPhotos.enumerated() {
                    let uniqueIndex = remotePhotoURLs.count + idx
                    let url = try await CloudinaryHelper.uploadPhoto(image: image, userId: userId, petId: finalPetId, index: uniqueIndex)
                    finalPhotoURLs.append(url)
                }
                
                // Determine Main Photo URL
                var finalMainPhotoURL: String? = nil
                if !finalPhotoURLs.isEmpty {
                    let safeIndex = min(max(0, mainPhotoIndex), finalPhotoURLs.count - 1)
                    finalMainPhotoURL = finalPhotoURLs[safeIndex]
                }
                // Combine pending deletions
                var finalPending = petToEdit?.pendingDeletion ?? []
                finalPending.append(contentsOf: pendingDeletions)
                let uniquePending = Array(Set(finalPending))
                
                let pet = Pet(id: finalPetId, ownerId: userId, name: name, ageYears: Int(ageYears) ?? 0, ageMonths: Int(ageMonths) ?? 0, weight: Double(weight) ?? 0, sex: sex, breed: [selectedBreed], isMicrochipped: isMicrochipped, isNeutered: isNeutered, friendlyWithChildren: kidsFriendly, friendlyWithDogs: dogsFriendly, friendlyWithCats: catsFriendly, additionalInfo: additionalInfo, photoURL: finalMainPhotoURL, photoURLs: finalPhotoURLs, mainPhotoURL: finalMainPhotoURL, pendingDeletion: uniquePending.isEmpty ? nil : uniquePending)
                
                try await appState.savePet(pet)
                
                await MainActor.run {
                    self.successMessage = "הכלב נשמר בהצלחה!"
                    self.isUploading = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "שגיאה בשמירת פרטי הכלב: \(error.localizedDescription)"
                    self.isUploading = false
                }
            }
        }
    }
}

struct PhotoSlotView: View {
    let imageURL: String?
    let image: UIImage?
    let isMain: Bool
    let size: CGFloat
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let uiImage = image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            Color.red
                        } else {
                            LottieProgressView(size: 36)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .cornerRadius(10)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.black)
                    .background(Color.white.clipShape(Circle()))
            }
            .padding(4)
            .buttonStyle(BorderlessButtonStyle())

            if isMain {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .shadow(radius: 2)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
    }
}
