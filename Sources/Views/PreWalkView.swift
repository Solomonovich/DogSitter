import SwiftUI
import MapKit
import CoreLocation

struct PreWalkView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    let chat: Chat

    @ObservedObject private var tracker = LocationTracker.shared
    @State private var totalHoursToday: String = "00:00"
    
    // Default region
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
        span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
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
                                .foregroundStyle(theme.color.textOnAccent)

                            Text("התחל הליכה")
                                .font(.headline)
                                .foregroundStyle(theme.color.textOnAccent)
                        }
                        .frame(width: 120, height: 120)
                        .background(LinearGradient(colors: theme.color.accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color.surface)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
            }
            
            // Top Floating Bubble
            VStack {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(theme.color.textPrimary)
                            .padding(12)
                            .background(theme.color.surface)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4)
                    }
                    .accessibilityLabel("חזור")
                    .padding(.leading, 16)

                    Spacer()
                }
                .padding(.top, 16)

                HStack {
                    Text("סך שעות הליכה היום")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(theme.color.textPrimary)

                    Spacer()

                    Text(totalHoursToday)
                        .font(.headline)
                        .foregroundStyle(theme.color.accent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(theme.color.surface)
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
            tracker.resetTracking()
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
                // F-18: require a verified email to start a walk.
                guard appState.requireVerifiedEmail() else { return }
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


// Color(hex:) moved to Sources/DesignSystem/Foundations/Color+Hex.swift
