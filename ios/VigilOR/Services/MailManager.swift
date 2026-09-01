import Foundation
import MessageUI
import SwiftUI
import UIKit

public class MailManager: NSObject, ObservableObject {
    public static let shared = MailManager()
    
    @Published public var mailResult: Result<MFMailComposeResult, Error>? = nil
    
    public let defaultRecipients = [
        "EmilyJenie.Maluyo@Multicare.org",
        "Richona.Hill@Multicare.org"
    ]
    
    public func generateSubject(conflict: ORConflictItem) -> String {
        return "[OR Block Notice] A. Alex Mohit, MD, PhD, FAANS - Protected Window (\(conflict.formattedDate))"
    }
    
    public func generateBody(conflict: ORConflictItem) -> String {
        return """
=============================================================
VIGILOR CLINICAL SCHEDULE SENTINEL - OR AVAILABILITY NOTICE
=============================================================

Surgeon: A. Alex Mohit, MD, PhD, FAANS (Neurological Surgery)
Facility: MultiCare Neuroscience Institute
Recipients: \(defaultRecipients.joined(separator: ", "))

PROTECTED SCHEDULE BLOCK DETAILS:
-------------------------------------------------------------
• Window: \(conflict.formattedDate) (\(conflict.formattedTimeRange))
• Status: \(conflict.sanitizedTitle)
• Action Requested: Hold OR schedule clear. Do NOT book surgery cases.

To acknowledge receipt and confirm this block is noted in the OR system:
https://alexmohit825.github.io/vigilor/?ack=\(conflict.id)&status=confirmed

Office Contact: mohalex@gmail.com
Sent via VigilOR Autonomous Surgical Schedule Sentinel.
"""
    }
    
    public func openMailApp(conflict: ORConflictItem) {
        let to = defaultRecipients.joined(separator: ",")
        let subject = generateSubject(conflict: conflict)
        let body = generateBody(conflict: conflict)
        
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        
        if let url = components.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    public func copyNoticeToClipboard(conflict: ORConflictItem) {
        UIPasteboard.general.string = generateBody(conflict: conflict)
    }
}
