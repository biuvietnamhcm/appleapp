import Foundation
import UserNotifications
import SwiftUI

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var pendingNotification: PendingNotificationInfo?
    @Published var isShowingNotificationDetail = false
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Notification authorization error: \(error.localizedDescription)")
                }
                completion(granted)
            }
        }
    }
    
    func scheduleNotifications(for medications: [Medication]) {
        // First, remove all pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        for medication in medications {
            for schedule in medication.timeToTake {
                scheduleNotification(for: medication, schedule: schedule)
            }
        }
        
        print("📅 Scheduled notifications for \(medications.count) medications")
    }
    
    private func scheduleNotification(for medication: Medication, schedule: Schedule) {
        let content = UNMutableNotificationContent()
        content.title = "💊 Time for your medication"
        content.body = "\(medication.type) - \(schedule.dosage)"
        content.sound = .default
        content.badge = 1
        
        // Store medication info in userInfo for deep linking
        content.userInfo = [
            "medicationId": medication.id.uuidString,
            "medicationType": medication.type,
            "tube": medication.tube,
            "dosage": schedule.dosage,
            "time": schedule.time,
            "amount": medication.amount
        ]
        
        // Parse time string (HH:mm format)
        let timeComponents = schedule.time.split(separator: ":")
        guard timeComponents.count == 2,
              let hour = Int(timeComponents[0]),
              let minute = Int(timeComponents[1]) else {
            print("❌ Invalid time format: \(schedule.time)")
            return
        }
        
        // Create date components for daily repeating notification
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create unique identifier for this notification
        let identifier = "\(medication.id.uuidString)-\(schedule.time)"
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error.localizedDescription)")
            } else {
                print("✅ Scheduled notification for \(medication.type) at \(schedule.time)")
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        print("🗑️ Cancelled all notifications")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        DispatchQueue.main.async {
            self.pendingNotification = PendingNotificationInfo(
                medicationType: userInfo["medicationType"] as? String ?? "Unknown",
                tube: userInfo["tube"] as? String ?? "Unknown",
                dosage: userInfo["dosage"] as? String ?? "Unknown",
                time: userInfo["time"] as? String ?? "Unknown",
                amount: userInfo["amount"] as? Int ?? 0
            )
            self.isShowingNotificationDetail = true
        }
        
        // Clear badge
        UNUserNotificationCenter.current().setBadgeCount(0)
        
        completionHandler()
    }
}

// Model for notification info to display
struct PendingNotificationInfo: Identifiable {
    let id = UUID()
    let medicationType: String
    let tube: String
    let dosage: String
    let time: String
    let amount: Int
}
