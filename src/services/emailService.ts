import { SurgeonProfile, Scheduler, NotificationRecord } from '../types/vigilor';
import { generateClinicalEmail } from '../engine/dispatcher';

export interface EmailDispatchResult {
  success: boolean;
  gatewayUsed: 'RESEND' | 'FORMSUBMIT' | 'MAILTO_CLIENT' | 'DIRECT_API';
  statusMessage: string;
  statusCode?: number;
  recordId: string;
  recipient: string;
  timestamp: string;
}

const FORMSUBMIT_VERIFIED_TOKEN = '0613e0d5ba48c05c2834b24e4ba63654';

/**
 * Builds a direct mailto URI for instant surgeon-authorized dispatch via native Outlook / Apple Mail
 */
export function buildSurgeonMailtoUri(
  profile: SurgeonProfile,
  schedulers: Scheduler[],
  formattedTimeWindow: string,
  sanitizedSummary: string,
  recordId: string
): string {
  const activeEmails = schedulers.filter(s => s.isActive && s.email).map(s => s.email.trim());
  const toParam = encodeURIComponent(activeEmails.join(', '));
  const surgeonFullName = `${profile.name}, ${profile.title}`;
  const subject = encodeURIComponent(`[OR Block Notice] ${surgeonFullName} - Protected Window (${formattedTimeWindow})`);
  
  const bodyText = 
`=============================================================
VIGILOR CLINICAL SCHEDULE SENTINEL - OR AVAILABILITY NOTICE
=============================================================

Surgeon: ${surgeonFullName} (${profile.specialty})
Facility: ${profile.primaryHospital}
Recipients: ${activeEmails.join(', ')}

PROTECTED SCHEDULE BLOCK DETAILS:
-------------------------------------------------------------
• Window: ${formattedTimeWindow}
• Status: ${sanitizedSummary}
• Action Requested: Hold OR schedule clear. Do NOT book surgery cases.

To acknowledge receipt and confirm this block is noted in the OR system:
https://alexmohit825.github.io/vigilor/?ack=${recordId}&status=confirmed

Office Contact: ${profile.officeEmail}
Sent via VigilOR Autonomous Surgical Schedule Sentinel.`;

  const bodyParam = encodeURIComponent(bodyText);
  return `mailto:${toParam}?subject=${subject}&body=${bodyParam}`;
}

/**
 * Dispatches an official clinical notice through the active API gateway
 */
export async function sendClinicalEmail(
  profile: SurgeonProfile,
  scheduler: Scheduler,
  formattedTimeWindow: string,
  sanitizedSummary: string,
  recordId: string,
  apiKey?: string
): Promise<EmailDispatchResult> {
  const payload = generateClinicalEmail(profile, scheduler, formattedTimeWindow, sanitizedSummary, recordId);
  const isGmailDev = scheduler.email.toLowerCase().includes('mohalex@gmail.com');
  const isHospitalDomain = scheduler.email.toLowerCase().includes('multicare.org');

  // Option 1: If Resend API Key is configured
  if (apiKey && apiKey.startsWith('re_')) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          from: 'VigilOR Sentinel <notifications@resend.dev>',
          to: [scheduler.email.trim()],
          subject: payload.subject,
          html: payload.html,
          text: payload.text
        })
      });

      if (res.ok) {
        return {
          success: true,
          gatewayUsed: 'RESEND',
          statusMessage: `Delivered via Resend API directly to ${scheduler.email}`,
          statusCode: res.status,
          recordId,
          recipient: scheduler.email,
          timestamp: new Date().toISOString()
        };
      }
    } catch (e: any) {
      console.warn('Resend API dispatch failed, falling back:', e.message);
    }
  }

  // Option 2: Direct FormSubmit endpoint
  const endpoint = isGmailDev 
    ? `https://formsubmit.co/ajax/${FORMSUBMIT_VERIFIED_TOKEN}`
    : `https://formsubmit.co/ajax/${encodeURIComponent(scheduler.email.trim())}`;

  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        _subject: payload.subject,
        surgeon: `${profile.name}, ${profile.title}`,
        specialty: profile.specialty,
        facility: profile.primaryHospital,
        recipient_name: scheduler.fullName,
        protected_window: formattedTimeWindow,
        block_type: sanitizedSummary,
        action_required: 'Please hold OR schedule clear. Do NOT book surgical cases during this upcoming protected window.',
        details: payload.text,
        _captcha: 'false'
      })
    });

    const data = await res.json().catch(() => ({}));

    if (res.ok) {
      if (isHospitalDomain) {
        return {
          success: true,
          gatewayUsed: 'FORMSUBMIT',
          statusMessage: `Transmitted to ${scheduler.email}. (Note: MultiCare corporate filters may require initial activation if not whitelisted).`,
          statusCode: res.status,
          recordId,
          recipient: scheduler.email,
          timestamp: new Date().toISOString()
        };
      }

      return {
        success: true,
        gatewayUsed: 'FORMSUBMIT',
        statusMessage: `Delivered to verified inbox ${scheduler.email}`,
        statusCode: res.status,
        recordId,
        recipient: scheduler.email,
        timestamp: new Date().toISOString()
      };
    } else {
      return {
        success: false,
        gatewayUsed: 'FORMSUBMIT',
        statusMessage: data.message || `FormSubmit HTTP Error ${res.status}`,
        statusCode: res.status,
        recordId,
        recipient: scheduler.email,
        timestamp: new Date().toISOString()
      };
    }
  } catch (err: any) {
    return {
      success: false,
      gatewayUsed: 'FORMSUBMIT',
      statusMessage: `Network transmission error: ${err.message}`,
      recordId,
      recipient: scheduler.email,
      timestamp: new Date().toISOString()
    };
  }
}
