import SwiftUI
import MessageUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @State private var filterSelection: Int = 0 // 0: Upcoming, 1: All, 2: Past
    @State private var selectedConflictForAction: ORConflictItem? = nil
    @State private var isShowingActionSheet: Bool = false
    @State private var isShowingInAppMail: Bool = false
    @State private var toastMessage: String? = nil
    
    var filteredConflicts: [ORConflictItem] {
        switch filterSelection {
        case 0:
            return calendarManager.detectedConflicts.filter { !$0.isPast }
        case 1:
            return calendarManager.detectedConflicts
        case 2:
            return calendarManager.detectedConflicts.filter { $0.isPast }
        default:
            return calendarManager.detectedConflicts
        }
    }
    
    var upcomingCount: Int {
        calendarManager.detectedConflicts.filter { !$0.isPast }.count
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.06, green: 0.09, blue: 0.16)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Surgeon Card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("A. Alex Mohit, MD, PhD, FAANS")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("MultiCare Neuroscience Institute • OR Sentinel")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button(action: {
                                calendarManager.scanForWednesdayConflicts()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.06, green: 0.75, blue: 0.50))
                                    .rotationEffect(.degrees(calendarManager.isScanning ? 360 : 0))
                                    .animation(calendarManager.isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: calendarManager.isScanning)
                            }
                        }
                        
                        Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 4)
                        
                        HStack {
                            Label("Calendar Sync: \(calendarManager.isAuthorized ? "Connected" : "Authorization Required")", systemImage: calendarManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(calendarManager.isAuthorized ? Color(red: 0.06, green: 0.75, blue: 0.50) : .orange)
                            
                            Spacer()
                            
                            Text("\(upcomingCount) Upcoming Blocks")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.06, green: 0.75, blue: 0.50).opacity(0.25))
                                .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(Color(red: 0.10, green: 0.14, blue: 0.22))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Filter Picker
                    Picker("Filter", selection: $filterSelection) {
                        Text("Upcoming (\(upcomingCount))").tag(0)
                        Text("All (\(calendarManager.detectedConflicts.count))").tag(1)
                        Text("Past History").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    // List of Conflicts
                    if calendarManager.isScanning {
                        Spacer()
                        ProgressView("Auditing Apple Calendar...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .foregroundColor(.gray)
                        Spacer()
                    } else if filteredConflicts.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.6))
                            Text("No Wednesday Conflicts Found")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Your Wednesday afternoons are clear or protected.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredConflicts) { item in
                                    ConflictCardView(item: item) {
                                        selectedConflictForAction = item
                                        isShowingActionSheet = true
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                        }
                    }
                }
                
                // Floating Toast
                if let message = toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(message)
                                .font(.footnote.bold())
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.12, green: 0.18, blue: 0.28))
                        .cornerRadius(20)
                        .shadow(radius: 8)
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(), value: toastMessage)
                }
            }
            .navigationTitle("🛡️ VigilOR Sentinel")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Send Protected Block Notice",
                isPresented: $isShowingActionSheet,
                titleVisibility: .visible
            ) {
                if let conflict = selectedConflictForAction {
                    Button("📧 Open in Apple Mail / Outlook (Recommended)") {
                        MailManager.shared.openMailApp(conflict: conflict)
                    }
                    
                    if MFMailComposeViewController.canSendMail() {
                        Button("✉️ Compose In-App") {
                            isShowingInAppMail = true
                        }
                    }
                    
                    Button("📋 Copy Notice Text to Clipboard") {
                        MailManager.shared.copyNoticeToClipboard(conflict: conflict)
                        showToast("Notice copied to clipboard!")
                    }
                    
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                if let conflict = selectedConflictForAction {
                    Text("Recipients: Emily Maluyo & Richona Hill\nBlock: \(conflict.formattedDate) (\(conflict.formattedTimeRange))")
                }
            }
            .sheet(isPresented: $isShowingInAppMail) {
                if let conflict = selectedConflictForAction {
                    MailComposeView(conflict: conflict, isShowing: $isShowingInAppMail)
                }
            }
        }
    }
    
    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }
}

struct ConflictCardView: View {
    let item: ORConflictItem
    let onDispatch: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.formattedDate)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
                Text(item.formattedTimeRange)
                    .font(.caption.bold())
                    .foregroundColor(Color(red: 0.60, green: 0.40, blue: 0.95))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.60, green: 0.40, blue: 0.95).opacity(0.15))
                    .cornerRadius(4)
            }
            
            Text(item.title)
                .font(.footnote)
                .foregroundColor(.gray)
            
            HStack {
                if item.isPast {
                    Text("Historical (No Alert Required)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                } else {
                    Text("Recipients: Emily & Richona (MultiCare)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: onDispatch) {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill")
                            Text("Send Notice")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.06, green: 0.75, blue: 0.50))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(red: 0.10, green: 0.14, blue: 0.22))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.isPast ? Color.gray.opacity(0.2) : Color.gray.opacity(0.4), lineWidth: 1)
        )
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let conflict: ORConflictItem
    @Binding var isShowing: Bool
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var parent: MailComposeView
        
        init(parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isShowing = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(MailManager.shared.defaultRecipients)
        vc.setSubject(MailManager.shared.generateSubject(conflict: conflict))
        vc.setMessageBody(MailManager.shared.generateBody(conflict: conflict), isHTML: false)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}
