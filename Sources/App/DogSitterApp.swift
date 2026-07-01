import SwiftUI
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        do {
            try Auth.auth().useUserAccessGroup(nil)
        } catch {
            print("Failed to clear access group: \(error.localizedDescription)")
        }
        // Re-acquire an in-flight walk Live Activity after relaunch, and ask once for
        // local-notification permission (used for sitter-side walk alerts).
        WalkLiveActivityManager.shared.reattach()
        NotificationManager.shared.requestAuthorization()
        return true
    }
}

@main
struct DogSitterApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Shared global state
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var chatReadStore = ChatReadStore()
    @StateObject private var paymentService = PaymentService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Force Right-To-Left for Hebrew layout mapping
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(chatReadStore)
                .environmentObject(paymentService)
                .environment(\.theme, themeManager.theme)
                .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
                .task {
                    // Fetch the active rail + Stripe publishable key once at launch.
                    await paymentService.loadConfig()
                }
                .onOpenURL { url in
                    guard url.scheme == "dogsitter" else { return }
                    switch url.host {
                    case "walk":
                        // Tapping the walk Live Activity: dogsitter://walk/{walkId}
                        let walkId = url.lastPathComponent
                        guard !walkId.isEmpty, walkId != "/" else { return }
                        appState.openWalk(byId: walkId)
                    case "pay":
                        // Grow hosted-page return (Phase 3): dogsitter://pay?...
                        NotificationCenter.default.post(name: .growPaymentReturn, object: url)
                    default:
                        break
                    }
                }
                .overlay(
                    Group {
                        if themeManager.isAnimating, let targetDark = themeManager.colorSchemeTransitioningToDark {
                            ThemeTransitionOverlay(
                                center: themeManager.circleCenter,
                                isDark: targetDark
                            )
                        }
                    }
                )
        }
    }
}

class ThemeManager: ObservableObject {
    @AppStorage("isDarkMode") var isDarkMode: Bool = true
    @AppStorage("themePalette") private var paletteRaw: String = ThemePalette.classic.rawValue

    // Visual preferences (cosmetic). Stored raw; exposed via typed accessors below.
    @AppStorage("textSizePref") private var textSizeRaw: String = TextSizePreference.standard.rawValue
    @AppStorage("cornerStylePref") private var cornerStyleRaw: String = CornerStyle.rounded.rawValue
    @AppStorage("avatarShapePref") private var avatarShapeRaw: String = AvatarShape.circle.rawValue
    @AppStorage("useGradientBackground") private var useGradientBackgroundRaw: Bool = false

    @Published var isAnimating = false
    @Published var circleCenter: CGPoint = .zero
    @Published var colorSchemeTransitioningToDark: Bool? = nil

    /// The user-selected color palette (persisted).
    var palette: ThemePalette {
        get { ThemePalette(rawValue: paletteRaw) ?? .classic }
        set { objectWillChange.send(); paletteRaw = newValue.rawValue }
    }

    // @AppStorage inside an ObservableObject doesn't auto-publish, so each setter
    // sends objectWillChange (same pattern as `palette`) to refresh the injected theme.

    /// App-wide text size.
    var textSize: TextSizePreference {
        get { TextSizePreference(rawValue: textSizeRaw) ?? .standard }
        set { objectWillChange.send(); textSizeRaw = newValue.rawValue }
    }

    /// App-wide corner roundness.
    var cornerStyle: CornerStyle {
        get { CornerStyle(rawValue: cornerStyleRaw) ?? .rounded }
        set { objectWillChange.send(); cornerStyleRaw = newValue.rawValue }
    }

    /// Avatar clip shape.
    var avatarShape: AvatarShape {
        get { AvatarShape(rawValue: avatarShapeRaw) ?? .circle }
        set { objectWillChange.send(); avatarShapeRaw = newValue.rawValue }
    }

    /// Soft brand-gradient screen background (vs. solid fill).
    var useGradientBackground: Bool {
        get { useGradientBackgroundRaw }
        set { objectWillChange.send(); useGradientBackgroundRaw = newValue }
    }

    /// The fully-resolved theme to inject into the environment.
    var theme: Theme {
        var t = palette.theme(for: isDarkMode ? .dark : .light)
        t.typography.scale = textSize.scale
        t.radius           = cornerStyle.radius
        t.backgroundStyle  = useGradientBackground ? .gradient : .solid
        t.avatarShape      = avatarShape
        return t
    }

    func toggleTheme(from location: CGPoint) {
        guard !isAnimating else { return }
        
        circleCenter = location
        colorSchemeTransitioningToDark = !isDarkMode
        isAnimating = true
        
        // Let the circle grow to cover screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.isDarkMode.toggle()
            // Let the circle fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.isAnimating = false
                self.colorSchemeTransitioningToDark = nil
            }
        }
    }
}

struct ThemeTransitionOverlay: View {
    let center: CGPoint
    let isDark: Bool
    
    @State private var radius: CGFloat = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        GeometryReader { geo in
            let maxRadius = sqrt(pow(geo.size.width, 2) + pow(geo.size.height, 2))
            
            Circle()
                .fill(isDark ? Color.black : Color.white)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .opacity(opacity)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.easeIn(duration: 0.35)) {
                        radius = maxRadius
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            opacity = 0
                        }
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

struct ThemeToggleView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Pill
                RoundedRectangle(cornerRadius: 30)
                    .fill(themeManager.isDarkMode ? Color(white: 0.25) : Color(white: 0.9))
                
                HStack(spacing: 0) {
                    // Moon Icon (Dark Mode)
                    ZStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(themeManager.isDarkMode ? .white : .gray)
                            .font(.system(size: 20))
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Sun Icon (Light Mode)
                    ZStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(themeManager.isDarkMode ? .gray : .black)
                            .font(.system(size: 20))
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Sliding Thumb
                GeometryReader { innerGeo in
                    RoundedRectangle(cornerRadius: 25)
                        .fill(themeManager.isDarkMode ? Color(white: 0.4) : Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
                        .frame(width: innerGeo.size.width / 2 - 6)
                        .padding(3)
                        .offset(x: themeManager.isDarkMode ? 0 : innerGeo.size.width / 2)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: themeManager.isDarkMode)
                }
            }
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .global) { location in
                        themeManager.toggleTheme(from: location)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .global)
                            .onEnded { value in
                                let isDraggingRight = value.translation.width > 0
                                let newIsDark = !isDraggingRight
                                if themeManager.isDarkMode != newIsDark {
                                    themeManager.toggleTheme(from: value.location)
                                }
                            }
                    )
            )
        }
        .frame(width: 140, height: 60)
        .environment(\.layoutDirection, .leftToRight) // Force toggle direction LTR to match icons
    }
}
