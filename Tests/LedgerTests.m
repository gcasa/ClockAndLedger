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
