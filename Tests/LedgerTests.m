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

/** Exercise persistence and accounting invariants in an isolated temp directory. */
int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent:
    [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"Ledger.plist"];
  NSString *error = nil;
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: &error];
  NSString *clientID;
  NSDictionary *invoice;
  CLLedger *reopened;
  NSMutableDictionary *business;
  NSString *entryID;
  NSString *blockedPath;
  CLLedger *blocked;
  unsigned int i;
  NSArray *invalidAmounts = [NSArray arrayWithObjects: @"", @"-1", @"nan", @"1.234", @"1e3", @"12x", @"1,000", @"1000000001", nil];

  Check (ledger != nil, @"Create empty ledger");
  for (i = 0; i < [invalidAmounts count]; i++)
    Check ([CLLedger centsFromString: [invalidAmounts objectAtIndex: i]] == nil, @"Reject invalid money");
  Check ([[CLLedger centsFromString: @"19.99"] longLongValue] == 1999, @"Exact cents");
  Check ([[CLLedger amountForSeconds: [NSNumber numberWithInt: 1800] rate: [NSNumber numberWithInt: 101]] intValue] == 51, @"Round half cent upward");
  Check ([ledger saveClient: nil name: @"Acme" email: @"billing@example.test" address: @"10 Main Street\nNew York" rate: @"125.50" error: &error], @"Create client");
  clientID = [[[[ledger clients] objectAtIndex: 0] objectForKey: @"id"] copy];
  Check (![ledger addTimeForClient: clientID date: @"2026-02-30" description: @"Invalid" hours: @"1" error: &error], @"Reject impossible date");
  Check (![ledger addTimeForClient: clientID date: [CLLedger today] description: @"Invalid" hours: @"0" error: &error], @"Reject zero duration");
  Check (![ledger addTimeForClient: clientID date: [CLLedger today] description: @"Invalid" hours: @"garbage" error: &error], @"Reject malformed duration");
  Check ([ledger addTimeForClient: clientID date: @"2026-01-15" description: @"Design" hours: @"1.25" error: &error], @"Record manual time");
  entryID = [[[[ledger entries] objectAtIndex: 0] objectForKey: @"id"] copy];
  Check ([ledger saveClient: clientID name: @"Acme" email: @"" address: @"" rate: @"200.00" error: &error], @"Change future rate");
  Check ([[[[ledger entries] objectAtIndex: 0] objectForKey: @"rate"] intValue] == 12550, @"Existing time keeps rate");
  Check (![ledger invoiceClient: clientID tax: @"101" dueDate: @"2099-01-01" error: &error], @"Reject excessive tax");
  Check ([ledger invoiceClient: clientID tax: @"8.25" dueDate: @"2099-01-01" error: &error], @"Issue invoice");
  invoice = [[ledger invoices] objectAtIndex: 0];
  Check ([[invoice objectForKey: @"subtotal"] intValue] == 15688, @"Line rounds half up");
  Check ([[invoice objectForKey: @"tax"] intValue] == 1294, @"Tax rounds once on subtotal");
  Check ([[invoice objectForKey: @"total"] intValue] == 16982, @"Invoice total exact");
  Check (![ledger invoiceClient: clientID tax: @"0" dueDate: @"2099-01-01" error: &error], @"Cannot invoice twice");
  Check (![ledger deleteEntry: entryID error: &error], @"Billed entry locked");
  Check (![ledger deleteClient: clientID error: &error], @"Referenced client protected");
  Check ([ledger saveClient: clientID name: @"New name" email: @"changed" address: @"Changed" rate: @"250" error: &error], @"Edit billed client");
  Check ([[[invoice objectForKey: @"client"] objectForKey: @"name"] isEqual: @"Acme"], @"Invoice client snapshot unchanged");
  business = [NSMutableDictionary dictionaryWithDictionary: [ledger business]];
  [business setObject: @"New Business" forKey: @"name"];
  Check ([ledger saveBusiness: business error: &error], @"Save business");
  Check ([[[invoice objectForKey: @"business"] objectForKey: @"name"] isEqual: @"Your business"], @"Invoice business snapshot unchanged");
  [business setObject: @"EUR" forKey: @"currency"];
  Check (![ledger saveBusiness: business error: &error], @"Currency locked after recording time");
  Check ([ledger togglePaid: [invoice objectForKey: @"id"] error: &error], @"Mark paid");
  Check ([[invoice objectForKey: @"paid"] boolValue], @"Paid recorded");
  Check ([ledger startTimerForClient: clientID description: @"Development" error: &error], @"Start timer");
  Check (![ledger startTimerForClient: clientID description: @"Second" error: &error], @"One timer only");
  reopened = [[CLLedger alloc] initWithPath: path error: &error];
  Check ([reopened timer] != nil, @"Timer survives restart");
  Check ([[reopened invoices] count] == 1, @"Invoice survives restart");
  Check ([reopened stopTimer: &error], @"Stop recovered timer");
  Check ([reopened timer] == nil && [[reopened entries] count] == 2, @"Timer becomes exactly one entry");
  Check ([[[[reopened entries] lastObject] objectForKey: @"seconds"] intValue] >= 1, @"Minimum timer second");
  Check ([reopened deleteEntry: [[[reopened entries] lastObject] objectForKey: @"id"] error: &error], @"Unbilled entry removable");
  Check ([reopened addTimeForClient: clientID date: [CLLedger today] description: @"More work" hours: @"2" error: &error], @"Add more time");
  Check ([reopened invoiceClient: clientID tax: @"0" dueDate: @"2099-01-01" error: &error], @"Second invoice");
  Check ([[[[reopened invoices] lastObject] objectForKey: @"id"] isEqual: @"INV-00002"], @"Sequential invoice numbering");
  [reopened release];
  [ledger release];

  {
    NSString *billingPath = [directory stringByAppendingPathComponent: @"Billing.plist"];
    CLLedger *billing = [[CLLedger alloc] initWithPath: billingPath error: &error];
    NSString *billingClient;
    NSDictionary *issued;
    Check ([billing saveClient: nil name: @"Hours only" email: @"client@example.test" address: @"" rate: @"100" error: &error], @"Create billing client");
    billingClient = [[[[billing clients] objectAtIndex: 0] objectForKey: @"id"] copy];
    Check (![billing invoiceClient: billingClient hours: @"0" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Reject zero invoice hours");
    Check (![billing invoiceClient: billingClient hours: @"-1" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Reject negative invoice hours");
    Check (![billing invoiceClient: billingClient hours: @"1e2" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Reject malformed invoice hours");
    Check (![billing invoiceClient: billingClient hours: @"8761" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Reject excessive invoice hours");
    Check ([billing invoiceClient: billingClient hours: @"1.2345" tax: @"10" dueDate: @"2099-01-01" error: &error], @"Invoice without any timesheet");
    issued = [[billing invoices] lastObject];
    Check ([[billing entries] count] == 0, @"Standalone billing creates no time entries");
    Check ([[issued objectForKey: @"subtotal"] intValue] == 12345 && [[issued objectForKey: @"total"] intValue] == 13580, @"Exact raw hours and tax rounding");
    Check (![billing deleteClient: billingClient error: &error], @"Keep client referenced by standalone invoice");
    Check ([billing addTimeForClient: billingClient date: [CLLedger today] description: @"Optional timesheet" hours: @"2" error: &error], @"Record optional time");
    Check ([billing invoiceClient: billingClient hours: @"3" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Direct billing alongside timesheet");
    Check ([CLLedger isUnbilledEntry: [[billing entries] lastObject]], @"Direct billing leaves time untouched");
    Check ([billing invoiceClient: billingClient tax: @"0" dueDate: @"2099-01-01" error: &error], @"Convert optional timesheet");
    Check (![billing invoiceClient: billingClient tax: @"0" dueDate: @"2099-01-01" error: &error], @"Prevent duplicate timesheet conversion");
    Check ([billing setInvoice: @"INV-00001" paid: YES error: &error], @"Mark standalone invoice paid");
    [billing release];
    billing = [[CLLedger alloc] initWithPath: billingPath error: &error];
    Check (billing != nil && [[billing invoices] count] == 3, @"Retain all direct and timesheet invoices after restart");
    Check ([[[[billing invoices] objectAtIndex: 0] objectForKey: @"paid"] boolValue], @"Paid status survives restart");
    Check ([[[[[[billing invoices] objectAtIndex: 0] objectForKey: @"lines"] objectAtIndex: 0] objectForKey: @"hours"] isEqual: @"1.2345"], @"Exact raw hours survive restart");
    Check (![billing deleteInvoice: @"missing" error: &error], @"Reject missing invoice without changes");
    {
      NSString *savedPath = [billingPath stringByAppendingString: @".saved"];
      [[NSFileManager defaultManager] moveItemAtPath: billingPath toPath: savedPath error: NULL];
      [[NSFileManager defaultManager] createDirectoryAtPath: billingPath withIntermediateDirectories: NO attributes: nil error: NULL];
      Check (![billing deleteInvoice: @"INV-00003" error: &error], @"Failed deletion reports disk error");
      Check ([[billing invoices] count] == 3 && ![CLLedger isUnbilledEntry: [[billing entries] lastObject]], @"Failed deletion restores invoice and billed time");
      [[NSFileManager defaultManager] removeItemAtPath: billingPath error: NULL];
      [[NSFileManager defaultManager] moveItemAtPath: savedPath toPath: billingPath error: NULL];
    }
    Check ([billing deleteInvoice: @"INV-00002" error: &error], @"Delete middle standalone invoice");
    Check (![CLLedger isUnbilledEntry: [[billing entries] lastObject]], @"Unrelated billed time stays locked");
    [billing release];
    billing = [[CLLedger alloc] initWithPath: billingPath error: &error];
    Check (billing != nil && [[billing invoices] count] == 2, @"Numbering gap survives restart");
    Check ([billing deleteInvoice: @"INV-00003" error: &error], @"Delete timesheet invoice");
    Check ([CLLedger isUnbilledEntry: [[billing entries] lastObject]], @"Linked time becomes unbilled");
    Check ([billing deleteInvoice: @"INV-00001" error: &error], @"Delete paid invoice");
    Check ([[billing invoices] count] == 0 && [billing hasIssuedInvoices], @"All deleted numbers remain reserved");
    Check ([billing saveBusiness: [billing business] error: &error], @"Business save after deletion does not reset sequence");
    [billing release];
    billing = [[CLLedger alloc] initWithPath: billingPath error: &error];
    Check (billing != nil && [[billing invoices] count] == 0, @"Empty invoice list with deletions survives restart");
    Check ([billing invoiceClient: billingClient tax: @"0" dueDate: @"2099-01-01" error: &error], @"Rebill released time");
    Check ([[[[billing invoices] lastObject] objectForKey: @"id"] isEqual: @"INV-00004"], @"Never reuse deleted invoice numbers");
    [billingClient release];
    [billing release];
  }

  {
    NSString *termsPath = [directory stringByAppendingPathComponent: @"Terms.plist"];
    CLLedger *terms = [[CLLedger alloc] initWithPath: termsPath error: &error];
    NSString *cid;
    NSArray *badDays = [NSArray arrayWithObjects: @"", @"-1", @"1.5", @"30.0", @"abc", @"1e2", @"36501", @"999999999999", nil];
    NSDictionary *issued;
    NSMutableDictionary *legacy;
    Check ([terms saveClient: nil name: @"Terms" email: @"" address: @"" rate: @"100" error: &error], @"Create Net 30 client");
    cid = [[[[terms clients] objectAtIndex: 0] objectForKey: @"id"] copy];
    Check ([CLLedger netDaysForClient: [terms clientWithID: cid]] == 30, @"Default terms are Net 30");
    Check ([[terms dueDateForClient: cid invoiceDate: @"2026-12-15"] isEqual: @"2027-01-14"], @"Net 30 crosses year boundary");
    for (i = 0; i < [badDays count]; i++)
      Check (![terms saveClient: cid name: @"Terms" email: @"" address: @"" rate: @"100" netDays: [badDays objectAtIndex: i] error: &error], @"Reject invalid net days");
    Check ([CLLedger netDaysForClient: [terms clientWithID: cid]] == 30, @"Invalid terms preserve client");
    Check ([terms saveClient: cid name: @"Terms" email: @"" address: @"" rate: @"100" netDays: @"1" error: &error], @"Save Net 1");
    Check ([[terms dueDateForClient: cid invoiceDate: @"2024-02-28"] isEqual: @"2024-02-29"], @"Leap day due date");
    Check ([[terms dueDateForClient: cid invoiceDate: @"2026-02-28"] isEqual: @"2026-03-01"], @"Non-leap month rollover");
    Check ([[terms dueDateForClient: cid invoiceDate: @"2026-03-08"] isEqual: @"2026-03-09"], @"Calendar days across daylight saving transition");
    Check ([terms invoiceClient: cid hours: @"2" tax: @"0" dueDate: nil error: &error], @"Direct invoice calculates due date");
    issued = [[[[terms invoices] lastObject] copy] autorelease];
    Check ([[issued objectForKey: @"dueDate"] isEqual: [terms dueDateForClient: cid invoiceDate: [issued objectForKey: @"date"]]], @"Direct invoice uses client terms");
    Check ([terms saveClient: cid name: @"Terms" email: @"" address: @"" rate: @"100" netDays: @"0" error: &error], @"Save due on receipt");
    Check ([terms addTimeForClient: cid date: [CLLedger today] description: @"Work" hours: @"1" error: &error], @"Add time for terms invoice");
    Check ([terms invoiceClient: cid tax: @"0" dueDate: nil error: &error], @"Timesheet invoice calculates due date");
    Check ([[[[terms invoices] lastObject] objectForKey: @"dueDate"] isEqual: [CLLedger today]], @"Net 0 due on issue date");
    Check ([[[terms invoices] objectAtIndex: 0] isEqual: issued], @"Terms changes preserve issued invoices");
    Check ([terms saveClient: cid name: @"Renamed" email: @"" address: @"" rate: @"150" error: &error], @"Legacy save preserves terms");
    Check ([CLLedger netDaysForClient: [terms clientWithID: cid]] == 0, @"Legacy save keeps Net 0");
    [terms release];
    terms = [[CLLedger alloc] initWithPath: termsPath error: &error];
    Check (terms != nil && [CLLedger netDaysForClient: [terms clientWithID: cid]] == 0, @"Terms survive reopening");
    Check ([terms invoiceClient: cid hours: @"1" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Allow explicit due date override");
    Check ([[[[terms invoices] lastObject] objectForKey: @"dueDate"] isEqual: @"2099-01-01"], @"Override is saved");
    [terms release];
    legacy = [NSMutableDictionary dictionaryWithContentsOfFile: termsPath];
    {
      NSMutableDictionary *oldClient = [NSMutableDictionary dictionaryWithDictionary: [[legacy objectForKey: @"clients"] objectAtIndex: 0]];
      [oldClient removeObjectForKey: @"netDays"];
      [legacy setObject: [NSArray arrayWithObject: oldClient] forKey: @"clients"];
      [legacy writeToFile: termsPath atomically: YES];
      terms = [[CLLedger alloc] initWithPath: termsPath error: &error];
      Check (terms != nil && [CLLedger netDaysForClient: [terms clientWithID: cid]] == 30, @"Old ledgers use Net 30");
      [terms release];
      [oldClient setObject: [NSNumber numberWithDouble: 1.5] forKey: @"netDays"];
      [legacy writeToFile: termsPath atomically: YES];
      terms = [[CLLedger alloc] initWithPath: termsPath error: &error];
      Check (terms == nil, @"Reject malformed persisted terms");
    }
    [cid release];
  }

  {
    NSString *numberPath = [directory stringByAppendingPathComponent: @"ClientNumbers.plist"];
    CLLedger *numbered = [[CLLedger alloc] initWithPath: numberPath error: &error];
    NSString *first;
    NSString *second;
    NSString *deleted;
    NSArray *invalidStarts = [NSArray arrayWithObjects: @"0", @"-1", @"1.5", @"INV-500", @"2147483646", nil];
    for (i = 0; i < [invalidStarts count]; i++)
      Check (![numbered saveClient: nil name: @"First" email: @"" address: @"" rate: @"100" netDays: @"30"
        startingInvoiceNumber: [invalidStarts objectAtIndex: i] error: &error], @"Reject invalid client starting number");
    Check ([[numbered clients] count] == 0, @"Invalid start does not add client");
    Check ([numbered saveClient: nil name: @"First" email: @"" address: @"" rate: @"100" netDays: @"30"
      startingInvoiceNumber: @"500" error: &error], @"Set client starting number");
    first = [[[[numbered clients] objectAtIndex: 0] objectForKey: @"id"] copy];
    Check ([numbered invoiceClient: first hours: @"1" tax: @"0" dueDate: nil error: &error], @"Issue client numbered invoice");
    Check ([[CLLedger invoiceNumber: [[numbered invoices] lastObject]] isEqual: @"INV-00500"], @"Client begins at requested number");
    Check ([numbered saveClient: nil name: @"Second" email: @"" address: @"" rate: @"100" netDays: @"15"
      startingInvoiceNumber: @"500" error: &error], @"Second client has own start");
    second = [[[[numbered clients] lastObject] objectForKey: @"id"] copy];
    Check ([numbered invoiceClient: second hours: @"1" tax: @"0" dueDate: nil error: &error], @"Issue second client's invoice");
    Check ([[CLLedger invoiceNumber: [[numbered invoices] lastObject]] isEqual: @"INV-00501"], @"Skip number used by another client");
    deleted = [[[[numbered invoices] lastObject] objectForKey: @"id"] copy];
    Check ([numbered deleteInvoice: deleted error: &error], @"Delete custom numbered invoice");
    Check (![numbered saveClient: second name: @"Second" email: @"" address: @"" rate: @"100" netDays: @"15"
      startingInvoiceNumber: @"700" error: &error], @"Starting number remains fixed after deletion");
    Check ([numbered saveClient: first name: @"Renamed" email: @"" address: @"" rate: @"150" netDays: @"10" error: &error], @"Old save API preserves numbering");
    [numbered release];
    numbered = [[CLLedger alloc] initWithPath: numberPath error: &error];
    Check (numbered != nil, @"Reopen client numbering ledger");
    Check ([numbered addTimeForClient: first date: [CLLedger today] description: @"Work" hours: @"2" error: &error], @"Add client numbered timesheet");
    Check ([numbered invoiceClient: first tax: @"0" dueDate: nil error: &error], @"Timesheet uses client numbering");
    Check ([[CLLedger invoiceNumber: [[numbered invoices] lastObject]] isEqual: @"INV-00502"], @"Continue sequence and skip deleted number");
    Check ([numbered invoiceClient: second hours: @"1" tax: @"0" dueDate: nil error: &error], @"Second client continues after reopening");
    Check ([[CLLedger invoiceNumber: [[numbered invoices] lastObject]] isEqual: @"INV-00503"], @"Second client counter survives deletion");
    [numbered release];
    numbered = [[CLLedger alloc] initWithPath: numberPath error: &error];
    Check (numbered != nil, @"Reopen after advancing client counters");
    Check ([numbered saveClient: nil name: @"Business default" email: @"" address: @"" rate: @"100" netDays: @"30"
      startingInvoiceNumber: @"" error: &error], @"Blank client start uses business sequence");
    Check ([numbered invoiceClient: [[[numbered clients] lastObject] objectForKey: @"id"] hours: @"1" tax: @"0" dueDate: nil error: &error], @"Issue with business numbering");
    Check ([[CLLedger invoiceNumber: [[numbered invoices] lastObject]] isEqual: @"INV-00005"], @"Business sequence remains available");
    [numbered release];
    [first release]; [second release]; [deleted release];
  }

  {
    NSString *issuedPath = [directory stringByAppendingPathComponent: @"IssuedDates.plist"];
    CLLedger *dated = [[CLLedger alloc] initWithPath: issuedPath error: &error];
    NSString *cid;
    NSDictionary *created;
    NSArray *invalidDates = [NSArray arrayWithObjects: @"", @"2026-02-30", @"not a date", nil];
    Check ([dated saveClient: nil name: @"Dated client" email: @"" address: @"" rate: @"100" netDays: @"15" error: &error], @"Create dated invoice client");
    cid = [[[[dated clients] lastObject] objectForKey: @"id"] copy];
    for (i = 0; i < [invalidDates count]; i++)
      Check (![dated invoiceClient: cid task: nil hours: @"1" tax: @"0" issuedDate: [invalidDates objectAtIndex: i] dueDate: nil error: &error], @"Reject invalid issued date");
    Check (![dated invoiceClient: cid task: nil hours: @"1" tax: @"0" issuedDate: @"2024-02-20" dueDate: @"2024-02-19" error: &error], @"Due date cannot precede issued date");
    Check ([[dated invoices] count] == 0, @"Invalid dates do not issue invoices");
    Check ([dated invoiceClient: cid task: nil hours: @"1" tax: @"0" issuedDate: @"2024-02-20" dueDate: nil error: &error], @"Backdate invoice and compute due date");
    created = [[dated invoices] lastObject];
    Check ([[created objectForKey: @"date"] isEqual: @"2024-02-20"], @"Invoice stores entered issued date");
    Check ([[created objectForKey: @"dueDate"] isEqual: @"2024-03-06"], @"Due date uses entered date plus net days across leap day");
    Check ([[[[created objectForKey: @"lines"] lastObject] objectForKey: @"date"] isEqual: @"2024-02-20"], @"Direct invoice service line uses issued date");
    Check ([dated invoiceClient: cid task: nil hours: @"1" tax: @"0" issuedDate: @"2099-12-20" dueDate: nil error: &error], @"Allow future issue date");
    Check ([[[[dated invoices] lastObject] objectForKey: @"dueDate"] isEqual: @"2100-01-04"], @"Future date crosses year boundary");
    Check ([dated addTimeForClient: cid date: @"2024-01-01" description: @"Recorded work" hours: @"2" error: &error], @"Record time before issue date");
    Check ([dated invoiceClient: cid task: nil hours: nil tax: @"0" issuedDate: @"2024-02-01" dueDate: nil error: &error], @"Timesheet invoice uses selected issue date");
    created = [[dated invoices] lastObject];
    Check ([[created objectForKey: @"date"] isEqual: @"2024-02-01"] && [[created objectForKey: @"dueDate"] isEqual: @"2024-02-16"], @"Timesheet due date uses selected issue date");
    Check ([[[[created objectForKey: @"lines"] lastObject] objectForKey: @"date"] isEqual: @"2024-01-01"], @"Timesheet work dates remain intact");
    Check ([dated invoiceClient: cid task: nil hours: @"1" tax: @"0" issuedDate: @"2024-02-01" dueDate: @"2024-02-10" error: &error], @"Manual due override may be historical but after issue date");
    [dated release];
    dated = [[CLLedger alloc] initWithPath: issuedPath error: &error];
    created = [[dated invoices] lastObject];
    Check (dated != nil && [[created objectForKey: @"date"] isEqual: @"2024-02-01"]
      && [[created objectForKey: @"dueDate"] isEqual: @"2024-02-10"], @"Issued and overridden due dates persist");
    [dated release]; [cid release];
  }

  blockedPath = [directory stringByAppendingPathComponent: @"not-a-directory"];
  [@"blocked" writeToFile: blockedPath atomically: YES encoding: NSUTF8StringEncoding error: NULL];
  blocked = [[CLLedger alloc] initWithPath: [blockedPath stringByAppendingPathComponent: @"Ledger.plist"] error: &error];
  Check (![blocked saveClient: nil name: @"Rollback" email: @"" address: @"" rate: @"1" error: &error], @"Unwritable path reports failure");
  Check ([[blocked clients] count] == 0, @"Failed save rolls back memory");
  [blocked release];
  {
    NSData *validData = [NSData dataWithContentsOfFile: path];
    NSMutableDictionary *invalid = [NSPropertyListSerialization propertyListWithData: validData
      options: NSPropertyListMutableContainersAndLeaves format: NULL error: NULL];
    [invalid setObject: [NSArray arrayWithObject: @"not a client"] forKey: @"clients"];
    [invalid writeToFile: path atomically: YES];
    ledger = [[CLLedger alloc] initWithPath: path error: &error];
    Check (ledger == nil, @"Malformed nested record refused");
    invalid = [NSPropertyListSerialization propertyListWithData: validData
      options: NSPropertyListMutableContainersAndLeaves format: NULL error: NULL];
    [invalid setObject: [NSNumber numberWithInt: 1] forKey: @"nextInvoice"];
    [invalid writeToFile: path atomically: YES];
    ledger = [[CLLedger alloc] initWithPath: path error: &error];
    Check (ledger == nil, @"Invalid invoice sequence refused");
  }
  {
    NSString *customPath = [directory stringByAppendingPathComponent: @"Custom.plist"];
    CLLedger *custom = [[CLLedger alloc] initWithPath: customPath error: &error];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithDictionary: [custom business]];
    NSArray *badStarts = [NSArray arrayWithObjects: @"0", @"-1", @"1.5", @"abc", @"2147483646", @"999999999999999999999", nil];
    NSData *logo = [@"embedded image bytes" dataUsingEncoding: NSUTF8StringEncoding];
    NSString *cid;
    for (i = 0; i < [badStarts count]; i++)
      {
        [settings setObject: [badStarts objectAtIndex: i] forKey: @"startingInvoiceNumber"];
        Check (![custom saveBusiness: settings error: &error], @"Reject invalid starting number");
      }
    [settings setObject: @"  " forKey: @"startingInvoiceNumber"];
    Check ([custom saveBusiness: settings error: &error], @"Blank starting number defaults to 1");
    Check ([[[custom business] objectForKey: @"startingInvoiceNumber"] isEqual: @"1"], @"Default is saved");
    [settings setObject: @"500" forKey: @"startingInvoiceNumber"];
    [settings setObject: logo forKey: @"logoData"];
    Check ([custom saveBusiness: settings error: &error], @"Save custom start and embedded logo");
    Check ([custom saveClient: nil name: @"Custom client" email: @"" address: @"" rate: @"10" error: &error], @"Custom client");
    cid = [[[custom clients] objectAtIndex: 0] objectForKey: @"id"];
    Check ([custom invoiceClient: cid hours: @"1" tax: @"0" dueDate: [CLLedger today] error: &error], @"Issue from custom start");
    Check ([[[[custom invoices] objectAtIndex: 0] objectForKey: @"id"] isEqual: @"INV-00500"], @"Custom invoice number");
    [settings setObject: @"1" forKey: @"startingInvoiceNumber"];
    Check (![custom saveBusiness: settings error: &error], @"Cannot renumber issued invoices");
    [settings setObject: @"500" forKey: @"startingInvoiceNumber"];
    [settings removeObjectForKey: @"logoData"];
    Check ([custom saveBusiness: settings error: &error], @"Remove logo for future invoices");
    Check ([[[[[custom invoices] objectAtIndex: 0] objectForKey: @"business"] objectForKey: @"logoData"] isEqual: logo], @"Issued logo preserved");
    [custom release];
    custom = [[CLLedger alloc] initWithPath: customPath error: &error];
    Check (custom != nil, @"Reopen custom numbering and logo snapshot");
    cid = [[[custom clients] objectAtIndex: 0] objectForKey: @"id"];
    Check ([custom invoiceClient: cid hours: @"1" tax: @"0" dueDate: [CLLedger today] error: &error], @"Continue custom numbering after restart");
    Check ([[[[custom invoices] objectAtIndex: 1] objectForKey: @"id"] isEqual: @"INV-00501"], @"Sequence increments");
    Check ([[[[custom invoices] objectAtIndex: 1] objectForKey: @"business"] objectForKey: @"logoData"] == nil, @"Future invoice omits removed logo");
    Check ([custom deleteInvoice: @"INV-00500" error: &error] && [custom deleteInvoice: @"INV-00501" error: &error], @"Delete all custom numbered invoices");
    [settings setObject: @"1" forKey: @"startingInvoiceNumber"];
    Check (![custom saveBusiness: settings error: &error], @"Starting number stays locked after all invoices are deleted");
    [settings setObject: @"500" forKey: @"startingInvoiceNumber"];
    Check ([custom saveBusiness: settings error: &error], @"Save original starting number after deletion");
    [custom release];
    custom = [[CLLedger alloc] initWithPath: customPath error: &error];
    Check (custom != nil, @"Reopen custom ledger with all invoices deleted");
    cid = [[[custom clients] objectAtIndex: 0] objectForKey: @"id"];
    Check ([custom invoiceClient: cid hours: @"1" tax: @"0" dueDate: [CLLedger today] error: &error], @"Issue after deleting all custom invoices");
    Check ([[[[custom invoices] lastObject] objectForKey: @"id"] isEqual: @"INV-00502"], @"Custom sequence preserved after deletion");
    [custom release];
  }
  [@"corrupt" writeToFile: path atomically: YES encoding: NSUTF8StringEncoding error: NULL];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger == nil, @"Corrupt ledger refused");
  Check ([[NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: NULL] isEqual: @"corrupt"], @"Corrupt file preserved");
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  [entryID release];
  [clientID release];
  NSLog (@"PASS: %u ledger checks", checks);
  [pool drain];
  return 0;
}
