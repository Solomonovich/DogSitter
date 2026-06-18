import FirebaseFirestore
import SwiftUI
import FirebaseAuth
import GoogleSignIn
import SecurityKit

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                if let user = appState.currentUser {
                    Section(header: Text("פרטים אישיים")) {
                        profileRow("שם מלא", user.name)
                        profileRow("שם משתמש", user.username)
                        profileRow("כתובת", user.address ?? "")
                        profileRow("טלפון", user.phone ?? "")
                    }
                }

                Section {
                    NavigationLink(destination: ThemePickerView()) {
                        Label("מראה ותצוגה", systemImage: "paintbrush.fill")
                            .foregroundStyle(theme.color.accent)
                    }
                }

                Section {
                    NavigationLink(destination: EditProfileView()) {
                        Text("ערוך פרופיל")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.color.accent)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(theme.color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    Button(action: {
                        do {
                            GIDSignIn.sharedInstance.signOut()
                            try Auth.auth().signOut()
                        } catch {
                            print("Error signing out: \(error)")
                        }
                    }) {
                        Text("התנתק")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.color.error)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(theme.color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))

                    // F-27: account deletion (required for App Store compliance).
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Text("מחק חשבון")
                            .font(theme.typography.subheadline)
                            .foregroundStyle(theme.color.error)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.top, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.background.edgesIgnoringSafeArea(.all))
            .navigationTitle("הפרופיל שלי")
            .alert("מחיקת חשבון", isPresented: $showDeleteConfirm) {
                Button("מחק", role: .destructive) {
                    Task { if let msg = await appState.deleteAccount() { deleteErrorMessage = msg } }
                }
                Button("ביטול", role: .cancel) {}
            } message: {
                Text("פעולה זו תמחק את חשבונך לצמיתות ולא ניתן לבטלה.")
            }
            .alert("שגיאה", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("סגור", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(theme.color.textSecondary)
        }
    }
}


struct EditProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.theme) private var theme

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        Form {
            Section(header: Text("פרטים אישיים")) {
                TextField("שם מלא", text: $name)
                TextField("שם משתמש", text: $username)
                TextField("כתובת", text: $address)
                if appState.currentUser?.role == "sitter" {
                    TextField("טלפון", text: $phone)
                        .keyboardType(.phonePad)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(theme.color.error)
                    .multilineTextAlignment(.center)
            }

            Button(action: saveProfile) {
                if isSaving {
                    LottieProgressView(size: 36)
                } else {
                    Text("שמור")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(name.isEmpty || username.isEmpty || isSaving)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.top, theme.spacing.md)
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.background.edgesIgnoringSafeArea(.all))
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("ערוך פרופיל")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let user = appState.currentUser {
                name = user.name
                username = user.username
                address = user.address ?? ""
                phone = user.phone ?? ""
            }
        }
    }
    
    func saveProfile() {
        guard var user = appState.currentUser, let uid = user.id else { return }

        user.name = name
        user.username = username
        user.address = address.isEmpty ? nil : address
        if user.role == "sitter" {
            user.phone = phone.isEmpty ? nil : phone
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                // F-01: write only the allow-listed editable fields instead of a full
                // setData(from:) overwrite, so role / email / reputation can never be
                // mutated from the client. Same fields the edit form exposes.
                try await appState.db.collection("users").document(uid).updateData(
                    ProfileFields.updatePayload(
                        name: name,
                        username: username,
                        address: address,
                        phone: phone,
                        isSitter: user.role == "sitter"
                    )
                )

                await MainActor.run {
                    appState.currentUser = user // Update local state directly
                    isSaving = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    // F-20: do not surface the raw backend error to the user.
                    errorMessage = "שגיאה בשמירת הפרופיל. אנא נסה שוב."
                    isSaving = false
                }
            }
        }
    }
}
