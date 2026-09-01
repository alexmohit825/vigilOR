import Foundation
import EventKit
import Combine

public struct ORConflictItem: Identifiable {
    public let id: String
    public let title: String
    public let sanitizedTitle: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    public let isPast: Bool
    public var isDispatched: Bool = false
    public var dispatchedAt: Date? = nil
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: startDate)
    }
    
    public var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }
}

public class CalendarManager: ObservableObject {
    public static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    @Published public var isAuthorized: Bool = false
    @Published public var detectedConflicts: [ORConflictItem] = []
    @Published public var isScanning: Bool = false
    @Published public var statusMessage: String = "Ready"
    
    public let primarySchedulers: [String] = [
        "EmilyJenie.Maluyo@Multicare.org",
        "Richona.Hill@Multicare.org"
    ]
    
    private init() {
        checkCurrentAuthorization()
    }
    
    public func checkCurrentAuthorization() {
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            self.isAuthorized = (status == .fullAccess || status == .authorized)
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            self.isAuthorized = (status == .authorized)
        }
    }
    
    public func requestAccess() {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.scanForWednesdayConflicts()
                    } else if let error = error {
                        self?.statusMessage = "Calendar access denied: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.scanForWednesdayConflicts()
                    } else if let error = error {
                        self?.statusMessage = "Calendar access denied: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    public func scanForWednesdayConflicts() {
        guard isAuthorized else {
            requestAccess()
            return
        }
        
        isScanning = true
        statusMessage = "Auditing Apple Calendar for Wednesday protected blocks..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let calendar = Calendar.current
            
            // Search window: 30 days past to 90 days future
            guard let startDate = calendar.date(byAdding: .day, value: -30, to: now),
                  let endDate = calendar.date(byAdding: .day, value: 90, to: now) else {
                DispatchQueue.main.async {
                    self.isScanning = false
                }
                return
            }
            
            let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let events = self.eventStore.events(matching: predicate)
            
            var conflicts: [ORConflictItem] = []
            
            for event in events {
                // Check if Wednesday (weekday == 4 in Gregorian calendar)
                let weekday = calendar.component(.weekday, from: event.startDate)
                guard weekday == 4 else { continue }
                
                // Check time range: intersects with 12:00 PM – 5:00 PM
                let startHour = calendar.component(.hour, from: event.startDate)
                let endHour = calendar.component(.hour, from: event.endDate)
                
                let isWednesdayAfternoon = (startHour >= 12 && startHour < 17) || (endHour > 12 && startHour < 17)
                guard isWednesdayAfternoon else { continue }
                
                // Exclude surgery tags
                let summary = event.title ?? "Personal Appointment"
                let lowerSummary = summary.lowercased()
                if lowerSummary.contains("#surgery") || lowerSummary.contains("#orcase") || lowerSummary.contains("grand rounds") {
                    continue
                }
                
                let isPast = event.endDate < now
                let sanitized = "Protected Schedule Block (A. Alex Mohit, MD, PhD, FAANS)"
                
                let item = ORConflictItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: summary,
                    sanitizedTitle: sanitized,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    location: event.location,
                    isPast: isPast,
                    isDispatched: false,
                    dispatchedAt: nil
                )
                conflicts.append(item)
            }
            
            // Sort chronologically
            conflicts.sort { $0.startDate < $1.startDate }
            
            DispatchQueue.main.async {
                self.detectedConflicts = conflicts
                self.isScanning = false
                let upcomingCount = conflicts.filter { !$0.isPast }.count
                self.statusMessage = "Scan complete: Found \(conflicts.count) total Wednesday appointments (\(upcomingCount) upcoming)."
            }
        }
    }
}
