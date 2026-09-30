#import "CLDateField.h"
#import "CLLedger.h"

static NSDateFormatter *
CLDateFieldFormatter (void)
{
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier: NSGregorianCalendar] autorelease];
  [calendar setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setCalendar: calendar];
  [formatter setTimeZone: [calendar timeZone]];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  [formatter setLenient: NO];
  return formatter;
}

@implementation CLDateField
+ (CLDateField *) fieldInView: (NSView *)parent value: (NSString *)value frame: (NSRect)frame
{
  CLDateField *field = [[[self alloc] initWithFrame: NSMakeRect (frame.origin.x, frame.origin.y, frame.size.width - 34, frame.size.height)] autorelease];
  NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect (NSMaxX (frame) - 30, frame.origin.y, 30, frame.size.height)] autorelease];
  [field setStringValue: value ?: @""];
  [field setToolTip: @"Type a date as YYYY-MM-DD, or use the calendar button."];
  [[field cell] setPlaceholderString: @"YYYY-MM-DD"];
  [button setTitle: @"▦"];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setToolTip: @"Choose a date from the calendar"];
#ifdef __APPLE__
  [button setAccessibilityLabel: @"Choose date from calendar"];
#endif
  [button setTarget: field];
  [button setAction: @selector(showCalendar:)];
  [parent addSubview: field];
  [parent addSubview: button];
  return field;
}

- (void) showCalendar: (id)sender
{
  NSDateFormatter *formatter = CLDateFieldFormatter ();
  NSDate *date = [formatter dateFromString: [self stringValue]];
  NSButton *button;
  if (_calendarPanel != nil) return;
  if (date == nil || ![[formatter stringFromDate: date] isEqual: [self stringValue]])
    date = [formatter dateFromString: [CLLedger today]];
  /* End text editing before opening a nested modal picker. */
  [[self window] makeFirstResponder: nil];
  _calendarPanel = [[NSPanel alloc] initWithContentRect: NSMakeRect (0, 0, 320, 270)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [_calendarPanel setTitle: @"Choose date"];
  [_calendarPanel setReleasedWhenClosed: NO];
  [_calendarPanel setWorksWhenModal: YES];
  _calendarPicker = [[[NSDatePicker alloc] initWithFrame: NSMakeRect (20, 66, 280, 190)] autorelease];
  [_calendarPicker setDatePickerStyle: NSClockAndCalendarDatePickerStyle];
  [_calendarPicker setDatePickerElements: NSYearMonthDayDatePickerElementFlag];
  [_calendarPicker setCalendar: [formatter calendar]];
  [_calendarPicker setTimeZone: [formatter timeZone]];
  [_calendarPicker setDateValue: date];
  [[_calendarPanel contentView] addSubview: _calendarPicker];
  button = [[[NSButton alloc] initWithFrame: NSMakeRect (14, 16, 84, 32)] autorelease];
  [button setTitle: @"Today"]; [button setBezelStyle: NSRoundedBezelStyle];
  [button setTarget: self]; [button setAction: @selector(selectToday:)];
  [[_calendarPanel contentView] addSubview: button];
  button = [[[NSButton alloc] initWithFrame: NSMakeRect (108, 16, 94, 32)] autorelease];
  [button setTitle: @"Cancel"]; [button setBezelStyle: NSRoundedBezelStyle];
  [button setTarget: self]; [button setAction: @selector(cancelCalendar:)]; [button setKeyEquivalent: @"\033"];
  [[_calendarPanel contentView] addSubview: button];
  button = [[[NSButton alloc] initWithFrame: NSMakeRect (212, 16, 94, 32)] autorelease];
  [button setTitle: @"Choose"]; [button setBezelStyle: NSRoundedBezelStyle];
  [button setTarget: self]; [button setAction: @selector(chooseDate:)]; [button setKeyEquivalent: @"\r"];
  [[_calendarPanel contentView] addSubview: button];
  [_calendarPanel center];
  [NSApp runModalForWindow: _calendarPanel];
  [_calendarPanel orderOut: nil];
  [_calendarPanel release]; _calendarPanel = nil; _calendarPicker = nil;
  [[self window] makeFirstResponder: self];
}

- (void) chooseDate: (id)sender
{
  if (_calendarPicker == nil) return;
  [self setStringValue: [CLDateFieldFormatter () stringFromDate: [_calendarPicker dateValue]]];
  /* Match manual editing so invoice due dates and period summaries update. */
  if ([[self delegate] respondsToSelector: @selector(controlTextDidChange:)])
    [[self delegate] controlTextDidChange: [NSNotification notificationWithName: NSControlTextDidChangeNotification object: self]];
  if ([self action] != NULL) [self sendAction: [self action] to: [self target]];
  [NSApp stopModal];
}

- (void) selectToday: (id)sender
{
  [_calendarPicker setDateValue: [CLDateFieldFormatter () dateFromString: [CLLedger today]]];
}

- (void) cancelCalendar: (id)sender
{
  [NSApp stopModal];
}
@end
