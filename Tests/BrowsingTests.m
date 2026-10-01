#import <AppKit/AppKit.h>
#import "CLAppController.h"
#import "CLLedger.h"
#import "CLBrowsing.h"
static int checks;
static void Check (BOOL ok, NSString *message) { checks++; if (!ok) { NSLog (@"FAIL: %@", message); exit (1); } }
@interface CLAppController (BrowsingTestAccess)
- (NSTableView *) tableIn: (NSView *)view columns: (NSArray *)columns widths: (NSArray *)widths;
- (NSView *) tab: (NSString *)title in: (NSTabView *)tabs;
- (void) setupBrowsing;
- (NSDictionary *) selectedRecord: (NSTableView *)table;
- (NSDictionary *) financeSelection;
- (void) browseChanged: (id)sender;
- (void) buildInsightsIn: (NSTabView *)tabs;
- (void) refreshInsights: (id)sender;
@end
@interface BrowseController : CLAppController
- (id) initWithLedger: (CLLedger *)ledger;
- (void) verify;
@end
@implementation BrowseController
- (id) initWithLedger: (CLLedger *)ledger
{
  self = [super init];
  if (self)
    {
      NSArray *columns = [NSArray arrayWithObjects: @"name", @"rate", @"date", @"amount", @"total", @"client", @"status", nil];
      NSArray *widths = [NSArray arrayWithObjects: [NSNumber numberWithInt: 200], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 100], nil];
      NSTabView *tabs = [[[NSTabView alloc] initWithFrame: NSMakeRect (0, 0, 1000, 600)] autorelease];
      _ledger = [ledger retain];
      _window = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, 1000, 600) styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
      [[_window contentView] addSubview: tabs];
      [self buildInsightsIn: tabs];
      _clientsTable = [self tableIn: [self tab: @"Clients" in: tabs] columns: columns widths: widths];
      _tasksTable = [self tableIn: [self tab: @"Tasks" in: tabs] columns: columns widths: widths];
      _timeTable = [self tableIn: [self tab: @"Time" in: tabs] columns: columns widths: widths];
      _invoicesTable = [self tableIn: [self tab: @"Invoices" in: tabs] columns: columns widths: widths];
      _financeTable = [self tableIn: [self tab: @"Finance" in: tabs] columns: columns widths: widths];
      _financeMode = [[[NSPopUpButton alloc] initWithFrame: NSZeroRect] autorelease];
      [_financeMode addItemsWithTitles: [NSArray arrayWithObjects: @"Accounts", @"Expenses", @"Payments", nil]];
      _tasksClient = [[[NSPopUpButton alloc] initWithFrame: NSZeroRect] autorelease];
      [_tasksClient addItemWithTitle: @"Client"];
      [[_tasksClient lastItem] setRepresentedObject: [[[ledger clients] objectAtIndex: 0] objectForKey: @"id"]];
      [self setupBrowsing];
    }
  return self;
}
- (void) verify
{
  CLRecordTable *clients = (CLRecordTable *)_clientsTable, *invoices = (CLRecordTable *)_invoicesTable;
  CLRecordTable *finances = (CLRecordTable *)_financeTable;
  NSString *selectedID;
  [clients reloadData];
  [clients setSortDescriptors: [NSArray arrayWithObject: [[[NSSortDescriptor alloc] initWithKey: @"rate" ascending: YES] autorelease]]];
  Check ([[[[clients visibleRecords] objectAtIndex: 0] objectForKey: @"rate"] intValue] == 200, @"Rates sort numerically: 2 before 10 and 100");
  [clients selectRowIndexes: [NSIndexSet indexSetWithIndex: 1] byExtendingSelection: NO];
  selectedID = [[[self selectedRecord: clients] objectForKey: @"id"] copy];
  [clients setSortDescriptors: [NSArray arrayWithObject: [[[NSSortDescriptor alloc] initWithKey: @"rate" ascending: NO] autorelease]]];
  Check ([[[self selectedRecord: clients] objectForKey: @"id"] isEqual: selectedID], @"Sorting preserves the selected record identity");
  [clients->search setStringValue: @"zebra"];
  [self browseChanged: clients->search];
  Check ([[clients visibleRecords] count] == 1 && [clients selectedRow] == -1, @"Filtering clears a hidden selection");
  [clients selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
  Check ([[[self selectedRecord: clients] objectForKey: @"name"] isEqual: @"Zébra"], @"Search is case/diacritic insensitive and actions resolve visible rows");
  [clients->search setStringValue: @"no-match"];
  [self browseChanged: clients->search];
  Check ([[clients visibleRecords] count] == 0 && [self selectedRecord: clients] == nil, @"Empty filters cannot target an underlying hidden record");
  [clients->search setStringValue: @""]; [clients reloadData];
  Check ([[clients visibleRecords] count] == 3, @"Clearing search restores all clients");
  [invoices reloadData];
  [invoices->statusFilter selectItemWithTitle: @"Partial"]; [invoices reloadData];
  Check ([[invoices visibleRecords] count] == 1, @"Partial payment filter");
  [invoices selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
  Check ([[CLLedger receivedForInvoice: [self selectedRecord: invoices]] intValue] == 500, @"Invoice actions resolve the partial invoice");
  [invoices->statusFilter selectItemWithTitle: @"Overdue"]; [invoices reloadData];
  Check ([[invoices visibleRecords] count] == 1, @"Overdue includes partially paid overdue invoices");
  [invoices->statusFilter selectItemAtIndex: 0]; [invoices->dateFilter selectItemWithTitle: @"This month"]; [invoices reloadData];
  Check ([[invoices visibleRecords] count] == 1, @"Date filter uses issued date");
  [invoices->clientFilter selectItemAtIndex: 1]; [invoices reloadData];
  Check ([[invoices visibleRecords] count] == 1, @"Client filter matches invoice snapshot IDs");
  Check ([[clients visibleRecords] count] == 3, @"Filters are independent across lists");
  [_financeMode selectItemAtIndex: 2]; [finances reloadData];
  Check ([[finances visibleRecords] count] == 1, @"Payments share the browsing pipeline");
  [finances selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
  Check ([[[self financeSelection] objectForKey: @"amount"] intValue] == 500, @"Finance actions resolve visible payment records");
  [_reportStart setStringValue: @"2026-02-30"]; [self refreshInsights: nil];
  Check (_reportData == nil && [[(CLRecordTable *)_reportTable visibleRecords] count] == 0, @"Invalid report dates clear results instead of showing stale data");
  [_reportStart setStringValue: @"2026-01-01"]; [_reportEnd setStringValue: @"2099-01-01"]; [self refreshInsights: nil];
  Check (_reportData != nil && [[(CLRecordTable *)_dashboardTable visibleRecords] count] == 1, @"Dashboard and reports refresh from ledger");
  [_reportMode selectItemAtIndex: 4]; [self refreshInsights: _reportMode];
  Check ([[_reportTable tableColumns] count] == 5 && [[(CLRecordTable *)_reportTable visibleRecords] count] == 2, @"Report switching rebuilds columns and current receivables");
  {
    CLRecordTable *tasks = (CLRecordTable *)_tasksTable, *time = (CLRecordTable *)_timeTable;
    [tasks->statusFilter selectItemWithTitle: @"Archived"]; [tasks reloadData];
    Check ([[tasks visibleRecords] count] == 1, @"Archived task filter");
    [tasks selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
    Check ([[[self selectedRecord: tasks] objectForKey: @"name"] isEqual: @"Old task"], @"Task actions use filtered selection");
    [time->statusFilter selectItemWithTitle: @"Nonbillable"]; [time reloadData];
    Check ([[time visibleRecords] count] == 1, @"Nonbillable time filter");
    [time->statusFilter selectItemWithTitle: @"Unbilled"]; [time reloadData];
    Check ([[time visibleRecords] count] == 1, @"Unbilled excludes nonbillable work");
    [_financeMode selectItemAtIndex: 1]; [finances->statusFilter selectItemWithTitle: @"Missing receipt"]; [finances reloadData];
    Check ([[finances visibleRecords] count] == 1, @"Missing receipt filter");
    [finances->statusFilter selectItemWithTitle: @"Has receipt"]; [finances reloadData];
    Check ([[finances visibleRecords] count] == 0, @"Receipt filters distinguish unattached expenses");
  }
  [selectedID release];
}
@end
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  CLLedger *ledger = [[CLLedger alloc] initWithPath: [directory stringByAppendingPathComponent: @"ledger.plist"] error: NULL];
  BrowseController *controller; NSDictionary *invoice; NSMutableDictionary *edit;
  [NSApplication sharedApplication];
  [ledger saveClient: nil name: @"Zébra" email: @"" address: @"" rate: @"100" error: NULL];
  [ledger saveClient: nil name: @"Alpha" email: @"" address: @"" rate: @"2" error: NULL];
  [ledger saveClient: nil name: @"Middle" email: @"" address: @"" rate: @"10" error: NULL];
  [ledger invoiceClient: [[[ledger clients] objectAtIndex: 0] objectForKey: @"id"] hours: @"1" tax: @"0" dueDate: @"2099-01-01" error: NULL];
  [ledger invoiceClient: [[[ledger clients] objectAtIndex: 1] objectForKey: @"id"] hours: @"10" tax: @"0" dueDate: @"2099-01-01" error: NULL];
  invoice = [[ledger invoices] lastObject];
  edit = [NSMutableDictionary dictionaryWithDictionary: [ledger editValuesForInvoice: invoice]];
  [edit setObject: @"2020-01-01" forKey: @"date"]; [edit setObject: @"2020-01-02" forKey: @"dueDate"];
  Check ([ledger updateInvoice: [invoice objectForKey: @"id"] values: edit error: NULL], @"Prepare overdue fixture");
  Check ([ledger savePayment: nil invoice: [invoice objectForKey: @"id"] values: [NSDictionary dictionaryWithObjectsAndKeys: @"5", @"amount", [CLLedger today], @"date", @"", @"accountID", @"Test", @"reference", nil] error: NULL], @"Prepare partial payment");
  {
    NSString *clientID = [[[ledger clients] objectAtIndex: 0] objectForKey: @"id"];
    NSDictionary *account = [NSDictionary dictionaryWithObjectsAndKeys: @"Checking", @"name", @"Bank", @"bank", @"", @"number", @"", @"routing", @"USD", @"currency", @"0", @"openingBalance", @"", @"notes", nil];
    Check ([ledger saveTask: nil client: clientID name: @"Old task" rate: @"5" error: NULL], @"Task fixture");
    [ledger toggleTaskArchived: [[[[ledger tasksForClient: clientID includeArchived: YES] lastObject] objectForKey: @"id"] description] error: NULL];
    [ledger saveTask: nil client: clientID name: @"Current task" rate: @"10" error: NULL];
    [ledger addTimeForClient: clientID date: [CLLedger today] description: @"Work" hours: @"1" error: NULL];
    [ledger addTimeRows: [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: [CLLedger today], @"date", @"0.5", @"hours", @"Break", @"description", nil]] client: clientID task: nil billable: NO error: NULL];
    Check ([ledger saveAccount: nil values: account error: NULL], @"Account fixture");
    Check ([ledger saveExpense: nil values: [NSDictionary dictionaryWithObjectsAndKeys: [CLLedger today], @"date", @"Shop", @"vendor", @"Office", @"category", @"10", @"amount", [[[ledger accounts] lastObject] objectForKey: @"id"], @"accountID", @"", @"reference", @"", @"notes", nil] error: NULL], @"Expense fixture");
  }
  controller = [[BrowseController alloc] initWithLedger: ledger]; [controller verify];
  [controller release]; [ledger release]; [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: %d browsing and report UI checks", checks); [pool drain]; return 0;
}
