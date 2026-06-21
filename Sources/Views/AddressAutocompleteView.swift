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
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String

    @StateObject private var viewModel = AddressSearchViewModel()
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(theme.color.textSecondary)
                TextField(placeholder, text: $viewModel.searchQuery, onEditingChanged: { editing in
                    showSuggestions = editing
                })
                .onChange(of: text) { newValue in
                    if viewModel.searchQuery != newValue {
                        viewModel.searchQuery = newValue
                    }
                }
                // Commit typed text as the address too, so onboarding isn't hard-blocked
                // when MapKit autocomplete returns no suggestions (network/region/device
                // state). Tapping a suggestion still overwrites this with the clean address.
                .onChange(of: viewModel.searchQuery) { newValue in
                    if text != newValue {
                        text = newValue
                    }
                }

                if viewModel.isSearching {
                    LottieProgressView(size: 40)
                        .padding(.trailing, 8)
                }
            }
            .padding()
            .background(theme.color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            
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
                                        .foregroundStyle(theme.color.textPrimary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(theme.color.textSecondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Divider()
                        }
                    }
                    .background(theme.color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
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
