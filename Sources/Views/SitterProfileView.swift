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
            ScrollView {
                VStack(spacing: theme.spacing.lg) {
                    if let user = appState.currentUser {
                        ProfileHeaderCard(user: user)
                        ProfileSettingsCard()
                        AccountActionsCard(
                            logout: signOut,
                            deleteTapped: { showDeleteConfirm = true }
                        )
                    }
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.vertical, theme.spacing.lg)
            }
            .screenBackground()
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

    private func signOut() {
        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
        } catch {
            print("Error signing out: \(error)")
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
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                VStack(spacing: theme.spacing.sm) {
                    ThemedInputField(icon: "person", placeholder: "שם מלא", text: $name)
                    ThemedInputField(icon: "at", placeholder: "שם משתמש", text: $username)
                    ThemedInputField(icon: "mappin.and.ellipse", placeholder: "כתובת", text: $address)
                    if appState.currentUser?.role == "sitter" {
                        ThemedInputField(icon: "phone", placeholder: "טלפון", text: $phone, keyboard: .phonePad)
                    }
                }
                .card()

                if let error = errorMessage {
                    Text(error)
                        .font(theme.typography.subheadline)
                        .foregroundStyle(theme.color.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
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
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
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
