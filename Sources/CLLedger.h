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
/** Calculate a line amount, rounded half up to cents. */
+ (NSNumber *) amountForSeconds: (NSNumber *)seconds rate: (NSNumber *)rate;
@end
