import SwiftUI
import MapKit
import FirebaseFirestore

struct OwnerCreatePostView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppState
    
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
    @State private var paymentPerDay = true
    @State private var paymentTiming = "לפי יום"
    
    @State private var isPublishing = false
    
    var body: some View {
        NavigationView {
            Form {
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
                
                Section(header: Text("אוכל וטיולים")) {
                    Toggle("אני מספק אוכל", isOn: $foodProvided)
                    if foodProvided {
                        Toggle("שקיות מוכנות מראש?", isOn: $preMadeBags)
                        if !preMadeBags {
                            HStack {
                                Text("כמות בארוחה (גרם):")
                                Spacer()
                                TextField("גרם", text: $foodGrams).keyboardType(.numberPad).frame(width: 80)
                            }
                        }
                    }
                    
                    Stepper("מספר טיולים ביום: \(walksPerDay)", value: $walksPerDay, in: 0...10)
                    Stepper("משך טיול: \(walkDuration) דק׳", value: $walkDuration, in: 10...120, step: 5)
                }
                
                Section(header: Text("זמן לבד")) {
                    Picker("כמה זמן הכלב יכול להישאר לבד?", selection: $aloneTime) {
                        ForEach(aloneOptions, id: \.self) { Text($0) }
                    }
                    if aloneTime == "הוראות מיוחדות" {
                        TextField("פרט כאן...", text: $aloneSpecial)
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
                        Text("סכום (₪):")
                        TextField("₪", text: $paymentAmount).keyboardType(.numberPad)
                    }
                    Picker("שיטת תשלום", selection: $paymentPerDay) {
                        Text("לפי יום").tag(true)
                        Text("לפי פרויקט מוגדר").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Picker("מתי לשלם?", selection: $paymentTiming) {
                        Text("לפי יום").tag("לפי יום")
                        Text("תשלום אחד בסוף").tag("תשלום אחד בסוף")
                    }
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
                
                Button(action: publishPost) {
                    if isPublishing {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("פרסם פוסט")
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
                .disabled(selectedPetIds.isEmpty || paymentAmount.isEmpty || isPublishing)
                
            }
            .navigationTitle("פוסט חדש")
        }
    }
    
    func publishPost() {
        guard let currentUser = appState.currentUser, let uid = currentUser.id else { return }
        
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
            
            let finalAloneTime = aloneTime == "הוראות מיוחדות" ? aloneSpecial : aloneTime
            var petAloneMap: [String: String] = [:]
            for pet in selectedPetIds {
                petAloneMap[pet] = finalAloneTime
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
                sittingType: SittingType.overnight.rawValue,
                description: postDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                foodProvided: foodProvided,
                foodSchedule: foodProvided ? (!preMadeBags ? "\(foodGrams) גרם" : "שקיות מוכנות") : nil,
                walksPerDay: walksPerDay,
                walkDuration: walkDuration,
                aloneTime: petAloneMap,
                medication: medicationNeeded,
                medicationInfo: medicationNeeded ? medNotes : nil,
                payAmount: Double(paymentAmount) ?? 0,
                payPer: paymentPerDay ? "day" : "stay",
                payTiming: paymentTiming == "לפי יום" ? "perDay" : "endOfStay",
                pickupType: pickupType,
                pickupAddress: pickupType == "pickUp" ? pickupAddress : nil,
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
                        .foregroundColor(.blue)
                }
            }
        }
        .foregroundColor(.primary)
    }
}
