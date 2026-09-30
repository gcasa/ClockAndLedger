#import <Foundation/Foundation.h>
#import "CLLedger.h"

static unsigned int checks = 0;
static void
Check (BOOL condition, NSString *message)
{
  checks++;
  if (!condition)
    {
      NSLog (@"FAIL: %@", message);
      exit (1);
    }
}

static NSDictionary *
Row (NSString *date, NSString *hours)
{
  return [NSDictionary dictionaryWithObjectsAndKeys: date, @"date", hours, @"hours", @"", @"description", nil];
}

/** Verify calendar boundaries, task ownership, rate snapshots, atomic timesheets
 * and compatibility with pre-task ledgers on both supported runtimes. */
int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"Ledger.plist"];
  NSString *error = nil;
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: &error];
  NSString *clientID;
  NSString *otherID;
  NSString *designID;
  NSString *supportID;
  NSDictionary *period;
  NSArray *rows;
  NSData *before;
  NSDictionary *invoice;
  NSUInteger count;
  NSMutableDictionary *legacy;
  NSTimeZone *originalZone = [[NSTimeZone defaultTimeZone] retain];

  [NSTimeZone setDefaultTimeZone: [NSTimeZone timeZoneWithName: @"America/New_York"]];
  period = [CLLedger periodContainingDate: @"2024-02-20" kind: @"month" error: &error];
  Check ([[period objectForKey: @"start"] isEqual: @"2024-02-01"] && [[period objectForKey: @"end"] isEqual: @"2024-02-29"], @"Leap February bounds");
  Check ([[period objectForKey: @"dates"] count] == 29, @"Leap month daily rows");
  period = [CLLedger periodContainingDate: @"2025-02-20" kind: @"month" error: &error];
  Check ([[period objectForKey: @"dates"] count] == 28, @"Ordinary February");
  period = [CLLedger periodContainingDate: @"2026-04-20" kind: @"month" error: &error];
  Check ([[period objectForKey: @"end"] isEqual: @"2026-04-30"], @"Thirty-day month");
  period = [CLLedger periodContainingDate: @"2026-12-20" kind: @"month" error: &error];
  Check ([[period objectForKey: @"end"] isEqual: @"2026-12-31"], @"December boundary");
  period = [CLLedger periodContainingDate: @"2026-01-01" kind: @"week" error: &error];
  Check ([[period objectForKey: @"start"] isEqual: @"2025-12-29"] && [[period objectForKey: @"end"] isEqual: @"2026-01-04"], @"Week crosses year");
  period = [CLLedger periodContainingDate: @"2026-03-08" kind: @"week" error: &error];
  Check ([[period objectForKey: @"start"] isEqual: @"2026-03-02"] && [[period objectForKey: @"end"] isEqual: @"2026-03-08"] && [[period objectForKey: @"dates"] count] == 7, @"Sunday and DST week");
  period = [CLLedger periodContainingDate: @"2026-03-09" kind: @"week" error: &error];
  Check ([[period objectForKey: @"start"] isEqual: @"2026-03-09"], @"Monday starts its own week");
  period = [CLLedger periodContainingDate: @"2026-11-20" kind: @"month" error: &error];
  Check ([[period objectForKey: @"dates"] count] == 30, @"Autumn DST does not duplicate dates");
  period = [CLLedger periodContainingDate: @"2026-09-25" kind: @"day" error: &error];
  Check ([[period objectForKey: @"start"] isEqual: [period objectForKey: @"end"]] && [[period objectForKey: @"dates"] count] == 1, @"Individual date");
  Check ([CLLedger periodContainingDate: @"2026-02-30" kind: @"month" error: &error] == nil, @"Reject impossible anchor");
  Check ([CLLedger periodContainingDate: @"2026-02-20" kind: @"year" error: &error] == nil, @"Reject unknown period");
  Check ([ledger saveClient: nil name: @"Acme" email: @"" address: @"" rate: @"90" error: &error], @"Create client");
  clientID = [[[[ledger clients] objectAtIndex: 0] objectForKey: @"id"] copy];
  Check ([ledger addTimeForClient: clientID date: @"2026-09-01" description: @"Legacy entry" hours: @"1" error: &error], @"Old API still works");
  [ledger release];
  legacy = [NSMutableDictionary dictionaryWithContentsOfFile: path];
  [legacy removeObjectForKey: @"tasks"];
  [legacy writeToFile: path atomically: YES];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil && [[ledger tasksForClient: clientID includeArchived: YES] count] == 0, @"Legacy ledger migration");
  Check ([ledger saveClient: nil name: @"Other" email: @"" address: @"" rate: @"50" error: &error], @"Create second client");
  otherID = [[[[ledger clients] objectAtIndex: 1] objectForKey: @"id"] copy];
  Check ([ledger saveTask: nil client: clientID name: @"Design" rate: @"150.50" error: &error], @"Create design task");
  designID = [[[[ledger tasksForClient: clientID includeArchived: NO] objectAtIndex: 0] objectForKey: @"id"] copy];
  Check ([ledger saveTask: nil client: clientID name: @"Support" rate: @"75" error: &error], @"Create support task");
  supportID = [[[[ledger tasksForClient: clientID includeArchived: NO] objectAtIndex: 1] objectForKey: @"id"] copy];
  Check (![ledger saveTask: nil client: clientID name: @"design" rate: @"5" error: &error], @"Task names unique per client");
  Check ([ledger saveTask: nil client: otherID name: @"Design" rate: @"5" error: &error], @"Same task name allowed for another client");
  Check (![ledger saveTask: designID client: otherID name: @"Moved" rate: @"10" error: &error], @"Task ownership cannot move");
  Check (![ledger saveTask: nil client: clientID name: @"Negative" rate: @"-1" error: &error], @"Reject invalid task rate");
  Check (![ledger addTimeForClient: otherID task: designID date: @"2026-09-25" period: @"day" description: @"" hours: @"1" error: &error], @"Cross-client task rejected");
  Check ([ledger addTimeForClient: clientID task: designID date: @"2026-09-25" period: @"week" description: @"Website" hours: @"10" error: &error], @"Weekly total");
  Check ([[[[ledger entries] lastObject] objectForKey: @"date"] isEqual: @"2026-09-21"] && [[[[ledger entries] lastObject] objectForKey: @"periodEnd"] isEqual: @"2026-09-27"], @"Week range persisted");
  Check ([[[[ledger entries] lastObject] objectForKey: @"seconds"] intValue] == 36000, @"Total is not multiplied by days");
  Check ([[CLLedger workLabelForEntry: [[ledger entries] lastObject]] isEqual: @"Design: Website"], @"Invoice work label includes task");
  Check ([[CLLedger dateLabelForEntry: [[ledger entries] lastObject]] rangeOfString: @"2026-09-27"].location != NSNotFound, @"Invoice date label includes end");
  Check ([ledger addTimeForClient: clientID task: supportID date: @"2024-02-10" period: @"month" description: @"" hours: @"20" error: &error], @"Monthly total and task description fallback");
  Check ([[[[ledger entries] lastObject] objectForKey: @"rate"] intValue] == 7500, @"Task-specific rate captured");
  rows = [NSArray arrayWithObjects: Row (@"2026-09-21", @"2"), Row (@"2026-09-22", @""), Row (@"2026-09-23", @"0"), Row (@"2026-09-24", @"1.5"), nil];
  count = [[ledger entries] count];
  Check ([ledger addTimeRows: rows client: clientID task: designID error: &error], @"Daily timesheet save");
  Check ([[ledger entries] count] == count + 2, @"Skip blank and zero days");
  Check ([[[[ledger entries] lastObject] objectForKey: @"seconds"] intValue] == 5400, @"Daily decimal hours converted");
  before = [NSData dataWithContentsOfFile: path];
  count = [[ledger entries] count];
  rows = [NSArray arrayWithObjects: Row (@"2026-09-21", @"2"), Row (@"2026-09-22", @"bad"), nil];
  Check (![ledger addTimeRows: rows client: clientID task: designID error: &error], @"One invalid row rejects whole sheet");
  Check ([[ledger entries] count] == count && [before isEqual: [NSData dataWithContentsOfFile: path]], @"No partial sheet in memory or on disk");
  Check (![ledger addTimeRows: [NSArray arrayWithObject: Row (@"2026-09-21", @"0")] client: clientID task: designID error: &error], @"All-zero sheet rejected");
  Check ([ledger startTimerForClient: clientID task: designID description: @"Timer work" error: &error], @"Start task timer");
  Check ([ledger saveTask: designID client: clientID name: @"Creative" rate: @"200" error: &error], @"Change task name and rate");
  Check ([[[ledger timer] objectForKey: @"rate"] intValue] == 15050 && [[[ledger timer] objectForKey: @"taskName"] isEqual: @"Design"], @"Running timer keeps its snapshot");
  Check ([[[[ledger entries] objectAtIndex: 1] objectForKey: @"rate"] intValue] == 15050 && [[[[ledger entries] objectAtIndex: 1] objectForKey: @"taskName"] isEqual: @"Design"], @"Past entry unaffected by task edit");
  Check ([ledger toggleTaskArchived: designID error: &error], @"Archive task");
  Check ([[ledger tasksForClient: clientID includeArchived: NO] count] == 1 && [[ledger tasksForClient: clientID includeArchived: YES] count] == 2, @"Archive hides only active choice");
  Check (![ledger addTimeForClient: clientID task: designID date: @"2026-09-25" period: @"day" description: @"" hours: @"1" error: &error], @"Archived task cannot record new time");
  [ledger release];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil && [[[ledger timer] objectForKey: @"taskName"] isEqual: @"Design"], @"Task timer survives reopen");
  {
    BOOL stopped = [ledger stopTimer: &error];
    if (!stopped)
      NSLog (@"Timer stop error: %@, timer: %@, now: %@", error, [ledger timer], [NSDate date]);
    if (!stopped)
      NSLog (@"Elapsed: %.6f", [ledger timerElapsed]);
    Check (stopped, @"Stop timer after task archived");
  }
  Check ([[[[ledger entries] lastObject] objectForKey: @"taskName"] isEqual: @"Design"], @"Stopped timer keeps original task");
  Check ([ledger deleteEntry: [[[ledger entries] lastObject] objectForKey: @"id"] error: &error], @"Remove test timer before exact invoice check");
  Check ([ledger toggleTaskArchived: designID error: &error], @"Restore task");
  Check ([ledger addTimeForClient: clientID task: designID date: @"2026-09-25" period: @"day" description: @"" hours: @"1" error: &error], @"Restored task can record time");
  Check ([[[[ledger entries] lastObject] objectForKey: @"rate"] intValue] == 20000, @"New time uses updated rate");
  Check ([ledger invoiceClient: clientID tax: @"0" dueDate: @"2099-01-01" error: &error], @"Invoice mixed periods and tasks");
  invoice = [[ledger invoices] lastObject];
  Check ([[invoice objectForKey: @"total"] intValue] == 382175, @"Invoice sums task snapshots and each period total once");
  Check ([ledger saveTask: designID client: clientID name: @"New name" rate: @"300" error: &error], @"Edit task after invoice");
  Check ([[[[invoice objectForKey: @"lines"] objectAtIndex: 1] objectForKey: @"taskName"] isEqual: @"Design"], @"Issued invoice task unchanged");
  Check (![ledger deleteClient: otherID error: &error], @"Client task history protected");
  [ledger release];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil && [[ledger invoices] count] == 1, @"Period and task invoices reopen");
  [ledger release];
  {
    NSString *blocked = [directory stringByAppendingPathComponent: @"blocked"];
    NSString *blockedLedger = [blocked stringByAppendingPathComponent: @"Ledger.plist"];
    CLLedger *failure = [[CLLedger alloc] initWithPath: blockedLedger error: &error];
    Check ([failure saveClient: nil name: @"Test" email: @"" address: @"" rate: @"100" error: &error], @"Create rollback fixture");
    [[NSFileManager defaultManager] removeItemAtPath: blockedLedger error: NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath: blockedLedger withIntermediateDirectories: YES attributes: nil error: NULL];
    rows = [NSArray arrayWithObjects:
      [NSDictionary dictionaryWithObjectsAndKeys: @"2026-09-25", @"date", @"2", @"hours", @"Work", @"description", nil], nil];
    Check (![failure addTimeRows: rows client: [[[failure clients] objectAtIndex: 0] objectForKey: @"id"] task: nil error: &error], @"Sheet write failure reported");
    Check ([[failure entries] count] == 0, @"Sheet write failure rolls back memory");
    [failure release];
  }
  [NSTimeZone setDefaultTimeZone: originalZone];
  [originalZone release];
  [clientID release];
  [otherID release];
  [designID release];
  [supportID release];
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: %u task and calendar checks", checks);
  [pool drain];
  return 0;
}
