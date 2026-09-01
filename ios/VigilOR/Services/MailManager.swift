import Foundation
import MessageUI
import SwiftUI

public class MailManager: NSObject, ObservableObject, MFMailComposeViewControllerDelegate {
    public static let shared = MailManager()
    
    @Published public var mailResult: Result<MFMailComposeResult, Error>? = nil
    
    public func createMailComposeViewController(
        conflict: ORConflictItem,
        schedulers: [String] = ["EmilyJenie.Maluyo@Multicare.org", "Richona.Hill@Multicare.org"]
    ) -> MFMailComposeViewController? {
        guard MFMailComposeViewController.canSendMail() else {
            return nil
        }
        
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = self
        vc.setToRecipients(schedulers)
        
        let subject = "[OR Block Notice] A. Alex Mohit, MD, PhD, FAANS - Protected Window (\(conflict.formattedDate) \(conflict.formattedTimeRange))"
        vc.setSubject(subject)
        
        let body = 
"""
=============================================================
VIGILOR CLINICAL SCHEDULE SENTINEL - OR AVAILABILITY NOTICE
=============================================================

Surgeon: A. Alex Mohit, MD, PhD, FAANS (Neurological Surgery)
Facility: MultiCare Neuroscience Institute
Recipients: \(schedulers.joined(separator: ", "))

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
        
        vc.setMessageBody(body, isHTML: false)
        return vc
    }
    
    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        if let error = error {
            mailResult = .failure(error)
        } else {
            mailResult = .success(result)
        }
        controller.dismiss(animated: true)
    }
}
