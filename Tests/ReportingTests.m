#import <Foundation/Foundation.h>
#import "CLLedger.h"
#import "CLReporting.h"
static int checks;
static void Check (BOOL ok, NSString *message) { checks++; if (!ok) { NSLog (@"FAIL: %@", message); exit (1); } }
@interface ReportLedger : CLLedger { NSDictionary *_fixture; }
- (id) initWithFixture: (NSDictionary *)fixture;
@end
@implementation ReportLedger
- (id) initWithFixture: (NSDictionary *)fixture { self = [super init]; if (self) _fixture = [fixture retain]; return self; }
- (void) dealloc { [_fixture release]; [super dealloc]; }
- (NSArray *) invoices { return [_fixture objectForKey: @"invoices"]; }
- (NSArray *) expenses { return [_fixture objectForKey: @"expenses"]; }
- (NSArray *) entries { return [_fixture objectForKey: @"entries"]; }
- (NSDictionary *) business { return [NSDictionary dictionaryWithObject: @"USD" forKey: @"currency"]; }
- (NSDictionary *) clientWithID: (NSString *)identifier { return [NSDictionary dictionaryWithObjectsAndKeys: identifier, @"id", @"Acme", @"name", nil]; }
@end
static NSMutableDictionary *Invoice (NSString *identifier, NSString *currency, long long total, NSString *issued, NSString *due)
{
  return [NSMutableDictionary dictionaryWithObjectsAndKeys: identifier, @"id", issued, @"date", due, @"dueDate", [NSNumber numberWithBool: NO], @"paid",
    [NSNumber numberWithLongLong: total], @"total", [NSDictionary dictionaryWithObject: currency forKey: @"currency"], @"business",
    [NSDictionary dictionaryWithObjectsAndKeys: @"client-a", @"id", @"Acme", @"name", nil], @"client", nil];
}
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSMutableDictionary *partial = Invoice (@"partial", @"USD", 10000, @"2026-01-01", @"2026-01-31");
  NSMutableDictionary *legacy = Invoice (@"legacy", @"USD", 20000, @"2026-02-01", @"2026-03-01");
  NSMutableDictionary *unknown = Invoice (@"unknown", @"USD", 50000, @"2026-02-01", @"2026-02-15");
  NSMutableDictionary *euro = Invoice (@"euro", @"EUR", 90000, @"2026-02-01", @"2026-02-15");
  NSMutableDictionary *overpaid = Invoice (@"credit", @"USD", 1000, @"2026-02-01", @"2026-02-15");
  NSDictionary *fixture, *report, *summary; ReportLedger *ledger; NSString *csv;
  [partial setObject: [NSArray arrayWithObjects:
    [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: 3000], @"amount", @"2026-01-31", @"date", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: 2000], @"amount", @"2026-02-28", @"date", nil], nil] forKey: @"payments"];
  [legacy setObject: [NSNumber numberWithBool: YES] forKey: @"paid"];
  [unknown setObject: [NSNumber numberWithBool: YES] forKey: @"paymentUnverified"];
  [overpaid setObject: [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: 1500], @"amount", @"2026-02-01", @"date", nil]] forKey: @"payments"];
  fixture = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSArray arrayWithObjects: partial, legacy, unknown, euro, overpaid, nil], @"invoices",
    [NSArray arrayWithObjects:
      [NSDictionary dictionaryWithObjectsAndKeys: @"USD", @"currency", @"2026-02-01", @"date", @"Office", @"category", [NSNumber numberWithInt: 1250], @"amount", nil],
      [NSDictionary dictionaryWithObjectsAndKeys: @"EUR", @"currency", @"2026-02-01", @"date", @"Office", @"category", [NSNumber numberWithInt: 7500], @"amount", nil], nil], @"expenses",
    [NSArray arrayWithObjects:
      [NSDictionary dictionaryWithObjectsAndKeys: @"client-a", @"clientID", @"2026-02-01", @"date", [NSNumber numberWithInt: 3600], @"seconds", [NSNumber numberWithInt: 10000], @"rate", @"", @"invoiceID", nil],
      [NSDictionary dictionaryWithObjectsAndKeys: @"client-a", @"clientID", @"2026-02-28", @"date", @"2026-03-06", @"periodEnd", [NSNumber numberWithInt: 1800], @"seconds", [NSNumber numberWithInt: 10000], @"rate", [NSNumber numberWithBool: NO], @"billable", @"", @"invoiceID", nil], nil], @"entries", nil];
  ledger = [[ReportLedger alloc] initWithFixture: fixture];
  report = [CLReporting reportForLedger: ledger from: @"2026-02-01" to: @"2026-02-28" currency: @"USD" today: @"2026-03-01"];
  summary = [report objectForKey: @"summary"];
  Check ([[summary objectForKey: @"received"] longLongValue] == 3500, @"Cash uses payment date, includes both range boundaries and overpayment");
  Check ([[summary objectForKey: @"expenses"] longLongValue] == 1250, @"Expenses exclude other currencies");
  Check ([[summary objectForKey: @"net"] longLongValue] == 2250, @"Net is receipts less expenses");
  Check ([[summary objectForKey: @"billed"] longLongValue] == 71000, @"Billing uses issue date, independently of settlement verification");
  Check ([[summary objectForKey: @"outstanding"] longLongValue] == 5000, @"Current outstanding excludes unknown payments and does not offset overpayments");
  Check ([[summary objectForKey: @"overdue"] longLongValue] == 5000, @"Overdue uses remaining partial balance");
  Check ([[summary objectForKey: @"undated"] intValue] == 1 && [[summary objectForKey: @"unverified"] intValue] == 1, @"Legacy and unverified exclusions are visible");
  Check ([[summary objectForKey: @"billableSeconds"] intValue] == 3600 && [[summary objectForKey: @"nonbillableSeconds"] intValue] == 1800, @"Time splits billability and includes period totals by start date");
  Check ([[summary objectForKey: @"unbilled"] intValue] == 10000, @"Unbilled excludes nonbillable time");
  Check ([[report objectForKey: @"monthly"] count] == 1 && [[[[report objectForKey: @"monthly"] objectAtIndex: 0] objectForKey: @"net"] intValue] == 2250, @"Monthly grouping reconciles to summary");
  Check ([[report objectForKey: @"receivables"] count] == 1, @"Receivables exclude paid and unverified invoices");
  report = [CLReporting reportForLedger: ledger from: @"2026-02-01" to: @"2026-02-28" currency: @"EUR" today: @"2026-03-01"];
  summary = [report objectForKey: @"summary"];
  Check ([[summary objectForKey: @"outstanding"] intValue] == 90000 && [[summary objectForKey: @"net"] intValue] == -7500, @"Foreign currency has independent totals including negative net");
  Check ([[report objectForKey: @"time"] count] == 0, @"Time is valued only in the ledger currency");
  csv = [CLReporting csvForRows: [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: @"=SUM(1,2)\n\"quoted\"", @"name", [NSNumber numberWithInt: 1234], @"amount", nil]] keys: [NSArray arrayWithObjects: @"name", @"amount", nil] titles: [NSArray arrayWithObjects: @"Name", @"Amount", nil] moneyKeys: [NSArray arrayWithObject: @"amount"]];
  Check ([csv rangeOfString: @"\"'=SUM(1,2)\n\"\"quoted\"\"\",\"12.34\""].location != NSNotFound, @"CSV preserves quotes/newlines, formats cents and neutralizes formulas");
  csv = [CLReporting csvForRows: [NSArray arrayWithObject: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: -7500] forKey: @"net"]] keys: [NSArray arrayWithObject: @"net"] titles: [NSArray arrayWithObject: @"Net"] moneyKeys: [NSArray arrayWithObject: @"net"]];
  Check ([csv rangeOfString: @"\"-75.00\""].location != NSNotFound, @"Negative cash totals remain numeric in CSV");
  Check (![CLReporting date: @"Unrecorded" from: @"2026-01-01" to: @"2026-12-31"], @"Undated records never enter cash ranges");
  [ledger release]; NSLog (@"PASS: %d reporting checks", checks); [pool drain]; return 0;
}
