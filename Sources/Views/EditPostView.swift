import SwiftUI
import MapKit
import FirebaseFirestore

struct EditPostView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.theme) private var theme

    let postToEdit: Post
    
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400)
    @State private var selectedPetIds: Set<String> = []
    
    @State private var pickupType = "dropOff"
    @State private var pickupAddress = ""
    
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    
    @State private var foodProvided = false
    @State private var preMadeBags = false
    @State private var foodGrams = ""
    
    @State private var walksPerDay = 2
    @State private var walkDuration = 30
    
    @State private var aloneTime = "1-4 שעות"
    let aloneOptions = ["פחות משעה", "1-4 שעות", "4-7 שעות", "הוראות מיוחדות"]
    @State private var aloneSpecial = ""
    
    @State private var medicationNeeded = false
    @State private var medNotes = ""
    
    @State private var postDescription = ""
    @State private var paymentAmount = ""

    @State private var isPublishing = false
    @State private var isDeleting = false
    @State private var showDeleteAlert = false

    /// The post type is fixed at creation (it determines the pricing model), so edit
    /// shows it read-only rather than letting the owner switch.
    private var postType: PostType { postToEdit.mappedPostType }
    
    var body: some View {
        Form {
            Section(header: Text("סוג השירות")) {
                HStack {
                    Label(postType.displayName, systemImage: postType.iconName)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    Text("לא ניתן לשינוי")
                        .font(theme.typography.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            Section(header: Text("תיאור")) {
                ZStack(alignment: .topTrailing) {
                    if postDescription.isEmpty {
                        Text("ספר למטפלים על הכלב שלך, על הבית שלך, ועל מה שחשוב לך...")
                            .foregroundColor(Color(.placeholderText))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: Binding(
                        get: { postDescription },
                        set: { newValue in
                            if newValue.count <= 500 {
                                postDescription = newValue
                            } else {
                                postDescription = String(newValue.prefix(500))
                            }
                        }
                    ))
                    .frame(minHeight: 120)
                }
                Text("\(postDescription.count)/500")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Section(header: Text("תאריכים")) {
                DatePicker("התחלה", selection: $startDate, displayedComponents: .date)
                DatePicker("סיום", selection: $endDate, displayedComponents: .date)
            }
            
            if postType == .overnight {
                Section(header: Text("איסוף או הבאה?")) {
                    Picker("איסוף", selection: $pickupType) {
                        Text("בעל הכלב יביא").tag("dropOff")
                        Text("המטפל יאסוף").tag("pickUp")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if pickupType == "pickUp" {
                        AddressAutocompleteField(placeholder: "כתובת לאיסוף", text: $pickupAddress)
                    }
                }
            }
            
            Section(header: Text("מי הכלבים?")) {
                List {
                    if appState.pets.isEmpty {
                        Text("טרם הוספת בעלי חיים לפרופיל")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(appState.pets) { pet in
                            MultipleSelectionRow(title: pet.name, isSelected: selectedPetIds.contains(pet.id ?? "")) {
                                guard let petId = pet.id else { return }
                                if selectedPetIds.contains(petId) {
                                    selectedPetIds.remove(petId)
                                } else {
                                    selectedPetIds.insert(petId)
                                }
                            }
                        }
                    }
                }
            }
            
            Section(header: Text(postType == .walking ? "אוכל וטיולים" : "אוכל")) {
                Toggle("אני מספק אוכל", isOn: $foodProvided)
                if foodProvided {
                    Toggle("שקיות מוכנות מראש?", isOn: $preMadeBags)
                    if !preMadeBags {
                        HStack {
                            Text("כמות בארוחה (גרם):")
                            Spacer()
                            TextField("גרם", text: $foodGrams).keyboardType(.decimalPad).frame(width: 80)
                        }
                    }
                }

                if postType == .walking {
                    Stepper("מספר טיולים ביום: \(walksPerDay)", value: $walksPerDay, in: 1...10)
                    Stepper("משך טיול: \(walkDuration) דק׳", value: $walkDuration, in: 10...120, step: 5)
                }
            }

            if postType == .overnight {
                Section(header: Text("זמן לבד")) {
                    Picker("כמה זמן הכלב יכול להישאר לבד?", selection: $aloneTime) {
                        ForEach(aloneOptions, id: \.self) { Text($0) }
                    }
                    if aloneTime == "הוראות מיוחדות" {
                        TextField("פרט כאן...", text: $aloneSpecial)
                    }
                }
            }
            
            Section(header: Text("בריאות וכללי")) {
                Toggle("צריך תרופות?", isOn: $medicationNeeded)
                if medicationNeeded {
                    TextField("פרט על התרופות...", text: $medNotes)
                }
            }
            
            Section(header: Text("תשלום")) {
                HStack {
                    Text(postType == .walking ? "מחיר לטיול (₪):" : "מחיר ללילה (₪):")
                    TextField("₪", text: $paymentAmount).keyboardType(.numberPad)
                }
                Text(postType == .walking
                     ? "החיוב מתבצע על כל טיול שמתבצע."
                     : "החיוב מתבצע בסיום האירוח: מספר הלילות × המחיר.")
                    .font(theme.typography.footnote)
                    .foregroundStyle(theme.color.textSecondary)
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

            Section {
                Button(action: saveChanges) {
                    if isPublishing {
                        LottieProgressView(size: 36)
                    } else {
                        Text("שמור שינויים")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isPublishing || isDeleting)

                Button(action: { showDeleteAlert = true }) {
                    if isDeleting {
                        LottieProgressView(size: 36)
                    } else {
                        Text("מחק פוסט")
                    }
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(isPublishing || isDeleting)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .navigationTitle("ערוך פוסט")
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("מחיקת פוסט"),
                message: Text("האם אתה בטוח שברצונך למחוק את הפוסט?"),
                primaryButton: .destructive(Text("מחק")) {
                    deletePost()
                },
                secondaryButton: .cancel(Text("ביטול"))
            )
        }
        .onAppear {
            loadInitialData()
        }
    }
    
    private func loadInitialData() {
        postDescription = postToEdit.description ?? ""
        startDate = postToEdit.startDate.dateValue()
        endDate = postToEdit.endDate.dateValue()
        selectedPetIds = Set(postToEdit.petIds)
        
        pickupType = postToEdit.pickupType ?? "dropOff"
        pickupAddress = postToEdit.pickupAddress ?? ""
        
        foodProvided = postToEdit.foodProvided
        let foodSched = postToEdit.foodSchedule ?? ""
        if foodSched == "שקיות מוכנות מראש" {
            preMadeBags = true
        } else if foodSched.contains("גרם בארוחה") {
            preMadeBags = false
            foodGrams = foodSched.replacingOccurrences(of: " גרם בארוחה", with: "")
        }
        
        walksPerDay = postToEdit.walksPerDay ?? 2
        walkDuration = postToEdit.walkDuration ?? 30
        
        if let petId = selectedPetIds.first, let aloneMap = postToEdit.aloneTime, let aloneVal = aloneMap[petId] {
            if aloneOptions.contains(aloneVal) {
                aloneTime = aloneVal
            } else {
                aloneTime = "הוראות מיוחדות"
                aloneSpecial = aloneVal
            }
        }
        
        medicationNeeded = postToEdit.medication
        medNotes = postToEdit.medicationInfo ?? ""
        
        paymentAmount = String(Int(postToEdit.payAmount))
    }
    
    private func saveChanges() {
        guard !selectedPetIds.isEmpty else {
            errorMessage = "אנא בחר לפחות כלב אחד"
            return
        }
        
        if paymentAmount.isEmpty {
            errorMessage = "אנא הזן סכום תשלום"
            return
        }
        
        if pickupType == "pickUp" && pickupAddress.isEmpty {
            errorMessage = "נא להזין כתובת לאיסוף"
            return
        }
        
        isPublishing = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                // Ensure geocoding fallback if Apple Maps fails for the owner's main address
                let geocoder = CLGeocoder()
                var lat: Double = 32.0853
                var lon: Double = 34.7818
                
                if let addr = appState.currentUser?.address {
                    if let placemarks = try? await geocoder.geocodeAddressString(addr), let location = placemarks.first?.location {
                        lat = location.coordinate.latitude
                        lon = location.coordinate.longitude
                    }
                }
                
                var finalFood = ""
                if foodProvided {
                    finalFood = preMadeBags ? "שקיות מוכנות מראש" : "\(foodGrams) גרם בארוחה"
                }
                
                let isWalking = postType == .walking
                let finalAlone = aloneTime == "הוראות מיוחדות" ? aloneSpecial : aloneTime
                var aloneDict: [String: String] = [:]
                if !isWalking {
                    for pid in selectedPetIds { aloneDict[pid] = finalAlone }
                }

                var updatedPost = postToEdit
                updatedPost.description = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedPost.petIds = Array(selectedPetIds)
                updatedPost.startDate = Timestamp(date: startDate)
                updatedPost.endDate = Timestamp(date: endDate)
                updatedPost.foodProvided = foodProvided
                updatedPost.foodSchedule = finalFood.isEmpty ? nil : finalFood
                updatedPost.walksPerDay = isWalking ? walksPerDay : nil
                updatedPost.walkDuration = isWalking ? walkDuration : nil
                updatedPost.aloneTime = isWalking ? nil : aloneDict
                updatedPost.medication = medicationNeeded
                updatedPost.medicationInfo = medicationNeeded ? medNotes : nil
                updatedPost.payAmount = Double(paymentAmount) ?? 0
                // postType is immutable in edit; keep payPer in sync with it.
                updatedPost.postType = postType.rawValue
                updatedPost.payPer = postType.payPerRaw
                updatedPost.payTiming = "endOfStay"
                updatedPost.pickupType = isWalking ? nil : pickupType
                updatedPost.pickupAddress = (!isWalking && pickupType == "pickUp") ? pickupAddress : nil
                updatedPost.latitude = lat
                updatedPost.longitude = lon
                
                try await appState.updatePost(updatedPost)
                
                await MainActor.run {
                    self.successMessage = "הפוסט עודכן בהצלחה!"
                    self.isPublishing = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "שגיאה בעדכון הפוסט. נסה שוב"
                    self.isPublishing = false
                }
            }
        }
    }
    
    private func deletePost() {
        isDeleting = true
        Task {
            do {
                if let id = postToEdit.id {
                    try await appState.deletePost(id)
                }
                await MainActor.run {
                    self.isDeleting = false
                    self.presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "שגיאה במחיקת הפוסט."
                    self.isDeleting = false
                }
            }
        }
    }
}
