import FirebaseFirestore
import SwiftUI
import FirebaseAuth
import GoogleSignIn

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            Form {
                if let user = appState.currentUser {
                    Section(header: Text("פרטים אישיים")) {
                        HStack {
                            Text("שם מלא")
                            Spacer()
                            Text(user.name).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("שם משתמש")
                            Spacer()
                            Text(user.username).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("כתובת")
                            Spacer()
                            Text(user.address ?? "").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("טלפון")
                            Spacer()
                            Text(user.phone ?? "").foregroundColor(.secondary)
                        }
                    }
                }
                
                
                Section {
                    NavigationLink(destination: EditProfileView()) {
                        Text("ערוך פרופיל")
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
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
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            .navigationTitle("הפרופיל שלי")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ThemeToggleView()
                        .scaleEffect(0.6)
                        .frame(width: 84, height: 36) // scaled down from 140x60
                }
            }
        }
    }
}


struct EditProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
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
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: saveProfile) {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("שמור")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.white)
                        .padding()
                        .background((name.isEmpty || username.isEmpty) ? Color.gray : Color.blue)
                        .cornerRadius(8)
                }
            }
            .disabled(name.isEmpty || username.isEmpty || isSaving)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.top, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
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
                try appState.db.collection("users").document(uid).setData(from: user)
                
                await MainActor.run {
                    appState.currentUser = user // Update local state directly
                    isSaving = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "שגיאה בשמירת הפרופיל: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}
