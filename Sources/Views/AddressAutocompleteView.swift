import SwiftUI
import MapKit
import Combine

class AddressSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private var completer: MKLocalSearchCompleter
    private var cancellable: AnyCancellable?
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        
        cancellable = $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    self.completions = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    // Append Israel to the query to strongly bias results
                    self.completer.queryFragment = query + ", ישראל"
                }
            }
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.completions = completer.results
            self.isSearching = false
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isSearching = false
            print("MKLocalSearchCompleter error: \(error.localizedDescription)")
        }
    }
}

struct AddressAutocompleteField: View {
    let placeholder: String
    @Binding var text: String
    
    @StateObject private var viewModel = AddressSearchViewModel()
    @State private var showSuggestions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.gray)
                TextField(placeholder, text: $viewModel.searchQuery, onEditingChanged: { editing in
                    showSuggestions = editing
                })
                .onChange(of: text) { newValue in
                    if viewModel.searchQuery != newValue {
                        viewModel.searchQuery = newValue
                    }
                }
                
                if viewModel.isSearching {
                    ProgressView()
                        .padding(.trailing, 8)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            
            if showSuggestions && !viewModel.completions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.completions, id: \.self) { completion in
                            Button(action: {
                                // Extract the clean title (usually the street address) or the full address
                                let fullAddress = "\(completion.title), \(completion.subtitle)"
                                    .replacingOccurrences(of: ", ישראל", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                self.text = fullAddress
                                self.viewModel.searchQuery = fullAddress
                                self.showSuggestions = false
                                
                                // Hide keyboard natively
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(completion.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Divider()
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                }
                .frame(maxHeight: 200)
                .padding(.top, 4)
            }
        }
        .onAppear {
            if !text.isEmpty {
                viewModel.searchQuery = text
            }
        }
    }
}
