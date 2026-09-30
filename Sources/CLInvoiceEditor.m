#import "CLInvoiceEditor.h"
#import "CLLedger.h"
#import "CLDateField.h"

static void CLELabel (NSView *parent, NSString *text, NSRect rect)
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame: rect] autorelease];
  [label setStringValue: text]; [label setEditable: NO]; [label setSelectable: NO];
  [label setBordered: NO]; [label setDrawsBackground: NO];
  [label setFont: [NSFont systemFontOfSize: 12]]; [parent addSubview: label];
}
static void CLEButton (NSView *parent, NSString *title, NSRect rect, id target, SEL action)
{
  NSButton *button = [[[NSButton alloc] initWithFrame: rect] autorelease];
  [button setTitle: title]; [button setBezelStyle: NSRoundedBezelStyle];
  [button setTarget: target]; [button setAction: action]; [parent addSubview: button];
}
static NSView *CLETab (NSTabView *tabs, NSString *title)
{
  NSTabViewItem *tab = [[[NSTabViewItem alloc] initWithIdentifier: title] autorelease];
  NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect (0, 0, 736, 460)] autorelease];
  [tab setLabel: title]; [tab setView: view]; [tabs addTabViewItem: tab]; return view;
}
static void CLEField (NSView *parent, NSMutableDictionary *fields, NSDictionary *values,
                      NSString *key, NSString *label, CGFloat y, BOOL date)
{
  NSTextField *field;
  CLELabel (parent, label, NSMakeRect (16, y + 4, 175, 26));
  if (date) field = [CLDateField fieldInView: parent value: [values objectForKey: key] frame: NSMakeRect (196, y, 510, 30)];
  else
    {
      field = [[[NSTextField alloc] initWithFrame: NSMakeRect (196, y, 510, 30)] autorelease];
      [field setStringValue: [values objectForKey: key] ?: @""]; [parent addSubview: field];
    }
  [fields setObject: field forKey: key];
}
static void CLEText (NSView *parent, NSMutableDictionary *fields, NSDictionary *values,
                     NSString *key, NSString *label, CGFloat y, CGFloat height)
{
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (196, y, 510, height)] autorelease];
  NSTextView *text = [[[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 488, height)] autorelease];
  CLELabel (parent, label, NSMakeRect (16, y + height - 26, 175, 26));
  [text setRichText: NO]; [text setFont: [NSFont systemFontOfSize: 13]];
  [text setString: [values objectForKey: key] ?: @""]; [text setVerticallyResizable: YES];
  [text setHorizontallyResizable: NO]; [[text textContainer] setWidthTracksTextView: YES];
  [scroll setHasVerticalScroller: YES]; [scroll setBorderType: NSBezelBorder];
  [scroll setDocumentView: text]; [parent addSubview: scroll]; [fields setObject: text forKey: key];
}
static void CLEReadFields (NSDictionary *fields, NSMutableDictionary *values)
{
  NSEnumerator *keys = [fields keyEnumerator]; NSString *key;
  while ((key = [keys nextObject]) != nil)
    {
      id field = [fields objectForKey: key];
      NSString *value = [field isKindOfClass: [NSTextView class]] ? [field string] :
        ([field isKindOfClass: [NSPopUpButton class]] ? [field titleOfSelectedItem] : [field stringValue]);
      [values setObject: value forKey: key];
    }
}
@implementation CLInvoiceEditor
- (id) initWithLedger: (CLLedger *)ledger invoice: (NSDictionary *)invoice
{
  self = [super init];
  if (self != nil)
    {
      _ledger = [ledger retain]; _identifier = [[invoice objectForKey: @"id"] copy];
      _values = [[NSMutableDictionary alloc] initWithDictionary: [ledger editValuesForInvoice: invoice]];
      _lines = [[NSMutableArray alloc] initWithArray: [_values objectForKey: @"lines"]];
      _fields = [[NSMutableDictionary alloc] init];
    }
  return self;
}
- (void) dealloc
{
  [_ledger release]; [_identifier release]; [_values release]; [_lines release];
  [_fields release]; [_panel release]; [super dealloc];
}
- (BOOL) run
{
  NSTabView *tabs;
  NSView *view;
  NSScrollView *scroll;
  NSPopUpButton *status;
  NSArray *columns = [NSArray arrayWithObjects: @"date", @"taskName", @"description", @"hours", @"rate", @"amount", nil];
  NSArray *titles = [NSArray arrayWithObjects: @"Service date", @"Task", @"Description", @"Hours", @"Rate", @"Amount override", nil];
  unsigned int i;
  _panel = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 780, 580) styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_panel setTitle: @"Edit Invoice"]; [_panel setReleasedWhenClosed: NO];
  tabs = [[[NSTabView alloc] initWithFrame: NSMakeRect (14, 80, 752, 480)] autorelease];
  [[_panel contentView] addSubview: tabs];
  view = CLETab (tabs, @"Invoice");
  CLEField (view, _fields, _values, @"number", @"Invoice number", 400, NO);
  CLEField (view, _fields, _values, @"date", @"Issued", 350, YES);
  [[_fields objectForKey: @"date"] setDelegate: (id)self];
  CLEField (view, _fields, _values, @"dueDate", @"Due date", 300, YES);
  CLEField (view, _fields, _values, @"taxPercent", @"Tax %", 250, NO);
  CLEField (view, _fields, _values, @"taxAmount", @"Tax amount override", 200, NO);
  [[[_fields objectForKey: @"taxAmount"] cell] setPlaceholderString: @"Blank calculates tax from the percentage"];
  CLELabel (view, @"Payment status", NSMakeRect (16, 150, 175, 26));
  status = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (196, 150, 240, 30) pullsDown: NO] autorelease];
  [status addItemsWithTitles: [NSArray arrayWithObjects: @"Unpaid", @"Paid", @"Unverified", nil]];
  [status selectItemWithTitle: [_values objectForKey: @"status"]]; [view addSubview: status]; [_fields setObject: status forKey: @"status"];
  CLELabel (view, @"Subtotal and total are recalculated from line amounts and tax when saved.", NSMakeRect (16, 100, 690, 40));
  view = CLETab (tabs, @"Client");
  CLEField (view, _fields, _values, @"client_name", @"Client name", 400, NO);
  CLEField (view, _fields, _values, @"client_email", @"Email", 350, NO);
  CLEText (view, _fields, _values, @"client_address", @"Address", 185, 140);
  CLEField (view, _fields, _values, @"netDays", @"Net payment days", 130, NO);
  [[_fields objectForKey: @"netDays"] setDelegate: (id)self];
  CLELabel (view, @"These details apply to this invoice only. The saved client profile is unchanged.", NSMakeRect (16, 50, 690, 44));
  view = CLETab (tabs, @"Business");
  CLEField (view, _fields, _values, @"business_name", @"Business name", 400, NO);
  CLEField (view, _fields, _values, @"business_email", @"Email", 355, NO);
  CLEText (view, _fields, _values, @"business_address", @"Address", 255, 80);
  CLEField (view, _fields, _values, @"currency", @"Currency", 210, NO);
  [[_fields objectForKey: @"currency"] setToolTip: @"Changing the currency label does not convert amounts. Edit line amounts as needed."];
  CLEText (view, _fields, _values, @"notes", @"Payment instructions", 110, 80);
  _logo = [[[NSImageView alloc] initWithFrame: NSMakeRect (16, 12, 170, 80)] autorelease];
  [_logo setImageScaling: NSImageScaleProportionallyUpOrDown];
  [_logo setImage: [[[NSImage alloc] initWithData: [_values objectForKey: @"logoData"]] autorelease]];
  [view addSubview: _logo];
  CLEButton (view, @"Choose Logo…", NSMakeRect (196, 35, 170, 32), self, @selector(chooseLogo:));
  CLEButton (view, @"Remove Logo", NSMakeRect (380, 35, 170, 32), self, @selector(removeLogo:));
  view = CLETab (tabs, @"Line Items");
  scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect (16, 75, 690, 350)] autorelease];
  [scroll setHasVerticalScroller: YES]; [scroll setHasHorizontalScroller: YES]; [scroll setBorderType: NSBezelBorder];
  _table = [[[NSTableView alloc] initWithFrame: [scroll bounds]] autorelease];
  for (i = 0; i < [columns count]; i++)
    {
      NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: [columns objectAtIndex: i]] autorelease];
      [[column headerCell] setStringValue: [titles objectAtIndex: i]];
      [column setWidth: i == 2 ? 230 : 115]; [column setEditable: NO]; [_table addTableColumn: column];
    }
  [_table setDataSource: (id)self]; [_table setTarget: self]; [_table setDoubleAction: @selector(editLine:)];
  [scroll setDocumentView: _table]; [view addSubview: scroll];
  CLEButton (view, @"Add Line", NSMakeRect (16, 22, 130, 32), self, @selector(addLine:));
  CLEButton (view, @"Edit Line…", NSMakeRect (160, 22, 130, 32), self, @selector(editLine:));
  CLEButton (view, @"Remove Line", NSMakeRect (304, 22, 140, 32), self, @selector(removeLine:));
  CLELabel ([_panel contentView], @"Saved changes affect new previews and emails. Previously sent copies are unchanged.", NSMakeRect (20, 52, 738, 22));
  CLEButton ([_panel contentView], @"Cancel", NSMakeRect (506, 12, 120, 32), self, @selector(cancel:));
  CLEButton ([_panel contentView], @"Save Invoice", NSMakeRect (636, 12, 130, 32), self, @selector(save:));
  [_panel center]; [NSApp runModalForWindow: _panel]; [_panel orderOut: nil]; return _saved;
}
- (void) controlTextDidChange: (NSNotification *)notification
{
  if ([notification object] == [_fields objectForKey: @"date"] || [notification object] == [_fields objectForKey: @"netDays"])
    {
      NSString *date = [[_fields objectForKey: @"date"] stringValue];
      NSString *days = [[_fields objectForKey: @"netDays"] stringValue];
      NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
      NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier: NSGregorianCalendar] autorelease];
      NSDateComponents *offset = [[[NSDateComponents alloc] init] autorelease];
      if ([CLLedger periodContainingDate: date kind: @"day" error: NULL] == nil || [days length] == 0 || [days length] > 5
          || [days integerValue] > 36500 || [days rangeOfCharacterFromSet: [[NSCharacterSet characterSetWithCharactersInString: @"0123456789"] invertedSet]].location != NSNotFound)
        { [[_fields objectForKey: @"dueDate"] setStringValue: @""]; return; }
      [calendar setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
      [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
      [formatter setCalendar: calendar]; [formatter setTimeZone: [calendar timeZone]];
      [formatter setDateFormat: @"yyyy-MM-dd"]; [offset setDay: [days integerValue]];
      [[_fields objectForKey: @"dueDate"] setStringValue: [formatter stringFromDate:
        [calendar dateByAddingComponents: offset toDate: [formatter dateFromString: date] options: 0]]];
    }
}
- (void) save: (id)sender
{
  NSString *error = nil;
  [_panel makeFirstResponder: nil]; CLEReadFields (_fields, _values); [_values setObject: _lines forKey: @"lines"];
  if (![_ledger updateInvoice: _identifier values: _values error: &error])
    { NSRunAlertPanel (@"Cannot save invoice", @"%@", @"OK", nil, nil, error); return; }
  _saved = YES; [NSApp stopModal];
}
- (void) cancel: (id)sender { [NSApp stopModal]; }
- (NSInteger) numberOfRowsInTableView: (NSTableView *)table { return [_lines count]; }
- (id) tableView: (NSTableView *)table objectValueForTableColumn: (NSTableColumn *)column row: (NSInteger)row
{ return [[_lines objectAtIndex: row] objectForKey: [column identifier]]; }
- (void) editLineRecord: (NSDictionary *)line index: (NSInteger)index
{
  NSMutableDictionary *draft = [NSMutableDictionary dictionaryWithDictionary: line];
  _lineFields = [[NSMutableDictionary alloc] init]; _lineAccepted = NO;
  _linePanel = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 736, 560) styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_linePanel setTitle: @"Edit Invoice Line"]; [_linePanel setReleasedWhenClosed: NO]; [_linePanel setWorksWhenModal: YES];
  CLEField ([_linePanel contentView], _lineFields, draft, @"date", @"Service date", 500, YES);
  CLEField ([_linePanel contentView], _lineFields, draft, @"endDate", @"End date (optional)", 450, YES);
  CLEField ([_linePanel contentView], _lineFields, draft, @"taskName", @"Task name", 400, NO);
  CLEText ([_linePanel contentView], _lineFields, draft, @"description", @"Description", 260, 120);
  CLEField ([_linePanel contentView], _lineFields, draft, @"hours", @"Hours", 210, NO);
  CLEField ([_linePanel contentView], _lineFields, draft, @"rate", @"Hourly rate", 160, NO);
  CLEField ([_linePanel contentView], _lineFields, draft, @"amount", @"Amount override", 110, NO);
  CLELabel ([_linePanel contentView], @"Leave amount blank to use hours × rate. An amount override replaces hours/rate billing.", NSMakeRect (16, 62, 690, 40));
  CLEButton ([_linePanel contentView], @"Cancel", NSMakeRect (466, 14, 120, 32), self, @selector(cancelLine:));
  CLEButton ([_linePanel contentView], @"Use Line", NSMakeRect (596, 14, 120, 32), self, @selector(acceptLine:));
  [_linePanel center]; [NSApp runModalForWindow: _linePanel];
  if (_lineAccepted)
    { CLEReadFields (_lineFields, draft); if (index < 0) [_lines addObject: draft]; else [_lines replaceObjectAtIndex: index withObject: draft]; [_table reloadData]; }
  [_linePanel orderOut: nil]; [_linePanel release]; _linePanel = nil; [_lineFields release]; _lineFields = nil;
}
- (void) addLine: (id)sender
{
  NSDictionary *line = [NSDictionary dictionaryWithObjectsAndKeys: [[NSProcessInfo processInfo] globallyUniqueString], @"id",
    [[_fields objectForKey: @"date"] stringValue], @"date", @"", @"endDate", @"", @"taskName", @"", @"description",
    @"1", @"hours", @"0.00", @"rate", @"", @"amount", nil];
  [self editLineRecord: line index: -1];
}
- (void) editLine: (id)sender
{ NSInteger row = [_table selectedRow]; if (row >= 0) [self editLineRecord: [_lines objectAtIndex: row] index: row]; }
- (void) removeLine: (id)sender
{ NSInteger row = [_table selectedRow]; if (row >= 0) { [_lines removeObjectAtIndex: row]; [_table reloadData]; } }
- (void) acceptLine: (id)sender { [_linePanel makeFirstResponder: nil]; _lineAccepted = YES; [NSApp stopModal]; }
- (void) cancelLine: (id)sender { [NSApp stopModal]; }
- (void) chooseLogo: (id)sender
{
  NSOpenPanel *picker = [NSOpenPanel openPanel];
  NSData *data;
  NSImage *image;
  [picker setAllowedFileTypes: [NSArray arrayWithObjects: @"png", @"jpg", @"jpeg", @"tiff", @"icns", nil]];
  [picker setAllowsMultipleSelection: NO];
  if ([picker runModal] != NSOKButton) return;
  data = [NSData dataWithContentsOfURL: [picker URL]]; image = [[[NSImage alloc] initWithData: data] autorelease];
  if ([data length] == 0 || [data length] > 5 * 1024 * 1024 || ![image isValid])
    { NSRunAlertPanel (@"Invalid logo", @"Choose an image no larger than 5 MB.", @"OK", nil, nil); return; }
  [_values setObject: data forKey: @"logoData"]; [_logo setImage: image];
}
- (void) removeLogo: (id)sender { [_values setObject: [NSData data] forKey: @"logoData"]; [_logo setImage: nil]; }
@end
