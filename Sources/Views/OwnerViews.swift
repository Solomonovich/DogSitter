import SwiftUI
import FirebaseAuth
import GoogleSignIn

struct OwnerProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: theme.spacing.lg) {
                    if let user = appState.currentUser {
                        VStack(spacing: theme.spacing.xs) {
                            Circle()
                                .fill(theme.color.surfaceSecondary)
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: user.photoURL ?? "person.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(theme.spacing.lg)
                                        .foregroundStyle(theme.color.textSecondary)
                                )
                            Text(user.name)
                                .font(theme.typography.title)
                            Text(user.username)
                                .font(theme.typography.subheadline)
                                .foregroundStyle(theme.color.textSecondary)
                            Text(user.address ?? "")
                                .font(theme.typography.subheadline)

                            NavigationLink(destination: EditProfileView()) {
                                Text("ערוך פרופיל")
                                    .font(theme.typography.subheadline)
                                    .padding(.horizontal, theme.spacing.lg)
                                    .padding(.vertical, theme.spacing.xs)
                                    .background(theme.color.accent)
                                    .foregroundStyle(theme.color.textOnAccent)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, theme.spacing.xxs)

                            NavigationLink(destination: ThemePickerView()) {
                                Label("מראה ותצוגה", systemImage: "paintbrush.fill")
                                    .font(theme.typography.subheadline)
                                    .foregroundStyle(theme.color.accent)
                            }
                            .padding(.top, theme.spacing.xxs)
                        }
                        .padding(.top)

                        Divider().overlay(theme.color.separator)

                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            Text("החיות שלי")
                                .sectionHeader()
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: theme.spacing.md) {
                                    ForEach(appState.pets) { pet in
                                        PetSquareCard(pet: pet)
                                    }

                                    NavigationLink(destination: AddPetView()) {
                                        VStack(spacing: theme.spacing.xs) {
                                            Image(systemName: "plus")
                                                .font(.largeTitle)
                                            Text("הוסף חיה")
                                                .font(theme.typography.headline)
                                        }
                                        .foregroundStyle(theme.color.accent)
                                        .frame(width: 120, height: 120)
                                        .background(
                                            RoundedRectangle(cornerRadius: theme.radius.card)
                                                .strokeBorder(theme.color.accent, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        Divider().overlay(theme.color.separator)
                            .padding(.vertical)

                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            HStack {
                                Text("פוסטים פעילים")
                                    .font(theme.typography.headline)
                                Spacer()
                                Text("פוסטים: \(appState.myActivePosts.count)")
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                            .padding(.horizontal)

                            if appState.myActivePosts.isEmpty {
                                Text("אין פוסטים פעילים")
                                    .font(theme.typography.subheadline)
                                    .foregroundStyle(theme.color.textSecondary)
                                    .padding(.horizontal)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: theme.spacing.md) {
                                        ForEach(appState.myActivePosts) { post in
                                            PostSquareCard(post: post)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        Spacer(minLength: theme.spacing.xl)

                        Button("התנתק") {
                            do {
                                GIDSignIn.sharedInstance.signOut()
                                try Auth.auth().signOut()
                            } catch {
                                print("Error signing out: \(error)")
                            }
                        }
                        .buttonStyle(DestructiveButtonStyle(fullWidth: false))
                        .padding(.bottom, theme.spacing.lg)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.background.edgesIgnoringSafeArea(.all))
            .navigationTitle("הפרופיל שלי")
        }
    }
}

struct PetSquareCard: View {
    @Environment(\.theme) private var theme
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
                CachedAsyncImage(
                    (pet.mainPhotoURL ?? pet.photoURL).flatMap { getValidURL(from: $0)?.absoluteString },
                    contentMode: .fill,
                    targetSize: 240
                ) {
                    petPlaceholder
                }
                .frame(width: 120, height: 120)
                .clipped()

                Text(pet.name)
                    .font(theme.typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.xxs)
                    .background(Color.black.opacity(0.6))
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        }
    }

    private var petPlaceholder: some View {
        ZStack {
            theme.color.surfaceSecondary
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(34)
                .foregroundStyle(theme.color.accent)
        }
        .frame(width: 120, height: 120)
    }
}

struct PostSquareCard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    let post: Post

    private var dogNames: String {
        appState.pets
            .filter { post.petIds.contains($0.id ?? "") }
            .map(\.name)
            .joined(separator: ", ")
    }

    var body: some View {
        NavigationLink(destination: EditPostView(postToEdit: post)) {
            VStack(spacing: theme.spacing.xs) {
                Image(systemName: "doc.text.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .foregroundStyle(theme.color.accent)

                Text(dogNames.isEmpty ? "כלבים" : dogNames)
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.color.textPrimary)
                    .lineLimit(1)

                Text("₪\(Int(post.payAmount))")
                    .font(theme.typography.subheadline)
                    .foregroundStyle(theme.color.success)
                    .bold()
            }
            .frame(width: 120, height: 120)
            .background(theme.color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        }
    }
}

struct AddPetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.theme) private var theme

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
                                        .font(theme.typography.caption)
                                }
                                .frame(width: slotSize, height: slotSize)
                                .background(theme.color.surfaceSecondary)
                                .foregroundStyle(theme.color.accent)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
                            }
                        }
                    }
                }
                .frame(height: gridHeight, alignment: .top)
                .animation(.easeInOut, value: currentTotal)
                .padding(.vertical, 8)
                
                if currentTotal > 0 {
                    Text("לחיצה ארוכה על תמונה תגדיר אותה כתמונה ראשית ⭐")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.textSecondary)
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
                    .foregroundStyle(theme.color.error)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let succ = successMessage {
                Text(succ)
                    .foregroundStyle(theme.color.success)
                    .bold()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button(action: savePet) {
                if isUploading {
                    LottieProgressView(size: 36)
                } else {
                    Text("שמור")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(name.isEmpty || ageYears.isEmpty || isUploading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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
                    self.errorMessage = "שגיאה בשמירת פרטי הכלב. אנא נסה שוב."
                    self.isUploading = false
                }
            }
        }
    }
}

struct PhotoSlotView: View {
    @Environment(\.theme) private var theme
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
                } else if let urlString = imageURL {
                    CachedAsyncImage(urlString, contentMode: .fill, targetSize: size * 2) {
                        ZStack {
                            theme.color.surfaceSecondary
                            LottieProgressView(size: 36)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))

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
