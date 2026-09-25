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
/** Find a client by stable identifier. */
- (NSDictionary *) clientWithID: (NSString *)identifier;
/** Add or update a client. Rate is a nonnegative decimal currency amount. */
- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate error: (NSString **)error;
/** Delete an unused client. Referenced clients are protected. */
- (BOOL) deleteClient: (NSString *)identifier error: (NSString **)error;
/** Add manual time. Date must use YYYY-MM-DD and hours must be positive. */
- (BOOL) addTimeForClient: (NSString *)identifier date: (NSString *)date
             description: (NSString *)description hours: (NSString *)hours
                   error: (NSString **)error;
/** Remove an unbilled time entry. Billed entries cannot be changed. */
- (BOOL) deleteEntry: (NSString *)identifier error: (NSString **)error;
/** Start one durable timer using the client's current rate. */
- (BOOL) startTimerForClient: (NSString *)identifier
               description: (NSString *)description error: (NSString **)error;
/** Stop the timer and save its elapsed duration as unbilled time. */
- (BOOL) stopTimer: (NSString **)error;
/** Issue an invoice for all unbilled time belonging to a client. Captures the
 * business, client, line items, tax, due date and total; prevents double billing. */
- (BOOL) invoiceClient: (NSString *)identifier tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error;
/** Toggle paid status without changing the invoice's financial snapshot. */
- (BOOL) togglePaid: (NSString *)identifier error: (NSString **)error;
/** Explicitly confirm an invoice's payment status, including imports. */
- (BOOL) setInvoice: (NSString *)identifier paid: (BOOL)paid error: (NSString **)error;
/** Return an imported original invoice number, or the local invoice number. */
+ (NSString *) invoiceNumber: (NSDictionary *)invoice;
/** Update business details. Currency is a three-letter code. */
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
