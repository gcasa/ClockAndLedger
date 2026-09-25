#import "CLAppController.h"
#import "CLLedger.h"
#import "CLInvoiceView.h"

static NSTextField *
CLLabel (NSView *parent, NSString *text, NSRect frame, CGFloat size)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame: frame] autorelease];
  [field setStringValue: text];
  [field setEditable: NO];
  [field setSelectable: NO];
  [field setBordered: NO];
  [field setDrawsBackground: NO];
  [field setFont: [NSFont systemFontOfSize: size]];
  [parent addSubview: field];
  return field;
}

static NSTextField *
CLField (NSView *parent, NSString *value, NSRect frame)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame: frame] autorelease];
  [field setStringValue: value != nil ? value : @""];
  [parent addSubview: field];
  return field;
}

static NSButton *
CLButton (NSView *parent, NSString *title, NSRect frame, id target, SEL action)
{
  NSButton *button = [[[NSButton alloc] initWithFrame: frame] autorelease];
  [button setTitle: title];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setTarget: target];
  [button setAction: action];
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
@end

@implementation CLAppController

- (void) dealloc
{
  [_pulse invalidate];
  [_pulse release];
  [_window release];
  [_businessFields release];
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
  _window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 1040, 700)
    styleMask: NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  [_window setTitle: @"Clock & Ledger"];
  [_window setMinSize: NSMakeSize (1040, 700)];
  [_window setReleasedWhenClosed: NO];
  [CLLabel ([_window contentView], @"Clock & Ledger", NSMakeRect (24, 642, 600, 36), 27)
    setAutoresizingMask: NSViewMinYMargin];
  _summaryLabel = CLLabel ([_window contentView], @"", NSMakeRect (24, 608, 980, 25), 13);
  [_summaryLabel setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
  tabs = [[[NSTabView alloc] initWithFrame: NSMakeRect (16, 16, 1008, 584)] autorelease];
  [tabs setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [[_window contentView] addSubview: tabs];

  view = [self tab: @"Clients" in: tabs];
  CLLabel (view, @"Your clients", NSMakeRect (18, 496, 600, 28), 20);
  CLLabel (view, @"Contact details and default hourly rates. Existing time keeps its original rate.", NSMakeRect (18, 467, 940, 24), 12);
  _clientsTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"name", @"email", @"address", @"rate", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 220], [NSNumber numberWithInt: 240], [NSNumber numberWithInt: 350], [NSNumber numberWithInt: 120], nil]];
  [_clientsTable setDoubleAction: @selector(editClient:)];
  [_clientsTable setTarget: self];
  CLButton (view, @"Add Client", NSMakeRect (12, 12, 130, 32), self, @selector(addClient:));
  CLButton (view, @"Edit", NSMakeRect (148, 12, 100, 32), self, @selector(editClient:));
  CLButton (view, @"Delete", NSMakeRect (254, 12, 100, 32), self, @selector(deleteClient:));

  view = [self tab: @"Time" in: tabs];
  CLLabel (view, @"Track your work", NSMakeRect (18, 500, 280, 28), 20);
  _timeClient = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 459, 220, 28) pullsDown: NO] autorelease];
  [view addSubview: _timeClient];
  _taskField = CLField (view, @"", NSMakeRect (249, 460, 393, 26));
  [_taskField setToolTip: @"Describe the work before starting a timer."];
  CLLabel (view, @"Work description", NSMakeRect (249, 488, 220, 18), 11);
  CLButton (view, @"Start", NSMakeRect (650, 455, 88, 34), self, @selector(startTimer:));
  CLButton (view, @"Stop", NSMakeRect (742, 455, 88, 34), self, @selector(stopTimer:));
  _timerLabel = CLLabel (view, @"No timer running", NSMakeRect (18, 425, 936, 25), 13);
  _timeTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"date", @"client", @"description", @"hours", @"amount", @"billing", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 155], [NSNumber numberWithInt: 340], [NSNumber numberWithInt: 80], [NSNumber numberWithInt: 100], [NSNumber numberWithInt: 145], nil]];
  [[_timeTable enclosingScrollView] setFrame: NSMakeRect (18, 58, 940, 359)];
  CLButton (view, @"Add Manual Time", NSMakeRect (12, 12, 170, 32), self, @selector(addTime:));
  CLButton (view, @"Delete Unbilled Entry", NSMakeRect (186, 12, 210, 32), self, @selector(deleteTime:));

  CLButton (view, @"Review Imported Time", NSMakeRect (406, 12, 220, 32), self, @selector(reviewImportedTime:));

  view = [self tab: @"Invoices" in: tabs];
  CLLabel (view, @"Invoice your time", NSMakeRect (18, 500, 500, 28), 20);
  CLLabel (view, @"Create an invoice from all unbilled entries for a client. Issued amounts and details are locked.", NSMakeRect (18, 472, 940, 22), 12);
  _invoiceClient = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (18, 427, 240, 28) pullsDown: NO] autorelease];
  [view addSubview: _invoiceClient];
  CLLabel (view, @"Tax %", NSMakeRect (272, 430, 50, 22), 12);
  _taxField = CLField (view, @"0", NSMakeRect (327, 429, 65, 26));
  CLLabel (view, @"Due date", NSMakeRect (408, 430, 65, 22), 12);
  {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd"];
    _dueField = CLField (view, [formatter stringFromDate: [NSDate dateWithTimeIntervalSinceNow: 30 * 86400]], NSMakeRect (481, 429, 130, 26));
  }
  CLButton (view, @"Create Invoice", NSMakeRect (629, 424, 170, 34), self, @selector(createInvoice:));
  _invoicesTable = [self tableIn: view
    columns: [NSArray arrayWithObjects: @"id", @"client", @"date", @"dueDate", @"total", @"status", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 145], [NSNumber numberWithInt: 275], [NSNumber numberWithInt: 130], [NSNumber numberWithInt: 130], [NSNumber numberWithInt: 130], [NSNumber numberWithInt: 110], nil]];
  [[_invoicesTable enclosingScrollView] setFrame: NSMakeRect (18, 58, 940, 354)];
  [_invoicesTable setDoubleAction: @selector(previewInvoice:)];
  [_invoicesTable setTarget: self];
  CLButton (view, @"Preview", NSMakeRect (12, 12, 120, 32), self, @selector(previewInvoice:));
  CLButton (view, @"Print…", NSMakeRect (138, 12, 120, 32), self, @selector(printInvoice:));
  CLButton (view, @"Toggle Paid / Unpaid", NSMakeRect (264, 12, 215, 32), self, @selector(togglePaid:));

  view = [self tab: @"Business" in: tabs];
  CLLabel (view, @"Business & payment details", NSMakeRect (18, 496, 800, 28), 20);
  CLLabel (view, @"Set these before issuing invoices. Each invoice preserves a copy of these details.", NSMakeRect (18, 467, 940, 24), 12);
  _businessFields = [[NSMutableDictionary alloc] init];
  keys = [NSArray arrayWithObjects: @"name", @"email", @"address", @"currency", @"notes", nil];
  labels = [NSArray arrayWithObjects: @"Business name", @"Email", @"Postal address", @"Currency code", @"Payment instructions", nil];
  for (i = 0; i < [keys count]; i++)
    {
      CGFloat y = 404 - i * 70;
      NSTextField *field;
      CLLabel (view, [labels objectAtIndex: i], NSMakeRect (20, y + 2, 165, 24), 13);
      field = CLField (view, [[_ledger business] objectForKey: [keys objectAtIndex: i]], NSMakeRect (190, y, 730, 48));
      if (i == 2 || i == 4)
        [[field cell] setWraps: YES];
      [_businessFields setObject: field forKey: [keys objectAtIndex: i]];
    }
  CLButton (view, @"Save Business Details", NSMakeRect (184, 42, 220, 34), self, @selector(saveBusiness:));
  CLButton (view, @"Back Up Ledger…", NSMakeRect (410, 42, 190, 34), self, @selector(backupLedger:));
  CLButton (view, @"Import QuickBooks…", NSMakeRect (606, 42, 210, 34), self, @selector(importQuickBooks:));
  /* Keep the editors above their expanding tables when resizing. */
  for (i = 0; i < [[tabs tabViewItems] count]; i++)
    {
      NSArray *children = [[[[tabs tabViewItems] objectAtIndex: i] view] subviews];
      unsigned int j;
      for (j = 0; j < [children count]; j++)
        {
          NSView *child = [children objectAtIndex: j];
          if (![child isKindOfClass: [NSScrollView class]] && [child frame].origin.y > 100)
            [child setAutoresizingMask: NSViewMinYMargin];
        }
    }
  [self refresh];
  _pulse = [[NSTimer scheduledTimerWithTimeInterval: 1 target: self selector: @selector(tick:) userInfo: nil repeats: YES] retain];
  [_window center];
  [_window makeKeyAndOrderFront: nil];
  [NSApp activateIgnoringOtherApps: YES];
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
  NSTableView *table = [[[NSTableView alloc] initWithFrame: [scroll bounds]] autorelease];
  unsigned int i;
  [scroll setBorderType: NSBezelBorder];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [table setRowHeight: 27];
  [table setAllowsMultipleSelection: NO];
  for (i = 0; i < [columns count]; i++)
    {
      NSString *key = [columns objectAtIndex: i];
      NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: key] autorelease];
      NSString *title = [key isEqual: @"dueDate"] ? @"Due date" : [key capitalizedString];
      [[column headerCell] setStringValue: title];
      [column setWidth: [[widths objectAtIndex: i] doubleValue]];
      [column setEditable: NO];
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
  if (table == _clientsTable)
    return [[_ledger clients] count];
  if (table == _timeTable)
    return [[_ledger entries] count];
  return [[_ledger invoices] count];
}

/** Format a ledger field for its read-only table cell. */
- (id) tableView: (NSTableView *)table objectValueForTableColumn: (NSTableColumn *)column row: (NSInteger)row
{
  NSString *key = [column identifier];
  NSDictionary *record;
  if (table == _clientsTable)
    {
      record = [[_ledger clients] objectAtIndex: row];
      if ([key isEqual: @"rate"])
        return [CLLedger money: [record objectForKey: key]];
    }
  else if (table == _timeTable)
    {
      record = [[_ledger entries] objectAtIndex: row];
      if ([key isEqual: @"client"])
        return [[_ledger clientWithID: [record objectForKey: @"clientID"]] objectForKey: @"name"];
      if ([key isEqual: @"hours"])
        return [NSString stringWithFormat: @"%.4f", [[record objectForKey: @"seconds"] doubleValue] / 3600.0];
      if ([key isEqual: @"amount"])
        return [CLLedger money: [CLLedger amountForSeconds: [record objectForKey: @"seconds"] rate: [record objectForKey: @"rate"]]];
      if ([key isEqual: @"billing"])
        return [[record objectForKey: @"invoiceID"] length] > 0 ? [record objectForKey: @"invoiceID"]
          : ([record objectForKey: @"externalBilling"] != nil ? [record objectForKey: @"externalBilling"] : @"Unbilled");
    }
  else
    {
      record = [[_ledger invoices] objectAtIndex: row];
      if ([key isEqual: @"id"])
        return [CLLedger invoiceNumber: record];
      if ([key isEqual: @"dueDate"] && [[record objectForKey: @"dueDateUnverified"] boolValue])
        return @"Not provided";
      if ([key isEqual: @"client"])
        return [[record objectForKey: @"client"] objectForKey: @"name"];
      if ([key isEqual: @"total"])
        return [CLLedger money: [record objectForKey: @"total"]];
      if ([key isEqual: @"status"])
        {
          if ([[record objectForKey: @"paymentUnverified"] boolValue])
            return @"Review payment";
          if ([[record objectForKey: @"paid"] boolValue])
            return @"Paid";
          return ![[record objectForKey: @"dueDateUnverified"] boolValue]
            && [(NSString *)[record objectForKey: @"dueDate"] compare: [CLLedger today]] == NSOrderedAscending ? @"Overdue" : @"Unpaid";
        }
    }
  return [record objectForKey: key];
}

- (NSDictionary *) selectedRecord: (NSTableView *)table
{
  NSInteger row = [table selectedRow];
  NSArray *records = table == _clientsTable ? [_ledger clients] : (table == _timeTable ? [_ledger entries] : [_ledger invoices]);
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
  long long outstanding = 0;
  long long paid = 0;
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
      if ([[invoice objectForKey: @"paid"] boolValue])
        paid += [[invoice objectForKey: @"total"] longLongValue];
      else
        outstanding += [[invoice objectForKey: @"total"] longLongValue];
    }
  [_summaryLabel setStringValue: [NSString stringWithFormat:
    @"%@   •   Unbilled: %@   •   Outstanding: %@   •   Paid: %@   •   %lu clients",
    [[_ledger business] objectForKey: @"currency"],
    [CLLedger money: [NSNumber numberWithLongLong: unbilled]],
    [CLLedger money: [NSNumber numberWithLongLong: outstanding]],
    [CLLedger money: [NSNumber numberWithLongLong: paid]], (unsigned long)[[_ledger clients] count]]];
  [_clientsTable reloadData];
  [_timeTable reloadData];
  [_invoicesTable reloadData];
  [self fillClients: _timeClient];
  [self fillClients: _invoiceClient];
  [self tick: nil];
}

- (NSDictionary *) editForm: (NSString *)title labels: (NSArray *)labels values: (NSArray *)values
{
  NSMutableDictionary *fields = [NSMutableDictionary dictionary];
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  unsigned int i;
  CGFloat height = 90 + [labels count] * 64;
  _dialog = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 610, height)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_dialog setTitle: title];
  [_dialog setReleasedWhenClosed: NO];
  for (i = 0; i < [labels count]; i++)
    {
      CGFloat y = height - 70 - i * 64;
      NSTextField *field;
      CLLabel ([_dialog contentView], [labels objectAtIndex: i], NSMakeRect (18, y + 10, 157, 24), 13);
      field = CLField ([_dialog contentView], [values objectAtIndex: i], NSMakeRect (180, y, 408, 45));
      [[field cell] setWraps: YES];
      [fields setObject: field forKey: [labels objectAtIndex: i]];
      if (i == 0)
        [_dialog setInitialFirstResponder: field];
    }
  [CLButton ([_dialog contentView], @"Cancel", NSMakeRect (366, 16, 106, 32), self, @selector(cancelDialog:)) setKeyEquivalent: @"\033"];
  [CLButton ([_dialog contentView], @"Save", NSMakeRect (480, 16, 106, 32), self, @selector(acceptDialog:)) setKeyEquivalent: @"\r"];
  _dialogAccepted = NO;
  [_dialog center];
  [NSApp runModalForWindow: _dialog];
  for (i = 0; i < [labels count]; i++)
    [result setObject: [[fields objectForKey: [labels objectAtIndex: i]] stringValue] forKey: [labels objectAtIndex: i]];
  [_dialog orderOut: nil];
  [_dialog release];
  _dialog = nil;
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
    [client objectForKey: @"email"], [client objectForKey: @"address"], [CLLedger money: [client objectForKey: @"rate"]], nil]
    : [NSArray arrayWithObjects: @"", @"", @"", @"100.00", nil];
  NSArray *labels = [NSArray arrayWithObjects: @"Name", @"Email", @"Address", @"Hourly rate", nil];
  NSDictionary *form;
  while ((form = [self editForm: client != nil ? @"Edit Client" : @"Add Client" labels: labels values: values]) != nil)
    {
      NSString *error = nil;
      if ([_ledger saveClient: [client objectForKey: @"id"] name: [form objectForKey: @"Name"]
        email: [form objectForKey: @"Email"] address: [form objectForKey: @"Address"]
        rate: [form objectForKey: @"Hourly rate"] error: &error])
        {
          [self refresh];
          break;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Name"], [form objectForKey: @"Email"],
        [form objectForKey: @"Address"], [form objectForKey: @"Hourly rate"], nil];
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
  NSArray *labels = [NSArray arrayWithObjects: @"Date (YYYY-MM-DD)", @"Description", @"Hours", nil];
  NSArray *values = [NSArray arrayWithObjects: [CLLedger today], [_taskField stringValue], @"1.00", nil];
  NSDictionary *form;
  NSString *clientID = [self selectedClient: _timeClient];
  if (clientID == nil)
    {
      [self showError: @"Add a client first, then select it in the Time tab."];
      return;
    }
  while ((form = [self editForm: @"Add Time for Selected Client" labels: labels values: values]) != nil)
    {
      NSString *error = nil;
      if ([_ledger addTimeForClient: clientID date: [form objectForKey: @"Date (YYYY-MM-DD)"]
        description: [form objectForKey: @"Description"] hours: [form objectForKey: @"Hours"] error: &error])
        {
          [self refresh];
          break;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Date (YYYY-MM-DD)"],
        [form objectForKey: @"Description"], [form objectForKey: @"Hours"], nil];
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
  [_ledger startTimerForClient: [self selectedClient: _timeClient] description: [_taskField stringValue] error: &error];
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
  NSDictionary *timer = [_ledger timer];
  if (timer == nil)
    [_timerLabel setStringValue: @"No timer running. Choose a client and describe your work, or add manual time below."];
  else
    {
      long long seconds = MAX (0, (long long)-[[timer objectForKey: @"started"] timeIntervalSinceNow]);
      [_timerLabel setStringValue: [NSString stringWithFormat: @"●  %02lld:%02lld:%02lld   %@ — %@  (continues while app is closed)",
        seconds / 3600, (seconds / 60) % 60, seconds % 60,
        [[_ledger clientWithID: [timer objectForKey: @"clientID"]] objectForKey: @"name"], [timer objectForKey: @"description"]]];
    }
}

- (void) createInvoice: (id)sender
{
  NSString *error = nil;
  if (NSRunAlertPanel (@"Issue invoice?", @"All unbilled time for the selected client will be locked into a new invoice. Check your business details, tax and due date first.", @"Cancel", @"Create Invoice", nil) != NSAlertAlternateReturn)
    return;
  if ([_ledger invoiceClient: [self selectedClient: _invoiceClient] tax: [_taxField stringValue] dueDate: [_dueField stringValue] error: &error])
    {
      [self refresh];
      [_invoicesTable selectRowIndexes: [NSIndexSet indexSetWithIndex: [[_ledger invoices] count] - 1] byExtendingSelection: NO];
      [self previewInvoice: nil];
    }
  else
    [self showError: error];
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

- (void) togglePaid: (id)sender
{
  NSString *error = nil;
  NSDictionary *invoice = [self selectedRecord: _invoicesTable];
  if ([[invoice objectForKey: @"paymentUnverified"] boolValue])
    {
      NSInteger answer = NSRunAlertPanel (@"Confirm imported payment status",
        @"The export did not include a reliable payment status. Check QuickBooks before confirming.",
        @"Cancel", @"Paid", @"Unpaid");
      if (answer == NSAlertDefaultReturn)
        return;
      [_ledger setInvoice: [invoice objectForKey: @"id"] paid: answer == NSAlertAlternateReturn error: &error];
    }
  else
    [_ledger togglePaid: [invoice objectForKey: @"id"] error: &error];
  [self showError: error];
  [self refresh];
}

- (void) saveBusiness: (id)sender
{
  NSMutableDictionary *business = [NSMutableDictionary dictionary];
  NSArray *keys = [_businessFields allKeys];
  unsigned int i;
  NSString *error = nil;
  for (i = 0; i < [keys count]; i++)
    [business setObject: [[_businessFields objectForKey: [keys objectAtIndex: i]] stringValue] forKey: [keys objectAtIndex: i]];
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
  return YES;
}

- (void) applicationWillTerminate: (NSNotification *)notification
{
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
  [scroll setBorderType: NSBezelBorder];
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
@end
