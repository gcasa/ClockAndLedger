#import <Foundation/Foundation.h>
#import "CLLedger.h"
static unsigned int checks;
static void Check (BOOL result, NSString *message)
{
  checks++;
  if (!result) { NSLog (@"FAIL: %@", message); exit (1); }
}
static NSDictionary *Schedule (NSString *month, NSArray *holidays)
{
  return [NSDictionary dictionaryWithObjectsAndKeys: month, @"nextMonth", holidays, @"holidays",
    [NSNumber numberWithBool: YES], @"enabled", [NSNumber numberWithInt: 5], @"day", @"10", @"tax", nil];
}
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"Ledger.plist"];
  NSString *error = nil, *identifier;
  NSArray *holidays = [NSArray arrayWithObject: @"2026-09-07"];
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: &error];
  NSDictionary *invoice;
  NSMutableDictionary *bad;
  NSData *before;
  Check ([ledger saveClient: nil name: @"Monthly" email: @"" address: @"" rate: @"100" error: &error], @"client");
  identifier = [[[[ledger clients] objectAtIndex: 0] objectForKey: @"id"] copy];
  Check ([ledger addTimeForClient: identifier date: @"2026-09-07" description: @"Holiday" hours: @"8" error: &error], @"holiday time");
  Check ([ledger addTimeForClient: identifier date: @"2026-09-08" description: @"Work" hours: @"2" error: &error], @"work time");
  Check ([ledger addTimeForClient: identifier date: @"2026-08-31" description: @"Earlier" hours: @"1" error: &error], @"earlier time");
  Check ([ledger addTimeRows: [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: @"2026-09-09", @"date", @"1", @"hours", @"Lunch", @"description", nil]] client: identifier task: nil billable: NO error: &error], @"nonbillable time");
  Check ([ledger saveRecurringForClient: identifier values: Schedule (@"2026-09", holidays) error: &error], @"save schedule");
  Check ([[ledger runRecurringOnDate: @"2026-10-04"] count] == 0 && [[ledger invoices] count] == 0, @"wait for issue day");
  Check ([[ledger runRecurringOnDate: @"2026-10-05"] count] == 0 && [[ledger invoices] count] == 1, @"issue on schedule");
  invoice = [[ledger invoices] objectAtIndex: 0];
  Check ([[invoice objectForKey: @"total"] intValue] == 22000 && [[invoice objectForKey: @"lines"] count] == 1, @"holiday nonbillable and outside-month exclusion with tax");
  Check ([[invoice objectForKey: @"date"] isEqual: @"2026-10-05"] && [[invoice objectForKey: @"dueDate"] isEqual: @"2026-11-04"], @"issue date and terms");
  Check ([[invoice objectForKey: @"billingMonth"] isEqual: @"2026-09"], @"billing month snapshot");
  [ledger release]; ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil && [[ledger runRecurringOnDate: @"2026-10-06"] count] == 0 && [[ledger invoices] count] == 1, @"restart idempotence");
  Check ([[ledger runRecurringOnDate: @"2027-01-05"] count] == 0 && [[ledger invoices] count] == 1, @"empty months skip without invoices");
  Check ([[[[ledger clientWithID: identifier] objectForKey: @"recurring"] objectForKey: @"nextMonth"] isEqual: @"2027-01"], @"year rollover progress");
  Check ([ledger invoiceMonth: @"2026-08" client: identifier holidays: holidays tax: @"0" issuedDate: @"2026-10-05" error: &error], @"manual billing month");
  Check (![ledger invoiceMonth: @"2026-08" client: identifier holidays: holidays tax: @"0" issuedDate: @"2026-10-05" error: &error], @"no duplicate manual billing");
  Check ([ledger addTimeForClient: identifier task: nil date: @"2027-01-15" period: @"month" description: @"Total" hours: @"80" error: &error], @"monthly aggregate");
  Check ([ledger saveRecurringForClient: identifier values: Schedule (@"2027-01", [NSArray arrayWithObject: @"2027-01-01"]) error: &error], @"holiday schedule");
  before = [NSData dataWithContentsOfFile: path];
  Check ([[ledger runRecurringOnDate: @"2027-02-05"] count] == 1, @"ambiguous aggregate requires review");
  Check ([before isEqual: [NSData dataWithContentsOfFile: path]], @"blocked run has no changes");
  Check ([ledger saveRecurringForClient: identifier values: Schedule (@"2027-01", [NSArray array]) error: &error], @"remove holiday");
  Check ([[ledger runRecurringOnDate: @"2027-02-05"] count] == 0 && [[ledger invoices] count] == 3, @"contained aggregate without holiday billed");
  Check ([ledger addTimeForClient: identifier task: nil date: @"2027-03-01" period: @"week" description: @"Week" hours: @"5" error: &error], @"week");
  Check ([ledger addTimeForClient: identifier task: nil date: @"2027-03-31" period: @"week" description: @"Crossing" hours: @"5" error: &error], @"crossing week");
  Check (![ledger invoiceMonth: @"2027-03" client: identifier holidays: [NSArray array] tax: @"0" issuedDate: @"2027-04-05" error: &error], @"cross-month aggregate blocks whole invoice");
  bad = [NSMutableDictionary dictionaryWithDictionary: Schedule (@"2027-03", holidays)];
  [bad setObject: [NSNumber numberWithInt: 29] forKey: @"day"];
  Check (![ledger saveRecurringForClient: identifier values: bad error: &error], @"invalid schedule rejected");
  Check ([ledger deleteEntry: [[[ledger entries] lastObject] objectForKey: @"id"] error: &error], @"remove ambiguous crossing total");
  Check ([ledger addTimeForClient: identifier date: @"2027-04-12" description: @"Rollback" hours: @"1" error: &error], @"rollback time");
  Check ([ledger saveRecurringForClient: identifier values: Schedule (@"2027-04", [NSArray array]) error: &error], @"rollback schedule");
  before = [NSData dataWithContentsOfFile: path];
  [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath: path withIntermediateDirectories: NO attributes: nil error: NULL];
  Check ([[ledger runRecurringOnDate: @"2027-05-05"] count] == 1 && [[ledger invoices] count] == 3, @"failed invoice save rolls back");
  Check ([[[[ledger clientWithID: identifier] objectForKey: @"recurring"] objectForKey: @"nextMonth"] isEqual: @"2027-04"], @"failed save does not advance schedule");
  [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
  [before writeToFile: path atomically: YES];
  Check ([[ledger runRecurringOnDate: @"2027-05-05"] count] == 0 && [[ledger invoices] count] == 4, @"retry after failure issues once");
  Check ([ledger deleteInvoice: [[[ledger invoices] lastObject] objectForKey: @"id"] error: &error], @"delete scheduled invoice");
  Check ([[ledger runRecurringOnDate: @"2027-05-05"] count] == 0 && [[ledger invoices] count] == 3, @"deletion does not rerun completed schedule");
  Check ([ledger addTimeForClient: identifier date: @"2027-06-12" description: @"June" hours: @"1" error: &error], @"catch-up June");
  Check ([ledger addTimeForClient: identifier date: @"2027-07-12" description: @"July" hours: @"1" error: &error], @"catch-up July");
  Check ([[ledger runRecurringOnDate: @"2027-08-05"] count] == 0 && [[ledger invoices] count] == 5, @"catch-up produces separate monthly invoices");
  Check ([[[[ledger invoices] lastObject] objectForKey: @"date"] isEqual: @"2027-08-05"], @"catch-up scheduled dates");
  bad = [NSMutableDictionary dictionaryWithDictionary: Schedule (@"2027-08", [NSArray array])];
  [bad setObject: [NSNumber numberWithBool: NO] forKey: @"enabled"];
  Check ([ledger saveRecurringForClient: identifier values: bad error: &error], @"disable schedule");
  Check ([[ledger runRecurringOnDate: @"2028-01-05"] count] == 0
    && [[[[ledger clientWithID: identifier] objectForKey: @"recurring"] objectForKey: @"nextMonth"] isEqual: @"2027-08"], @"disabled schedule stays unchanged");
  [ledger release];
  bad = [NSMutableDictionary dictionaryWithContentsOfFile: path];
  [[[bad objectForKey: @"clients"] objectAtIndex: 0] setObject: @"broken" forKey: @"recurring"];
  [bad writeToFile: path atomically: YES];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger == nil, @"corrupt schedule refused on load");
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  [identifier release];
  NSLog (@"Passed %u recurring billing checks", checks);
  [pool drain]; return 0;
}
