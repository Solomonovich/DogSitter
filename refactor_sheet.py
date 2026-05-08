import re

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"

with open(file_path, "r") as f:
    content = f.read()

# Replace the state variables
old_state = """    @State private var currentHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    
    @State private var selectedPostIndex: Int = 0
    @State private var mapCenter: CLLocationCoordinate2D?
    
    let minHeight: CGFloat = 220
    let midHeight: CGFloat = UIScreen.main.bounds.height * 0.6
    let maxHeight: CGFloat = UIScreen.main.bounds.height - 120
    
    var sheetPosition: SheetPosition {
        if currentHeight <= minHeight + 50 { return .collapsed }
        if currentHeight >= maxHeight - 50 { return .full }
        return .half
    }
    
    enum SheetPosition {
        case collapsed, half, full
    }"""

new_state = """    let collapsedHeight: CGFloat = UIScreen.main.bounds.height * 0.33
    let expandedHeight: CGFloat = UIScreen.main.bounds.height * 0.67
    let fullHeight: CGFloat = UIScreen.main.bounds.height - 100
    
    @State private var isShowingPostDetail: Bool = false
    @State private var sheetHeight: CGFloat = UIScreen.main.bounds.height * 0.33
    @State private var previousSheetHeight: CGFloat = UIScreen.main.bounds.height * 0.33
    @State private var detailDragOffset: CGFloat = 0
    
    @State private var selectedPostIndex: Int = 0
    @State private var mapCenter: CLLocationCoordinate2D?"""

content = content.replace(old_state, new_state)

# Replace the body
pattern = r"    var body: some View \{.*?\n    \}"
match = re.search(pattern, content, re.DOTALL)

new_body = """    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(
                centerCoordinate: mapCenter,
                annotations: mapAnnotations,
                selectedAnnotationID: selectedPost?.id,
                onAnnotationTapped: { ann in
                    if let id = ann.subtitle, let post = sortedPosts.first(where: { $0.id == id }) {
                        openPost(post)
                    }
                },
                onMapTapped: {
                    if !isShowingPostDetail {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            sheetHeight = collapsedHeight
                        }
                    }
                }
            )
                .ignoresSafeArea()
            
            if !isShowingPostDetail {
                FilterBarView(selectedSittingType: $selectedSittingType, selectedPetCount: $selectedPetCount)
                    .padding(.top, 50)
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    if !isShowingPostDetail {
                        Capsule()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        sheetHeight = max(collapsedHeight, min(expandedHeight, sheetHeight - value.translation.height))
                                    }
                                    .onEnded { value in
                                        let velocity = -value.velocity.height
                                        let midpoint = (collapsedHeight + expandedHeight) / 2
                                        
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            if velocity > 300 || sheetHeight > midpoint {
                                                sheetHeight = expandedHeight
                                            } else if velocity < -300 || sheetHeight < midpoint {
                                                sheetHeight = collapsedHeight
                                            } else {
                                                if sheetHeight > midpoint {
                                                    sheetHeight = expandedHeight
                                                } else {
                                                    sheetHeight = collapsedHeight
                                                }
                                            }
                                        }
                                    }
                            )
                        
                        if sheetHeight <= collapsedHeight + 50 {
                            if !sortedPosts.isEmpty {
                                TabView(selection: $selectedPostIndex) {
                                    ForEach(Array(sortedPosts.enumerated()), id: \\.element.id) { index, post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal)
                                            .tag(index)
                                            .onTapGesture {
                                                openPost(post)
                                            }
                                    }
                                }
                                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                            } else {
                                Text("אין פוסטים שמתאימים לסינון")
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(sortedPosts) { post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal)
                                            .onTapGesture {
                                                openPost(post)
                                            }
                                    }
                                }
                                .padding(.bottom, 20)
                            }
                        }
                    } else if let post = selectedPost {
                        PostDetailSheetView(post: post, onClose: {
                            closePost()
                        })
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        detailDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    let velocity = value.velocity.height
                                    if detailDragOffset > 100 || velocity > 300 {
                                        detailDragOffset = 0
                                        closePost()
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            detailDragOffset = 0
                                        }
                                    }
                                }
                        )
                    }
                }
                .frame(height: sheetHeight)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.15), radius: 10, y: -5)
                .clipped()
                .offset(y: isShowingPostDetail ? max(0, detailDragOffset) : 0)
            }
        }
        .onAppear {
            if !hasGeocoded {
                hasGeocoded = true
                let geocoder = CLGeocoder()
                if let currentUser = appState.currentUser, let address = currentUser.address {
                    geocoder.geocodeAddressString(address) { placemarks, error in
                        if let loc = placemarks?.first?.location {
                            self.sitterLocation = loc.coordinate
                            self.mapCenter = loc.coordinate
                        }
                    }
                }
            }
        }
    }
    
    func openPost(_ post: Post) {
        previousSheetHeight = sheetHeight
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sheetHeight = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowingPostDetail = true
            selectedPost = post
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                sheetHeight = expandedHeight
            }
        }
    }
    
    func closePost() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sheetHeight = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowingPostDetail = false
            selectedPost = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                sheetHeight = previousSheetHeight
            }
        }
    }"""

if match:
    # also remove fullScreenCover
    part2 = content[match.end():]
    part2 = part2.replace(""".fullScreenCover(item: $selectedPost) { post in
            PostDetailSheetView(post: post, onClose: {
                selectedPost = nil
            })
        }
        .onAppear {""", ".onAppear {")
    content = content[:match.start()] + new_body + part2

with open(file_path, "w") as f:
    f.write(content)

print("Updated View")
