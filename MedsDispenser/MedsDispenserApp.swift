import SwiftUI

@main
struct MedsDispenserApp: App {
    @State private var showIntro = true
    @StateObject private var notificationManager = MedicationNotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showIntro {
                    IntroView()
                        .onAppear {
                            // Hide intro after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showIntro = false
                                }
                            }
                            
                            notificationManager.requestAuthorization { granted in
                                print("Notification permission: \(granted ? "granted" : "denied")")
                            }
                        }
                } else {
                    ContentView()
                        .transition(.opacity)
                        .environmentObject(notificationManager)
                }
            }
            .sheet(isPresented: $notificationManager.isShowingNotificationDetail) {
                if let notification = notificationManager.pendingNotification {
                    NotificationDetailView(notification: notification) {
                        notificationManager.isShowingNotificationDetail = false
                        notificationManager.pendingNotification = nil
                    }
                }
            }
        }
    }
}
