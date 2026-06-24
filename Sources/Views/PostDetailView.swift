import SwiftUI

struct PostDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
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
                        .fill(theme.color.surfaceSecondary)
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: post.ownerPhotoURL ?? "person.fill").resizable().padding().foregroundStyle(theme.color.textSecondary))

                    VStack(alignment: .leading) {
                        Text(post.ownerName)
                            .font(theme.typography.title2)
                        Text(post.address)
                            .font(.subheadline)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                
                Divider()
                
                // Dates and Service
                HStack {
                    VStack(alignment: .leading) {
                        Text("תאריכים")
                            .font(.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        Text("\(post.startDate.dateValue(), style: .date) - \(post.endDate.dateValue(), style: .date)")
                            .font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("סוג שירות")
                            .font(.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        Label(post.mappedPostType.displayName, systemImage: post.mappedPostType.iconName)
                            .font(.headline)
                            .foregroundStyle(post.mappedPostType.chipTint)
                    }
                }
                
                if let pickup = post.pickupType {
                    Divider()
                    HStack {
                        if pickup == "dropOff" {
                            Image(systemName: "car.fill").foregroundStyle(theme.color.accent)
                            Text("בעל הכלב יביא את הכלב")
                        } else {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(theme.color.error)
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
                                .background(theme.color.warning.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
                        }
                    }
                    .padding()
                    .background(theme.color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
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
                            .foregroundStyle(theme.color.error)
                        if let medInfo = post.medicationInfo {
                            Text(medInfo)
                                .padding()
                                .background(theme.color.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
                        }
                    }
                }
                
                Divider()
                
                // Payment
                HStack {
                    VStack(alignment: .leading) {
                        Text("תשלום")
                            .font(.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        Text("₪\(Int(post.payAmount)) \(post.mappedPostType.perUnitLabel)")
                            .font(theme.typography.title2)
                            .foregroundStyle(theme.color.success)
                        Text(post.mappedPostType == .overnight
                             ? "החיוב מתבצע בסיום האירוח (\(post.nightsCount) לילות)"
                             : "החיוב מתבצע על כל טיול")
                            .font(.caption)
                    }
                }
                
                Spacer(minLength: 40)
                
                Button(action: {
                    showConfirm = true
                }) {
                    if isSubmitting {
                        LottieProgressView(size: 36)
                    } else {
                        Text("אני מעוניין")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)
                .alert("נשלח לבעל הכלב!", isPresented: $showConfirm) {
                    Button("אישור") {
                        Task {
                            // F-18: require a verified email to express interest.
                            guard appState.requireVerifiedEmail() else { return }
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
        .background(theme.color.background.edgesIgnoringSafeArea(.all))
        .navigationTitle("פרטי הבקשה")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var pets: [Pet] { appState.pets.filter { post.petIds.contains($0.id ?? "") } }
}

struct PetAvatarCircle: View {
    @Environment(\.theme) private var theme
    let pet: Pet

    private var validURLString: String? {
        guard let photoStr = pet.mainPhotoURL ?? pet.photoURL,
              !photoStr.isEmpty, !photoStr.hasPrefix("pawprint") else { return nil }
        return photoStr
    }

    var body: some View {
        CachedAsyncImage(validURLString, contentMode: .fill, targetSize: 100) {
            Circle()
                .fill(theme.color.surfaceSecondary)
                .overlay(Image(systemName: "pawprint.fill").foregroundStyle(theme.color.accent))
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
        .overlay(Circle().stroke(theme.color.surface, lineWidth: 2))
    }
}
