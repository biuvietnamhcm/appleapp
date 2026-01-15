import SwiftUI

struct NotificationDetailView: View {
    let notification: PendingNotificationInfo
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "pills.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Medication Reminder")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("It's time to take your medication")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            
            // Medication Details Card
            VStack(alignment: .leading, spacing: 16) {
                DetailRow(icon: "pills.fill", label: "Medication", value: notification.medicationType, color: .blue)
                
                Divider()
                
                DetailRow(icon: "testtube.2", label: "Tube", value: notification.tube.uppercased(), color: .purple)
                
                Divider()
                
                DetailRow(icon: "clock.fill", label: "Scheduled Time", value: notification.time, color: .orange)
                
                Divider()
                
                DetailRow(icon: "number", label: "Dosage", value: notification.dosage, color: .green)
                
                Divider()
                
                DetailRow(icon: "list.clipboard", label: "Total in Tube", value: "\(notification.amount) tablets", color: .red)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(15)
            .padding(.horizontal)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                Button(action: {
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Got it, Thanks!")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    onDismiss()
                }) {
                    Text("Dismiss")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Spacer()
        }
    }
}
