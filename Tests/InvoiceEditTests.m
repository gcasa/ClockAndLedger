#import <Foundation/Foundation.h>
#import "CLLedger.h"
static unsigned int checks;
static void Check (BOOL ok, NSString *label) { checks++; if (!ok) { NSLog (@"FAIL: %@", label); exit (1); } }
static NSMutableDictionary *Draft (CLLedger *ledger, NSDictionary *invoice)
{
  NSData *data = [NSPropertyListSerialization dataWithPropertyList: [ledger editValuesForInvoice: invoice] format: NSPropertyListBinaryFormat_v1_0 options: 0 error: NULL];
  return [NSPropertyListSerialization propertyListWithData: data options: NSPropertyListMutableContainersAndLeaves format: NULL error: NULL];
}
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"Ledger.plist"];
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: NULL];
  NSString *cid, *iid;
  NSDictionary *invoice;
  NSMutableDictionary *draft;
  NSMutableDictionary *business = [NSMutableDictionary dictionaryWithDictionary: [ledger business]];
  NSString *error = nil;
  [business setObject: @"sender@example.test" forKey: @"email"];
  Check ([ledger saveBusiness: business error: &error], @"Business fixture");
  Check ([ledger saveClient: nil name: @"Original" email: @"original@example.test" address: @"Original address" rate: @"100" error: &error], @"Client fixture");
  cid = [[[[ledger clients] lastObject] objectForKey: @"id"] copy];
  Check ([ledger addTimeForClient: cid date: @"2026-01-01" description: @"First" hours: @"1" error: &error], @"First timesheet line");
  Check ([ledger addTimeForClient: cid date: @"2026-01-02" description: @"Second" hours: @"2" error: &error], @"Second timesheet line");
  Check ([ledger invoiceClient: cid tax: @"10" dueDate: @"2099-04-01" error: &error], @"Issue timesheet invoice");
  invoice = [[ledger invoices] lastObject]; iid = [[invoice objectForKey: @"id"] copy];
  draft = Draft (ledger, invoice);
  Check ([[draft objectForKey: @"taxAmount"] isEqual: @""], @"Percentage tax recalculates by default");
  [draft setObject: @"Revised name" forKey: @"client_name"];
  [draft setObject: @"revised@example.test" forKey: @"client_email"];
  [draft setObject: @"Revised address" forKey: @"client_address"];
  [draft setObject: @"Renamed business" forKey: @"business_name"];
  [draft setObject: @"other-sender@example.test" forKey: @"business_email"];
  [draft setObject: @"REVISED-500" forKey: @"number"];
  [draft setObject: @"2026-02-01" forKey: @"date"];
  [draft setObject: @"2026-03-01" forKey: @"dueDate"];
  [draft setObject: @"Paid" forKey: @"status"];
  [draft setObject: @"Pay by bank transfer" forKey: @"notes"];
  [[[draft objectForKey: @"lines"] objectAtIndex: 0] setObject: @"3.5" forKey: @"hours"];
  [[[draft objectForKey: @"lines"] objectAtIndex: 0] setObject: @"125" forKey: @"rate"];
  [[[draft objectForKey: @"lines"] objectAtIndex: 0] setObject: @"Custom task" forKey: @"taskName"];
  [[[draft objectForKey: @"lines"] objectAtIndex: 0] setObject: @"2026-01-10" forKey: @"endDate"];
  [[draft objectForKey: @"lines"] removeLastObject];
  Check ([ledger updateInvoice: iid values: draft error: &error], [NSString stringWithFormat: @"Save full edit: %@", error]);
  Check ([[invoice objectForKey: @"id"] isEqual: iid] && [[CLLedger invoiceNumber: invoice] isEqual: @"REVISED-500"], @"Display number changes without replacing internal ID");
  Check ([[invoice objectForKey: @"subtotal"] intValue] == 43750 && [[invoice objectForKey: @"tax"] intValue] == 4375 && [[invoice objectForKey: @"total"] intValue] == 48125, @"Totals recomputed exactly");
  Check ([[invoice objectForKey: @"paid"] boolValue], @"Payment state editable");
  Check ([[[invoice objectForKey: @"client"] objectForKey: @"name"] isEqual: @"Revised name"], @"Invoice client name updated");
  Check ([[[ledger clientWithID: cid] objectForKey: @"name"] isEqual: @"Original"], @"Client profile stays unchanged");
  Check (![[[ledger business] objectForKey: @"name"] isEqual: @"Renamed business"], @"Business profile stays unchanged");
  Check ([[[ledger billingClientForInvoice: invoice] objectForKey: @"email"] isEqual: @"revised@example.test"], @"Emails use invoice recipient override");
  Check ([[ledger senderForInvoice: invoice] isEqual: @"other-sender@example.test"], @"Sender uses invoice override");
  Check ([[[ledger entries] objectAtIndex: 0] objectForKey: @"invoiceID"] != nil && [[[[ledger entries] objectAtIndex: 0] objectForKey: @"invoiceID"] isEqual: iid], @"Retained time remains billed");
  Check ([CLLedger isUnbilledEntry: [[ledger entries] objectAtIndex: 1]], @"Removed line releases linked time");
  Check ([[[[ledger entries] objectAtIndex: 0] objectForKey: @"rate"] intValue] == 10000, @"Editing invoice preserves source time rate");
  Check ([[CLLedger dateLabelForEntry: [[invoice objectForKey: @"lines"] objectAtIndex: 0]] isEqual: @"2026-01-01 to 2026-01-10"], @"Edited service date range rendered");
  [ledger release]; ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil, [NSString stringWithFormat: @"Reopen edited ledger: %@", error]);
  invoice = [[ledger invoices] lastObject];
  Check ([[[ledger billingClientForInvoice: invoice] objectForKey: @"name"] isEqual: @"Revised name"], @"Edited contact survives restart");
  draft = Draft (ledger, invoice);
  [draft setObject: @"Unpaid" forKey: @"status"];
  [draft setObject: @"7.25" forKey: @"taxAmount"];
  [[[draft objectForKey: @"lines"] objectAtIndex: 0] setObject: @"500.10" forKey: @"amount"];
  Check ([ledger updateInvoice: iid values: draft error: &error], @"Edit explicit amounts");
  Check ([[invoice objectForKey: @"total"] intValue] == 50735, @"Amount overrides control total");
  Check ([[[[invoice objectForKey: @"lines"] objectAtIndex: 0] objectForKey: @"importedAmount"] boolValue], @"Amount-only line does not display inconsistent hours calculation");
  Check (![ledger updateInvoice: iid values: [NSDictionary dictionary] error: &error], @"Incomplete edit rejected");
  draft = Draft (ledger, invoice); [draft setObject: @"" forKey: @"client_name"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Blank client name rejected");
  Check ([[[invoice objectForKey: @"client"] objectForKey: @"name"] isEqual: @"Revised name"], @"Invalid edits are atomic");
  draft = Draft (ledger, invoice); [draft setObject: @"2026-02-30" forKey: @"date"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Invalid date rejected");
  draft = Draft (ledger, invoice); [draft setObject: @"2020-01-01" forKey: @"dueDate"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Due before issue rejected");
  draft = Draft (ledger, invoice); [draft setObject: @"101" forKey: @"taxPercent"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Invalid tax rejected");
  draft = Draft (ledger, invoice); [draft setObject: [NSMutableArray array] forKey: @"lines"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Empty invoice rejected");
  Check ([ledger invoiceClient: cid hours: @"1" tax: @"0" dueDate: @"2099-04-01" error: &error], @"Create another invoice");
  draft = Draft (ledger, [[ledger invoices] lastObject]); [draft setObject: @"REVISED-500" forKey: @"number"];
  Check (![ledger updateInvoice: [[[ledger invoices] lastObject] objectForKey: @"id"] values: draft error: &error], @"Reject duplicate displayed numbers");
  [draft setObject: iid forKey: @"number"];
  Check (![ledger updateInvoice: [[[ledger invoices] lastObject] objectForKey: @"id"] values: draft error: &error], @"Original number remains reserved");
  Check ([ledger saveRemindersForClient: cid enabled: YES daysBefore: @"3" message: @"Hello {client}" overdueMessage: @"Late {client}" error: &error], @"Enable reminders for test");
  Check ([[ledger paymentMessageForInvoice: invoice onDate: @"2026-02-20"] isEqual: @"Hello Revised name"], @"Reminder uses edited client name");
  Check ([ledger beginReminder: iid stage: @"due" onDate: @"2026-02-27" error: &error], @"Journal pending email");
  Check (![ledger updateInvoice: iid values: Draft (ledger, invoice) error: &error], @"Pending send blocks edits");
  Check ([ledger finishReminder: iid stage: @"due" submitted: YES detail: @"Test only" error: &error], @"Resolve pending email");
  Check ([ledger updateInvoice: iid values: Draft (ledger, invoice) error: &error], @"Edit after submission");
  Check ([[CLLedger reminderStatusForInvoice: invoice] isEqual: @"Reminder: submitted"], @"Edits do not resend previous reminders");
  [ledger release]; ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil, @"Reopen amount-only edited invoice");
  {
    NSMutableDictionary *unchanged = Draft (ledger, [[ledger invoices] objectAtIndex: 0]);
    NSData *before = [NSData dataWithContentsOfFile: path];
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath: path withIntermediateDirectories: NO attributes: nil error: NULL];
    [unchanged setObject: @"Must roll back" forKey: @"client_name"];
    Check (![ledger updateInvoice: iid values: unchanged error: &error], @"Write failure reported");
    Check ([[[[[ledger invoices] objectAtIndex: 0] objectForKey: @"client"] objectForKey: @"name"] isEqual: @"Revised name"], @"Write failure restores original invoice");
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL]; [before writeToFile: path atomically: YES];
  }
  [ledger release]; [cid release]; [iid release];
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: %u invoice editing checks", checks); [pool drain]; return 0;
}
