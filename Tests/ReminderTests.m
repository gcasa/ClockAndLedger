#import <Foundation/Foundation.h>
#import "CLLedger.h"
static unsigned int checks;
static void Check (BOOL ok, NSString *label)
{
  checks++;
  if (!ok) { NSLog (@"FAIL: %@", label); exit (1); }
}
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"Ledger.plist"];
  NSString *error = nil;
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: &error];
  NSMutableDictionary *business = [NSMutableDictionary dictionaryWithDictionary: [ledger business]];
  NSString *cid;
  NSString *otherID;
  NSString *taskID;
  NSString *invoiceID;
  NSDictionary *invoice;
  NSMutableDictionary *variant;
  NSArray *badDays = [NSArray arrayWithObjects: @"", @"-1", @"1.5", @"NaN", @"36501", nil];
  unsigned int i;
  [business setObject: @"sender@example.test" forKey: @"email"];
  Check ([ledger saveBusiness: business error: &error], @"Configure business sender");
  Check ([ledger saveClient: nil name: @"Acme" email: @"client@example.test" address: @"" rate: @"100" error: &error], @"Create client");
  cid = [[[[ledger clients] lastObject] objectForKey: @"id"] copy];
  Check ([ledger saveTask: nil client: cid name: @"Consulting" rate: @"175.50" error: &error], @"Create billable task");
  taskID = [[[[ledger tasksForClient: cid includeArchived: NO] lastObject] objectForKey: @"id"] copy];
  Check ([ledger invoiceClient: cid task: taskID hours: @"2.5" tax: @"0" dueDate: @"2099-04-01" error: &error], @"Bill a task directly");
  invoice = [[ledger invoices] lastObject];
  invoiceID = [[invoice objectForKey: @"id"] copy];
  Check ([[invoice objectForKey: @"subtotal"] intValue] == 43875, @"Task rate determines amount, not client rate");
  Check ([[[[invoice objectForKey: @"lines"] lastObject] objectForKey: @"taskName"] isEqual: @"Consulting"], @"Task name is on invoice");
  Check ([[ledger entries] count] == 0, @"Direct task billing does not create time entries");
  Check ([ledger saveTask: taskID client: cid name: @"Renamed" rate: @"200" error: &error], @"Edit future task rate");
  Check ([[invoice objectForKey: @"subtotal"] intValue] == 43875
    && [[[[invoice objectForKey: @"lines"] lastObject] objectForKey: @"rate"] intValue] == 17550, @"Issued task rate is immutable");
  Check ([ledger saveClient: nil name: @"Other" email: @"other@example.test" address: @"" rate: @"50" error: &error], @"Create second client");
  otherID = [[[[ledger clients] lastObject] objectForKey: @"id"] copy];
  Check (![ledger invoiceClient: otherID task: taskID hours: @"1" tax: @"0" dueDate: nil error: &error], @"Reject another client's task");
  Check ([ledger toggleTaskArchived: taskID error: &error], @"Archive task");
  Check (![ledger invoiceClient: cid task: taskID hours: @"1" tax: @"0" dueDate: nil error: &error], @"Reject archived task");
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-03-29"] == nil, @"Automatic mail defaults off");
  for (i = 0; i < [badDays count]; i++)
    Check (![ledger saveRemindersForClient: cid enabled: YES daysBefore: [badDays objectAtIndex: i] message: @"" overdueMessage: @"" error: &error], @"Reject invalid reminder days");
  Check ([ledger saveRemindersForClient: cid enabled: YES daysBefore: @"0" message: @"" overdueMessage: @"" error: &error], @"Configure due-date-only reminder");
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-03-31"] == nil, @"Zero threshold excludes previous day");
  Check ([[ledger reminderStageForInvoice: invoice onDate: @"2099-04-01"] isEqual: @"due"], @"Zero threshold includes due date");
  Check ([ledger saveRemindersForClient: cid enabled: YES daysBefore: @"3" message: @"" overdueMessage: @"" error: &error], @"Enable client reminders");
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-03-28"] == nil, @"No early reminder outside threshold");
  Check ([[ledger reminderStageForInvoice: invoice onDate: @"2099-03-29"] isEqual: @"due"], @"Threshold is inclusive across month boundary");
  Check ([[ledger reminderStageForInvoice: invoice onDate: @"2099-04-01"] isEqual: @"due"], @"Due date is not overdue");
  Check ([[ledger reminderStageForInvoice: invoice onDate: @"2099-04-02"] isEqual: @"overdue"], @"Day after due uses overdue message");
  Check ([[ledger paymentMessageForInvoice: invoice onDate: @"2099-03-29"] rangeOfString: @"friendly reminder"].location != NSNotFound, @"Blank friendly message has boilerplate");
  Check ([[ledger paymentMessageForInvoice: invoice onDate: @"2099-04-02"] rangeOfString: @"arrange payment promptly"].location != NSNotFound, @"Blank overdue message has sterner boilerplate");
  Check ([ledger saveRemindersForClient: cid enabled: YES daysBefore: @"3" message: @"Hello {client}, {invoice}: {total} due {dueDate}." overdueMessage: @"Late: {invoice}. Please pay now." error: &error], @"Custom reminder messages");
  Check ([[ledger paymentMessageForInvoice: invoice onDate: @"2099-03-29"] isEqual: @"Hello Acme, INV-00001: USD 438.75 due 2099-04-01."], @"Current client template expands placeholders");
  Check ([[ledger paymentMessageForInvoice: invoice onDate: @"2099-04-02"] isEqual: @"Late: INV-00001. Please pay now."], @"Overdue custom message selected");
  variant = [NSMutableDictionary dictionaryWithDictionary: invoice];
  [variant setObject: [NSNumber numberWithBool: YES] forKey: @"paid"];
  Check ([ledger reminderStageForInvoice: variant onDate: @"2099-03-29"] == nil, @"Never remind paid invoice");
  Check ([[ledger paymentMessageForInvoice: variant onDate: @"2099-04-02"] rangeOfString: @"Thank you"].location != NSNotFound, @"Paid email does not demand payment");
  [variant setObject: [NSNumber numberWithBool: NO] forKey: @"paid"];
  [variant setObject: [NSNumber numberWithBool: YES] forKey: @"paymentUnverified"];
  Check ([ledger reminderStageForInvoice: variant onDate: @"2099-03-29"] == nil, @"Unknown payment state excluded");
  [variant removeObjectForKey: @"paymentUnverified"];
  [variant setObject: [NSNumber numberWithBool: YES] forKey: @"dueDateUnverified"];
  Check ([ledger reminderStageForInvoice: variant onDate: @"2099-03-29"] == nil, @"Unknown due date excluded");
  [variant removeObjectForKey: @"dueDateUnverified"];
  [variant setObject: [NSNumber numberWithInt: 0] forKey: @"total"];
  Check ([ledger reminderStageForInvoice: variant onDate: @"2099-03-29"] == nil, @"Zero invoices excluded");
  Check (![ledger beginReminder: invoiceID stage: @"due" onDate: @"2099-03-28" error: &error], @"Cannot claim before threshold");
  Check ([ledger beginReminder: invoiceID stage: @"due" onDate: @"2099-03-29" error: &error], @"Persist send attempt before delivery");
  Check (![ledger beginReminder: invoiceID stage: @"due" onDate: @"2099-03-29" error: &error], @"Prevent duplicate attempt");
  [ledger release];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil, @"Reopen interrupted send");
  invoice = [[ledger invoices] lastObject];
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-04-02"] == nil, @"Interrupted attempt blocks further mail after restart");
  Check ([[CLLedger reminderStatusForInvoice: invoice] isEqual: @"Review email"], @"Interrupted send is visible");
  Check ([ledger finishReminder: invoiceID stage: @"due" submitted: NO detail: @"Mail denied permission" error: &error], @"Record Mail failure");
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-03-30"] == nil, @"No automatic resend on uncertain failure");
  Check ([ledger resolveReminder: invoiceID stage: @"due" submitted: NO error: &error], @"Explicit retry after checking Mail");
  Check ([[ledger reminderStageForInvoice: invoice onDate: @"2099-03-30"] isEqual: @"due"], @"Retry makes reminder eligible");
  Check ([ledger beginReminder: invoiceID stage: @"due" onDate: @"2099-03-30" error: &error], @"Retry journaled");
  Check ([ledger finishReminder: invoiceID stage: @"due" submitted: YES detail: @"Mail accepted" error: &error], @"Record submission");
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-04-01"] == nil, @"Only one friendly reminder");
  Check ([[ledger reminderStageForInvoice: invoice onDate: @"2099-04-02"] isEqual: @"overdue"], @"Separate overdue stage after friendly reminder");
  Check ([ledger beginReminder: invoiceID stage: @"overdue" onDate: @"2099-04-02" error: &error], @"Journal overdue attempt");
  Check ([ledger resolveReminder: invoiceID stage: @"overdue" submitted: YES error: &error], @"Confirm interrupted Mail submission manually");
  Check ([ledger reminderStageForInvoice: invoice onDate: @"2099-05-01"] == nil, @"No repeated overdue spam");
  Check ([ledger saveRemindersForClient: cid enabled: NO daysBefore: @"0" message: @"" overdueMessage: @"" error: &error], @"Disable reminders");
  Check ([CLLedger reminderDaysForClient: [ledger clientWithID: cid]] == 0, @"Zero-day threshold supported");
  Check (![CLLedger validEmailAddress: @"a@example.test,b@example.test"], @"Reject multiple recipients");
  Check (![CLLedger validEmailAddress: @"a@example.test\nBcc: other@example.test"], @"Reject header injection");
  [ledger release];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil && [[[ledger clientWithID: cid] objectForKey: @"autoReminders"] boolValue] == NO, @"Settings and history persist");
  [ledger release];
  {
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithContentsOfFile: path];
    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary: [[data objectForKey: @"clients"] objectAtIndex: 0]];
    NSMutableArray *clients = [NSMutableArray arrayWithArray: [data objectForKey: @"clients"]];
    [record setObject: @"bad" forKey: @"reminderDays"];
    [clients replaceObjectAtIndex: 0 withObject: record];
    [data setObject: clients forKey: @"clients"];
    [data writeToFile: path atomically: YES];
    ledger = [[CLLedger alloc] initWithPath: path error: &error];
    Check (ledger == nil, @"Reject malformed persisted reminder settings");
  }
  {
    NSString *failureDirectory = [directory stringByAppendingPathComponent: @"unwritable"];
    NSString *failurePath = [failureDirectory stringByAppendingPathComponent: @"Ledger.plist"];
    CLLedger *failure = [[CLLedger alloc] initWithPath: failurePath error: &error];
    NSString *failureClient;
    NSDictionary *pendingInvoice;
    Check ([failure saveBusiness: business error: &error], @"Failure fixture business");
    Check ([failure saveClient: nil name: @"Failure" email: @"failure@example.test" address: @"" rate: @"100" error: &error], @"Failure fixture client");
    failureClient = [[[failure clients] lastObject] objectForKey: @"id"];
    Check ([failure saveRemindersForClient: failureClient enabled: YES daysBefore: @"3" message: @"" overdueMessage: @"" error: &error], @"Failure fixture reminder settings");
    Check ([failure invoiceClient: failureClient hours: @"1" tax: @"0" dueDate: @"2099-04-01" error: &error], @"Failure fixture invoice");
    pendingInvoice = [[failure invoices] lastObject];
    [[NSFileManager defaultManager] removeItemAtPath: failureDirectory error: NULL];
    [@"blocked" writeToFile: failureDirectory atomically: YES encoding: NSUTF8StringEncoding error: NULL];
    Check (![failure beginReminder: [pendingInvoice objectForKey: @"id"] stage: @"due" onDate: @"2099-03-29" error: &error], @"No Mail handoff when attempt cannot persist");
    Check ([[[failure invoices] lastObject] objectForKey: @"reminders"] == nil, @"Failed reminder write rolls back memory");
    [failure release];
  }
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  [cid release]; [otherID release]; [taskID release]; [invoiceID release];
  NSLog (@"PASS: %u reminder and task billing checks (no mail sent)", checks);
  [pool drain];
  return 0;
}
