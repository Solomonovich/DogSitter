import os

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/SitterProfileView.swift"

with open(file_path, "r") as f:
    content = f.read()

# Add imports
if "import FirebaseFirestore" not in content:
    content = "import FirebaseFirestore\nimport FirebaseFirestoreSwift\n" + content

# Add the struct
struct_code = """

struct EditProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\\.presentationMode) var presentationMode
    
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
        .environment(\\.layoutDirection, .rightToLeft)
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
                    errorMessage = "שגיאה בשמירת הפרופיל: \\(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}
"""
content += struct_code

with open(file_path, "w") as f:
    f.write(content)

# delete the extra file
extra_file = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/EditProfileView.swift"
if os.path.exists(extra_file):
    os.remove(extra_file)

print("Fixed scope error")
