import SwiftUI
import MapKit
import CoreLocation

struct PreWalkView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var appState: AppState
    let chat: Chat
    
    @StateObject private var tracker = LocationTracker()
    @State private var totalHoursToday: String = "00:00"
    
    // Default region
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Map Area (60%)
                GeometryReader { geo in
                    Map(coordinateRegion: $region, showsUserLocation: true)
                        .onChange(of: tracker.currentLocation) { newLoc in
                            if let newLoc = newLoc {
                                withAnimation {
                                    region.center = newLoc.coordinate
                                }
                            }
                        }
                        .frame(height: geo.size.height)
                }
                .frame(height: UIScreen.main.bounds.height * 0.6)
                
                // Start Button Area (40%)
                VStack {
                    Spacer()
                    
                    Button(action: startWalkAction) {
                        VStack(spacing: 8) {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("התחל הליכה")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(width: 120, height: 120)
                        .background(Color(hex: "#4A90D9"))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
            }
            
            // Top Floating Bubble
            VStack {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4)
                    }
                    .padding(.leading, 16)
                    
                    Spacer()
                }
                .padding(.top, 16)
                
                HStack {
                    Text("Total Walk Hours Today")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Text(totalHoursToday)
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                
                Spacer()
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) } // Adjust for safe area if needed
        }
        .navigationBarHidden(true)
        .onAppear {
            tracker.requestPermission()
            Task {
                if let chatId = chat.id {
                    totalHoursToday = await appState.getTotalWalkHoursForChat(chatId: chatId)
                }
            }
        }
    }
    
    private func startWalkAction() {
        tracker.startTracking()
        
        let geocoder = CLGeocoder()
        let location = tracker.currentLocation ?? CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            var addressString = "מיקום נוכחי"
            if let pm = placemarks?.first {
                let street = pm.thoroughfare ?? ""
                let city = pm.locality ?? ""
                addressString = street.isEmpty ? city : "\(street), \(city)"
            }
            
            Task {
                if let chatId = chat.id {
                    let _ = await appState.startWalk(chatId: chatId, postId: chat.postId, startAddress: addressString)
                    
                    // Push Notification placeholder
                    print("🐾 הליכה התחילה! (Push Notification sent to owner)")
                    
                    await MainActor.run {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
