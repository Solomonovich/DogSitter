import SwiftUI
import MapKit
import FirebaseFirestore

struct OwnerCreatePostView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    @State private var postType: PostType = .walking
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
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("סוג השירות")) {
                    Picker("סוג", selection: $postType) {
                        ForEach(PostType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    Text(postType == .walking
                         ? "המטפל מגיע אליך ומוציא את הכלב. התשלום הוא לפי טיול."
                         : "אתה מביא את הכלב לבית המטפל. התשלום הוא לפי לילה.")
                        .font(theme.typography.footnote)
                        .foregroundStyle(theme.color.textSecondary)
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

                    // The owner specifies how many times to take the dog out only for
                    // Walking posts (that's the billable unit). Overnight walks are at
                    // the sitter's discretion and not charged.
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

                Button(action: publishPost) {
                    if isPublishing {
                        LottieProgressView(size: 36)
                    } else {
                        Text("פרסם פוסט")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(selectedPetIds.isEmpty || paymentAmount.isEmpty || isPublishing)

            }
            .navigationTitle("פוסט חדש")
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    func publishPost() {
        guard let currentUser = appState.currentUser, let uid = currentUser.id else { return }
        // F-18: require a verified email to publish (matches the server-side rule).
        guard appState.requireVerifiedEmail() else { return }

        errorMessage = nil
        successMessage = nil
        
        if selectedPetIds.isEmpty {
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
        
        Task {
            let geocoder = CLGeocoder()
            var lat: Double? = nil
            var lon: Double? = nil
            
            do {
                let addressString = currentUser.address ?? "תל אביב"
                let placemarks = try await geocoder.geocodeAddressString(addressString)
                if let location = placemarks.first?.location {
                    lat = location.coordinate.latitude
                    lon = location.coordinate.longitude
                }
            } catch {
                print("Geocoding unresolvable: \(error)")
            }
            
            if lat == nil || lon == nil {
                lat = 32.0853
                lon = 34.7818
            }
            
            let isWalking = postType == .walking
            let finalAloneTime = aloneTime == "הוראות מיוחדות" ? aloneSpecial : aloneTime
            var petAloneMap: [String: String] = [:]
            if !isWalking {
                for pet in selectedPetIds {
                    petAloneMap[pet] = finalAloneTime
                }
            }

            let newPost = Post(
                ownerId: uid,
                ownerName: currentUser.name,
                ownerPhotoURL: currentUser.photoURL,
                petIds: Array(selectedPetIds),
                address: currentUser.address ?? "ישראל",
                latitude: lat,
                longitude: lon,
                startDate: Timestamp(date: startDate),
                endDate: Timestamp(date: endDate),
                sittingType: (isWalking ? SittingType.walk : SittingType.overnight).rawValue,
                description: postDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                foodProvided: foodProvided,
                foodSchedule: foodProvided ? (!preMadeBags ? "\(foodGrams) גרם" : "שקיות מוכנות") : nil,
                walksPerDay: isWalking ? walksPerDay : nil,
                walkDuration: isWalking ? walkDuration : nil,
                aloneTime: isWalking ? nil : petAloneMap,
                medication: medicationNeeded,
                medicationInfo: medicationNeeded ? medNotes : nil,
                postType: postType.rawValue,
                payAmount: Double(paymentAmount) ?? 0,
                payPer: postType.payPerRaw,
                payTiming: "endOfStay",
                pickupType: isWalking ? nil : pickupType,
                pickupAddress: (!isWalking && pickupType == "pickUp") ? pickupAddress : nil,
                interestedCount: 0,
                status: PostStatus.open.rawValue
            )
            
            do {
                try await appState.createPost(newPost)
                
                await MainActor.run {
                    self.isPublishing = false
                    self.successMessage = "הפוסט פורסם בהצלחה!"
                    self.selectedPetIds.removeAll()
                    self.paymentAmount = ""
                    self.postDescription = ""
                    
                    // Navigate to owner profile
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.selectedTab = 0
                        self.successMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "שגיאה ביצירת פוסט. אנא נסה שוב."
                    self.isPublishing = false
                }
            }
        }
    }
}
    
struct MultipleSelectionRow: View {
    @Environment(\.theme) private var theme
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.color.accent)
                }
            }
        }
        .foregroundStyle(theme.color.textPrimary)
    }
}
