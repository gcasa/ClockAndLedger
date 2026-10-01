#import "CLAppController.h"
#import "CLLedger.h"
#import "CLInvoiceView.h"
#import "CLInvoiceMailer.h"
#import "CLDateField.h"
#import "CLInvoiceEditor.h"

#import "CLReporting.h"
#import "CLBrowsing.h"
#include "CLAppearance.inc"
#include "CLBrowsing.inc"

static NSTextField *
CLLabel (NSView *parent, NSString *text, NSRect frame, CGFloat size)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame: frame] autorelease];
  [field setStringValue: text];
  [field setEditable: NO];
  [field setSelectable: NO];
  [field setBordered: NO];
  [field setDrawsBackground: NO];
  [field setFont: size >= 20 ? [NSFont boldSystemFontOfSize: size] : [NSFont systemFontOfSize: size]];
#ifdef __APPLE__
  [field setTextColor: size >= 20 ? [NSColor labelColor] : [NSColor secondaryLabelColor]];
#else
  [field setTextColor: [NSColor controlTextColor]];
#endif
  [parent addSubview: field];
  return field;
}

static NSTextField *
CLField (NSView *parent, NSString *value, NSRect frame)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame: frame] autorelease];
  [field setStringValue: value != nil ? value : @""];
  [field setFont: [NSFont systemFontOfSize: 13]];
  [field setBezelStyle: NSTextFieldRoundedBezel];
  [parent addSubview: field];
  return field;
}

static NSButton *
CLButton (NSView *parent, NSString *title, NSRect frame, id target, SEL action)
{
  BOOL primary = [title hasPrefix: @"Add"] || [title hasPrefix: @"Create Invoice"] ||
    [title isEqual: @"Start Timer"] || [title isEqual: @"Save Business Details"];
  NSButton *button = [[[(primary ? [CLPrimaryButton class] : [NSButton class]) alloc] initWithFrame: frame] autorelease];
  [button setTitle: title];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setTarget: target];
  [button setAction: action];
  [button setFont: [NSFont systemFontOfSize: 13]];
  [parent addSubview: button];
  return button;
}

static NSString *
CLLedgerPath (void)
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains (NSApplicationSupportDirectory, NSUserDomainMask, YES);
  NSString *base = [paths count] > 0 ? [paths objectAtIndex: 0] : NSHomeDirectory ();
  return [[base stringByAppendingPathComponent: @"ClockAndLedger"] stringByAppendingPathComponent: @"Ledger.plist"];
}

@interface CLAppController (Private)
/** Refresh tables, client choices and financial summary after a mutation. */
#ifdef __APPLE__
- (void) setupStatusItem;
- (void) toggleDockVisibility: (id)sender;
- (void) updateStatusItem: (id)sender;
- (void) startStatusTimer: (id)sender;
- (void) showMainWindow: (id)sender;
#endif
- (NSArray *) financeRows;
- (void) buildInsightsIn: (NSTabView *)tabs;
- (void) refreshInsights: (id)sender;
- (void) setupBrowsing;
- (void) browseChanged: (id)sender;
- (NSDictionary *) browsePeriod: (NSInteger)index;
- (NSArray *) rawRowsForTable: (NSTableView *)table;
- (id) valueForRecord: (NSDictionary *)record column: (NSString *)key table: (NSTableView *)table;
- (void) financeChanged: (id)sender;
- (void) financeEditRecord: (NSDictionary *)record;
- (void) editPaymentForInvoice: (NSDictionary *)invoice payment: (NSDictionary *)payment;
- (void) refresh;
/** Show a recoverable operation failure if an error is present. */
- (void) showError: (NSString *)error;
/** Append an empty native tab and return its content view. */
- (NSView *) tab: (NSString *)title in: (NSTabView *)tabs;
/** Build a read-only, scrollable table with named columns. */
- (NSTableView *) tableIn: (NSView *)view columns: (NSArray *)columns widths: (NSArray *)widths;
/** Resolve the selected table row to its current ledger record. */
- (NSDictionary *) selectedRecord: (NSTableView *)table;
/** Return the stable identifier represented by the selected menu item. */
- (NSString *) selectedClient: (NSPopUpButton *)popup;
/** Rebuild client choices while preserving selection by identifier. */
- (void) fillClients: (NSPopUpButton *)popup;
/** Run a modal editor and return entered values, or nil on cancel. */
- (NSDictionary *) editForm: (NSString *)title labels: (NSArray *)labels values: (NSArray *)values;
/** Edit a client, retaining entered values across validation failures. */
- (void) editClientRecord: (NSDictionary *)client;
/** Rebuild the selected client's active task menu with current rates. */
- (void) fillTimeTasks;
/** Edit task definition while retaining form values after invalid input. */
- (void) editTaskRecord: (NSDictionary *)task;
/** Enter daily hours for a resolved calendar period and save them atomically. */
- (void) enterTimesheet: (NSDictionary *)period;
@end

@implementation CLAppController

#include "CLStatusBar.inc"
#include "CLInsightsUI.inc"
#include "CLBrowseUI.inc"

- (void) dealloc
{
#ifdef __APPLE__
  [_statusPulse invalidate];
  [_statusPulse release];
  if (_statusItem != nil) [[NSStatusBar systemStatusBar] removeStatusItem: _statusItem];
  [_statusItem release];
#endif
  [_pulse invalidate];
  [_pulse release];
  [_reminderPulse invalidate];
  [_reminderPulse release];
  [_mailer release];
  [_mailInvoiceID release];
  [_mailStage release];
  [_reminderSnoozes release];
#ifdef __APPLE__
  if (_backgroundActivity != nil) [[NSProcessInfo processInfo] endActivity: _backgroundActivity];
#endif
  [_backgroundActivity release];
  [_dashboardCards release];
  [_dashboardReport release];
  [_reportData release];
  [_window release];
  [_businessFields release];
  [_businessLogoData release];
  [_dialogInvoiceClientID release];
  [_ledger release];
  [_lock release];
  [super dealloc];
}

- (void) showError: (NSString *)error
{
  if (error != nil)
    NSRunAlertPanel (@"Clock & Ledger", @"%@", @"OK", nil, nil, error);
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  NSString *error = nil;
  NSString *directory = [CLLedgerPath () stringByDeletingLastPathComponent];
  NSMenu *menu;
  NSMenu *appMenu;
  NSMenuItem *item;
  NSTabView *tabs;
  NSView *view;
  NSArray *keys;
  NSArray *labels;
  unsigned int i;

  [[NSFileManager defaultManager] createDirectoryAtPath: directory
    withIntermediateDirectories: YES attributes: nil error: NULL];
  _lock = [[NSDistributedLock alloc] initWithPath: [directory stringByAppendingPathComponent: @"Writer.lock"]];
  if (![_lock tryLock])
    {
      NSInteger choice = NSRunAlertPanel (@"Ledger is locked",
        @"Another copy may be using this ledger. If a previous session crashed, close all other copies before recovering the lock.",
        @"Quit", @"Recover lock", nil);
      if (choice != NSAlertAlternateReturn)
        {
          [NSApp terminate: nil];
          return;
        }
      [_lock breakLock];
      if (![_lock tryLock])
        {
          [self showError: @"Cannot acquire the ledger lock. Check that the data directory is writable."];
          [NSApp terminate: nil];
          return;
        }
    }
  _ownsLock = YES;
  _ledger = [[CLLedger alloc] initWithPath: CLLedgerPath () error: &error];
  if (_ledger == nil)
    {
      [self showError: error]; [NSApp terminate: nil];
      return;
    }

  menu = [[[NSMenu alloc] initWithTitle: @"Main"] autorelease];
  item = [[[NSMenuItem alloc] initWithTitle: @"Clock & Ledger" action: NULL keyEquivalent: @""] autorelease];
  [menu addItem: item];
  appMenu = [[[NSMenu alloc] initWithTitle: @"Clock & Ledger"] autorelease];
  [appMenu addItemWithTitle: @"About Clock & Ledger" action: @selector(orderFrontStandardAboutPanel:) keyEquivalent: @""];
  [appMenu addItem: [NSMenuItem separatorItem]];
  [[appMenu addItemWithTitle: @"Import QuickBooks…" action: @selector(importQuickBooks:) keyEquivalent: @"i"] setTarget: self];
  [[appMenu addItemWithTitle: @"Back Up Ledger…" action: @selector(backupLedger:) keyEquivalent: @"b"] setTarget: self];
  [[appMenu addItemWithTitle: @"Print Selected Invoice…" action: @selector(printInvoice:) keyEquivalent: @"p"] setTarget: self];
  [appMenu addItem: [NSMenuItem separatorItem]];
  [appMenu addItemWithTitle: @"Quit Clock & Ledger" action: @selector(terminate:) keyEquivalent: @"q"];
  [item setSubmenu: appMenu];
  [NSApp setMainMenu: menu];
  _window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 1240, 760)
    styleMask: NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  [_window setTitle: @"Clock & Ledger"];
  [_window setMinSize: NSMakeSize (1240, 760)];
  [_window setReleasedWhenClosed: NO];
  [_window setContentView: [[[CLWorkspaceView alloc] initWithFrame: NSMakeRect (0, 0, 1240, 760)] autorelease]];
  [CLLabel ([_window contentView], @"Clock & Ledger", NSMakeRect (236, 695, 700, 40), 30)
    setAutoresizingMask: NSViewMinYMargin];
  [CLLabel ([_window contentView], @"A little clarity for your working day.", NSMakeRect (238, 668, 800, 22), 13)
    setAutoresizingMask: NSViewMinYMargin];
  _summaryLabel = CLLabel ([_window contentView], @"", NSMakeRect (238, 626, 970, 28), 13);
  [_summaryLabel setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
  tabs = [[[NSTabView alloc] initWithFrame: NSMakeRect (224, 28, 984, 574)] autorelease];
  [tabs setTabViewType: NSNoTabsNoBorder];
  [tabs setDrawsBackground: NO];
  [tabs setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  _workspaceTabs = tabs;
  [[_window contentView] addSubview: tabs];
  {
    NSTextField *brand = CLLabel ([_window contentView], @"C / L", NSMakeRect (24, 690, 150, 42), 28);
    NSTextField *caption = CLLabel ([_window contentView], @"YOUR WORKSPACE", NSMakeRect (25, 636, 160, 22), 10);
    NSTextField *footer = CLLabel ([_window contentView], @"Time well spent.\nBooks well kept.", NSMakeRect (24, 28, 155, 48), 12);
    [brand setTextColor: [NSColor whiteColor]];
    [caption setTextColor: [NSColor colorWithCalibratedWhite: 1 alpha: 0.5]];
    [footer setTextColor: [NSColor colorWithCalibratedWhite: 1 alpha: 0.5]];
    [brand setAutoresizingMask: NSViewMinYMargin];
    [caption setAutoresizingMask: NSViewMinYMargin];
  }

  [self buildInsightsIn: tabs];

  view = [self tab: @"Clients" in: tabs];
  CLLabel (view, @"Your clients", NSMakeRect (18, 496, 600, 28), 20);
  CLLabel (view, @"Contact details, hourly rates and net payment days. Use 0 days for payment due on receipt.", NSMakeRect (18, 467, 940, 24), 12);
  _clientsTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"name", @"email", @"address", @"rate", @"netDays", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 220], [NSNumber numberWithInt: 240], [NSNumber numberWithInt: 230], [NSNumber numberWithInt: 120], [NSNumber numberWithInt: 120], nil]];
  [_clientsTable setDoubleAction: @selector(editClient:)];
  [_clientsTable setTarget: self];
  CLButton (view, @"Add Client", NSMakeRect (12, 12, 130, 32), self, @selector(addClient:));
  CLButton (view, @"Edit", NSMakeRect (148, 12, 100, 32), self, @selector(editClient:));
  CLButton (view, @"Delete", NSMakeRect (254, 12, 100, 32), self, @selector(deleteClient:));
  CLButton (view, @"Email Reminders…", NSMakeRect (368, 12, 190, 32), self, @selector(editClientReminders:));

  view = [self tab: @"Client Tasks" in: tabs];
  CLLabel (view, @"Tasks & hourly rates", NSMakeRect (18, 500, 700, 28), 20);
  _tasksClient = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 453, 280, 28) pullsDown: NO] autorelease];
  [_tasksClient setTarget: self];
  [_tasksClient setAction: @selector(tasksClientChanged:)];
  [view addSubview: _tasksClient];
  CLLabel (view, @"Each client can have different tasks and rates. Changes apply to future time.", NSMakeRect (310, 452, 635, 28), 12);
  _tasksTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"name", @"rate", @"status", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 560], [NSNumber numberWithInt: 180], [NSNumber numberWithInt: 180], nil]];
  [[_tasksTable enclosingScrollView] setFrame: NSMakeRect (18, 58, 940, 380)];
  [_tasksTable setTarget: self];
  [_tasksTable setDoubleAction: @selector(editTask:)];
  CLButton (view, @"Add Task", NSMakeRect (12, 12, 130, 32), self, @selector(addTask:));
  CLButton (view, @"Edit Task", NSMakeRect (148, 12, 130, 32), self, @selector(editTask:));
  CLButton (view, @"Archive / Restore", NSMakeRect (284, 12, 190, 32), self, @selector(archiveTask:));

  view = [self tab: @"Timesheets" in: tabs];
  CLLabel (view, @"Track your work", NSMakeRect (18, 500, 280, 28), 20);
  CLLabel (view, @"Client", NSMakeRect (18, 480, 220, 18), 11);
  _timeClient = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 451, 235, 28) pullsDown: NO] autorelease];
  [_timeClient setTarget: self];
  [_timeClient setAction: @selector(timeClientChanged:)];
  [view addSubview: _timeClient];
  CLLabel (view, @"Task / hourly rate", NSMakeRect (267, 480, 450, 18), 11);
  _timeTask = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (267, 451, 470, 28) pullsDown: NO] autorelease];
  [view addSubview: _timeTask];
  CLLabel (view, @"Work description (optional when using a task)", NSMakeRect (18, 429, 600, 18), 11);
  _taskField = CLField (view, @"", NSMakeRect (18, 400, 630, 26));
  CLButton (view, @"Start Timer", NSMakeRect (662, 396, 132, 34), self, @selector(startTimer:));
  CLButton (view, @"Stop", NSMakeRect (804, 396, 88, 34), self, @selector(stopTimer:));
  CLLabel (view, @"Period", NSMakeRect (18, 376, 130, 18), 11);
  _periodChoice = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 347, 130, 28) pullsDown: NO] autorelease];
  [_periodChoice addItemsWithTitles: [NSArray arrayWithObjects: @"Day", @"Week", @"Month", nil]];
  [_periodChoice setTarget: self];
  [_periodChoice setAction: @selector(periodChanged:)];
  [view addSubview: _periodChoice];
  CLLabel (view, @"Date in period (YYYY-MM-DD)", NSMakeRect (160, 376, 210, 18), 11);
  _periodDate = [CLDateField fieldInView: view value: [CLLedger today] frame: NSMakeRect (160, 349, 195, 26)];
  [_periodDate setDelegate: (id)self];
  [_periodDate setTarget: self];
  [_periodDate setAction: @selector(periodChanged:)];
  CLLabel (view, @"Entry method", NSMakeRect (370, 376, 240, 18), 11);
  _entryMode = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (370, 347, 240, 28) pullsDown: NO] autorelease];
  [_entryMode addItemsWithTitles: [NSArray arrayWithObjects: @"One total for period", @"Daily timesheet", nil]];
  [view addSubview: _entryMode];
  _nonbillableTime = [[[NSButton alloc] initWithFrame: NSMakeRect (625, 347, 330, 28)] autorelease];
  [_nonbillableTime setButtonType: NSSwitchButton];
  [_nonbillableTime setTitle: @"Nonbillable time (lunch, breaks, etc.)"];
  [_nonbillableTime setToolTip: @"Applies to Add Time and daily timesheets. Timers remain billable; edit a stopped timer entry to change its billability."];
  [view addSubview: _nonbillableTime];
  _periodLabel = CLLabel (view, @"", NSMakeRect (18, 321, 936, 22), 12);
  _timerLabel = CLLabel (view, @"No timer running", NSMakeRect (18, 292, 936, 25), 12);
  _timeTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"date", @"client", @"taskName", @"description", @"hours", @"rate", @"amount", @"billing", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 195], [NSNumber numberWithInt: 120], [NSNumber numberWithInt: 130], [NSNumber numberWithInt: 180], [NSNumber numberWithInt: 65], [NSNumber numberWithInt: 80], [NSNumber numberWithInt: 85], [NSNumber numberWithInt: 150], nil]];
  [[_timeTable enclosingScrollView] setFrame: NSMakeRect (18, 88, 940, 194)];
  CLButton (view, @"Add Time…", NSMakeRect (12, 12, 135, 32), self, @selector(addTime:));
  CLButton (view, @"Edit Entry…", NSMakeRect (150, 12, 130, 32), self, @selector(editTime:));
  [_timeTable setTarget: self];
  [_timeTable setDoubleAction: @selector(editTime:)];
  CLButton (view, @"Delete Entry", NSMakeRect (283, 12, 130, 32), self, @selector(deleteTime:));
  CLButton (view, @"Review Imported Time", NSMakeRect (416, 12, 220, 32), self, @selector(reviewImportedTime:));

  _timesheetTotal = CLLabel (view, @"", NSMakeRect (18, 57, 940, 25), 12);
  [CLButton (view, @"Create Invoice…", NSMakeRect (640, 12, 190, 32), self, @selector(invoiceTimesheet:))
    setToolTip: @"Bills all eligible unbilled time for the client selected above. List search and filters do not limit the invoice."];

  view = [self tab: @"Invoices" in: tabs];
  CLLabel (view, @"Billing", NSMakeRect (18, 500, 500, 28), 20);
  CLLabel (view, @"Choose a client and task, then enter hours to bill at the task’s current rate.", NSMakeRect (18, 472, 940, 22), 12);
  _invoiceClient = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 427, 180, 28) pullsDown: NO] autorelease];
  [view addSubview: _invoiceClient];
  [_invoiceClient setTarget: self];
  [_invoiceClient setAction: @selector(invoiceClientChanged:)];
  CLLabel (view, @"Tax %", NSMakeRect (208, 430, 40, 22), 12);
  _taxField = CLField (view, @"0", NSMakeRect (248, 429, 45, 26));
  CLLabel (view, @"Issued", NSMakeRect (303, 430, 45, 22), 12);
  _issuedField = [CLDateField fieldInView: view value: [CLLedger today] frame: NSMakeRect (350, 429, 155, 26)];
  [_issuedField setDelegate: (id)self];
  [_issuedField setToolTip: @"YYYY-MM-DD. Changing this date recalculates the due date using the client's net payment days."];
  CLLabel (view, @"Due date", NSMakeRect (518, 430, 55, 22), 12);
  _dueField = [CLDateField fieldInView: view value: @"" frame: NSMakeRect (575, 429, 155, 26)];
  CLButton (view, @"Create Invoice", NSMakeRect (750, 424, 195, 34), self, @selector(createInvoice:));
  CLLabel (view, @"Hours", NSMakeRect (18, 389, 55, 24), 12);
  _invoiceHours = CLField (view, @"", NSMakeRect (78, 389, 130, 26));
  _invoiceRate = CLLabel (view, @"", NSMakeRect (225, 389, 650, 24), 12);
  CLLabel (view, @"Task", NSMakeRect (18, 350, 55, 24), 12);
  _invoiceTask = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (78, 347, 480, 28) pullsDown: NO] autorelease];
  [_invoiceTask setTarget: self];
  [_invoiceTask setAction: @selector(invoiceTaskChanged:)];
  [view addSubview: _invoiceTask];
  CLButton (view, @"Review Email…", NSMakeRect (775, 345, 175, 30), self, @selector(reviewReminder:));
  _mailStatus = CLLabel (view, @"Email opens a draft with a PDF. Scheduled reminders ask before sending.", NSMakeRect (18, 311, 935, 26), 11);
  _invoicesTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"id", @"client", @"date", @"dueDate", @"paymentDays", @"total", @"status", @"reminder", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 125], [NSNumber numberWithInt: 165], [NSNumber numberWithInt: 105], [NSNumber numberWithInt: 105], [NSNumber numberWithInt: 125], [NSNumber numberWithInt: 110], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 175], nil]];
  [[[_invoicesTable tableColumnWithIdentifier: @"paymentDays"] headerCell] setStringValue: @"Days until payment"];
  [_invoicesTable setToolTip: @"Days until payment: 0 means due today; +n means n days overdue. — means paid or unverified."];
  [[[_invoicesTable tableColumnWithIdentifier: @"date"] headerCell] setStringValue: @"Issued"];
  [[_invoicesTable enclosingScrollView] setFrame: NSMakeRect (18, 58, 940, 245)];
  [_invoicesTable setDoubleAction: @selector(previewInvoice:)];
  [_invoicesTable setTarget: self];
  CLButton (view, @"Edit Invoice…", NSMakeRect (12, 12, 130, 32), self, @selector(editInvoice:));
  CLButton (view, @"Preview", NSMakeRect (148, 12, 90, 32), self, @selector(previewInvoice:));
  CLButton (view, @"Print…", NSMakeRect (244, 12, 90, 32), self, @selector(printInvoice:));
  CLButton (view, @"Record Payment…", NSMakeRect (340, 12, 180, 32), self, @selector(togglePaid:));

  CLButton (view, @"Email Invoice…", NSMakeRect (526, 12, 180, 32), self, @selector(emailInvoice:));

  CLButton (view, @"Delete Invoice…", NSMakeRect (712, 12, 180, 32), self, @selector(deleteInvoice:));

  view = [self tab: @"Company Finances" in: tabs];
  CLLabel (view, @"Company finances", NSMakeRect (18, 515, 600, 28), 20);
  _financeMode = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 475, 260, 30) pullsDown: NO] autorelease];
  [_financeMode addItemsWithTitles: [NSArray arrayWithObjects: @"Bank accounts", @"Expenses & receipts", @"Invoice payments", nil]];
  [_financeMode setTarget: self]; [_financeMode setAction: @selector(financeChanged:)]; [view addSubview: _financeMode];
  CLLabel (view, @"Balance = opening balance + recorded receipts − expenses. No bank synchronization.", NSMakeRect (290, 476, 665, 28), 12);
  _financeTable = [self tableIn: view columns: [NSArray arrayWithObjects: @"name", @"date", @"vendor", @"category", @"amount", @"account", @"reference", @"receiptName", nil] widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 180], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 150], [NSNumber numberWithInt: 110], [NSNumber numberWithInt: 135], [NSNumber numberWithInt: 150], [NSNumber numberWithInt: 160], [NSNumber numberWithInt: 180], nil]];
  CLButton (view, @"Add…", NSMakeRect (18, 12, 100, 32), self, @selector(financeAdd:));
  CLButton (view, @"Edit…", NSMakeRect (122, 12, 100, 32), self, @selector(financeEdit:));
  CLButton (view, @"Delete…", NSMakeRect (226, 12, 100, 32), self, @selector(financeDelete:));
  CLButton (view, @"Attach Receipt…", NSMakeRect (334, 12, 165, 32), self, @selector(financeReceipt:));
  CLButton (view, @"Export CSV…", NSMakeRect (718, 12, 135, 32), self, @selector(financeExport:));
  CLButton (view, @"Export / Open Receipt…", NSMakeRect (505, 12, 205, 32), self, @selector(financeOpenReceipt:));

  view = [self tab: @"Business" in: tabs];
  CLLabel (view, @"Business & payment details", NSMakeRect (18, 496, 800, 28), 20);
  CLLabel (view, @"Set these before issuing invoices. Each invoice preserves a copy of these details.", NSMakeRect (18, 467, 940, 24), 12);
  _businessFields = [[NSMutableDictionary alloc] init];
  keys = [NSArray arrayWithObjects: @"name", @"email", @"address", @"currency", @"notes", nil];
  labels = [NSArray arrayWithObjects: @"Business name", @"Email", @"Postal address", @"Currency code", @"Payment instructions", nil];
  for (i = 0; i < [keys count]; i++)
    {
      CGFloat y = 412 - i * 56;
      NSTextField *field;
      CLLabel (view, [labels objectAtIndex: i], NSMakeRect (20, y + 2, 165, 24), 13);
      field = CLField (view, [[_ledger business] objectForKey: [keys objectAtIndex: i]], NSMakeRect (190, y, 730, 48));
      if (i == 2 || i == 4)
        [[field cell] setWraps: YES];
      if ([[labels objectAtIndex: i] isEqual: @"Starting invoice #"])
        {
          [[field cell] setPlaceholderString: @"Blank uses business numbering"];
          [field setToolTip: @"For example, 500 starts at INV-00500. Used numbers are skipped. The starting number is fixed once used."];
        }
      [_businessFields setObject: field forKey: [keys objectAtIndex: i]];
    }
  CLLabel (view, @"Starting invoice number", NSMakeRect (20, 151, 170, 24), 13);
  {
    NSString *start = [[_ledger business] objectForKey: @"startingInvoiceNumber"];
    NSTextField *field = CLField (view, start != nil ? start : @"", NSMakeRect (190, 150, 150, 26));
    [[field cell] setPlaceholderString: @"1"];
    [field setEnabled: ![_ledger hasIssuedInvoices]];
    [_businessFields setObject: field forKey: @"startingInvoiceNumber"];
  }
  CLLabel (view, @"Defaults to 1; fixed after the first invoice or import.", NSMakeRect (350, 151, 560, 24), 12);
  _businessLogoData = [[[_ledger business] objectForKey: @"logoData"] copy];
  _businessLogoPreview = [[[NSImageView alloc] initWithFrame: NSMakeRect (190, 83, 100, 60)] autorelease];
  [_businessLogoPreview setImageScaling: NSImageScaleProportionallyUpOrDown];
  if (_businessLogoData != nil)
    [_businessLogoPreview setImage: [[[NSImage alloc] initWithData: _businessLogoData] autorelease]];
  [view addSubview: _businessLogoPreview];
  CLLabel (view, @"Business icon or logo", NSMakeRect (20, 102, 170, 24), 13);
  CLButton (view, @"Choose Image…", NSMakeRect (310, 98, 160, 32), self, @selector(chooseBusinessLogo:));
  CLButton (view, @"Remove Logo", NSMakeRect (480, 98, 140, 32), self, @selector(removeBusinessLogo:));
  CLButton (view, @"Save Business Details", NSMakeRect (184, 42, 220, 34), self, @selector(saveBusiness:));
  CLButton (view, @"Back Up Ledger…", NSMakeRect (410, 42, 190, 34), self, @selector(backupLedger:));
  CLButton (view, @"Import QuickBooks…", NSMakeRect (606, 42, 210, 34), self, @selector(importQuickBooks:));
  [self setupBrowsing];
  for (i = 0; i < [[tabs tabViewItems] count]; i++)
    {
      CLNavigationButton *button = [[[CLNavigationButton alloc] initWithFrame: NSMakeRect (12, 570 - i * 50, 172, 44)] autorelease];
      [button setTitle: [[[tabs tabViewItems] objectAtIndex: i] label]];
      [button setButtonType: NSPushOnPushOffButton];
      [button setBordered: NO];
      [button setTag: i];
      [button setState: i == 0 ? NSOnState : NSOffState];
      [button setTarget: self];
      [button setAction: @selector(selectWorkspace:)];
      [button setAutoresizingMask: NSViewMinYMargin];
      [[_window contentView] addSubview: button];
    }
  /* Keep the editors above their expanding tables when resizing. */
  for (i = 0; i < [[tabs tabViewItems] count]; i++)
    {
      NSArray *children = [[[[tabs tabViewItems] objectAtIndex: i] view] subviews];
      unsigned int j;
      for (j = 0; j < [children count]; j++)
        {
          NSView *child = [children objectAtIndex: j];
          if (![child isKindOfClass: [NSScrollView class]] &&
              ([child frame].origin.y > 100 || i == [[tabs tabViewItems] count] - 1))
            [child setAutoresizingMask: NSViewMinYMargin];
        }
    }
#ifdef __APPLE__
  [self setupStatusItem];
#endif
  [self refresh];
  _pulse = [[NSTimer scheduledTimerWithTimeInterval: 1 target: self selector: @selector(tick:) userInfo: nil repeats: YES] retain];
  _reminderPulse = [[NSTimer scheduledTimerWithTimeInterval: 60 target: self selector: @selector(checkReminders:) userInfo: nil repeats: YES] retain];
  [_window center];
#ifndef __APPLE__
  /* macOS opens the workspace on demand from the menu bar. */
  [_window makeKeyAndOrderFront: nil];
  [NSApp activateIgnoringOtherApps: YES];
#endif
}

- (void) selectWorkspace: (NSButton *)sender
{
  NSView *view;
  [_workspaceTabs selectTabViewItemAtIndex: [sender tag]];
  if ([sender tag] < 2) [self refreshInsights: nil];
  else
    for (view in [[[_workspaceTabs selectedTabViewItem] view] subviews])
      if ([view isKindOfClass: [NSScrollView class]] && [[(NSScrollView *)view documentView] isKindOfClass: [CLRecordTable class]])
        [(NSTableView *)[(NSScrollView *)view documentView] reloadData];
  for (view in [[_window contentView] subviews])
    if ([view isKindOfClass: [CLNavigationButton class]])
      {
        [(NSButton *)view setState: view == sender ? NSOnState : NSOffState];
        [view setNeedsDisplay: YES];
      }
}

- (NSView *) tab: (NSString *)title in: (NSTabView *)tabs
{
  NSTabViewItem *item = [[[NSTabViewItem alloc] initWithIdentifier: title] autorelease];
  NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect (0, 0, 976, 540)] autorelease];
  [item setLabel: title];
  [item setView: view];
  [tabs addTabViewItem: item];
  return view;
}

- (NSTableView *) tableIn: (NSView *)view columns: (NSArray *)columns widths: (NSArray *)widths
{
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (18, 58, 940, 395)] autorelease];
  NSTableView *table = [[[CLRecordTable alloc] initWithFrame: [scroll bounds]] autorelease];
  unsigned int i;
  [scroll setBorderType: NSLineBorder];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [table setRowHeight: 34];
  [table setIntercellSpacing: NSMakeSize (12, 4)];
  [table setUsesAlternatingRowBackgroundColors: YES];
  [table setGridStyleMask: NSTableViewGridNone];
  [table setBackgroundColor: [NSColor controlBackgroundColor]];
  [table setAllowsMultipleSelection: NO];
  for (i = 0; i < [columns count]; i++)
    {
      NSString *key = [columns objectAtIndex: i];
      NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: key] autorelease];
      NSString *title = [key isEqual: @"netDays"] ? @"Net days" : [key isEqual: @"dueDate"] ? @"Due date" : ([key isEqual: @"taskName"] ? @"Task" : ([key isEqual: @"date"] ? @"Date / period" : [key capitalizedString]));
      [[column headerCell] setStringValue: title];
      [column setWidth: [[widths objectAtIndex: i] doubleValue]];
      [column setEditable: NO];
      [[column dataCell] setFont: [NSFont systemFontOfSize: 13]];
      if ([[NSArray arrayWithObjects: @"rate", @"hours", @"amount", @"total", @"netDays", @"paymentDays", nil] containsObject: key])
        [[column dataCell] setAlignment: NSRightTextAlignment];
      [column setSortDescriptorPrototype: [[[NSSortDescriptor alloc] initWithKey: key ascending: YES] autorelease]];
      [table addTableColumn: column];
    }
  [table setDataSource: (id)self];
  [scroll setDocumentView: table];
  [view addSubview: scroll];
  return table;
}

/** Return the size of the collection represented by a table. */
- (NSInteger) numberOfRowsInTableView: (NSTableView *)table
{
  return [[(CLRecordTable *)table visibleRecords] count];
}

/** Format a ledger field for its read-only table cell. */
- (id) tableView: (NSTableView *)table objectValueForTableColumn: (NSTableColumn *)column row: (NSInteger)row
{
  NSArray *rows = [(CLRecordTable *)table visibleRecords];
  if (row < 0 || (NSUInteger)row >= [rows count]) return @"";
  return [self valueForRecord: [rows objectAtIndex: row] column: [column identifier] table: table];
}

- (id) valueForRecord: (NSDictionary *)record column: (NSString *)key table: (NSTableView *)table
{
  if (table == _reportTable || table == _dashboardTable)
    {
      id value = [record objectForKey: key];
      if ([[NSArray arrayWithObjects: @"received", @"expenses", @"net", @"billed", @"outstanding", @"value", nil] containsObject: key])
        return [CLLedger money: value ?: [NSNumber numberWithInt: 0]];
      if ([key hasSuffix: @"Hours"]) return [NSString stringWithFormat: @"%.2f", [value doubleValue]];
      return value ?: @"";
    }
  if (table == _financeTable)
    {
      if ([_financeMode indexOfSelectedItem] == 0)
        {
          if ([key isEqual: @"amount"]) return [NSString stringWithFormat: @"%@ %@", [record objectForKey: @"currency"], [CLLedger money: [_ledger balanceForAccount: [record objectForKey: @"id"]]]];
          if ([key isEqual: @"vendor"]) return [record objectForKey: @"bank"];
          if ([key isEqual: @"reference"]) return [record objectForKey: @"notes"];
          if ([key isEqual: @"account"]) { NSString *number = [record objectForKey: @"number"]; return [number length] ? [@"•••• " stringByAppendingString: [number substringFromIndex: [number length] > 4 ? [number length]-4 : 0]] : @""; }
        }
      if ([key isEqual: @"amount"]) return [NSString stringWithFormat: @"%@ %@", [record objectForKey: @"currency"], [CLLedger money: [record objectForKey: @"amount"]]];
      if ([key isEqual: @"account"]) { NSDictionary *account; for (account in [_ledger accounts]) if ([[account objectForKey: @"id"] isEqual: [record objectForKey: @"accountID"]]) return [account objectForKey: @"name"]; return @"Unassigned"; }
      return [record objectForKey: key] ?: @"";
    }
  if (table == _tasksTable)
    {
      if ([key isEqual: @"rate"])
        return [CLLedger money: [record objectForKey: @"rate"]];
      if ([key isEqual: @"status"])
        return [[record objectForKey: @"archived"] boolValue] ? @"Archived" : @"Active";
    }
  else if (table == _clientsTable)
    {
      if ([key isEqual: @"netDays"])
        return [NSNumber numberWithInteger: [CLLedger netDaysForClient: record]];
      if ([key isEqual: @"rate"])
        return [CLLedger money: [record objectForKey: key]];
    }
  else if (table == _timeTable)
    {
      if ([key isEqual: @"date"])
        return [CLLedger dateLabelForEntry: record];
      if ([key isEqual: @"taskName"])
        return [record objectForKey: @"taskName"] != nil ? [record objectForKey: @"taskName"] : @"Client default";
      if ([key isEqual: @"rate"])
        return [CLLedger money: [record objectForKey: @"rate"]];
      if ([key isEqual: @"client"])
        return [[_ledger clientWithID: [record objectForKey: @"clientID"]] objectForKey: @"name"];
      if ([key isEqual: @"hours"])
        return [NSString stringWithFormat: @"%.4f", [[record objectForKey: @"seconds"] doubleValue] / 3600.0];
      if ([key isEqual: @"amount"])
        return [CLLedger isBillableEntry: record] ? [CLLedger money: [CLLedger amountForSeconds: [record objectForKey: @"seconds"] rate: [record objectForKey: @"rate"]]] : @"0.00";
      if ([key isEqual: @"billing"] && ![CLLedger isBillableEntry: record])
        return @"Nonbillable";
      if ([key isEqual: @"billing"])
        return [[record objectForKey: @"invoiceID"] length] > 0 ? [record objectForKey: @"invoiceID"]
          : ([record objectForKey: @"externalBilling"] != nil ? [record objectForKey: @"externalBilling"] : @"Unbilled");
    }
  else
    {
      if ([key isEqual: @"id"])
        return [CLLedger invoiceNumber: record];
      if ([key isEqual: @"paymentDays"])
        return [CLLedger paymentDaysForInvoice: record onDate: [CLLedger today]];
      if ([key isEqual: @"reminder"])
        return [CLLedger reminderStatusForInvoice: record];
      if ([key isEqual: @"dueDate"] && [[record objectForKey: @"dueDateUnverified"] boolValue])
        return @"Not provided";
      if ([key isEqual: @"client"])
        return [[record objectForKey: @"client"] objectForKey: @"name"];
      if ([key isEqual: @"total"])
        return [NSString stringWithFormat: @"%@ %@", [[record objectForKey: @"business"] objectForKey: @"currency"], [CLLedger money: [record objectForKey: @"total"]]];
      if ([key isEqual: @"status"])
        {
          if ([[record objectForKey: @"paymentUnverified"] boolValue])
            return @"Review payment";
          if ([[CLLedger receivedForInvoice: record] longLongValue] > [[record objectForKey: @"total"] longLongValue]) return @"Overpaid";
          if ([[record objectForKey: @"paid"] boolValue]) return @"Paid";
          if ([[CLLedger receivedForInvoice: record] longLongValue] > 0) return [NSString stringWithFormat: @"Partial (%@ due)", [CLLedger money: [CLLedger balanceForInvoice: record]]];
          return ![[record objectForKey: @"dueDateUnverified"] boolValue]
            && [(NSString *)[record objectForKey: @"dueDate"] compare: [CLLedger today]] == NSOrderedAscending ? @"Overdue" : @"Unpaid";
        }
    }
  return [record objectForKey: key];
}

- (NSDictionary *) selectedRecord: (NSTableView *)table
{
  NSInteger row = [table selectedRow];
  NSArray *records = [table isKindOfClass: [CLRecordTable class]] ? [(CLRecordTable *)table visibleRecords] : [self rawRowsForTable: table];
  if (row < 0 || (NSUInteger)row >= [records count])
    return nil;
  return [records objectAtIndex: row];
}

- (NSString *) selectedClient: (NSPopUpButton *)popup
{
  return [[popup selectedItem] representedObject];
}

- (void) fillClients: (NSPopUpButton *)popup
{
  NSString *previous = [[self selectedClient: popup] retain];
  unsigned int i;
  [popup removeAllItems];
  for (i = 0; i < [[_ledger clients] count]; i++)
    {
      NSDictionary *client = [[_ledger clients] objectAtIndex: i];
      NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: [client objectForKey: @"name"] action: NULL keyEquivalent: @""] autorelease];
      [item setRepresentedObject: [client objectForKey: @"id"]];
      [[popup menu] addItem: item];
      if ([[client objectForKey: @"id"] isEqual: previous])
        [popup selectItem: item];
    }
  [previous release];
}

- (void) refresh
{
  unsigned int i;
  long long unbilled = 0;
  NSMutableDictionary *outstanding = [NSMutableDictionary dictionary];
  NSMutableDictionary *paid = [NSMutableDictionary dictionary];
  NSMutableArray *outstandingText = [NSMutableArray array];
  NSMutableArray *paidText = [NSMutableArray array];
  NSMutableSet *currencies = [NSMutableSet setWithObject: [[_ledger business] objectForKey: @"currency"]];
  NSArray *currencyNames;
  NSTextField *startField = [_businessFields objectForKey: @"startingInvoiceNumber"];
  [startField setEnabled: ![_ledger hasIssuedInvoices]];
  if ([_ledger hasIssuedInvoices])
    {
      NSString *start = [[_ledger business] objectForKey: @"startingInvoiceNumber"];
      [startField setStringValue: start != nil ? start : @"1"];
    }
  for (i = 0; i < [[_ledger entries] count]; i++)
    {
      NSDictionary *entry = [[_ledger entries] objectAtIndex: i];
      if ([CLLedger isUnbilledEntry: entry])
        unbilled += [[CLLedger amountForSeconds: [entry objectForKey: @"seconds"] rate: [entry objectForKey: @"rate"]] longLongValue];
    }
  for (i = 0; i < [[_ledger invoices] count]; i++)
    {
      NSDictionary *invoice = [[_ledger invoices] objectAtIndex: i];
      if ([[invoice objectForKey: @"paymentUnverified"] boolValue])
        continue;
      {
        NSString *currency = [[invoice objectForKey: @"business"] objectForKey: @"currency"];
        NSDecimalNumber *received = [NSDecimalNumber decimalNumberWithDecimal: [[CLLedger receivedForInvoice: invoice] decimalValue]];
        NSDecimalNumber *owed = [NSDecimalNumber decimalNumberWithDecimal: [[CLLedger balanceForInvoice: invoice] decimalValue]];
        [currencies addObject: currency];
        [paid setObject: [[paid objectForKey: currency] ?: [NSDecimalNumber zero] decimalNumberByAdding: received] forKey: currency];
        [outstanding setObject: [[outstanding objectForKey: currency] ?: [NSDecimalNumber zero] decimalNumberByAdding: owed] forKey: currency];
      }
    }
  currencyNames = [[currencies allObjects] sortedArrayUsingSelector: @selector(compare:)];
  for (i = 0; i < [currencyNames count]; i++)
    {
      NSString *currency = [currencyNames objectAtIndex: i];
      NSDecimalNumber *scale = [NSDecimalNumber decimalNumberWithString: @"100"];
      NSDecimalNumber *owed = [[outstanding objectForKey: currency] ?: [NSDecimalNumber zero] decimalNumberByDividingBy: scale];
      NSDecimalNumber *received = [[paid objectForKey: currency] ?: [NSDecimalNumber zero] decimalNumberByDividingBy: scale];
      [outstandingText addObject: [NSString stringWithFormat: @"%@ %@", currency, owed]];
      [paidText addObject: [NSString stringWithFormat: @"%@ %@", currency, received]];
    }
  [_summaryLabel setStringValue: [NSString stringWithFormat:
    @"%@   •   Unbilled: %@   •   Outstanding: %@   •   Paid: %@   •   %lu clients",
    [[_ledger business] objectForKey: @"currency"],
    [CLLedger money: [NSNumber numberWithLongLong: unbilled]],
     [outstandingText componentsJoinedByString: @" / "],
    [paidText componentsJoinedByString: @" / "], (unsigned long)[[_ledger clients] count]]];
  [_summaryLabel setToolTip: [_summaryLabel stringValue]];
  [self refreshInsights: nil];
  [self financeChanged: nil];
  [_clientsTable reloadData];
  [_timeTable reloadData];
  [_invoicesTable reloadData];
  [self fillClients: _timeClient];
  [self fillClients: _invoiceClient];
  [self fillClients: _tasksClient];
  [_tasksTable reloadData];
  [self timeClientChanged: nil];
  [self invoiceClientChanged: nil];
  [self periodChanged: nil];
  [self tick: nil];
}

- (NSDictionary *) editForm: (NSString *)title labels: (NSArray *)labels values: (NSArray *)values
{
  NSMutableDictionary *fields = [NSMutableDictionary dictionary];
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  unsigned int i;
  CGFloat height = 90;
  CGFloat cursor;
  BOOL reminderForm = [labels containsObject: @"Payment reminder"];
  for (i = 0; i < [labels count]; i++)
    height += ([[labels objectAtIndex: i] isEqual: @"Payment reminder"] || [[labels objectAtIndex: i] isEqual: @"Overdue reminder"]) ? 150 : 64;
  _dialog = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 610, height)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_dialog setTitle: title];
  [_dialog setReleasedWhenClosed: NO];
  cursor = height - 70;
  for (i = 0; i < [labels count]; i++)
    {
      NSString *label = [labels objectAtIndex: i];
      BOOL message = [label isEqual: @"Payment reminder"] || [label isEqual: @"Overdue reminder"];
      CGFloat rowHeight = message ? 150 : 64;
      CGFloat y = cursor - (rowHeight - 64);
      cursor -= rowHeight;
      NSTextField *field;
      CLLabel ([_dialog contentView], [labels objectAtIndex: i], NSMakeRect (18, y + 10, 157, 24), 13);
      if ([label isEqual: @"Period"])
        {
          NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (180, y, 408, 40) pullsDown: NO] autorelease];
          NSString *kind;
          for (kind in [NSArray arrayWithObjects: @"day", @"week", @"month", nil])
            {
              [popup addItemWithTitle: [kind capitalizedString]];
              [[popup lastItem] setRepresentedObject: kind];
              if ([kind isEqual: [values objectAtIndex: i]]) [popup selectItem: [popup lastItem]];
            }
          [[_dialog contentView] addSubview: popup];
          [fields setObject: popup forKey: label];
          continue;
        }
      if ([label isEqual: @"Bank account"] || [label isEqual: @"Invoice"])
        {
          BOOL choosingInvoice = [label isEqual: @"Invoice"];
          NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (180, y, 408, 40) pullsDown: NO] autorelease];
          NSDictionary *record;
          [popup addItemWithTitle: choosingInvoice ? @"Select an invoice" : @"Unassigned"]; [[popup lastItem] setRepresentedObject: @""];
          for (record in choosingInvoice ? [_ledger invoices] : [_ledger accounts])
            { [popup addItemWithTitle: choosingInvoice ? [NSString stringWithFormat: @"%@ — %@", [CLLedger invoiceNumber: record], [[record objectForKey: @"client"] objectForKey: @"name"]] : [NSString stringWithFormat: @"%@ (%@)", [record objectForKey: @"name"], [record objectForKey: @"currency"]]];
              [[popup lastItem] setRepresentedObject: [record objectForKey: @"id"]];
              if ([[record objectForKey: @"id"] isEqual: [values objectAtIndex: i]]) [popup selectItem: [popup lastItem]]; }
          [[_dialog contentView] addSubview: popup]; [fields setObject: popup forKey: label]; continue;
        }
      if ([label isEqual: @"Automatic email"] || [label isEqual: @"Billable (Yes / No)"])
        {
          NSButton *toggle = [[[NSButton alloc] initWithFrame: NSMakeRect (180, y, 408, 45)] autorelease];
          [toggle setButtonType: NSSwitchButton];
          [toggle setTitle: [label isEqual: @"Automatic email"] ? @"Send reminders through Apple Mail" : @"Include these hours on invoices"];
          [toggle setState: [[[values objectAtIndex: i] lowercaseString] isEqual: @"yes"] ? NSOnState : NSOffState];
          [[_dialog contentView] addSubview: toggle];
          [fields setObject: toggle forKey: label];
          continue;
        }
      if (message)
        {
          NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (180, y, 408, rowHeight - 19)] autorelease];
          NSTextView *text = [[[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 390, rowHeight - 19)] autorelease];
          [text setRichText: NO];
          [text setFont: [NSFont systemFontOfSize: 13]];
          [text setString: [values objectAtIndex: i]];
          [text setVerticallyResizable: YES];
          [text setHorizontallyResizable: NO];
          [[text textContainer] setWidthTracksTextView: YES];
          [scroll setBorderType: NSLineBorder];
          [scroll setHasVerticalScroller: YES];
          [scroll setDocumentView: text];
          [[_dialog contentView] addSubview: scroll];
          [fields setObject: text forKey: label];
          continue;
        }
      if ([label isEqual: @"Issued"] || [label isEqual: @"Due date"] || [label isEqual: @"Date"])
        field = [CLDateField fieldInView: [_dialog contentView] value: [values objectAtIndex: i] frame: NSMakeRect (180, y, 408, 45)];
      else
        field = CLField ([_dialog contentView], [values objectAtIndex: i], NSMakeRect (180, y, 408, 45));
      if ([label isEqual: @"Issued"] && _dialogInvoiceClientID != nil)
        { _dialogIssuedField = field; [field setDelegate: (id)self]; }
      if ([label isEqual: @"Due date"] && _dialogInvoiceClientID != nil)
        _dialogDueField = field;
            [[field cell] setWraps: YES];
      [fields setObject: field forKey: [labels objectAtIndex: i]];
      if (i == 0)
        [_dialog setInitialFirstResponder: field];
    }
  if (reminderForm)
    CLLabel ([_dialog contentView], @"Blank messages use defaults. Fields: {client}, {invoice}, {total}, {dueDate}", NSMakeRect (18, 56, 570, 22), 11);
  [CLButton ([_dialog contentView], @"Cancel", NSMakeRect (366, 16, 106, 32), self, @selector(cancelDialog:)) setKeyEquivalent: @"\033"];
  [CLButton ([_dialog contentView], @"Save", NSMakeRect (480, 16, 106, 32), self, @selector(acceptDialog:)) setKeyEquivalent: @"\r"];
  _dialogAccepted = NO;
  [_dialog center];
  [NSApp runModalForWindow: _dialog];
  for (i = 0; i < [labels count]; i++)
    {
      id field = [fields objectForKey: [labels objectAtIndex: i]];
      NSString *value = [field isKindOfClass: [NSPopUpButton class]] ? [[field selectedItem] representedObject] : [field isKindOfClass: [NSButton class]] ? ([field state] == NSOnState ? @"yes" : @"no")
        : ([field isKindOfClass: [NSTextView class]] ? [field string] : [field stringValue]);
      [result setObject: value forKey: [labels objectAtIndex: i]];
    }
  [_dialog orderOut: nil];
  [_dialog release];
  _dialog = nil;
  _dialogIssuedField = nil;
  _dialogDueField = nil;
  return _dialogAccepted ? result : nil;
}

- (void) acceptDialog: (id)sender
{
  [_dialog makeFirstResponder: nil];
  _dialogAccepted = YES;
  [NSApp stopModal];
}

- (void) cancelDialog: (id)sender
{
  _dialogAccepted = NO;
  [NSApp stopModal];
}

- (void) editClientRecord: (NSDictionary *)client
{
  NSArray *values = client != nil ? [NSArray arrayWithObjects: [client objectForKey: @"name"],
    [client objectForKey: @"email"], [client objectForKey: @"address"], [CLLedger money: [client objectForKey: @"rate"]],
    [NSString stringWithFormat: @"%ld", (long)[CLLedger netDaysForClient: client]],
    [client objectForKey: @"startingInvoiceNumber"] ?: @"", nil]
    : [NSArray arrayWithObjects: @"", @"", @"", @"100.00", @"30", @"", nil];
  NSArray *labels = [NSArray arrayWithObjects: @"Name", @"Email", @"Address", @"Hourly rate", @"Net payment days", @"Starting invoice #", nil];
  NSDictionary *form;
  while ((form = [self editForm: client != nil ? @"Edit Client" : @"Add Client" labels: labels values: values]) != nil)
    {
      NSString *error = nil;
      if ([_ledger saveClient: [client objectForKey: @"id"] name: [form objectForKey: @"Name"]
        email: [form objectForKey: @"Email"] address: [form objectForKey: @"Address"]
        rate: [form objectForKey: @"Hourly rate"] netDays: [form objectForKey: @"Net payment days"]
        startingInvoiceNumber: [form objectForKey: @"Starting invoice #"] error: &error])
        {
          [self refresh];
          break;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Name"], [form objectForKey: @"Email"],
        [form objectForKey: @"Address"], [form objectForKey: @"Hourly rate"], [form objectForKey: @"Net payment days"], [form objectForKey: @"Starting invoice #"], nil];
    }
}

- (void) addClient: (id)sender
{
  [self editClientRecord: nil];
}

- (void) editClient: (id)sender
{
  NSDictionary *client = [self selectedRecord: _clientsTable];
  if (client != nil)
    [self editClientRecord: [[client copy] autorelease]];
  else
    [self showError: @"Select a client to edit."];
}

- (void) deleteClient: (id)sender
{
  NSString *error = nil;
  NSDictionary *client = [self selectedRecord: _clientsTable];
  if (client == nil)
    {
      [self showError: @"Select a client first."];
      return;
    }
  if (NSRunAlertPanel (@"Delete client?", @"Delete %@?", @"Cancel", @"Delete", nil, [client objectForKey: @"name"]) != NSAlertAlternateReturn)
    return;
  [_ledger deleteClient: [client objectForKey: @"id"] error: &error];
  [self showError: error];
  [self refresh];
}

- (void) addTime: (id)sender
{
  NSString *error = nil;
  NSString *kind = [[_periodChoice titleOfSelectedItem] lowercaseString];
  NSDictionary *period = [CLLedger periodContainingDate: [_periodDate stringValue] kind: kind error: &error];
  NSArray *labels = [NSArray arrayWithObjects: @"Description", @"Total hours", nil];
  NSArray *values = [NSArray arrayWithObjects: [_taskField stringValue], @"1.00", nil];
  NSDictionary *form;
  NSString *clientID = [self selectedClient: _timeClient];
  NSString *title;
  if (clientID == nil)
    {
      [self showError: @"Add a client first, then select it in the Time tab."];
      return;
    }
  if (period == nil)
    {
      [self showError: error];
      return;
    }
  [self periodChanged: nil];
  if ([_entryMode indexOfSelectedItem] == 1)
    {
      [self enterTimesheet: period];
      return;
    }
  title = [NSString stringWithFormat: @"%@ total: %@ to %@", [kind capitalizedString],
    [period objectForKey: @"start"], [period objectForKey: @"end"]];
  while ((form = [self editForm: title labels: labels values: values]) != nil)
    {
      NSDictionary *row = [NSDictionary dictionaryWithObjectsAndKeys:
        [period objectForKey: @"start"], @"date", [period objectForKey: @"end"], @"periodEnd", kind, @"periodKind",
        [form objectForKey: @"Description"], @"description", [form objectForKey: @"Total hours"], @"hours", nil];
      if ([_ledger addTimeRows: [NSArray arrayWithObject: row] client: clientID
        task: [[_timeTask selectedItem] representedObject] billable: [_nonbillableTime state] != NSOnState error: &error])
        {
          [self refresh];
          break;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Description"], [form objectForKey: @"Total hours"], nil];
    }
}

- (void) editTime: (id)sender
{
  NSDictionary *entry = [self selectedRecord: _timeTable];
  NSArray *labels = [NSArray arrayWithObjects: @"Date", @"Period", @"Description", @"Hours", @"Hourly rate", @"Billable (Yes / No)", nil];
  NSArray *keys = [NSArray arrayWithObjects: @"date", @"period", @"description", @"hours", @"rate", @"billable", nil];
  NSArray *values;
  NSDictionary *form;
  NSString *identifier;
  if (entry == nil) { [self showError: @"Select a time entry first."]; return; }
  if ([[entry objectForKey: @"invoiceID"] length] > 0
      || [[entry objectForKey: @"externalBilling"] isEqual: @"Billed in QuickBooks"])
    { [self showError: @"Invoiced time is locked and cannot be edited."]; return; }
  identifier = [[[entry objectForKey: @"id"] copy] autorelease];
  values = [NSArray arrayWithObjects: [entry objectForKey: @"date"], [entry objectForKey: @"periodKind"] ?: @"day",
    [entry objectForKey: @"description"], [NSString stringWithFormat: @"%.4f", [[entry objectForKey: @"seconds"] doubleValue] / 3600.0],
    [CLLedger money: [entry objectForKey: @"rate"]], [CLLedger isBillableEntry: entry] ? @"Yes" : @"No", nil];
  while ((form = [self editForm: @"Edit Time Entry" labels: labels values: values]) != nil)
    {
      NSMutableDictionary *changes = [NSMutableDictionary dictionary];
      NSMutableArray *retry = [NSMutableArray array];
      NSString *error = nil;
      NSUInteger i;
      for (i = 0; i < [keys count]; i++)
        {
          NSString *value = [form objectForKey: [labels objectAtIndex: i]];
          [changes setObject: value forKey: [keys objectAtIndex: i]];
          [retry addObject: value];
        }
      if ([_ledger updateTimeEntry: identifier values: changes error: &error])
        { [self refresh]; break; }
      [self showError: error];
      values = retry;
    }
}

- (void) deleteTime: (id)sender
{
  NSString *error = nil;
  NSDictionary *entry = [self selectedRecord: _timeTable];
  if (entry == nil)
    {
      [self showError: @"Select a time entry first."];
      return;
    }
  if (NSRunAlertPanel (@"Delete time entry?", @"This removes the selected unbilled time entry permanently.", @"Cancel", @"Delete", nil) != NSAlertAlternateReturn)
    return;
  [_ledger deleteEntry: [entry objectForKey: @"id"] error: &error];
  [self showError: error];
  [self refresh];
}

- (void) startTimer: (id)sender
{
  NSString *error = nil;
  [_ledger startTimerForClient: [self selectedClient: _timeClient] task: [[_timeTask selectedItem] representedObject] description: [_taskField stringValue] error: &error];
  [self showError: error];
  [self refresh];
}

- (void) stopTimer: (id)sender
{
  NSString *error = nil;
  [_ledger stopTimer: &error];
  [self showError: error];
  [self refresh];
}

- (void) tick: (id)sender
{
#ifdef __APPLE__
  [self updateStatusItem: nil];
#endif
  if (_mailer != nil && !_mailStarting && ![_mailer isRunning])
    {
      NSString *error = nil;
      BOOL ok = [_mailer succeeded];
      NSString *detail = ok ? @"Submitted to Apple Mail. Check Mail for delivery or bounce notices." : [_mailer failure];
      if (_mailInvoiceID != nil)
        {
          if (![_ledger finishReminder: _mailInvoiceID stage: _mailStage submitted: ok detail: detail error: &error])
            { detail = error; ok = NO; }
          [_invoicesTable reloadData];
        }
      [_mailStatus setStringValue: ok ? (_mailInvoiceID != nil ? @"Reminder submitted to Apple Mail with PDF attached." : @"Draft opened in Apple Mail with PDF attached. Review it and send when ready.") : @"Email needs review. Check Mail and use Review Email before retrying."];
      [_mailStatus setToolTip: detail];
      if (!ok && _mailInvoiceID == nil) [self showError: detail];
      [_mailer release]; _mailer = nil;
      [_mailInvoiceID release]; _mailInvoiceID = nil;
      [_mailStage release]; _mailStage = nil;
    }
  NSDictionary *timer = [_ledger timer];
  if (timer == nil)
    [_timerLabel setStringValue: @"No timer running. Choose a client and describe your work, or add manual time below."];
  else
    {
      long long seconds = MAX (0, (long long)[_ledger timerElapsed]);
      [_timerLabel setStringValue: [NSString stringWithFormat: @"●  %02lld:%02lld:%02lld   %@ — %@  (continues while app is closed)",
        seconds / 3600, (seconds / 60) % 60, seconds % 60,
        [[_ledger clientWithID: [timer objectForKey: @"clientID"]] objectForKey: @"name"], [CLLedger workLabelForEntry: timer]]];
    }
}

- (void) editInvoice: (id)sender
{
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  CLInvoiceEditor *editor;
  if (invoice == nil) { [self showError: @"Select an invoice to edit."]; return; }
  if (_mailer != nil) { [self showError: @"Wait for the current email operation to finish before editing invoices."]; return; }
  editor = [[CLInvoiceEditor alloc] initWithLedger: _ledger invoice: invoice];
  if ([editor run]) [self refresh];
  [editor release];
}

- (void) createInvoice: (id)sender
{
  NSString *error = nil;
  if ([[_invoiceTask selectedItem] representedObject] == nil)
    { [self showError: @"Add an active task in Client Tasks and select it before creating an invoice."]; return; }
  if (NSRunAlertPanel (@"Issue invoice?", @"Create an invoice for the entered hours at the selected task’s current hourly rate? Check your business details, tax, issued date and due date first.", @"Cancel", @"Create Invoice", nil) != NSAlertAlternateReturn)
    return;
  if ([_ledger invoiceClient: [self selectedClient: _invoiceClient] task: [[_invoiceTask selectedItem] representedObject] hours: [_invoiceHours stringValue] tax: [_taxField stringValue] issuedDate: [_issuedField stringValue] dueDate: [_dueField stringValue] error: &error])
    {
      [self refresh];
      [_invoiceHours setStringValue: @""];
      [_invoicesTable selectRowIndexes: [NSIndexSet indexSetWithIndex: [[_ledger invoices] count] - 1] byExtendingSelection: NO];
      [self previewInvoice: nil];
    }
  else
    [self showError: error];
}

- (void) invoiceClientChanged: (id)sender
{
  NSDictionary *client = [_ledger clientWithID: [self selectedClient: _invoiceClient]];
  NSArray *tasks = [_ledger tasksForClient: [client objectForKey: @"id"] includeArchived: NO];
  NSString *previous = [[[_invoiceTask selectedItem] representedObject] copy];
  unsigned int i;
  [_dueField setStringValue: [_ledger dueDateForClient: [client objectForKey: @"id"] invoiceDate: [_issuedField stringValue]] ?: @""];
  [_invoiceTask removeAllItems];
  for (i = 0; i < [tasks count]; i++)
    {
      NSDictionary *task = [tasks objectAtIndex: i];
      NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: [task objectForKey: @"name"] action: NULL keyEquivalent: @""] autorelease];
      [item setRepresentedObject: [task objectForKey: @"id"]];
      [[_invoiceTask menu] addItem: item];
      if ([[task objectForKey: @"id"] isEqual: previous]) [_invoiceTask selectItem: item];
    }
  if ([tasks count] == 0) [_invoiceTask addItemWithTitle: @"Add a task in Client Tasks"];
  [_invoiceTask setEnabled: [tasks count] > 0];
  [previous release];
  [self invoiceTaskChanged: nil];
}

- (void) controlTextDidChange: (NSNotification *)notification
{
  [self browseChanged: [notification object]];
  if ([notification object] == _periodDate)
    [self periodChanged: nil];
  else if ([notification object] == _issuedField)
    [_dueField setStringValue: [_ledger dueDateForClient: [self selectedClient: _invoiceClient]
      invoiceDate: [_issuedField stringValue]] ?: @""];
  else if ([notification object] == _dialogIssuedField && _dialogInvoiceClientID != nil)
    [_dialogDueField setStringValue: [_ledger dueDateForClient: _dialogInvoiceClientID
      invoiceDate: [_dialogIssuedField stringValue]] ?: @""];
}

- (void) invoiceTaskChanged: (id)sender
{
  NSArray *tasks = [_ledger tasksForClient: [self selectedClient: _invoiceClient] includeArchived: NO];
  unsigned int i;
  [_invoiceRate setStringValue: @"Choose an active task to set the invoice rate."];
  for (i = 0; i < [tasks count]; i++)
    {
      NSDictionary *task = [tasks objectAtIndex: i];
      if ([[task objectForKey: @"id"] isEqual: [[_invoiceTask selectedItem] representedObject]])
        [_invoiceRate setStringValue: [NSString stringWithFormat: @"%@ %@ / hour — %@", [[_ledger business] objectForKey: @"currency"],
          [CLLedger money: [task objectForKey: @"rate"]], [task objectForKey: @"name"]]];
    }
}

- (void) invoiceTimesheet: (id)sender
{
  NSArray *labels = [NSArray arrayWithObjects: @"Tax %", @"Issued", @"Due date", nil];
  NSArray *values;
  NSDictionary *form;
  NSString *error = nil;
  NSString *issuedDate = [_issuedField stringValue];
  if ([self selectedClient: _timeClient] == nil)
    { [self showError: @"Select a timesheet client first."]; return; }
  [_dialogInvoiceClientID release];
  _dialogInvoiceClientID = [[self selectedClient: _timeClient] copy];
  values = [NSArray arrayWithObjects: [_taxField stringValue], issuedDate,
    [_ledger dueDateForClient: _dialogInvoiceClientID invoiceDate: issuedDate] ?: @"", nil];
  while ((form = [self editForm: @"Invoice all unbilled hours at their recorded rates" labels: labels values: values]) != nil)
    {
      if ([_ledger invoiceClient: _dialogInvoiceClientID task: nil hours: nil tax: [form objectForKey: @"Tax %"]
        issuedDate: [form objectForKey: @"Issued"] dueDate: [form objectForKey: @"Due date"] error: &error])
        {
          [self refresh];
          [_invoicesTable selectRowIndexes: [NSIndexSet indexSetWithIndex: [[_ledger invoices] count] - 1] byExtendingSelection: NO];
          [self previewInvoice: nil];
          break;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Tax %"], [form objectForKey: @"Issued"], [form objectForKey: @"Due date"], nil];
    }
  [_dialogInvoiceClientID release];
  _dialogInvoiceClientID = nil;
}

- (void) emailInvoice: (id)sender
{
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  NSDictionary *client;
  NSString *error = nil;
  if (invoice == nil) { [self showError: @"Select an invoice first."]; return; }
  if (_mailer != nil) { [self showError: @"Wait for the current Mail operation to finish."]; return; }
  client = [_ledger billingClientForInvoice: invoice];
  _mailer = [[CLInvoiceMailer alloc] init];
  _mailStarting = YES;
  if (![_mailer startInvoice: invoice recipient: [client objectForKey: @"email"]
      sender: [_ledger senderForInvoice: invoice]
      message: [_ledger paymentMessageForInvoice: invoice onDate: [CLLedger today]] send: NO error: &error])
    { _mailStarting = NO; [_mailer release]; _mailer = nil; [self showError: error]; return; }
  _mailStarting = NO;
  [_mailStatus setStringValue: @"Preparing an Apple Mail draft with the invoice PDF attached…"];
}

- (void) previewInvoice: (id)sender
{
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  NSWindow *preview;
  NSScrollView *scroll;
  CLInvoiceView *document;
  if (invoice == nil)
    {
      [self showError: @"Select an invoice first."];
      return;
    }
  preview = [[NSWindow alloc] initWithContentRect: NSMakeRect (150, 150, 580, 760)
    styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  [preview setTitle: [NSString stringWithFormat: @"Invoice Preview — %@", [CLLedger invoiceNumber: invoice]]];
  [preview setMinSize: NSMakeSize (560, 400)];
  [preview setReleasedWhenClosed: YES];
  document = [[[CLInvoiceView alloc] initWithInvoice: invoice] autorelease];
  scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (10, 54, 560, 696)] autorelease];
  [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setDocumentView: document];
  [[preview contentView] addSubview: scroll];
  CLButton ([preview contentView], @"Print…", NSMakeRect (438, 12, 130, 32), document, @selector(printInvoice:));
  [preview center];
  [preview makeKeyAndOrderFront: nil];
}

- (void) printInvoice: (id)sender
{
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  CLInvoiceView *view;
  if (invoice == nil)
    {
      [self showError: @"Select an invoice in the Invoices tab first."];
      return;
    }
  view = [[[CLInvoiceView alloc] initWithInvoice: invoice] autorelease];
  [view printInvoice: sender];
}

- (void) deleteInvoice: (id)sender
{
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  NSString *error = nil;
  NSString *warning;
  if (invoice == nil)
    { [self showError: @"Select an invoice first."]; return; }
  warning = [NSString stringWithFormat:
    @"Permanently delete invoice %@ for %@?\n\nThis cannot be undone. The invoice and its payment status will be removed from this ledger and its totals. Any time entries billed by this invoice will become unbilled and available to invoice again. Its number will not be reused.\n\nCopies already printed or emailed, and records in QuickBooks, will not be changed. Deleting a paid invoice does not refund a payment.",
    [CLLedger invoiceNumber: invoice], [[invoice objectForKey: @"client"] objectForKey: @"name"]];
  if (NSRunAlertPanel (@"Delete invoice permanently?", @"%@", @"Cancel", @"Delete Invoice", nil, warning) != NSAlertAlternateReturn)
    return;
  if ([_ledger deleteInvoice: [invoice objectForKey: @"id"] error: &error])
    [_invoicesTable deselectAll: nil];
  [self showError: error];
  [self refresh];
}

- (void) togglePaid: (id)sender
{
  [self editPaymentForInvoice: [self selectedRecord: _invoicesTable] payment: nil];
}

- (void) chooseBusinessLogo: (id)sender
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  NSData *data;
  NSImage *image;
  [panel setAllowsMultipleSelection: NO];
  [panel setCanChooseDirectories: NO];
  [panel setAllowedFileTypes: [NSArray arrayWithObjects: @"png", @"jpg", @"jpeg", @"tiff", @"tif", @"icns", nil]];
  if ([panel runModal] != NSOKButton) return;
  data = [NSData dataWithContentsOfURL: [panel URL]];
  image = [[[NSImage alloc] initWithData: data] autorelease];
  if (data == nil || [data length] > 5 * 1024 * 1024 || ![image isValid]
      || [image size].width <= 0 || [image size].height <= 0)
    { [self showError: @"Choose a valid PNG, JPEG, TIFF or icon image no larger than 5 MB."]; return; }
  [_businessLogoData release];
  _businessLogoData = [data copy];
  [_businessLogoPreview setImage: image];
}

- (void) removeBusinessLogo: (id)sender
{
  [_businessLogoData release];
  _businessLogoData = nil;
  [_businessLogoPreview setImage: nil];
}

- (void) saveBusiness: (id)sender
{
  NSMutableDictionary *business = [NSMutableDictionary dictionary];
  NSArray *keys = [_businessFields allKeys];
  unsigned int i;
  NSString *error = nil;
  for (i = 0; i < [keys count]; i++)
    [business setObject: [[_businessFields objectForKey: [keys objectAtIndex: i]] stringValue] forKey: [keys objectAtIndex: i]];
  if (_businessLogoData != nil)
    [business setObject: _businessLogoData forKey: @"logoData"];
  if ([_ledger saveBusiness: business error: &error])
    NSRunAlertPanel (@"Business details saved", @"New invoices will use these details.", @"OK", nil, nil);
  [self showError: error];
  [self refresh];
}

- (void) backupLedger: (id)sender
{
  NSSavePanel *panel = [NSSavePanel savePanel];
  NSError *error = nil;
  NSData *bytes = [NSData dataWithContentsOfFile: CLLedgerPath ()];
  if (bytes == nil)
    {
      [self showError: @"Save business details or add a client before making your first backup."];
      return;
    }
  [panel setTitle: @"Back Up Ledger"];
  [panel setNameFieldStringValue: [NSString stringWithFormat: @"ClockAndLedger-%@.plist", [CLLedger today]]];
  if ([panel runModal] == NSOKButton)
    if (![bytes writeToURL: [panel URL] options: NSDataWritingAtomic error: &error])
      [self showError: [error localizedDescription]];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)application
{
  return NO;
}

- (BOOL) applicationShouldHandleReopen: (NSApplication *)application hasVisibleWindows: (BOOL)visible
{
  if (!visible) [_window makeKeyAndOrderFront: nil];
  return YES;
}

- (void) applicationWillTerminate: (NSNotification *)notification
{
#ifdef __APPLE__
  [_statusPulse invalidate];
#endif
  [_reminderPulse invalidate];
  [_mailer cancel];
  [_pulse invalidate];
  if (_ownsLock)
    {
      [_lock unlock];
      _ownsLock = NO;
    }
}

- (void) importQuickBooks: (id)sender
{
  NSOpenPanel *picker = [NSOpenPanel openPanel];
  NSData *data;
  NSString *filename;
  NSString *error = nil;
  NSString *report = nil;
  NSScrollView *scroll;
  NSTextView *text;
  [picker setTitle: @"Import QuickBooks Export"];
  [picker setMessage: @"Choose an IIF or CSV export. QBW/QBB files require exporting from QuickBooks first."];
  [picker setAllowsMultipleSelection: NO];
  [picker setCanChooseDirectories: NO];
  if ([picker runModal] != NSOKButton)
    return;
  filename = [[picker URL] path];
  data = [NSData dataWithContentsOfFile: filename];
  if (![_ledger importQuickBooksData: data filename: filename commit: NO report: &report error: &error])
    {
      [self showError: error];
      return;
    }
  _dialog = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 780, 600)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_dialog setTitle: @"Review QuickBooks Import"];
  [_dialog setReleasedWhenClosed: NO];
  scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (18, 65, 744, 515)] autorelease];
  [scroll setHasVerticalScroller: YES];
  [scroll setBorderType: NSLineBorder];
  text = [[[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 720, 515)] autorelease];
  [text setEditable: NO];
  [text setFont: [NSFont systemFontOfSize: 13]];
  [text setString: report];
  [text setVerticallyResizable: YES];
  [text setMaxSize: NSMakeSize (720, 1000000)];
  [[text textContainer] setContainerSize: NSMakeSize (700, 1000000)];
  [[text textContainer] setWidthTracksTextView: YES];
  [scroll setDocumentView: text];
  [[_dialog contentView] addSubview: scroll];
  [CLButton ([_dialog contentView], @"Cancel", NSMakeRect (478, 18, 120, 32), self, @selector(cancelDialog:)) setKeyEquivalent: @"\033"];
  CLButton ([_dialog contentView], @"Import Records", NSMakeRect (608, 18, 154, 32), self, @selector(acceptDialog:));
  _dialogAccepted = NO;
  [_dialog center];
  [NSApp runModalForWindow: _dialog];
  [_dialog orderOut: nil];
  [_dialog release];
  _dialog = nil;
  if (!_dialogAccepted)
    return;
  if (![_ledger importQuickBooksData: data filename: filename commit: YES report: &report error: &error])
    [self showError: error];
  else
    NSRunAlertPanel (@"QuickBooks import complete", @"%@", @"OK", nil, nil,
      [[report componentsSeparatedByString: @"\n\n"] objectAtIndex: 1]);
  [self refresh];
}

- (void) reviewImportedTime: (id)sender
{
  NSDictionary *entry = [self selectedRecord: _timeTable];
  NSArray *labels = [NSArray arrayWithObjects: @"Hourly rate", @"Billable (Yes / No)", nil];
  NSArray *values;
  NSDictionary *form;
  if (entry == nil || [entry objectForKey: @"externalBilling"] == nil)
    {
      [self showError: @"Select an imported time entry first."];
      return;
    }
  values = [NSArray arrayWithObjects: [CLLedger money: [entry objectForKey: @"rate"]],
    [CLLedger isUnbilledEntry: entry] ? @"Yes" : @"No", nil];
  form = [self editForm: @"Review Imported Time" labels: labels values: values];
  if (form != nil)
    {
      NSString *error = nil;
      NSString *billable = [[form objectForKey: @"Billable (Yes / No)"] lowercaseString];
      if (![billable isEqual: @"yes"] && ![billable isEqual: @"no"])
        error = @"Billable must be Yes or No.";
      else
        [_ledger reviewImportedTime: [entry objectForKey: @"id"] rate: [form objectForKey: @"Hourly rate"]
          billable: [billable isEqual: @"yes"] error: &error];
      [self showError: error];
      [self refresh];
    }
}

- (void) fillTimeTasks
{
  NSString *previous = [[[_timeTask selectedItem] representedObject] retain];
  NSString *clientID = [self selectedClient: _timeClient];
  NSDictionary *client = [_ledger clientWithID: clientID];
  NSArray *tasks = [_ledger tasksForClient: clientID includeArchived: NO];
  NSUInteger i;
  [_timeTask removeAllItems];
  [_timeTask addItemWithTitle: [NSString stringWithFormat: @"Client default — %@ %@/hr",
    [[_ledger business] objectForKey: @"currency"], [CLLedger money: [client objectForKey: @"rate"]]]];
  for (i = 0; i < [tasks count]; i++)
    {
      NSDictionary *task = [tasks objectAtIndex: i];
      NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:
        [NSString stringWithFormat: @"%@ — %@ %@/hr", [task objectForKey: @"name"],
          [[_ledger business] objectForKey: @"currency"], [CLLedger money: [task objectForKey: @"rate"]]]
        action: NULL keyEquivalent: @""] autorelease];
      [item setRepresentedObject: [task objectForKey: @"id"]];
      [[_timeTask menu] addItem: item];
      if ([[task objectForKey: @"id"] isEqual: previous])
        [_timeTask selectItem: item];
    }
  [previous release];
}

- (void) timeClientChanged: (id)sender
{
  unsigned int i;
  double total = 0, unbilled = 0, nonbillable = 0;
  [self fillTimeTasks];
  for (i = 0; i < [[_ledger entries] count]; i++)
    {
      NSDictionary *entry = [[_ledger entries] objectAtIndex: i];
      if ([[entry objectForKey: @"clientID"] isEqual: [self selectedClient: _timeClient]])
        {
          total += [[entry objectForKey: @"seconds"] doubleValue] / 3600.0;
          if (![CLLedger isBillableEntry: entry])
            nonbillable += [[entry objectForKey: @"seconds"] doubleValue] / 3600.0;
          if ([CLLedger isUnbilledEntry: entry])
            unbilled += [[entry objectForKey: @"seconds"] doubleValue] / 3600.0;
        }
    }
  [_timesheetTotal setStringValue: [NSString stringWithFormat:
    @"Selected client: %.4f total hours • %.4f nonbillable • %.4f ready to invoice (timer excluded)", total, nonbillable, unbilled]];
}

- (void) tasksClientChanged: (id)sender
{
  [_tasksTable deselectAll: nil];
  [_tasksTable reloadData];
}

- (void) periodChanged: (id)sender
{
  NSString *error = nil;
  NSDictionary *period = [CLLedger periodContainingDate: [_periodDate stringValue]
    kind: [[_periodChoice titleOfSelectedItem] lowercaseString] error: &error];
  [_periodLabel setStringValue: period == nil ? error : [NSString stringWithFormat:
    @"%@ to %@ · %lu day(s) · Weeks run Monday–Sunday. Use Add Time below.",
    [period objectForKey: @"start"], [period objectForKey: @"end"],
    (unsigned long)[[period objectForKey: @"dates"] count]]];
}

- (void) editTaskRecord: (NSDictionary *)task
{
  NSString *clientID = [self selectedClient: _tasksClient];
  NSArray *labels = [NSArray arrayWithObjects: @"Task name", @"Hourly rate", nil];
  NSArray *values;
  NSDictionary *form;
  if (clientID == nil)
    {
      [self showError: @"Add a client, then select it in Client Tasks."];
      return;
    }
  values = [NSArray arrayWithObjects: task != nil ? [task objectForKey: @"name"] : @"",
    [CLLedger money: [(task != nil ? task : [_ledger clientWithID: clientID]) objectForKey: @"rate"]], nil];
  while ((form = [self editForm: task != nil ? @"Edit Client Task" : @"Add Client Task" labels: labels values: values]) != nil)
    {
      NSString *error = nil;
      if ([_ledger saveTask: [task objectForKey: @"id"] client: clientID
        name: [form objectForKey: @"Task name"] rate: [form objectForKey: @"Hourly rate"] error: &error])
        {
          [self refresh];
          break;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Task name"], [form objectForKey: @"Hourly rate"], nil];
    }
}

- (void) addTask: (id)sender
{
  [self editTaskRecord: nil];
}

- (void) editTask: (id)sender
{
  NSDictionary *task = [self selectedRecord: _tasksTable];
  if (task == nil)
    [self showError: @"Select a task to edit."];
  else
    [self editTaskRecord: [[task copy] autorelease]];
}

- (void) archiveTask: (id)sender
{
  NSString *error = nil;
  [_ledger toggleTaskArchived: [[self selectedRecord: _tasksTable] objectForKey: @"id"] error: &error];
  [self showError: error];
  [self refresh];
}

- (void) enterTimesheet: (NSDictionary *)period
{
  NSArray *dates = [period objectForKey: @"dates"];
  NSMutableArray *fields = [NSMutableArray array];
  NSScrollView *scroll;
  NSView *document;
  NSTextField *description;
  CGFloat contentHeight = MAX (360, [dates count] * 36 + 12);
  NSUInteger i;
  BOOL saved = NO;
  _dialog = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 690, 610)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_dialog setTitle: [NSString stringWithFormat: @"Daily Timesheet — %@ to %@",
    [period objectForKey: @"start"], [period objectForKey: @"end"]]];
  [_dialog setReleasedWhenClosed: NO];
  CLLabel ([_dialog contentView], [NSString stringWithFormat: @"%@ · %@",
    [[_ledger clientWithID: [self selectedClient: _timeClient]] objectForKey: @"name"],
    [_timeTask titleOfSelectedItem]], NSMakeRect (18, 565, 654, 25), 13);
  CLLabel ([_dialog contentView], @"Description for these entries (optional with a task)", NSMakeRect (18, 536, 654, 20), 12);
  description = CLField ([_dialog contentView], [_taskField stringValue], NSMakeRect (18, 507, 654, 26));
  CLLabel ([_dialog contentView], @"Adds new entries. Leave days blank or zero to skip; enter decimal hours (1.5 = 1h 30m).",
    NSMakeRect (18, 478, 654, 22), 11);
  CLLabel ([_dialog contentView], @"Date", NSMakeRect (34, 448, 350, 22), 12);
  CLLabel ([_dialog contentView], @"Hours", NSMakeRect (396, 448, 160, 22), 12);
  scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (18, 65, 654, 380)] autorelease];
  [scroll setHasVerticalScroller: YES];
  [scroll setBorderType: NSLineBorder];
  document = [[[NSView alloc] initWithFrame: NSMakeRect (0, 0, 630, contentHeight)] autorelease];
  for (i = 0; i < [dates count]; i++)
    {
      CGFloat y = contentHeight - 40 - i * 36;
      NSTextField *field;
      CLLabel (document, [dates objectAtIndex: i], NSMakeRect (16, y, 340, 26), 13);
      field = CLField (document, @"", NSMakeRect (376, y, 170, 26));
      [fields addObject: field];
      if (i == 0)
        [_dialog setInitialFirstResponder: field];
      else
        [[fields objectAtIndex: i - 1] setNextKeyView: field];
    }
  [scroll setDocumentView: document];
  [[_dialog contentView] addSubview: scroll];
  [[scroll contentView] scrollToPoint: NSMakePoint (0, MAX (0, contentHeight - [[scroll contentView] bounds].size.height))];
  [scroll reflectScrolledClipView: [scroll contentView]];
  [CLButton ([_dialog contentView], @"Cancel", NSMakeRect (406, 18, 120, 32), self, @selector(cancelDialog:)) setKeyEquivalent: @"\033"];
  CLButton ([_dialog contentView], @"Save Time", NSMakeRect (536, 18, 136, 32), self, @selector(acceptDialog:));
  [_dialog center];
  while (!saved)
    {
      NSMutableArray *rows = [NSMutableArray array];
      NSString *error = nil;
      _dialogAccepted = NO;
      [NSApp runModalForWindow: _dialog];
      if (!_dialogAccepted)
        break;
      for (i = 0; i < [dates count]; i++)
        [rows addObject: [NSDictionary dictionaryWithObjectsAndKeys: [dates objectAtIndex: i], @"date",
          [[fields objectAtIndex: i] stringValue], @"hours", [description stringValue], @"description", nil]];
      saved = [_ledger addTimeRows: rows client: [self selectedClient: _timeClient]
        task: [[_timeTask selectedItem] representedObject] billable: [_nonbillableTime state] != NSOnState error: &error];
      if (!saved)
        [self showError: error];
    }
  [_dialog orderOut: nil];
  [_dialog release];
  _dialog = nil;
  if (saved)
    [self refresh];
}

- (void) editClientReminders: (id)sender
{
  NSDictionary *client = [self selectedRecord: _clientsTable];
  NSArray *labels = [NSArray arrayWithObjects: @"Automatic email", @"Days before due", @"Payment reminder", @"Overdue reminder", nil];
  NSArray *values;
  NSDictionary *form;
  NSString *identifier;
  if (client == nil) { [self showError: @"Select a client first."]; return; }
  identifier = [[[client objectForKey: @"id"] copy] autorelease];
  values = [NSArray arrayWithObjects: [[client objectForKey: @"autoReminders"] boolValue] ? @"yes" : @"no",
    [NSString stringWithFormat: @"%ld", (long)[CLLedger reminderDaysForClient: client]],
    [client objectForKey: @"reminderMessage"] ?: @"", [client objectForKey: @"overdueMessage"] ?: @"", nil];
  while ((form = [self editForm: @"Email reminders — one before due, one when overdue" labels: labels values: values]) != nil)
    {
      NSString *error = nil;
      BOOL enabled = [[form objectForKey: @"Automatic email"] isEqual: @"yes"];
#ifndef __APPLE__
      if (enabled) { [self showError: @"Automatic reminders require Apple Mail on macOS."]; return; }
#endif
      if ([_ledger saveRemindersForClient: identifier enabled: enabled daysBefore: [form objectForKey: @"Days before due"]
          message: [form objectForKey: @"Payment reminder"] overdueMessage: [form objectForKey: @"Overdue reminder"] error: &error])
        {
          [self refresh];
          [_mailStatus setStringValue: enabled ? @"Reminders enabled. Keep the app running; a sound and alert will ask before each send." : @"Automatic reminders disabled for this client. Custom messages still apply to email drafts."];
          return;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Automatic email"], [form objectForKey: @"Days before due"],
        [form objectForKey: @"Payment reminder"], [form objectForKey: @"Overdue reminder"], nil];
    }
}

- (BOOL) confirmReminderForInvoice: (NSDictionary *)invoice stage: (NSString *)stage
{
  NSDictionary *client = [_ledger billingClientForInvoice: invoice];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText: [stage isEqual: @"overdue"] ? @"Send overdue payment reminder?" : @"Send payment reminder?"];
  [alert setInformativeText: [NSString stringWithFormat:
    @"Invoice %@\nTo: %@ <%@>\nDue: %@\n\n%@\n\nThe invoice PDF will be attached.",
    [CLLedger invoiceNumber: invoice], [client objectForKey: @"name"], [client objectForKey: @"email"],
    [invoice objectForKey: @"dueDate"], [_ledger paymentMessageForInvoice: invoice onDate: [CLLedger today]]]];
  [[alert addButtonWithTitle: @"Send Reminder"] setKeyEquivalent: @""];
  [[alert addButtonWithTitle: @"Remind Me in 1 Hour"] setKeyEquivalent: @"\r"];
  [NSApp activateIgnoringOtherApps: YES];
  NSBeep ();
  return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void) checkReminders: (id)sender
{
  NSArray *invoices;
  unsigned int i;
#ifdef __APPLE__
  BOOL enabled = NO;
#endif
  [_invoicesTable reloadData];
#ifdef __APPLE__
  for (i = 0; i < [[_ledger clients] count]; i++)
    if ([[[[_ledger clients] objectAtIndex: i] objectForKey: @"autoReminders"] boolValue]) enabled = YES;
  if (enabled && _backgroundActivity == nil)
    _backgroundActivity = [[[NSProcessInfo processInfo] beginActivityWithOptions: NSActivityUserInitiatedAllowingIdleSystemSleep
      reason: @"Check scheduled invoice reminders while the app runs in the background"] retain];
  if (!enabled && _backgroundActivity != nil)
    { [[NSProcessInfo processInfo] endActivity: _backgroundActivity]; [_backgroundActivity release]; _backgroundActivity = nil; }
#else
  return;
#endif
  if (_mailer != nil || _reminderPromptActive || [NSApp modalWindow] != nil) return;
  invoices = [_ledger invoices];
  for (i = 0; i < [invoices count]; i++)
    {
      NSDictionary *invoice = [invoices objectAtIndex: i];
      NSString *stage = [_ledger reminderStageForInvoice: invoice onDate: [CLLedger today]];
      NSString *error = nil;
      NSDictionary *client;
      NSString *snoozeKey;
      NSDate *snoozedUntil;
      BOOL approved;
      if (stage == nil) continue;
      snoozeKey = [NSString stringWithFormat: @"%@:%@", [invoice objectForKey: @"id"], stage];
      snoozedUntil = [_reminderSnoozes objectForKey: snoozeKey];
      if (snoozedUntil != nil && [snoozedUntil timeIntervalSinceNow] > 0) continue;
      _reminderPromptActive = YES;
      approved = [self confirmReminderForInvoice: invoice stage: stage];
      _reminderPromptActive = NO;
      if (!approved)
        {
          if (_reminderSnoozes == nil) _reminderSnoozes = [[NSMutableDictionary alloc] init];
          [_reminderSnoozes setObject: [NSDate dateWithTimeIntervalSinceNow: 3600] forKey: snoozeKey];
          [_mailStatus setStringValue: @"Reminder postponed for one hour. No email sent."];
          continue;
        }
      [_reminderSnoozes removeObjectForKey: snoozeKey];
      _mailInvoiceID = [[invoice objectForKey: @"id"] copy];
      _mailStage = [stage copy];
      if (![_ledger beginReminder: _mailInvoiceID stage: stage onDate: [CLLedger today] error: &error])
        {
          [_mailInvoiceID release]; _mailInvoiceID = nil; [_mailStage release]; _mailStage = nil;
          [_mailStatus setStringValue: @"Could not save the reminder attempt. No email sent."];
          [_mailStatus setToolTip: error];
          return;
        }
      client = [_ledger billingClientForInvoice: invoice];
      _mailer = [[CLInvoiceMailer alloc] init];
      _mailStarting = YES;
      if (![_mailer startInvoice: invoice recipient: [client objectForKey: @"email"] sender: [_ledger senderForInvoice: invoice]
          message: [_ledger paymentMessageForInvoice: invoice onDate: [CLLedger today]] send: YES error: &error])
        {
          [_ledger finishReminder: _mailInvoiceID stage: stage submitted: NO detail: error error: NULL];
          [_mailer release]; _mailer = nil;
          [_mailInvoiceID release]; _mailInvoiceID = nil; [_mailStage release]; _mailStage = nil;
          [_mailStatus setStringValue: @"Automatic email needs review. Select the invoice and choose Review Email."];
          [_mailStatus setToolTip: error];
        }
      else [_mailStatus setStringValue: @"Submitting an automatic reminder with the invoice PDF to Apple Mail…"];
      _mailStarting = NO;
      [_invoicesTable reloadData];
      return;
    }
}

- (void) reviewReminder: (id)sender
{
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  NSDictionary *history = [invoice objectForKey: @"reminders"];
  NSArray *stages = [NSArray arrayWithObjects: @"due", @"overdue", nil];
  unsigned int i;
  if (invoice == nil) { [self showError: @"Select an invoice first."]; return; }
  if ([[invoice objectForKey: @"id"] isEqual: _mailInvoiceID])
    { [self showError: @"Wait for this Mail operation to finish before reviewing it."]; return; }
  for (i = 0; i < [stages count]; i++)
    {
      NSString *stage = [stages objectAtIndex: i];
      NSDictionary *attempt = [history objectForKey: stage];
      NSInteger answer;
      NSString *error = nil;
      if (attempt == nil || [[attempt objectForKey: @"status"] isEqual: @"submitted"]) continue;
      answer = NSRunAlertPanel (@"Review reminder in Apple Mail",
        @"%@\n\nCheck Drafts, Outbox and Sent for invoice %@. If Mail has it queued or sent, choose Already Submitted. Only choose Retry if you have verified it was not submitted and removed any stale draft. Retrying makes it eligible for the next automatic check.",
        @"Cancel", @"Already Submitted", @"Retry", [attempt objectForKey: @"detail"], [CLLedger invoiceNumber: invoice]);
      if (answer != NSAlertDefaultReturn)
        {
          [_ledger resolveReminder: [invoice objectForKey: @"id"] stage: stage submitted: answer == NSAlertAlternateReturn error: &error];
          [self showError: error];
          [_invoicesTable reloadData];
        }
      return;
    }
  [self showError: [history count] > 0 ? @"Reminder submission is recorded. Apple Mail handles delivery; check its Outbox and any bounce notices." : @"No automatic reminder has been attempted. Configure Email Reminders for this client in Clients."];
}

#include "CLFinanceUI.inc"
@end
