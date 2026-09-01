import SwiftUI
import EventKit

@main
struct VigilORApp: App {
    @StateObject private var calendarManager = CalendarManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarManager)
                .onAppear {
                    calendarManager.requestAccess()
                }
        }
    }
}
