import { CalendarEvent, ProtectionRule, Scheduler, SurgeonProfile, NotificationRecord } from '../types/vigilor';
import { evaluateEventAgainstRule, formatTime12h } from './ruleEvaluator';
import { generateClinicalEmail } from './dispatcher';
import { sendClinicalEmail, buildSurgeonMailtoUri, EmailDispatchResult } from '../services/emailService';

export interface PreExistingConflictItem {
  id: string;
  event: CalendarEvent;
  ruleName: string;
  originalSummary: string;
  sanitizedSummary: string;
  eventDateFormatted: string;
  timeWindowFormatted: string;
  targetSchedulers: Scheduler[];
  isPreExisting: boolean;
  isPast: boolean;
  status: 'PENDING_DISPATCH' | 'DISPATCHED' | 'PAST_EXPIRED' | 'FAILED';
  dispatchedAt?: string;
  mailtoUri?: string;
  lastDispatchResult?: EmailDispatchResult;
}

/**
 * Scans a list of calendar events and identifies all conflicting Wednesday appointments.
 * Strictly separates past vs future events.
 */
export function scanCalendarForConflicts(
  events: CalendarEvent[],
  rules: ProtectionRule[],
  schedulers: Scheduler[],
  profile: SurgeonProfile
): PreExistingConflictItem[] {
  const activeRules = rules.filter(r => r.isActive);
  if (activeRules.length === 0) return [];

  const now = new Date();
  const results: PreExistingConflictItem[] = [];

  for (const event of events) {
    for (const rule of activeRules) {
      const evaluation = evaluateEventAgainstRule(event, rule, schedulers, `${profile.name}, ${profile.title}`);
      if (evaluation.isMatch) {
        const start = new Date(event.start);
        const end = new Date(event.end);

        const isPast = end.getTime() < now.getTime();

        const dateOptions: Intl.DateTimeFormatOptions = {
          weekday: 'long',
          year: 'numeric',
          month: 'short',
          day: 'numeric'
        };
        const eventDateFormatted = start.toLocaleDateString('en-US', dateOptions);

        const startTimeStr = formatTime12h(`${start.getHours().toString().padStart(2, '0')}:${start.getMinutes().toString().padStart(2, '0')}`);
        const endTimeStr = formatTime12h(`${end.getHours().toString().padStart(2, '0')}:${end.getMinutes().toString().padStart(2, '0')}`);
        const timeWindowFormatted = `${startTimeStr} – ${endTimeStr}`;
        const fullWindowStr = `${eventDateFormatted} (${timeWindowFormatted})`;

        const mailtoUri = buildSurgeonMailtoUri(
          profile,
          evaluation.targetSchedulers,
          fullWindowStr,
          evaluation.sanitizedSummary,
          `conflict_${event.uid}`
        );

        results.push({
          id: `audit_conflict_${event.uid}`,
          event,
          ruleName: rule.name,
          originalSummary: event.summary,
          sanitizedSummary: evaluation.sanitizedSummary,
          eventDateFormatted,
          timeWindowFormatted,
          targetSchedulers: evaluation.targetSchedulers,
          isPreExisting: true,
          isPast,
          status: isPast ? 'PAST_EXPIRED' : 'PENDING_DISPATCH',
          mailtoUri
        });
        break; // Match first active rule per event
      }
    }
  }

  // Sort chronologically
  return results.sort((a, b) => new Date(a.event.start).getTime() - new Date(b.event.start).getTime());
}

/**
 * Dispatches an official OR Blackout notice for a single pre-existing conflict.
 * MANDATORY GUARD: Rejects any past events from dispatching notices.
 */
export async function dispatchConflictNotice(
  item: PreExistingConflictItem,
  profile: SurgeonProfile,
  apiKey?: string
): Promise<{ records: NotificationRecord[]; results: EmailDispatchResult[] }> {
  const now = new Date();
  const end = new Date(item.event.end);

  // STRICT SAFETY GUARD: Do NOT send notices for events in the past
  if (item.isPast || end.getTime() < now.getTime()) {
    console.warn(`[SAFETY FILTER] Blocked dispatch for historical/past event on ${item.eventDateFormatted}.`);
    return { records: [], results: [] };
  }

  const records: NotificationRecord[] = [];
  const results: EmailDispatchResult[] = [];
  const start = new Date(item.event.start);
  const fullWindowStr = `${item.eventDateFormatted} (${item.timeWindowFormatted})`;

  for (const scheduler of item.targetSchedulers) {
    if (!scheduler.isActive || !scheduler.email) continue;

    const recordId = `notif_pre_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const emailPayload = generateClinicalEmail(
      profile,
      scheduler,
      fullWindowStr,
      item.sanitizedSummary,
      recordId
    );

    const dispatchResult = await sendClinicalEmail(
      profile,
      scheduler,
      fullWindowStr,
      item.sanitizedSummary,
      recordId,
      apiKey
    );
    results.push(dispatchResult);

    const record: NotificationRecord = {
      id: recordId,
      ruleId: 'rule_pre_existing_scan',
      ruleName: item.ruleName,
      schedulerId: scheduler.id,
      schedulerName: scheduler.fullName,
      schedulerFacility: scheduler.facilityName,
      recipientEmail: scheduler.email,
      eventUid: item.event.uid,
      eventSummary: item.sanitizedSummary,
      eventStart: start.toISOString(),
      eventEnd: end.toISOString(),
      emailSubject: emailPayload.subject,
      emailHtml: emailPayload.html,
      emailText: emailPayload.text,
      deliveryStatus: dispatchResult.success ? 'SENT' : 'FAILED',
      sentAt: new Date().toISOString(),
      ackStatus: 'UNACKNOWLEDGED'
    };

    records.push(record);
  }

  return { records, results };
}

/**
 * Generates an illustrative demonstration calendar with upcoming Wednesdays and past dates
 */
export function generateSamplePreExistingCalendar(): CalendarEvent[] {
  const today = new Date();
  
  // Past Wednesday (2 weeks ago)
  const pastWed = new Date(today);
  pastWed.setDate(today.getDate() - 14 - ((today.getDay() - 3 + 7) % 7));
  const pastWedStart = new Date(pastWed);
  pastWedStart.setHours(13, 0, 0, 0);
  const pastWedEnd = new Date(pastWed);
  pastWedEnd.setHours(16, 0, 0, 0);

  // Upcoming Wednesday #1 (Next week)
  const daysUntilNextWed = (3 - today.getDay() + 7) % 7 || 7;
  const nextWed1 = new Date(today);
  nextWed1.setDate(today.getDate() + daysUntilNextWed);
  const nextWed1Start = new Date(nextWed1);
  nextWed1Start.setHours(13, 0, 0, 0);
  const nextWed1End = new Date(nextWed1);
  nextWed1End.setHours(16, 30, 0, 0);

  // Upcoming Wednesday #2 (Following week)
  const nextWed2 = new Date(nextWed1);
  nextWed2.setDate(nextWed1.getDate() + 7);
  const nextWed2Start = new Date(nextWed2);
  nextWed2Start.setHours(14, 0, 0, 0);
  const nextWed2End = new Date(nextWed2);
  nextWed2End.setHours(17, 0, 0, 0);

  return [
    {
      uid: 'evt_past_wed_academic',
      summary: 'Academic Department Faculty Meeting (Completed)',
      start: pastWedStart,
      end: pastWedEnd,
      calendarName: 'Personal',
      location: 'Faculty Boardroom'
    },
    {
      uid: 'evt_upcoming_wed_1',
      summary: 'Outpatient Neurotrauma Consultation Clinic Block',
      start: nextWed1Start,
      end: nextWed1End,
      calendarName: 'Personal',
      location: 'Suite 400 - Medical Tower'
    },
    {
      uid: 'evt_upcoming_wed_2',
      summary: 'Protected Academic Research & Operative Planning Window',
      start: nextWed2Start,
      end: nextWed2End,
      calendarName: 'Personal',
      location: 'Research Office'
    }
  ];
}
