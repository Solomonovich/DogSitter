import SwiftUI

struct PostDetailView: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    
    @State private var showConfirm = false
    @State private var isSubmitting = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Owner Info
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: post.ownerPhotoURL ?? "person.fill").resizable().padding().foregroundColor(.gray))
                    
                    VStack(alignment: .leading) {
                        Text(post.ownerName)
                            .font(.title2.bold())
                        Text(post.address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Dates and Service
                HStack {
                    VStack(alignment: .leading) {
                        Text("תאריכים")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(post.startDate.dateValue(), style: .date) - \(post.endDate.dateValue(), style: .date)")
                            .font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("סוג שירות")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(post.mappedSittingType.rawValue)
                            .font(.headline)
                    }
                }
                
                if let pickup = post.pickupType {
                    Divider()
                    HStack {
                        if pickup == "dropOff" {
                            Image(systemName: "car.fill").foregroundColor(.blue)
                            Text("בעל הכלב יביא את הכלב")
                        } else {
                            Image(systemName: "mappin.and.ellipse").foregroundColor(.red)
                            Text("המטפל יאסוף מ: \(post.pickupAddress ?? "לא צוין")")
                        }
                    }
                    .font(.headline)
                }
                
                Divider()
                
                Text("הכלבים")
                    .font(.title2.bold())
                
                ForEach(pets) { pet in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            PetAvatarCircle(pet: pet)
                            Text(pet.name)
                                .font(.title3.bold())
                        }
                        
                        let infoString = "\(pet.breed.joined(separator: ", ")) • בן \(pet.ageYears) ו-\(pet.ageMonths) חודשים • \(pet.weight) ק״מ • \(pet.sex)"
                        Text(infoString)
                            .font(.subheadline)
                        
                        HStack {
                            Label(pet.isMicrochipped ? "יש שבב" : "אין שבב", systemImage: "memorychip")
                            Spacer()
                            Label(pet.isNeutered ? "מסורס/מעוקרת" : "לא מחוסן", systemImage: "scissors")
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                        
                        // Behavior
                        VStack(alignment: .leading, spacing: 4) {
                            Text("התנהגות:")
                                .font(.caption.bold())
                            Text("עם ילדים: \(pet.friendlyWithChildren)")
                            Text("עם כלבים: \(pet.friendlyWithDogs)")
                            Text("עם חתולים: \(pet.friendlyWithCats)")
                        }
                        .font(.caption)
                        
                        if !pet.additionalInfo.isEmpty {
                            Text("מידע נוסף: \(pet.additionalInfo)")
                                .font(.caption)
                                .padding()
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Divider()
                
                // Care Instructions
                Text("הוראות טיפול")
                    .font(.title2.bold())
                
                VStack(alignment: .leading, spacing: 8) {
                    if post.foodProvided {
                        Text("אוכל:")
                            .font(.headline)
                        if let schedule = post.foodSchedule {
                            Text(schedule)
                        }
                    }
                    
                    Text("הליכות: \(post.walksPerDay ?? 0) פעמים ביום, \(post.walkDuration ?? 0) דקות כל פעם.")
                    
                    if let aloneMap = post.aloneTime {
                        ForEach(Array(aloneMap.keys), id: \.self) { petId in
                            if let petName = pets.first(where: { $0.id == petId })?.name {
                                Text("\(petName) יכול להישאר לבד: \(aloneMap[petId] ?? "")")
                            }
                        }
                    }
                    
                    if post.medication {
                        Text("תרופות:")
                            .font(.headline)
                            .foregroundColor(.red)
                        if let medInfo = post.medicationInfo {
                            Text(medInfo)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                
                Divider()
                
                // Payment
                HStack {
                    VStack(alignment: .leading) {
                        Text("תשלום")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("₪\(Int(post.payAmount)) \(post.payPer == "day" ? "ליום" : "לפרויקט")")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                        Text("תשלום יתבצע \(post.payTiming == "perDay" ? "לפי יום" : "בסוף")")
                            .font(.caption)
                    }
                }
                
                Spacer(minLength: 40)
                
                Button(action: {
                    showConfirm = true
                }) {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("אני מעוניין")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .shadow(radius: 5)
                    }
                }
                .disabled(isSubmitting)
                .alert("נשלח לבעל הכלב!", isPresented: $showConfirm) {
                    Button("אישור") {
                        Task {
                            isSubmitting = true
                            do {
                                try await appState.expressInterest(in: post)
                                presentationMode.wrappedValue.dismiss()
                            } catch {
                                appState.activeError = "שגיאה בפנייה לפוסט."
                            }
                            isSubmitting = false
                        }
                    }
                } message: {
                    Text("בעל הכלב יקבל התראה ויחזור אליך בצ'אט אם ישמור על קשר.")
                }
            }
            .padding()
        }
        .background(Color.white.edgesIgnoringSafeArea(.all))
        .environment(\.colorScheme, .light)
        .navigationTitle("פרטי הבקשה")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var pets: [Pet] { appState.pets.filter { post.petIds.contains($0.id ?? "") } }
}

struct PetAvatarCircle: View {
    let pet: Pet
    
    var body: some View {
        Group {
            if let photoStr = pet.mainPhotoURL ?? pet.photoURL, !photoStr.isEmpty, let url = URL(string: photoStr), !photoStr.hasPrefix("pawprint") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Color.gray
                    } else {
                        ProgressView()
                    }
                }
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .overlay(Image(systemName: "pawprint.fill").foregroundColor(.orange))
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
}
