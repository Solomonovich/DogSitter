import SwiftUI

/// Shared building blocks for the redesigned "פוסטים" (browse posts) experience.
/// Visual only — every action is delegated back to the host screen via bindings or
/// closures, so the existing browse/filter/detail behavior is preserved untouched.
/// All visuals come from the design system (ProfileAvatar, Badge, theme tokens),
/// so the appearance settings (text size, roundness, avatar shape) apply here too.

// MARK: - Sorting

/// How the browse list is ordered. `recommended` is the original weighted
/// distance + time score; the rest are simple single-key sorts.
enum PostSortMode: String, CaseIterable, Identifiable {
    case recommended, distance, date, price
    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: return "מומלץ"
        case .distance:    return "מרחק"
        case .date:        return "תאריך"
        case .price:       return "מחיר"
        }
    }
}

// MARK: - Filter chip

/// A small selectable capsule used across every filter row.
/// Selected → accent fill; otherwise a muted surface fill.
struct FilterChip: View {
    @Environment(\.theme) private var theme
    let title: String
    let isSelected: Bool
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(theme.typography.caption.weight(isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? theme.color.textOnAccent : theme.color.textPrimary)
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.xs)
            .background(isSelected ? theme.color.accent : theme.color.surfaceSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post card

/// The headline card for a post: owner identity, sitting type, distance, key
/// facts (location · pets · dates) and pay. Used in the browse carousel, the
/// expanded list, and (with `isDetail`) as the fixed banner of the detail sheet.
struct PostCardBanner: View {
    @Environment(\.theme) private var theme
    let post: Post
    var isDetail: Bool = false
    /// e.g. "2.3 ק״מ ממך". `nil` hides the distance badge (not geocoded yet).
    var distanceText: String? = nil
    /// The sitter already has a chat about this post → show an "in contact" badge.
    var alreadyInContact: Bool = false
    var onClose: (() -> Void)? = nil
    @AppStorage("savedPostIDs") private var savedPostIDsData: String = ""

    private var savedPostIDs: [String] {
        savedPostIDsData.isEmpty ? [] : savedPostIDsData.components(separatedBy: ",")
    }

    private var isSaved: Bool {
        savedPostIDs.contains(post.id ?? "")
    }

    private func toggleSave() {
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

    private var dateString: String {
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
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            header
            Divider().overlay(theme.color.separator)
            infoRows
            payRow
            if let pickup = post.pickupType {
                pickupRow(pickup)
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isDetail ? theme.color.surface : theme.color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .elevation(theme.elevation.card)
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            ProfileAvatar(photoURL: post.ownerPhotoURL, size: 52)

            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(post.ownerName)
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: theme.spacing.xxs) {
                    Badge(text: post.mappedSittingType.rawValue, kind: .accent)
                    if alreadyInContact {
                        Badge(text: "בקשר", kind: .success, systemImage: "checkmark.bubble.fill")
                    }
                    if let distanceText {
                        Badge(text: distanceText, kind: .neutral, systemImage: "location.fill")
                    }
                }
            }

            Spacer(minLength: theme.spacing.xs)

            actions
        }
    }

    private var actions: some View {
        HStack(spacing: theme.spacing.sm) {
            Button(action: toggleSave) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(theme.typography.title3)
                    .foregroundStyle(isSaved ? theme.color.accent : theme.color.textSecondary)
            }
            .accessibilityLabel(isSaved ? "הסר שמירה" : "שמור מודעה")

            ShareLink(item: "בדוק את המודעה הזו ב-דוגסיטר!\nמאת \(post.ownerName)\nב-\(post.address)") {
                Image(systemName: "square.and.arrow.up")
                    .font(theme.typography.title3)
                    .foregroundStyle(theme.color.textSecondary)
            }

            if isDetail {
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(theme.typography.footnote.weight(.bold))
                        .foregroundStyle(theme.color.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(theme.color.surfaceSecondary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("סגור")
            }
        }
    }

    // MARK: Info rows

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            infoRow(icon: "mappin.and.ellipse",
                    text: post.address.components(separatedBy: ",").first ?? post.address)
            infoRow(icon: "pawprint.fill", text: "חיות: \(post.petIds.count)")
            infoRow(icon: "calendar", text: dateString)
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Image(systemName: icon)
                .font(theme.typography.footnote)
                .foregroundStyle(theme.color.accent)
                .frame(width: 18)
            Text(text)
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.color.textSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Pay

    private var payRow: some View {
        let interval = post.payPer == "day" ? "ללילה" : "לשעה"
        let daysCount = max(1, post.endDate.dateValue().timeIntervalSince(post.startDate.dateValue()) / (60 * 60 * 24))
        let total = post.payAmount * (post.payPer == "day" ? daysCount : 1)

        return HStack {
            Spacer(minLength: 0)
            HStack(spacing: theme.spacing.xs) {
                Text("₪\(Int(post.payAmount))/\(interval)")
                Image(systemName: "arrow.left")
                    .font(theme.typography.caption.weight(.bold))
                Text("סה״כ ₪\(Int(total))")
            }
            .font(theme.typography.subheadline.weight(.bold))
            .foregroundStyle(theme.color.textOnAccent)
            .padding(.vertical, theme.spacing.xs)
            .padding(.horizontal, theme.spacing.md)
            .background(LinearGradient(colors: theme.color.accentGradient, startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
        }
    }

    // MARK: Pickup

    private func pickupRow(_ pickup: String) -> some View {
        HStack {
            Badge(text: pickup == "dropOff" ? "🏠 בעל הכלב יביא" : "🚗 המטפל יאסוף",
                  kind: pickup == "dropOff" ? .neutral : .warning)
            Spacer()
        }
    }
}

// MARK: - Behavior pills

enum BehaviorStatus {
    case positive, negative, neutral
}

func getBehaviorStatus(for text: String) -> BehaviorStatus {
    if text == "כן מאוד" { return .positive }
    if text == "לא בכלל" { return .negative }
    return .neutral
}

struct BehaviorPill: View {
    @Environment(\.theme) private var theme
    let title: String
    let status: BehaviorStatus

    private var tint: Color {
        switch status {
        case .positive: return theme.color.success
        case .negative: return theme.color.error
        case .neutral:  return theme.color.warning
        }
    }
    private var icon: String {
        switch status {
        case .positive: return "✓"
        case .negative: return "✗"
        case .neutral:  return "~"
        }
    }

    var body: some View {
        HStack(spacing: theme.spacing.xxs) {
            Text(icon).font(theme.typography.caption.weight(.bold))
            Text(title).font(theme.typography.caption)
        }
        .foregroundStyle(tint)
        .padding(.vertical, theme.spacing.xxs)
        .padding(.horizontal, theme.spacing.xs)
        .background(tint.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Dog card

/// One pet inside the post detail: photo · name/age · behavior pills.
/// Tappable by the host to open the full pet overlay (chevron hints at it).
struct DogCardView: View {
    @Environment(\.theme) private var theme
    let pet: Pet
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(spacing: theme.spacing.sm) {
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

                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text("\(pet.name) · \(pet.ageYears) שנים")
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.color.textPrimary)
                    Text(pet.sex)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.backward")
                    .font(theme.typography.footnote)
                    .foregroundStyle(theme.color.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    BehaviorPill(title: "תרופות", status: post.medication ? .negative : .positive)
                    BehaviorPill(title: "נחמד לילדים", status: getBehaviorStatus(for: pet.friendlyWithChildren))
                    BehaviorPill(title: "נחמד לכלבים", status: getBehaviorStatus(for: pet.friendlyWithDogs))

                    if !pet.friendlyWithCats.isEmpty && pet.friendlyWithCats != "לא רלוונטי" {
                        BehaviorPill(title: "נחמד לחתולים", status: getBehaviorStatus(for: pet.friendlyWithCats))
                    }
                }
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .elevation(theme.elevation.card)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - Filter bar

/// Floating filter control: a slider button (with an active-filter count badge)
/// that expands a panel of sort + sitting-type + pet-count + dates + saved filters.
struct FilterBarView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedDateRange: ClosedRange<Date>?
    @Binding var selectedPetCount: String
    @Binding var selectedSittingType: SittingType?
    @Binding var sortMode: PostSortMode
    @Binding var showSavedOnly: Bool
    let activeCount: Int

    @State private var isExpanded: Bool = false
    @State private var showCalendar: Bool = false

    let petCounts = ["הכל", "1", "2", "3+"]

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            if isExpanded {
                panel
            }
            filterButton
        }
    }

    private var panel: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.sm) {
            SortFilterView(sortMode: $sortMode)
            SittingTypeFilterView(selectedSittingType: $selectedSittingType)
            PetCountFilterView(selectedPetCount: $selectedPetCount, petCounts: petCounts)
            DatesFilterView(selectedDateRange: $selectedDateRange, showCalendar: $showCalendar)
            savedToggle
        }
        .frame(width: 280, alignment: .trailing)
        .padding(theme.spacing.sm)
        .background(theme.color.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .elevation(theme.elevation.float)
        .environment(\.layoutDirection, .rightToLeft)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 20)),
            removal: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity).combined(with: .offset(x: 20))
        ))
    }

    private var savedToggle: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
            Text("מועדפים")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)
            FilterChip(title: "שמורים בלבד",
                       isSelected: showSavedOnly,
                       systemImage: showSavedOnly ? "bookmark.fill" : "bookmark") {
                withAnimation(.easeInOut(duration: 0.2)) { showSavedOnly.toggle() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var filterButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded.toggle()
                if !isExpanded { showCalendar = false }
            }
        }) {
            Image(systemName: "slider.horizontal.3")
                .font(theme.typography.headline)
                .foregroundStyle(isExpanded ? theme.color.textOnAccent : theme.color.textSecondary)
                .frame(width: 44, height: 44)
                .background(isExpanded ? theme.color.accent : theme.color.surface)
                .clipShape(Circle())
                .elevation(theme.elevation.raised)
                .overlay(alignment: .topTrailing) {
                    if activeCount > 0 && !isExpanded {
                        Text("\(activeCount)")
                            .font(theme.typography.caption.weight(.bold))
                            .foregroundStyle(theme.color.textOnAccent)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(theme.color.accent)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.color.surface, lineWidth: 2))
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .accessibilityLabel("סינון")
        .padding(.trailing, theme.spacing.md)
    }
}

// MARK: - Filter rows

struct SortFilterView: View {
    @Environment(\.theme) private var theme
    @Binding var sortMode: PostSortMode

    var body: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
            Text("מיון")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(PostSortMode.allCases) { mode in
                        FilterChip(title: mode.label, isSelected: sortMode == mode) {
                            withAnimation(.easeInOut(duration: 0.2)) { sortMode = mode }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct SittingTypeFilterView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedSittingType: SittingType?

    var body: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
            Text("סוג טיפול")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    FilterChip(title: "הכל", isSelected: selectedSittingType == nil) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedSittingType = nil }
                    }
                    ForEach(SittingType.allCases) { type in
                        FilterChip(title: type.rawValue, isSelected: selectedSittingType == type) {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedSittingType = type }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct PetCountFilterView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedPetCount: String
    let petCounts: [String]

    var body: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
            Text("מספר כלבים")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(petCounts, id: \.self) { count in
                        FilterChip(title: count, isSelected: selectedPetCount == count) {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedPetCount = count }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DatesFilterView: View {
    @Environment(\.theme) private var theme
    @Binding var selectedDateRange: ClosedRange<Date>?
    @Binding var showCalendar: Bool

    private var dateString: String {
        guard let range = selectedDateRange else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }

    private var isActive: Bool { showCalendar || selectedDateRange != nil }

    var body: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
            Text("תאריכים")
                .font(theme.typography.captionBold)
                .foregroundStyle(theme.color.textPrimary)

            Button(action: {
                withAnimation { showCalendar.toggle() }
            }) {
                HStack(spacing: theme.spacing.xxs) {
                    Text(selectedDateRange != nil ? dateString : "בחר תאריכים")
                    Image(systemName: "calendar")
                }
                .font(theme.typography.caption.weight(isActive ? .bold : .regular))
                .foregroundStyle(isActive ? theme.color.textOnAccent : theme.color.textPrimary)
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xs)
                .background(isActive ? theme.color.accent : theme.color.surfaceSecondary)
                .clipShape(Capsule())
            }

            if showCalendar {
                DragSelectCalendarView(selectedDateRange: $selectedDateRange)
                    .frame(width: 280)
                    .background(theme.color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                    .elevation(theme.elevation.raised)
                    .padding(.top, theme.spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Drag-select calendar

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
                        .font(theme.typography.caption)
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
                        .font(theme.typography.caption)
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
