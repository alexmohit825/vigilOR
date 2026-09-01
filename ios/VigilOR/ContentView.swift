import SwiftUI
import MessageUI

struct ContentView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @State private var filterSelection: Int = 0 // 0: Upcoming, 1: All, 2: Past
    @State private var selectedConflictForMail: ORConflictItem? = nil
    @State private var isShowingMailCompose: Bool = false
    @State private var showSettingsSheet: Bool = false
    
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
                                        selectedConflictForMail = item
                                        if MFMailComposeViewController.canSendMail() {
                                            isShowingMailCompose = true
                                        } else {
                                            openMailtoFallback(item: item)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("🛡️ VigilOR Sentinel")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingMailCompose) {
                if let conflict = selectedConflictForMail {
                    MailComposeView(conflict: conflict)
                }
            }
        }
    }
    
    private func openMailtoFallback(item: ORConflictItem) {
        let to = "EmilyJenie.Maluyo@Multicare.org,Richona.Hill@Multicare.org"
        let subject = "[OR Block Notice] A. Alex Mohit, MD, PhD, FAANS - Protected Window (\(item.formattedDate))"
        let body = "Please hold OR schedule clear for Wednesday \(item.formattedDate) (\(item.formattedTimeRange)). Do NOT book surgery cases."
        let urlStr = "mailto:\(to)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
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
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        MailManager.shared.createMailComposeViewController(conflict: conflict) ?? MFMailComposeViewController()
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}
