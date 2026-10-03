#import <Foundation/Foundation.h>

/** Persistent, single-user ledger. Amounts are integer cents and durations are
 * seconds. All mutations are saved atomically before returning success. */
@interface CLLedger : NSObject
{
  NSString *_path;
  NSMutableDictionary *_data;
}
/** Open a ledger, creating an empty one if the file does not exist. Invalid
 * files return nil and are never overwritten. */
- (id) initWithPath: (NSString *)path error: (NSString **)error;
/** Client records in creation order. Treat returned collections as read-only. */
- (NSArray *) clients;
/** Time records, including billed entries. */
- (NSArray *) entries;
/** Immutable-at-issue invoice snapshots. */
- (NSArray *) invoices;
/** Business name, postal address, email, currency and payment instructions. */
- (NSDictionary *) business;
/** Persisted running timer, or nil. */
- (NSDictionary *) timer;
/** Elapsed wall-clock timer seconds, using a timezone-independent timestamp. */
- (NSTimeInterval) timerElapsed;
/** Find a client by stable identifier. */
- (NSDictionary *) clientWithID: (NSString *)identifier;
/** Add or update a client. Rate is a nonnegative decimal currency amount. */
- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate error: (NSString **)error;
/** Save payment terms as whole calendar days (0–36500); zero is due on receipt. */
- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate netDays: (NSString *)netDays error: (NSString **)error;
/** Optional client numbering; blank uses the business sequence. Once used,
 * the starting number is fixed and the client counter survives deletion. */
- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate netDays: (NSString *)netDays
 startingInvoiceNumber: (NSString *)startingNumber error: (NSString **)error;
/** Legacy clients default to Net 30. */
+ (NSInteger) netDaysForClient: (NSDictionary *)client;
/** Calculate a due date from an issue date (YYYY-MM-DD) and client terms. */
- (NSString *) dueDateForClient: (NSString *)identifier invoiceDate: (NSString *)date;
/** Delete an unused client. Referenced clients are protected. */
- (BOOL) deleteClient: (NSString *)identifier error: (NSString **)error;
/** Add manual time. Date must use YYYY-MM-DD and hours must be positive. */
- (BOOL) addTimeForClient: (NSString *)identifier date: (NSString *)date
             description: (NSString *)description hours: (NSString *)hours
                   error: (NSString **)error;
/** Return task definitions for a client; archived tasks are optional. */
- (NSArray *) tasksForClient: (NSString *)identifier includeArchived: (BOOL)includeArchived;
/** Create or update a task and its hourly rate. Changes affect future time only. */
- (BOOL) saveTask: (NSString *)identifier client: (NSString *)clientID
            name: (NSString *)name rate: (NSString *)rate error: (NSString **)error;
/** Archive or restore a task while preserving past entries and timer snapshots. */
- (BOOL) toggleTaskArchived: (NSString *)identifier error: (NSString **)error;
/** Resolve a calendar day, Monday-Sunday week or month from an ISO date.
 * Returns start, end and individual dates using Gregorian calendar arithmetic. */
+ (NSDictionary *) periodContainingDate: (NSString *)date kind: (NSString *)kind error: (NSString **)error;
/** Describe the single date or inclusive date range represented by an entry. */
+ (NSString *) dateLabelForEntry: (NSDictionary *)entry;
/** Combine the snapshotted task name and work description for printing. */
+ (NSString *) workLabelForEntry: (NSDictionary *)entry;
/** Add one total for a day, week or month using the selected task's current rate.
 * A nil task uses the client's default. Period totals are never spread over days. */
- (BOOL) addTimeForClient: (NSString *)identifier task: (NSString *)taskID
                    date: (NSString *)date period: (NSString *)kind
             description: (NSString *)description hours: (NSString *)hours
                   error: (NSString **)error;
/** Atomically add daily timesheet rows (date, hours, description). Blank/zero
 * hours are skipped; invalid rows abort the whole save. Task rates are snapshots. */
- (BOOL) addTimeRows: (NSArray *)rows client: (NSString *)identifier
               task: (NSString *)taskID error: (NSString **)error;
/** Add rows with explicit billability; nonbillable hours are never invoiced. */
- (BOOL) addTimeRows: (NSArray *)rows client: (NSString *)identifier
               task: (NSString *)taskID billable: (BOOL)billable error: (NSString **)error;
/** Edit uninvoiced time, preserving client/task identity and snapshot metadata.
 * Values: date, period (day/week/month), description, hours, rate, billable (Yes/No).
 * Unchanged displayed hours preserve the original duration to the second. */
- (BOOL) updateTimeEntry: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
+ (BOOL) isBillableEntry: (NSDictionary *)entry;
/** Start a timer with the selected task name and rate captured immediately. */
- (BOOL) startTimerForClient: (NSString *)identifier task: (NSString *)taskID
               description: (NSString *)description error: (NSString **)error;
/** Remove an unbilled time entry. Billed entries cannot be changed. */
- (BOOL) deleteEntry: (NSString *)identifier error: (NSString **)error;
/** Start one durable timer using the client's current rate. */
- (BOOL) startTimerForClient: (NSString *)identifier
               description: (NSString *)description error: (NSString **)error;
/** Stop the timer and save its elapsed duration as unbilled time. */
- (BOOL) stopTimer: (NSString **)error;
/** Issue an invoice for all unbilled time belonging to a client. Captures the
 * business, client, line items, tax, due date and total; prevents double billing.
 * A nil due date uses the client’s payment terms. */
- (BOOL) invoiceClient: (NSString *)identifier tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error;
/** Issue a standalone invoice from decimal hours at the client's current rate.
 * Does not create or consume timesheet entries. nil hours uses unbilled time. */
- (BOOL) invoiceClient: (NSString *)identifier hours: (NSString *)hours tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error;
/** Direct billing using an active task's current rate and snapshotted name. */
- (BOOL) invoiceClient: (NSString *)identifier task: (NSString *)taskID
                hours: (NSString *)hours tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error;
/** Issue using an explicit YYYY-MM-DD date; nil dueDate adds client net days.
 * Past and future issue dates are allowed. Due date must not precede issue date.
 * nil hours invoices unbilled time at its recorded dates and rates. */
- (BOOL) invoiceClient: (NSString *)identifier task: (NSString *)taskID
                hours: (NSString *)hours tax: (NSString *)tax
           issuedDate: (NSString *)issuedDate dueDate: (NSString *)dueDate error: (NSString **)error;
/** Monthly schedule: enabled, nextMonth (YYYY-MM), day (1–28), tax, holidays (ISO dates).
 * Each run bills the prior completed month; persisted progress prevents repeats. */
- (BOOL) saveRecurringForClient: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
/** Invoice eligible time in one month, excluding explicit holiday dates.
 * Ambiguous period totals require daily entries rather than guessed allocation. */
- (BOOL) invoiceMonth: (NSString *)month client: (NSString *)identifier holidays: (NSArray *)holidays
                 tax: (NSString *)tax issuedDate: (NSString *)issuedDate error: (NSString **)error;
/** Catch up due monthly schedules. Returns per-client errors; no email is sent. */
- (NSArray *) runRecurringOnDate: (NSString *)date;
/** Per-client email settings. Empty messages use the built-in templates. */
- (BOOL) saveRemindersForClient: (NSString *)identifier enabled: (BOOL)enabled
                   daysBefore: (NSString *)days message: (NSString *)message
               overdueMessage: (NSString *)overdue error: (NSString **)error;
+ (BOOL) validEmailAddress: (NSString *)email;
+ (NSInteger) reminderDaysForClient: (NSDictionary *)client;
+ (NSString *) defaultReminderMessage: (BOOL)overdue;
/** Current client message with invoice placeholders expanded. */
- (NSString *) paymentMessageForInvoice: (NSDictionary *)invoice onDate: (NSString *)date;
/** Eligible stage: due or overdue. Paid/unverified invoices and previously
 * attempted stages are excluded. A pending/review attempt blocks further mail. */
- (NSString *) reminderStageForInvoice: (NSDictionary *)invoice onDate: (NSString *)date;
/** Persist an attempt before handing it to Mail, preventing duplicate sends. */
- (BOOL) beginReminder: (NSString *)identifier stage: (NSString *)stage
               onDate: (NSString *)date error: (NSString **)error;
- (BOOL) finishReminder: (NSString *)identifier stage: (NSString *)stage
             submitted: (BOOL)submitted detail: (NSString *)detail error: (NSString **)error;
/** After checking Mail, mark an uncertain attempt submitted or allow a retry. */
- (BOOL) resolveReminder: (NSString *)identifier stage: (NSString *)stage
              submitted: (BOOL)submitted error: (NSString **)error;
+ (NSString *) reminderStatusForInvoice: (NSDictionary *)invoice;
/** Editable invoice fields, separate from stable internal IDs and billing links. */
- (NSDictionary *) editValuesForInvoice: (NSDictionary *)invoice;
- (BOOL) updateInvoice: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
/** Invoice-specific contact overrides take precedence over current profiles. */
- (NSDictionary *) billingClientForInvoice: (NSDictionary *)invoice;
- (NSString *) senderForInvoice: (NSDictionary *)invoice;
/** Whether any invoice has ever been issued or imported, including deletions. */
- (BOOL) hasIssuedInvoices;
/** Permanently delete an invoice, release its linked time for billing, and
 * reserve its number. Caller must obtain confirmation. Saves atomically. */
- (BOOL) deleteInvoice: (NSString *)identifier error: (NSString **)error;
/** Toggle paid status without changing the invoice's financial snapshot. */
- (BOOL) togglePaid: (NSString *)identifier error: (NSString **)error;
/** Explicitly confirm an invoice's payment status, including imports. */
- (BOOL) setInvoice: (NSString *)identifier paid: (BOOL)paid error: (NSString **)error;
/** Return an imported original invoice number, or the local invoice number. */
+ (NSString *) invoiceNumber: (NSDictionary *)invoice;
/** Update business details. Currency is a three-letter code. Optional logoData
 * embeds up to 5 MB of image data. Optional startingInvoiceNumber is a positive
 * integer string (blank defaults to 1), fixed once invoices exist. */
- (BOOL) saveBusiness: (NSDictionary *)business error: (NSString **)error;
/** Parse and stage a QuickBooks text export. A dry run produces a review report
 * without mutation. A committed import saves every record in one atomic write.
 * Existing customers are matched by case-insensitive full name and preserved. */
- (BOOL) importQuickBooksData: (NSData *)bytes filename: (NSString *)filename
                     commit: (BOOL)shouldCommit report: (NSString **)report
                      error: (NSString **)error;
/** Whether a time entry is eligible for a new invoice. Imported billed,
 * nonbillable and unverified time is excluded. */
+ (BOOL) isUnbilledEntry: (NSDictionary *)entry;
/** Review imported unbilled time and explicitly assign its rate and billability.
 * Previously billed time remains locked. */
- (BOOL) reviewImportedTime: (NSString *)identifier rate: (NSString *)rate
                 billable: (BOOL)billable error: (NSString **)error;
/** Convert a decimal amount into cents, rejecting malformed inputs. */
+ (NSNumber *) centsFromString: (NSString *)string;
/** Format integer cents without using floating-point arithmetic. */
+ (NSString *) money: (NSNumber *)cents;
/** Return today's local calendar date. */
+ (NSString *) today;
/** Days remaining, +days overdue, or an em dash when payment timing is unavailable. */
+ (NSString *) paymentDaysForInvoice: (NSDictionary *)invoice onDate: (NSString *)date;
/** Calculate a line amount, rounded half up to cents. */
+ (NSNumber *) amountForSeconds: (NSNumber *)seconds rate: (NSNumber *)rate;
/** Owned apps, proceeds, bank deposits and noninvoiceable development time. */
- (NSArray *) ownedApps;
- (NSArray *) appRevenue;
- (NSArray *) appPayouts;
- (NSArray *) appTime;
- (NSDictionary *) ownedApp: (NSString *)identifier;
- (BOOL) saveOwnedApp: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) saveAppRevenue: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) saveAppPayout: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) saveAppTime: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
/** Allocate source-currency proceeds and explicit bank-currency cash to a payout. */
- (BOOL) saveAppAllocation: (NSString *)identifier payout: (NSString *)payoutID values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) deleteAppAllocation: (NSString *)identifier payout: (NSString *)payoutID error: (NSString **)error;
- (NSNumber *) settledAppRevenue: (NSString *)identifier;
- (BOOL) deleteAppRecord: (NSString *)identifier collection: (NSString *)collection error: (NSString **)error;
/** Preview or atomically commit normalized CSV or Apple financial TSV; duplicates skipped. */
- (BOOL) importAppRevenueData: (NSData *)data commit: (BOOL)commit report: (NSString **)report error: (NSString **)error;
- (NSArray *) accounts;
- (NSArray *) expenses;
+ (NSNumber *) receivedForInvoice: (NSDictionary *)invoice;
+ (NSNumber *) balanceForInvoice: (NSDictionary *)invoice;
- (NSNumber *) balanceForAccount: (NSString *)identifier;
- (BOOL) saveAccount: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) saveExpense: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) deleteExpense: (NSString *)identifier error: (NSString **)error;
- (BOOL) savePayment: (NSString *)identifier invoice: (NSString *)invoiceID values: (NSDictionary *)values error: (NSString **)error;
- (BOOL) deletePayment: (NSString *)identifier invoice: (NSString *)invoiceID error: (NSString **)error;
@end
