import SwiftUI
import MapKit
import CoreLocation

struct BrowsePostsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    @State private var selectedPost: Post?
    @State private var sitterLocation: CLLocationCoordinate2D?
    @State private var hasGeocoded = false

    // Filters & sort
    @State private var selectedDateRange: ClosedRange<Date>? = nil
    @State private var selectedPetCount: String = "הכל"
    @State private var selectedPostType: PostType? = nil
    @State private var sortMode: PostSortMode = .recommended
    @State private var showSavedOnly: Bool = false
    @AppStorage("savedPostIDs") private var savedPostIDsData: String = ""

    let collapsedHeight: CGFloat = 400
    let expandedHeight: CGFloat = (UIScreen.main.bounds.height - 83) * 0.8
    let fullHeight: CGFloat = UIScreen.main.bounds.height - 100

    @State private var isShowingPostDetail: Bool = false
    @State private var sheetHeight: CGFloat = 400
    @State private var detailDragOffset: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 400
    // Drives carousel (collapsed) vs. list (expanded). Decoupled from the live
    // `sheetHeight` so the heavy paging TabView is only built/torn down at rest —
    // never mid-animation, which is what caused the collapse stutter.
    @State private var showCarousel: Bool = true

    @State private var selectedPostIndex: Int = 0
    @State private var previousPostIndex: Int = 0
    @State private var mapCenter: CLLocationCoordinate2D?

    // Cached results — recomputed only when inputs change (posts / location / filters),
    // not on every body evaluation. Avoids per-frame distance sorting jank during drags.
    @State private var sortedPosts: [Post] = []
    @State private var mapAnnotations: [MKPointAnnotation] = []

    /// How many filters differ from their default — drives the slider-button badge.
    private var activeFilterCount: Int {
        var n = 0
        if selectedDateRange != nil { n += 1 }
        if selectedPetCount != "הכל" { n += 1 }
        if selectedPostType != nil { n += 1 }
        if sortMode != .recommended { n += 1 }
        if showSavedOnly { n += 1 }
        return n
    }

    // MARK: - Distance helpers

    private func meters(for post: Post, from location: CLLocationCoordinate2D) -> CLLocationDistance {
        let myLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let loc = CLLocation(latitude: post.latitude ?? 0, longitude: post.longitude ?? 0)
        return loc.distance(from: myLoc)
    }

    /// User-facing distance from the sitter to a post; nil when not geocoded or no coords.
    private func distanceText(for post: Post) -> String? {
        guard let location = sitterLocation, post.latitude != nil, post.longitude != nil else { return nil }
        let d = meters(for: post, from: location)
        if d < 950 {
            let rounded = Int((d / 10).rounded()) * 10
            return "\(rounded) מ׳ ממך"
        }
        return String(format: "%.1f ק״מ ממך", d / 1000)
    }

    /// Whether the sitter already has a chat about this post — drives the
    /// "in contact" badge so they can see it before opening the detail.
    private func alreadyInContact(_ post: Post) -> Bool {
        guard let id = post.id else { return false }
        return appState.existingSitterChat(forPostId: id) != nil
    }

    private func totalPay(_ post: Post) -> Double {
        let span = max(1, post.endDate.dateValue().timeIntervalSince(post.startDate.dateValue()) / (60 * 60 * 24))
        if post.mappedPostType == .overnight {
            return post.payAmount * span
        }
        // Walking: estimate by price × walks/day × days (for price sorting).
        return post.payAmount * Double(post.walksPerDay ?? 1) * span
    }

    private func computeSortedPosts() -> [Post] {
        var posts = appState.posts

        if let range = selectedDateRange {
            posts = posts.filter { post in
                let postStart = post.startDate.dateValue()
                let postEnd = post.endDate.dateValue()
                return postStart <= range.upperBound && postEnd >= range.lowerBound
            }
        }

        if selectedPetCount != "הכל" {
            posts = posts.filter { String($0.petIds.count) == selectedPetCount || (selectedPetCount == "3+" && $0.petIds.count >= 3) }
        }

        if let type = selectedPostType {
            posts = posts.filter { $0.mappedPostType == type }
        }

        if showSavedOnly {
            let saved = Set(savedPostIDsData.isEmpty ? [] : savedPostIDsData.components(separatedBy: ","))
            posts = posts.filter { saved.contains($0.id ?? "") }
        }

        switch sortMode {
        case .recommended:
            return recommendedSort(posts)
        case .distance:
            guard let location = sitterLocation else { return posts }
            return posts.sorted { meters(for: $0, from: location) < meters(for: $1, from: location) }
        case .date:
            return posts.sorted { $0.startDate.dateValue() < $1.startDate.dateValue() }
        case .price:
            return posts.sorted { totalPay($0) > totalPay($1) }
        }
    }

    /// Original weighted distance (60%) + start-time proximity (40%) score.
    private func recommendedSort(_ posts: [Post]) -> [Post] {
        guard let location = sitterLocation else { return posts }
        let myLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)

        return posts.sorted { p1, p2 in
            let loc1 = CLLocation(latitude: p1.latitude ?? 0, longitude: p1.longitude ?? 0)
            let loc2 = CLLocation(latitude: p2.latitude ?? 0, longitude: p2.longitude ?? 0)

            let dist1 = loc1.distance(from: myLoc)
            let dist2 = loc2.distance(from: myLoc)

            let maxDist = 50000.0
            let distScore1 = max(0, 1 - (dist1 / maxDist))
            let distScore2 = max(0, 1 - (dist2 / maxDist))

            let maxTime = 30 * 24 * 3600.0
            let t1 = p1.startDate.dateValue().timeIntervalSinceNow
            let t2 = p2.startDate.dateValue().timeIntervalSinceNow
            let timeScore1 = max(0, 1 - (t1 / maxTime))
            let timeScore2 = max(0, 1 - (t2 / maxTime))

            let score1 = (distScore1 * 0.6) + (timeScore1 * 0.4)
            let score2 = (distScore2 * 0.6) + (timeScore2 * 0.4)

            return score1 > score2
        }
    }

    private func computeAnnotations(_ posts: [Post]) -> [MKPointAnnotation] {
        posts.compactMap { post in
            guard let lat = post.latitude, let lon = post.longitude else { return nil }
            let ann = MKPointAnnotation()
            ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            ann.title = post.ownerName
            ann.subtitle = post.id
            return ann
        }
    }

    private func recomputePosts() {
        let result = computeSortedPosts()
        // Apply without implicit animation so the carousel doesn't visibly reshuffle
        // when geocoding finishes or posts stream in (fixes the on-appear stutter).
        // User-driven sheet/paging animations stay intact.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            sortedPosts = result
            mapAnnotations = computeAnnotations(result)
        }
    }

    /// Pull-to-refresh: re-geocode the sitter's address and re-sort the posts.
    @MainActor
    private func refresh() async {
        if let address = appState.currentUser?.address {
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.geocodeAddressString(address),
               let loc = placemarks.first?.location {
                sitterLocation = loc.coordinate
                mapCenter = loc.coordinate
            }
        }
        // Keep the refresh indicator visible briefly even when geocoding is cached.
        try? await Task.sleep(nanoseconds: 350_000_000)
        recomputePosts()
    }

    var currentSelectedPostID: String? {
        guard !isShowingPostDetail else {
            return selectedPost?.id
        }
        guard sheetHeight <= collapsedHeight + 50 else {
            return nil
        }
        return sortedPosts.indices.contains(selectedPostIndex) ? sortedPosts[selectedPostIndex].id : nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(
                centerCoordinate: $mapCenter,
                annotations: mapAnnotations,
                selectedAnnotationID: currentSelectedPostID,
                accentColor: theme.color.accent,
                onAnnotationTapped: { ann in
                    if let id = ann.subtitle, let post = sortedPosts.first(where: { $0.id == id }) {
                        if let idx = sortedPosts.firstIndex(where: { $0.id == post.id }) {
                            selectedPostIndex = idx
                        }
                    }
                },
                onMapTapped: {
                    if !isShowingPostDetail {
                        snap(to: collapsedHeight, response: 0.35, damping: 0.75)
                    }
                }
            )
                .ignoresSafeArea()

            if !isShowingPostDetail {
                HStack {
                    Spacer()
                    FilterBarView(
                        selectedDateRange: $selectedDateRange,
                        selectedPetCount: $selectedPetCount,
                        selectedPostType: $selectedPostType,
                        sortMode: $sortMode,
                        showSavedOnly: $showSavedOnly,
                        activeCount: activeFilterCount
                    )
                }
                .padding(.top, 50)
                .zIndex(2)
            }

            // BROWSE SHEET — carousel (collapsed) or list (expanded). Always present;
            // the detail view slides up OVER it, so this sheet never re-animates its
            // height during open/close (which was the source of the stutter / dip).
            browseSheet
                .ignoresSafeArea(.all, edges: .bottom)

            // DETAIL OVERLAY — a separate, fixed-height sheet that slides up over the
            // browse sheet and stays stationary; on close it slides straight back down.
            // Fully decoupled from `sheetHeight`, so neither open nor close juggles the
            // browse sheet's height — no stutter, and the detail never dips out of place.
            if isShowingPostDetail, let post = selectedPost {
                VStack(spacing: 0) {
                    Spacer()
                    PostDetailSheetView(post: post, onClose: { closePost() })
                        .frame(height: expandedHeight)
                        .frame(maxWidth: .infinity)
                        .background(theme.color.surface)
                        .cornerRadius(theme.radius.sheet, corners: [.topLeft, .topRight])
                        .shadow(color: .black.opacity(0.15), radius: 12, y: -6)
                        .offset(y: max(0, detailDragOffset))
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        detailDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    let velocity = value.velocity.height
                                    if detailDragOffset > 100 || velocity > 300 {
                                        closePost()
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            detailDragOffset = 0
                                        }
                                    }
                                }
                        )
                }
                .ignoresSafeArea(.all, edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(3)
            }
        }
        .onAppear {
            recomputePosts()
            if !hasGeocoded {
                hasGeocoded = true
                if let address = appState.currentUser?.address {
                    let geocoder = CLGeocoder()
                    geocoder.geocodeAddressString(address) { placemarks, _ in
                        guard let loc = placemarks?.first?.location else { return }
                        DispatchQueue.main.async {
                            self.sitterLocation = loc.coordinate
                            self.mapCenter = loc.coordinate
                            self.recomputePosts()
                        }
                    }
                }
            }
        }
        .onReceive(appState.$posts) { _ in
            recomputePosts()
        }
        .onChange(of: selectedDateRange) { _, _ in
            recomputePosts()
        }
        .onChange(of: selectedPetCount) { _, _ in
            recomputePosts()
        }
        .onChange(of: selectedPostType) { _, _ in
            recomputePosts()
        }
        .onChange(of: sortMode) { _, _ in
            recomputePosts()
        }
        .onChange(of: showSavedOnly) { _, _ in
            recomputePosts()
        }
    }

    // MARK: - Browse sheet (carousel / list)

    private var browseSheet: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                Capsule()
                    .fill(theme.color.separator)
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    // Enlarge the grab handle's touch target without changing how it
                    // looks: grow the hit region with extra padding above and below,
                    // capture it as the content shape, then negate that space further
                    // down so the handle and carousel don't visually shift.
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Tap the grab handle to pull the sheet up / push it down.
                        let target = sheetHeight <= collapsedHeight + 50 ? expandedHeight : collapsedHeight
                        snap(to: target, response: 0.35, damping: 0.8)
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartHeight == 0 { dragStartHeight = sheetHeight }
                                sheetHeight = max(collapsedHeight, min(expandedHeight, dragStartHeight - value.translation.height))
                                // Dragging up past the threshold reveals the list immediately
                                // (cheap to resize). The carousel is never built mid-drag — only
                                // at rest in snap(), so it can't stutter.
                                if sheetHeight > collapsedHeight + 50 && showCarousel {
                                    setCarousel(false)
                                }
                            }
                            .onEnded { value in
                                dragStartHeight = 0
                                let velocity = -value.velocity.height
                                let midpoint = (collapsedHeight + expandedHeight) / 2
                                let target: CGFloat
                                if velocity > 300 {
                                    target = expandedHeight
                                } else if velocity < -300 {
                                    target = collapsedHeight
                                } else {
                                    target = sheetHeight > midpoint ? expandedHeight : collapsedHeight
                                }
                                snap(to: target, response: 0.35, damping: 0.75)
                            }
                    )
                    // Cancel the layout effect of the hit-area padding so nothing moves,
                    // and lift the handle above the carousel so a near-miss just below
                    // the bar still grabs the handle instead of the cards underneath.
                    .padding(.vertical, -16)
                    .zIndex(1)

                // Quick All / Walking / Overnight type toggle.
                HStack(spacing: theme.spacing.xs) {
                    FilterChip(title: "הכל", isSelected: selectedPostType == nil) {
                        selectedPostType = nil
                    }
                    ForEach(PostType.allCases) { type in
                        FilterChip(title: type.displayName,
                                   isSelected: selectedPostType == type,
                                   systemImage: type.iconName) {
                            selectedPostType = (selectedPostType == type) ? nil : type
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.bottom, theme.spacing.sm)

                if showCarousel {
                    if !sortedPosts.isEmpty {
                        TabView(selection: $selectedPostIndex) {
                            ForEach(Array(sortedPosts.enumerated()), id: \.element.id) { index, post in
                                PostCardBanner(post: post, distanceText: distanceText(for: post), alreadyInContact: alreadyInContact(post))
                                    .padding(.horizontal, theme.spacing.md)
                                    .padding(.top, theme.spacing.xs)
                                    .padding(.bottom, theme.spacing.md)
                                    .onTapGesture {
                                        openPost(post)
                                    }
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        .onChange(of: selectedPostIndex) { newIndex in
                            guard newIndex < sortedPosts.count else { return }
                            let post = sortedPosts[newIndex]
                            if let lat = post.latitude, let lon = post.longitude {
                                mapCenter = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            }
                        }
                    } else {
                        EmptyStateView(
                            icon: showSavedOnly ? "bookmark" : "magnifyingglass",
                            title: showSavedOnly ? "אין מודעות שמורות" : "אין פוסטים שמתאימים לסינון",
                            message: showSavedOnly ? "שמור מודעות עם הסימנייה כדי לראות אותן כאן" : "נסה לשנות את הסינון או להרחיב את טווח התאריכים"
                        )
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: theme.spacing.md) {
                            ForEach(sortedPosts) { post in
                                PostCardBanner(post: post, distanceText: distanceText(for: post), alreadyInContact: alreadyInContact(post))
                                    .padding(.horizontal)
                                    .onTapGesture {
                                        openPost(post)
                                    }
                            }
                        }
                        .padding(.bottom, 83)
                    }
                    .refreshable {
                        await refresh()
                    }
                }
            }
            .frame(height: sheetHeight)
            .frame(maxWidth: .infinity)
            .background(theme.color.surface)
            .cornerRadius(theme.radius.sheet, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.15), radius: 12, y: -6)
        }
    }

    func openPost(_ post: Post) {
        previousPostIndex = selectedPostIndex
        if let idx = sortedPosts.firstIndex(where: { $0.id == post.id }) {
            selectedPostIndex = idx
        }
        // The detail view is a separate overlay that slides up over the browse sheet.
        // Reset any leftover drag offset, set the post, then animate it in — the browse
        // sheet stays exactly where it is, so the detail arrives stationary in place.
        detailDragOffset = 0
        // Set both inside the same animated transaction so the overlay's insertion
        // transition (slide up) is guaranteed to animate.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedPost = post
            isShowingPostDetail = true
        }
    }

    func closePost() {
        // Slide the detail overlay straight back down. Nothing else animates — the
        // browse sheet underneath is already at its previous height, so it's simply
        // revealed, with no height juggling and therefore no stutter.
        selectedPostIndex = previousPostIndex
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isShowingPostDetail = false
        }
    }

    /// Swap the carousel/list mode instantly, with no implicit animation, so the
    /// content change itself never animates.
    private func setCarousel(_ on: Bool) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { showCarousel = on }
    }

    /// Animate the browse sheet to a snap point. Crucially, the carousel (a paging
    /// TabView, which hitches when it lays out) is only ever shown at rest:
    /// - Expanding: switch to the lightweight list FIRST, then grow — the list
    ///   resizes smoothly, so there is no stutter.
    /// - Collapsing: keep the list during the shrink, and swap in the carousel only
    ///   once the spring has settled. The TabView is built at the final height, off
    ///   the animation, so it can't stutter "before going into place".
    private func snap(to target: CGFloat, response: Double = 0.35, damping: Double = 0.8) {
        let collapsing = target <= collapsedHeight + 50
        if collapsing {
            withAnimation(.spring(response: response, dampingFraction: damping)) {
                sheetHeight = target
            } completion: {
                // Guard against a gesture that re-expanded mid-animation.
                if sheetHeight <= collapsedHeight + 50 { setCarousel(true) }
            }
        } else {
            setCarousel(false)
            withAnimation(.spring(response: response, dampingFraction: damping)) {
                sheetHeight = target
            }
        }
    }
}

// cornerRadius(_:corners:) and RoundedCorner moved to Sources/DesignSystem/Foundations/Radius.swift
// PostCardBanner, BehaviorPill, DogCardView, the filter bar + rows, and the
// drag-select calendar moved to Sources/Views/PostComponents.swift

struct PostDetailSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    let post: Post
    var onClose: () -> Void

    @State private var isSubmitting = false
    @State private var loadedPets: [Pet] = []
    @State private var selectedPet: Pet? = nil

    /// The sitter's existing chat for this post, if any. When present the bottom
    /// button becomes "go to chat" instead of letting them express interest twice.
    private var existingChat: ChatWrapper? {
        guard let id = post.id else { return nil }
        return appState.existingSitterChat(forPostId: id)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // FIXED TOP BANNER
                PostCardBanner(post: post, isDetail: true, alreadyInContact: existingChat != nil, onClose: onClose)
                    .background(theme.color.surface.shadow(color: .black.opacity(0.05), radius: 5, y: 5))
                    .zIndex(1)

                // SCROLLABLE CONTENT
                ScrollView {
                    VStack(alignment: .trailing, spacing: theme.spacing.md) {
                        // SECTION 1 - USER NOTES
                        if let desc = post.description, !desc.isEmpty {
                            Text(desc)
                                .font(theme.typography.subheadline)
                                .foregroundStyle(theme.color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .card()
                                .padding(.horizontal, theme.spacing.md)
                                .padding(.top, theme.spacing.md)
                        }

                        // SECTION 2 - DOG CARDS
                        if !loadedPets.isEmpty {
                            Text("הכלבים")
                                .sectionHeader()
                                .padding(.horizontal, theme.spacing.md)
                                .padding(.top, theme.spacing.xs)
                        }

                        ForEach(loadedPets) { pet in
                            DogCardView(pet: pet, post: post)
                                .padding(.horizontal, theme.spacing.md)
                                .onTapGesture {
                                    selectedPet = pet
                                }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, theme.spacing.xs)
                    .environment(\.layoutDirection, .rightToLeft)
                }
                .background(theme.color.background)

                // FIXED BOTTOM BUTTON
                Button(action: {
                    // Already in contact about this post → teleport to the chat
                    // instead of opening a second one.
                    if let chat = existingChat, let chatId = chat.chat.id {
                        onClose()
                        appState.openChat(chatId)
                        return
                    }
                    Task {
                        // F-18: require a verified email to express interest.
                        guard appState.requireVerifiedEmail() else { return }
                        isSubmitting = true
                        try? await appState.expressInterest(in: post)
                        isSubmitting = false
                        onClose()
                    }
                }) {
                    if isSubmitting {
                        LottieProgressView(size: 36)
                    } else if existingChat != nil {
                        Label("עבור לצ׳אט", systemImage: "bubble.left.and.bubble.right.fill")
                    } else {
                        Text("אני מעוניין")
                    }
                }
                .disabled(isSubmitting)
                .font(theme.typography.headline.weight(.bold))
                .foregroundStyle(theme.color.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(LinearGradient(colors: theme.color.accentGradient, startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                .padding(.horizontal, theme.spacing.md)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 83 + 16)
                .padding(.top, theme.spacing.md)
                .background(theme.color.background)
            }
        }
        .task {
            loadedPets = await appState.fetchPets(for: post.petIds)
        }
        .sheet(item: $selectedPet) { pet in
            PetDetailOverlayView(pet: pet, post: post)
        }
    }
}

struct PetDetailOverlayView: View {
    let pet: Pet
    let post: Post
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.theme) private var theme
    @State private var selectedImageURL: String? = nil

    var ageString: String {
        if pet.ageMonths > 0 {
            return "\(pet.ageYears) שנים ו-\(pet.ageMonths) חודשים"
        }
        return "\(pet.ageYears) שנים"
    }

    private func friendlyKind(_ value: String) -> BadgeKind {
        switch getBehaviorStatus(for: value) {
        case .positive: return .success
        case .neutral:  return .warning
        case .negative: return .error
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    .accessibilityLabel("סגור")
                    Spacer()
                    Text(pet.name)
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    Image(systemName: "xmark.circle.fill").opacity(0)
                }
                .padding()
                .background(theme.color.surface)
                .environment(\.layoutDirection, .leftToRight) // Force X on left

                ScrollView {
                    VStack(spacing: theme.spacing.lg) {
                        if let urls = pet.photoURLs, !urls.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: theme.spacing.sm) {
                                    ForEach(urls, id: \.self) { urlString in
                                        CachedAsyncImage(urlString, contentMode: .fill, targetSize: 500) {
                                            theme.color.surfaceSecondary
                                        }
                                        .frame(width: 250, height: 250)
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                                        .clipped()
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedImageURL = urlString
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .environment(\.layoutDirection, .rightToLeft)
                        }

                        VStack(alignment: .leading, spacing: theme.spacing.md) {

                            // Age summary
                            HStack(spacing: theme.spacing.xs) {
                                Image(systemName: "pawprint.fill")
                                    .foregroundStyle(theme.color.accent)
                                Text(ageString)
                                    .font(theme.typography.body)
                                    .foregroundStyle(theme.color.textPrimary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Additional Info
                            if !pet.additionalInfo.isEmpty {
                                Text(pet.additionalInfo)
                                    .font(theme.typography.subheadline)
                                    .foregroundStyle(theme.color.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .card()
                            }

                            // Behavior section
                            Text("התנהגות")
                                .font(theme.typography.headline)
                                .foregroundStyle(theme.color.textPrimary)
                                .padding(.top, theme.spacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                                friendlyRow(title: "ידידותי לילדים", value: pet.friendlyWithChildren)
                                friendlyRow(title: "ידידותי לכלבים", value: pet.friendlyWithDogs)
                                friendlyRow(title: "ידידותי לחתולים", value: pet.friendlyWithCats)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()

                            // Medical section (LAST)
                            Text("מידע רפואי")
                                .font(theme.typography.headline)
                                .foregroundStyle(theme.color.textPrimary)
                                .padding(.top, theme.spacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                                medicalRow(text: pet.isMicrochipped ? "יש שבב" : "אין שבב",
                                           ok: pet.isMicrochipped)
                                medicalRow(text: pet.isNeutered ? "מסורס" : "לא מסורס",
                                           ok: pet.isNeutered)
                                if post.medication {
                                    medicalRow(text: "תרופות: \(post.medicationInfo ?? "")", ok: false)
                                } else {
                                    medicalRow(text: "ללא תרופות", ok: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                        .padding(.horizontal)
                        .environment(\.layoutDirection, .rightToLeft)
                    }
                    .padding(.vertical)
                }
                .background(theme.color.background.edgesIgnoringSafeArea(.all))
            }

            // LIGHTBOX OVERLAY
            if let imageURL = selectedImageURL {
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedImageURL = nil
                            }
                        }

                    VStack {
                        HStack {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedImageURL = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding()

                        Spacer()

                        CachedAsyncImage(imageURL, contentMode: .fit, targetSize: 1000) {
                            LottieProgressView(size: 36)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()
                    }
                }
                .transition(.opacity)
                .zIndex(100)
                .environment(\.layoutDirection, .leftToRight) // Force X on left
            }
        }
    }

    private func friendlyRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(theme.color.textPrimary)
            Badge(text: value, kind: friendlyKind(value))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medicalRow(text: String, ok: Bool) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? theme.color.success : theme.color.warning)
            Text(text)
                .font(theme.typography.body)
                .foregroundStyle(theme.color.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
