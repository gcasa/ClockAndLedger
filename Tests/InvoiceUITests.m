#import <AppKit/AppKit.h>
#import "CLAppController.h"
#import "CLLedger.h"
#import "CLDateField.h"
#import "CLInvoiceEditor.h"

static unsigned int checks;
static void Check (BOOL ok, NSString *label)
{
  checks++;
  if (!ok) { NSLog (@"FAIL: %@", label); exit (1); }
}
@interface CLAppController (FormTest)
- (NSDictionary *) editForm: (NSString *)title labels: (NSArray *)labels values: (NSArray *)values;
@end
@interface CLTestController : CLAppController
- (id) initWithLedger: (CLLedger *)ledger;
- (void) verifyTasks;
- (void) verifyCalendar;
- (void) inspectCalendar: (NSTimer *)timer;
- (void) pickDate: (NSString *)date inField: (CLDateField *)field;
- (void) inspectForm: (NSTimer *)timer;
- (void) verifyIssuedForm;
- (void) inspectIssuedForm: (NSTimer *)timer;
@end
@implementation CLTestController
- (id) initWithLedger: (CLLedger *)ledger
{
  self = [super init];
  if (self != nil)
    {
      NSMenuItem *item;
      _ledger = [ledger retain];
      _window = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, 610, 518) styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
      _invoiceClient = [[[NSPopUpButton alloc] initWithFrame: NSZeroRect pullsDown: NO] autorelease];
      item = [[[NSMenuItem alloc] initWithTitle: @"Client" action: NULL keyEquivalent: @""] autorelease];
      [item setRepresentedObject: [[[ledger clients] objectAtIndex: 0] objectForKey: @"id"]];
      [[_invoiceClient menu] addItem: item];
      _invoiceTask = [[[NSPopUpButton alloc] initWithFrame: NSZeroRect pullsDown: NO] autorelease];
      _issuedField = [CLDateField fieldInView: [_window contentView] value: [CLLedger today] frame: NSMakeRect (20, 20, 195, 26)];
      [_issuedField setStringValue: [CLLedger today]];
      _dueField = [[[NSTextField alloc] initWithFrame: NSZeroRect] autorelease];
      _invoiceRate = [[[NSTextField alloc] initWithFrame: NSZeroRect] autorelease];
    }
  return self;
}
- (void) pickDate: (NSString *)date inField: (CLDateField *)field
{
  NSTimer *timer = [NSTimer timerWithTimeInterval: 0.1 target: self selector: @selector(inspectCalendar:)
    userInfo: [NSDictionary dictionaryWithObjectsAndKeys: field, @"field", date, @"date", nil] repeats: NO];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
  [field showCalendar: nil];
}
- (void) inspectCalendar: (NSTimer *)timer
{
  CLDateField *field = [[timer userInfo] objectForKey: @"field"];
  NSString *date = [[timer userInfo] objectForKey: @"date"];
  NSArray *views = [[[NSApp modalWindow] contentView] subviews];
  NSDatePicker *picker = nil;
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  unsigned int i;
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  for (i = 0; i < [views count]; i++)
    if ([[views objectAtIndex: i] isKindOfClass: [NSDatePicker class]]) picker = [views objectAtIndex: i];
  Check (picker != nil && [picker datePickerStyle] == NSClockAndCalendarDatePickerStyle, @"Calendar opens as graphical date picker");
  if ([date isEqual: @"cancel"])
    { [field cancelCalendar: nil]; return; }
  Check ([[formatter stringFromDate: [picker dateValue]] isEqual: [field stringValue]], @"Picker starts at manually entered date");
  [picker setDateValue: [formatter dateFromString: date]];
  [field chooseDate: nil];
}
- (void) verifyCalendar
{
  [_issuedField setStringValue: @"2024-02-15"];
  [_issuedField setDelegate: (id)self];
  [self pickDate: @"2024-02-29" inField: (CLDateField *)_issuedField];
  Check ([[_issuedField stringValue] isEqual: @"2024-02-29"], @"Calendar selection updates editable text");
  Check ([[_dueField stringValue] isEqual: @"2024-03-30"], @"Calendar selection recalculates due date");
  [_issuedField setStringValue: @"2024-02-30"];
  [self pickDate: @"cancel" inField: (CLDateField *)_issuedField];
  Check ([[_issuedField stringValue] isEqual: @"2024-02-30"], @"Cancel preserves invalid manual text for correction");
  [_issuedField setStringValue: @"2026-12-31"];
  [self controlTextDidChange: [NSNotification notificationWithName: NSControlTextDidChangeNotification object: _issuedField]];
  Check ([[_dueField stringValue] isEqual: @"2027-01-30"], @"Manual entry still works after using calendar");
}
- (void) verifyTasks
{
  [self invoiceClientChanged: nil];
  Check ([_invoiceTask numberOfItems] == 2, @"Invoice picker contains active client tasks only");
  Check ([[_invoiceRate stringValue] rangeOfString: @"150.00"].location != NSNotFound, @"Initial task rate is shown");
  [_invoiceTask selectItemAtIndex: 1];
  [self invoiceTaskChanged: nil];
  Check ([[_invoiceRate stringValue] rangeOfString: @"75.00"].location != NSNotFound, @"Selecting another task changes displayed rate");
  [self invoiceClientChanged: nil];
  Check ([_invoiceTask indexOfSelectedItem] == 1, @"Task selection survives refresh");
  [_issuedField setStringValue: @"2024-02-15"];
  [self controlTextDidChange: [NSNotification notificationWithName: NSControlTextDidChangeNotification object: _issuedField]];
  Check ([[_dueField stringValue] isEqual: @"2024-03-16"], @"Issued date edits recalculate Net 30 across leap day");
  [_issuedField setStringValue: @"2024-02-30"];
  [self controlTextDidChange: [NSNotification notificationWithName: NSControlTextDidChangeNotification object: _issuedField]];
  Check ([[_dueField stringValue] length] == 0, @"Invalid issued date clears stale due date");
  [_issuedField setStringValue: @"2026-12-15"];
  [self invoiceClientChanged: nil];
  Check ([[_dueField stringValue] isEqual: @"2027-01-14"], @"Client refresh calculates from entered date");
  Check (![self applicationShouldTerminateAfterLastWindowClosed: NSApp], @"Closing window keeps background checks running");
}
- (void) verifyIssuedForm
{
  NSDictionary *form;
  NSTimer *timer = [NSTimer timerWithTimeInterval: 0.1 target: self selector: @selector(inspectIssuedForm:) userInfo: nil repeats: NO];
  _dialogInvoiceClientID = [[[[ _ledger clients] objectAtIndex: 0] objectForKey: @"id"] copy];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
  form = [self editForm: @"Timesheet issued date test"
    labels: [NSArray arrayWithObjects: @"Tax %", @"Issued", @"Due date", nil]
    values: [NSArray arrayWithObjects: @"0", @"2024-01-01", @"2024-01-31", nil]];
  Check ([[form objectForKey: @"Issued"] isEqual: @"2024-02-15"], @"Timesheet form preserves entered issue date");
  Check ([[form objectForKey: @"Due date"] isEqual: @"2024-03-20"], @"Timesheet form retains manual due override");
  [_dialogInvoiceClientID release]; _dialogInvoiceClientID = nil;
}
- (void) inspectIssuedForm: (NSTimer *)timer
{
  Check ([_dialogIssuedField isKindOfClass: [CLDateField class]] && [_dialogDueField isKindOfClass: [CLDateField class]], @"Timesheet invoice has both calendar fields");
  [self pickDate: @"2024-02-15" inField: (CLDateField *)_dialogIssuedField];
  Check ([[_dialogDueField stringValue] isEqual: @"2024-03-16"], @"Nested calendar updates timesheet due date");
  [_dialogIssuedField setStringValue: @"2024-02-15"];
  [self controlTextDidChange: [NSNotification notificationWithName: NSControlTextDidChangeNotification object: _dialogIssuedField]];
  Check ([[_dialogDueField stringValue] isEqual: @"2024-03-16"], @"Timesheet issue date recalculates due date");
  [_dialogDueField setStringValue: @"2024-03-20"];
  [self acceptDialog: nil];
}
- (void) inspectForm: (NSTimer *)timer
{
  NSArray *views = [[_dialog contentView] subviews];
  unsigned int i, editors = 0, toggles = 0;
  for (i = 0; i < [views count]; i++)
    {
      NSView *view = [views objectAtIndex: i];
      Check (NSContainsRect ([[_dialog contentView] bounds], [view frame]), @"Form control fits within dialog");
      if ([view isKindOfClass: [NSScrollView class]])
        {
          NSTextView *text = [(NSScrollView *)view documentView];
          [text setString: editors == 0 ? @"Friendly message\nSecond line" : @"Please pay promptly."];
          editors++;
        }
      if ([view isKindOfClass: [NSButton class]] && [[(NSButton *)view title] isEqual: @"Send reminders through Apple Mail"])
        { [(NSButton *)view setState: NSOnState]; toggles++; }
    }
  Check (editors == 2 && toggles == 1, @"Separate multiline messages and opt-in checkbox");
  [self acceptDialog: nil];
}
@end
@interface CLTestInvoiceEditor : CLInvoiceEditor
- (void) inspectEditor: (NSTimer *)timer;
- (void) inspectLine: (NSTimer *)timer;
@end
@implementation CLTestInvoiceEditor
- (void) inspectEditor: (NSTimer *)timer
{
  NSString *mode = [timer userInfo];
  Check ([_fields count] == 15, @"Invoice editor exposes invoice, client and business fields");
  Check ([[_fields objectForKey: @"date"] isKindOfClass: [CLDateField class]]
    && [[_fields objectForKey: @"dueDate"] isKindOfClass: [CLDateField class]], @"Editor dates support calendar and manual entry");
  [[_fields objectForKey: @"client_name"] setStringValue: @"Edited in UI"];
  [[_fields objectForKey: @"date"] setStringValue: @"2024-02-15"];
  [self controlTextDidChange: [NSNotification notificationWithName: NSControlTextDidChangeNotification object: [_fields objectForKey: @"date"]]];
  Check ([[[_fields objectForKey: @"dueDate"] stringValue] isEqual: @"2024-03-16"], @"Edited issue date recalculates due from invoice terms");
  if ([mode isEqual: @"cancel"]) { [self cancel: nil]; return; }
  {
    NSTimer *lineTimer = [NSTimer timerWithTimeInterval: 0.1 target: self selector: @selector(inspectLine:) userInfo: nil repeats: NO];
    [[NSRunLoop currentRunLoop] addTimer: lineTimer forMode: NSModalPanelRunLoopMode];
    [_table selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
    [self editLine: nil];
  }
  [self save: nil];
}
- (void) inspectLine: (NSTimer *)timer
{
  Check ([[_lineFields objectForKey: @"date"] isKindOfClass: [CLDateField class]]
    && [[_lineFields objectForKey: @"endDate"] isKindOfClass: [CLDateField class]], @"Line service dates have calendar controls");
  [[_lineFields objectForKey: @"description"] setString: @"Edited services"];
  [[_lineFields objectForKey: @"hours"] setStringValue: @"2"];
  [self acceptLine: nil];
}
@end
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  CLLedger *ledger;
  CLTestController *controller;
  NSString *cid;
  NSString *other;
  NSDictionary *form;
  [NSApplication sharedApplication];
  ledger = [[CLLedger alloc] initWithPath: [directory stringByAppendingPathComponent: @"Ledger.plist"] error: NULL];
  [ledger saveClient: nil name: @"Client" email: @"client@example.test" address: @"" rate: @"999" error: NULL];
  cid = [[[ledger clients] lastObject] objectForKey: @"id"];
  [ledger saveTask: nil client: cid name: @"Design" rate: @"150" error: NULL];
  [ledger saveTask: nil client: cid name: @"Support" rate: @"75" error: NULL];
  [ledger saveTask: nil client: cid name: @"Archived" rate: @"300" error: NULL];
  [ledger toggleTaskArchived: [[[ledger tasksForClient: cid includeArchived: YES] lastObject] objectForKey: @"id"] error: NULL];
  [ledger saveClient: nil name: @"Other" email: @"" address: @"" rate: @"10" error: NULL];
  other = [[[ledger clients] lastObject] objectForKey: @"id"];
  [ledger saveTask: nil client: other name: @"Other client task" rate: @"1" error: NULL];
  controller = [[CLTestController alloc] initWithLedger: ledger];
  [controller verifyTasks];
  [controller verifyCalendar];
  [controller verifyIssuedForm];
  {
    NSTimer *timer = [NSTimer timerWithTimeInterval: 0.1 target: controller selector: @selector(inspectForm:) userInfo: nil repeats: NO];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
  }
  form = [controller editForm: @"Reminder UI test (no mail sent)"
    labels: [NSArray arrayWithObjects: @"Automatic email", @"Days before due", @"Payment reminder", @"Overdue reminder", nil]
    values: [NSArray arrayWithObjects: @"no", @"3", @"", @"", nil]];
  Check ([[form objectForKey: @"Automatic email"] isEqual: @"yes"], @"Checkbox saved as enabled");
  Check ([[form objectForKey: @"Payment reminder"] isEqual: @"Friendly message\nSecond line"], @"Multiline message preserved");
  Check ([[form objectForKey: @"Overdue reminder"] isEqual: @"Please pay promptly."], @"Overdue message saved separately");
  {
    CLTestInvoiceEditor *editor;
    NSTimer *timer;
    NSDictionary *invoice;
    [ledger invoiceClient: cid hours: @"1" tax: @"0" dueDate: @"2099-01-01" error: NULL];
    invoice = [[ledger invoices] lastObject];
    editor = [[CLTestInvoiceEditor alloc] initWithLedger: ledger invoice: invoice];
    timer = [NSTimer timerWithTimeInterval: 0.1 target: editor selector: @selector(inspectEditor:) userInfo: @"cancel" repeats: NO];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
    Check (![editor run], @"Cancel exits editor without saving");
    Check ([[[invoice objectForKey: @"client"] objectForKey: @"name"] isEqual: @"Client"], @"Cancel does not alter invoice");
    [editor release];
    editor = [[CLTestInvoiceEditor alloc] initWithLedger: ledger invoice: invoice];
    timer = [NSTimer timerWithTimeInterval: 0.1 target: editor selector: @selector(inspectEditor:) userInfo: @"save" repeats: NO];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
    Check ([editor run], @"Save editor commits changes");
    Check ([[[invoice objectForKey: @"client"] objectForKey: @"name"] isEqual: @"Edited in UI"], @"Client name edit saved from UI");
    Check ([[invoice objectForKey: @"total"] intValue] == 199800, @"Edited hours recalculate total through UI");
    [editor release];
  }
  [controller release]; [ledger release];
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: %u invoice/reminder UI checks (no mail sent)", checks);
  [pool drain];
  return 0;
}
