import SwiftUI
import MapKit
import CoreLocation

struct BrowsePostsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    @State private var selectedPost: Post?
    @State private var sitterLocation: CLLocationCoordinate2D?
    @State private var hasGeocoded = false
    @State private var selectedDateRange: ClosedRange<Date>? = nil
    @State private var selectedPetCount: String = "הכל"
    
    let collapsedHeight: CGFloat = 400
    let expandedHeight: CGFloat = (UIScreen.main.bounds.height - 83) * 0.8
    let fullHeight: CGFloat = UIScreen.main.bounds.height - 100
    
    @State private var isShowingPostDetail: Bool = false
    @State private var sheetHeight: CGFloat = 400
    @State private var previousSheetHeight: CGFloat = 400
    @State private var detailDragOffset: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 400
    
    @State private var selectedPostIndex: Int = 0
    @State private var previousPostIndex: Int = 0
    @State private var mapCenter: CLLocationCoordinate2D?
    
    // Cached results — recomputed only when inputs change (posts / location / filters),
    // not on every body evaluation. Avoids per-frame distance sorting jank during drags.
    @State private var sortedPosts: [Post] = []
    @State private var mapAnnotations: [MKPointAnnotation] = []

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
        sortedPosts = result
        mapAnnotations = computeAnnotations(result)
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            sheetHeight = collapsedHeight
                        }
                    }
                }
            )
                .ignoresSafeArea()
            
            if !isShowingPostDetail {
                HStack {
                    Spacer()
                    FilterBarView(selectedDateRange: $selectedDateRange, selectedPetCount: $selectedPetCount)
                }
                .padding(.top, 50)
                .zIndex(2)
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    if !isShowingPostDetail {
                        VStack {
                            Capsule()
                                .fill(theme.color.separator)
                                .frame(width: 40, height: 5)
                                .padding(.top, 8)
                                .padding(.bottom, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if dragStartHeight == 0 { dragStartHeight = sheetHeight }
                                    sheetHeight = max(collapsedHeight, min(expandedHeight, dragStartHeight - value.translation.height))
                                }
                                .onEnded { value in
                                    dragStartHeight = 0
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
                                    ForEach(Array(sortedPosts.enumerated()), id: \.element.id) { index, post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                            .padding(.bottom, 16)
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
                                    icon: "magnifyingglass",
                                    title: "אין פוסטים שמתאימים לסינון",
                                    message: "נסה לשנות את הסינון או להרחיב את טווח התאריכים"
                                )
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
                                .padding(.bottom, 83)
                            }
                        }
                    } else if let post = selectedPost {
                        PostDetailSheetView(post: post, onClose: {
                            closePost()
                        })
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
                .background(theme.color.surface)
                .cornerRadius(theme.radius.lg, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.15), radius: 10, y: -5)
                .offset(y: isShowingPostDetail ? max(0, detailDragOffset) : 0)
            }
            .ignoresSafeArea(.all, edges: .bottom)
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
    }

    func openPost(_ post: Post) {
        previousPostIndex = selectedPostIndex
        if let idx = sortedPosts.firstIndex(where: { $0.id == post.id }) {
            selectedPostIndex = idx
        }
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
            selectedPostIndex = previousPostIndex
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                sheetHeight = previousSheetHeight
            }
        }
    }
}

// cornerRadius(_:corners:) and RoundedCorner moved to Sources/DesignSystem/Foundations/Radius.swift

struct FilterBarView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedDateRange: ClosedRange<Date>?
    @Binding var selectedPetCount: String
    @State private var isExpanded: Bool = false
    @State private var showCalendar: Bool = false

    let petCounts = ["הכל", "1", "2", "3+"]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 12) {
                    PetCountFilterView(selectedPetCount: $selectedPetCount, petCounts: petCounts)
                    DatesFilterView(selectedDateRange: $selectedDateRange, showCalendar: $showCalendar)
                }
                .padding(12)
                .background(theme.color.surface.opacity(0.97))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 20)),
                    removal: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 20))
                ))
            }

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    if !isExpanded { showCalendar = false }
                }
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isExpanded ? theme.color.textOnAccent : theme.color.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(isExpanded ? theme.color.accent : theme.color.surface)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .accessibilityLabel("סינון")
            .padding(.trailing, 16)
        }
    }
}

struct PetCountFilterView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedPetCount: String
    let petCounts: [String]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("מספר כלבים")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(petCounts, id: \.self) { count in
                        Text(count)
                            .font(theme.typography.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedPetCount == count ? theme.color.accent : theme.color.surfaceSecondary)
                            .foregroundStyle(selectedPetCount == count ? theme.color.textOnAccent : theme.color.textPrimary)
                            .clipShape(Capsule())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedPetCount = count
                                }
                            }
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct DatesFilterView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedDateRange: ClosedRange<Date>?
    @Binding var showCalendar: Bool

    var dateString: String {
        guard let range = selectedDateRange else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("תאריכים")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)

            Button(action: {
                withAnimation {
                    showCalendar.toggle()
                }
            }) {
                HStack {
                    if selectedDateRange != nil {
                        Text(dateString)
                    } else {
                        Text("בחר תאריכים")
                    }
                    Image(systemName: "calendar")
                }
                .font(theme.typography.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(showCalendar || selectedDateRange != nil ? theme.color.accent : theme.color.surfaceSecondary)
                .foregroundStyle(showCalendar || selectedDateRange != nil ? theme.color.textOnAccent : theme.color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
            }

            if showCalendar {
                DragSelectCalendarView(selectedDateRange: $selectedDateRange)
                    .frame(width: 280)
                    .background(theme.color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                    .shadow(radius: 5)
                    .padding(.top, 8)
            }
        }
    }
}

struct DragSelectCalendarView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedDateRange: ClosedRange<Date>?

    @State private var dragStartDate: Date? = nil
    @State private var hoverEndDate: Date? = nil
    @State private var monthOffset: Int = 0
    
    let calendar = Calendar.current
    let today = Calendar.current.startOfDay(for: Date())
    
    private func days(for offset: Int) -> [Date] {
        let targetMonth = calendar.date(byAdding: .month, value: offset, to: today)!
        let components = calendar.dateComponents([.year, .month], from: targetMonth)
        let startOfMonth = calendar.date(from: components)!
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
        
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let wOffset = firstWeekday - calendar.firstWeekday
        let adjustedOffset = wOffset < 0 ? wOffset + 7 : wOffset
        
        var dates: [Date] = []
        for i in 0..<adjustedOffset {
            dates.append(calendar.date(byAdding: .day, value: -adjustedOffset + i, to: startOfMonth)!)
        }
        for i in 0..<range.count {
            dates.append(calendar.date(byAdding: .day, value: i, to: startOfMonth)!)
        }
        
        let remaining = 42 - dates.count
        if let lastDate = dates.last {
            for i in 1...remaining {
                dates.append(calendar.date(byAdding: .day, value: i, to: lastDate)!)
            }
        }
        
        return dates
    }
    
    private func monthString(for offset: Int) -> String {
        let targetMonth = calendar.date(byAdding: .month, value: offset, to: today)!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.string(from: targetMonth)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: {
                    withAnimation { monthOffset -= 1 }
                }) {
                    Image(systemName: "chevron.right")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(monthOffset > 0 ? theme.color.accent : theme.color.textSecondary.opacity(0.5))
                }
                .disabled(monthOffset <= 0)

                Spacer()
                Text(monthString(for: monthOffset))
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.color.textPrimary)
                Spacer()

                Button(action: {
                    withAnimation { monthOffset += 1 }
                }) {
                    Image(systemName: "chevron.left")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(theme.color.accent)
                }
            }
            .padding(.top, 4)
            
            TabView(selection: $monthOffset) {
                ForEach(0..<12, id: \.self) { offset in
                    calendarGrid(for: offset)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            
            if selectedDateRange != nil {
                Button(action: {
                    selectedDateRange = nil
                }) {
                    Text("נקה בחירה")
                        .font(.caption)
                        .foregroundStyle(theme.color.error)
                }
                .padding(.bottom, 8)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .coordinateSpace(name: "CalendarGrid")
        .onPreferenceChange(DateRectKey.self) { rects in
            self.dateRects = rects
        }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("CalendarGrid"))
                .onChanged { value in
                    if let date = dateAt(point: value.location), date >= today {
                        if dragStartDate == nil {
                            dragStartDate = date
                        }
                        hoverEndDate = date
                        updateSelection()
                    }
                }
                .onEnded { value in
                    dragStartDate = nil
                    hoverEndDate = nil
                }
        )
    }
    
    @ViewBuilder
    private func calendarGrid(for offset: Int) -> some View {
        let targetMonth = calendar.date(byAdding: .month, value: offset, to: today)!
        let gridDays = days(for: offset)
        
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["א", "ב", "ג", "ד", "ה", "ו", "ש"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(theme.color.textSecondary)
                }
                
                ForEach(gridDays, id: \.self) { date in
                    let isCurrentMonth = calendar.isDate(date, equalTo: targetMonth, toGranularity: .month)
                    let isPast = date < today
                    
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 14))
                        .strikethrough(isPast, color: theme.color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(backgroundFor(date: date, isPast: isPast))
                        .foregroundColor(textColorFor(date: date, isCurrentMonth: isCurrentMonth, isPast: isPast))
                        .clipShape(Circle())
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: DateRectKey.self,
                                    value: [date: geo.frame(in: .named("CalendarGrid"))]
                                )
                            }
                        )
                        .onTapGesture {
                            guard date >= today else { return }
                            if dragStartDate == nil || (dragStartDate != nil && hoverEndDate != dragStartDate && hoverEndDate != nil) {
                                // Start new selection
                                dragStartDate = date
                                hoverEndDate = date
                            } else {
                                // Complete selection
                                hoverEndDate = date
                            }
                            updateSelection()
                        }
                }
            }
            .padding(.horizontal, 8)
            Spacer()
        }
    }
    
    @State private var dateRects: [Date: CGRect] = [:]
    
    private func dateAt(point: CGPoint) -> Date? {
        for (date, rect) in dateRects {
            if rect.contains(point) {
                return date
            }
        }
        return nil
    }
    
    private func updateSelection() {
        guard let start = dragStartDate, let end = hoverEndDate else { return }
        
        let validStart = max(start, today)
        let validEnd = max(end, today)
        
        let lower = min(validStart, validEnd)
        let upper = max(validStart, validEnd)
        
        let startOfDayLower = calendar.startOfDay(for: lower)
        let endOfDayUpper = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: upper) ?? upper
        
        selectedDateRange = startOfDayLower...endOfDayUpper
    }
    
    private func isDateSelected(_ date: Date) -> Bool {
        guard let range = selectedDateRange else { return false }
        let startOfDay = calendar.startOfDay(for: date)
        let lowerStart = calendar.startOfDay(for: range.lowerBound)
        let upperStart = calendar.startOfDay(for: range.upperBound)
        return startOfDay >= lowerStart && startOfDay <= upperStart
    }
    
    private func backgroundFor(date: Date, isPast: Bool) -> Color {
        if !isPast && isDateSelected(date) {
            return theme.color.accent
        }
        return Color.clear
    }

    private func textColorFor(date: Date, isCurrentMonth: Bool, isPast: Bool) -> Color {
        if isPast {
            return theme.color.textSecondary.opacity(0.5)
        }
        if !isCurrentMonth {
            return theme.color.textSecondary.opacity(0.4)
        }
        if isDateSelected(date) {
            return theme.color.textOnAccent
        }
        return theme.color.textPrimary
    }
}

struct DateRectKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

struct PostCardBanner: View {
    @Environment(\.theme) private var theme
    let post: Post
    var isDetail: Bool = false
    var onClose: (() -> Void)? = nil
    @AppStorage("savedPostIDs") private var savedPostIDsData: String = ""
    
    var savedPostIDs: [String] {
        savedPostIDsData.isEmpty ? [] : savedPostIDsData.components(separatedBy: ",")
    }
    
    var isSaved: Bool {
        savedPostIDs.contains(post.id ?? "")
    }
    
    func toggleSave() {
        var ids = savedPostIDs
        if let id = post.id {
            if ids.contains(id) {
                ids.removeAll { $0 == id }
            } else {
                ids.append(id)
            }
            savedPostIDsData = ids.joined(separator: ",")
        }
    }
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        let start = post.startDate.dateValue()
        let end = post.endDate.dateValue()
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "d MMMM, HH:mm"
            let startStr = formatter.string(from: start)
            formatter.dateFormat = "HH:mm"
            let endStr = formatter.string(from: end)
            return "\(startStr) - \(endStr)"
        } else {
            formatter.dateFormat = "d MMMM"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // TOP ROW
            HStack(alignment: .top) {
                // LEFT - icons
                HStack(spacing: 12) {
                    Button(action: toggleSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 22))
                            .foregroundStyle(isSaved ? theme.color.accent : theme.color.textSecondary)
                    }
                    .accessibilityLabel(isSaved ? "הסר שמירה" : "שמור מודעה")

                    ShareLink(item: "בדוק את המודעה הזו ב-דוגסיטר!\nמאת \(post.ownerName)\nב-\(post.address)") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.color.textSecondary)
                    }

                    if isDetail {
                        Button(action: { onClose?() }) {
                            Circle()
                                .fill(theme.color.surfaceSecondary)
                                .frame(width: 30, height: 30)
                                .overlay(Image(systemName: "xmark").foregroundStyle(theme.color.textSecondary).font(.system(size: 14, weight: .bold)))
                        }
                        .accessibilityLabel("סגור")
                    }
                }
                
                Spacer()
                
                // RIGHT - name then photo
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        let nameParts = post.ownerName.components(separatedBy: " ")
                        let firstName = nameParts.first ?? ""
                        let lastName = nameParts.count > 1 ? nameParts.dropFirst().joined(separator: " ") : ""
                        
                        Text(firstName)
                            .bold()
                            .font(.system(size: 17))
                            .foregroundStyle(theme.color.textPrimary)
                            .multilineTextAlignment(.trailing)

                        if !lastName.isEmpty {
                            Text(lastName)
                                .bold()
                                .font(.system(size: 17))
                                .foregroundStyle(theme.color.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                        }
                    }

                    if let photo = post.ownerPhotoURL, photo.hasPrefix("http") {
                        CachedAsyncImage(photo, contentMode: .fill, targetSize: 104) {
                            ownerPhotoPlaceholder
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    } else {
                        ownerPhotoPlaceholder
                            .frame(width: 52, height: 52)
                    }
                }
            }
            
            // DIVIDER
            Rectangle()
                .fill(theme.color.separator)
                .frame(height: 1)
                .padding(.vertical, 10)

            // SECOND ROW (all content right-aligned)
            VStack(alignment: .trailing, spacing: 8) {
                Text(post.address.components(separatedBy: ",").first ?? post.address)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text("חיות: \(post.petIds.count)")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(dateString)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                // PRICE BUBBLE - Push to RIGHT with Spacer
                HStack {
                    Spacer()
                    let interval = post.payPer == "day" ? "ללילה" : "לשעה"
                    let daysCount = max(1, post.endDate.dateValue().timeIntervalSince(post.startDate.dateValue()) / (60 * 60 * 24))
                    let total = post.payAmount * (post.payPer == "day" ? daysCount : 1)

                    HStack(spacing: 8) {
                        Text("סה״כ ₪\(Int(total))")
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("₪\(Int(post.payAmount))/\(interval)")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.color.textOnAccent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(theme.color.accent)
                    .clipShape(Capsule())
                }
            }

            // PICKUP ROW
            if let pickup = post.pickupType {
                HStack {
                    Text(pickup == "dropOff" ? "🏠 בעל הכלב יביא" : "🚗 המטפל יאסוף")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.color.error)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(isDetail ? theme.color.surface : theme.color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var ownerPhotoPlaceholder: some View {
        Circle()
            .fill(theme.color.surfaceSecondary)
            .overlay(Image(systemName: "person.fill").foregroundStyle(theme.color.textSecondary))
    }
}

enum BehaviorStatus {
    case positive, negative, neutral
}

struct BehaviorPill: View {
    @Environment(\.theme) private var theme
    let title: String
    let status: BehaviorStatus

    var tint: Color {
        switch status {
        case .positive: return theme.color.success
        case .negative: return theme.color.error
        case .neutral:  return theme.color.warning
        }
    }
    var icon: String {
        switch status {
        case .positive: return "✓"
        case .negative: return "✗"
        case .neutral: return "~"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 10, weight: .bold))
            Text(title)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(tint)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
    }
}

func getBehaviorStatus(for text: String) -> BehaviorStatus {
    if text == "כן מאוד" { return .positive }
    if text == "לא בכלל" { return .negative }
    return .neutral
}

struct DogCardView: View {
    @Environment(\.theme) private var theme
    let pet: Pet
    let post: Post

    var body: some View {
        VStack(spacing: 12) {
            // TOP ROW
            HStack(alignment: .top) {
                // FAR RIGHT
                CachedAsyncImage(
                    (pet.mainPhotoURL?.isEmpty == false ? pet.mainPhotoURL : nil),
                    contentMode: .fill,
                    targetSize: 104
                ) {
                    ZStack {
                        theme.color.surfaceSecondary
                        Image(systemName: "pawprint.fill").foregroundStyle(theme.color.textSecondary)
                    }
                }
                .frame(width: 52, height: 52)
                .background(theme.color.surfaceSecondary)
                .clipShape(Circle())

                // LEFT OF PHOTO
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(pet.ageYears) שנים - \(pet.name)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.color.textPrimary)

                    Text(pet.sex)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.color.textSecondary)
                }

                Spacer()
            }

            // BEHAVIOR ROW
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BehaviorPill(title: "תרופות", status: post.medication ? .negative : .positive)
                    BehaviorPill(title: "נחמד לילדים", status: getBehaviorStatus(for: pet.friendlyWithChildren))
                    BehaviorPill(title: "נחמד לכלבים", status: getBehaviorStatus(for: pet.friendlyWithDogs))

                    if !pet.friendlyWithCats.isEmpty && pet.friendlyWithCats != "לא רלוונטי" {
                        BehaviorPill(title: "נחמד לחתולים", status: getBehaviorStatus(for: pet.friendlyWithCats))
                    }
                }
            }
        }
        .padding(16)
        .background(theme.color.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct PostDetailSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    let post: Post
    var onClose: () -> Void

    @State private var isSubmitting = false
    @State private var loadedPets: [Pet] = []
    @State private var selectedPet: Pet? = nil
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // FIXED TOP BANNER
                PostCardBanner(post: post, isDetail: true, onClose: onClose)
                    .background(theme.color.surface.shadow(color: .black.opacity(0.05), radius: 5, y: 5))
                    .zIndex(1)

                // SCROLLABLE CONTENT
                ScrollView {
                    VStack(spacing: 12) {
                        // SECTION 1 - USER NOTES
                        if let desc = post.description, !desc.isEmpty {
                            VStack {
                                Text(desc)
                                    .font(.system(size: 15))
                                    .foregroundStyle(theme.color.textSecondary)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .background(theme.color.surfaceSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                            }
                            .padding(16)
                            .background(theme.color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        } else {
                            Spacer().frame(height: 16)
                        }
                        
                        // SECTION 2 - DOG CARDS
                        ForEach(loadedPets) { pet in
                            DogCardView(pet: pet, post: post)
                                .padding(.horizontal, 16)
                                .onTapGesture {
                                    selectedPet = pet
                                }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
                .background(theme.color.background)

                // FIXED BOTTOM BUTTON
                Button(action: {
                    Task {
                        isSubmitting = true
                        try? await appState.expressInterest(in: post)
                        isSubmitting = false
                        onClose()
                    }
                }) {
                    if isSubmitting {
                        LottieProgressView(size: 36)
                    } else {
                        Text("אני מעוניין")
                    }
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.color.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(LinearGradient(colors: theme.color.accentGradient, startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 83 + 16)
                .padding(.top, 16)
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

    private func friendlyTint(_ value: String) -> Color {
        switch getBehaviorStatus(for: value) {
        case .positive: return theme.color.success
        case .neutral:  return theme.color.warning
        case .negative: return theme.color.error
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
                    VStack(spacing: 20) {
                        if let urls = pet.photoURLs, !urls.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
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
                        
                        VStack(alignment: .leading, spacing: 16) {

                            // 2. Additional Info
                            if !pet.additionalInfo.isEmpty {
                                Text(pet.additionalInfo)
                                    .foregroundStyle(theme.color.textPrimary)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.color.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                            }

                            // 3. Behavior section
                            Text("התנהגות").font(theme.typography.headline).padding(.top, 8).foregroundStyle(theme.color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("ידידותי לילדים")
                                        .foregroundColor(.primary)
                                    Text(pet.friendlyWithChildren)
                                        .font(theme.typography.captionBold)
                                        .foregroundStyle(friendlyTint(pet.friendlyWithChildren))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(friendlyTint(pet.friendlyWithChildren).opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Text("ידידותי לכלבים")
                                        .foregroundColor(.primary)
                                    Text(pet.friendlyWithDogs)
                                        .font(theme.typography.captionBold)
                                        .foregroundStyle(friendlyTint(pet.friendlyWithDogs))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(friendlyTint(pet.friendlyWithDogs).opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Text("ידידותי לחתולים")
                                        .foregroundColor(.primary)
                                    Text(pet.friendlyWithCats)
                                        .font(theme.typography.captionBold)
                                        .foregroundStyle(friendlyTint(pet.friendlyWithCats))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(friendlyTint(pet.friendlyWithCats).opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(theme.color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                            .shadow(color: .black.opacity(0.05), radius: 5)
                            
                            // 4. Medical section (LAST)
                            Text("מידע רפואי").font(theme.typography.headline).padding(.top, 8).foregroundStyle(theme.color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(pet.isMicrochipped ? "יש שבב ✅" : "אין שבב ❌")
                                        .foregroundColor(.primary)
                                        .font(.body)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    Text(pet.isNeutered ? "מסורס ✅" : "לא מסורס ❌")
                                        .foregroundColor(.primary)
                                        .font(.body)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    if post.medication {
                                        Text("תרופות: \(post.medicationInfo ?? "")")
                                            .foregroundColor(.primary)
                                            .font(.body)
                                    } else {
                                        Text("ללא תרופות ✅")
                                            .foregroundColor(.primary)
                                            .font(.body)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(theme.color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                            .shadow(color: .black.opacity(0.05), radius: 5)
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
}

