#import <AppKit/AppKit.h>

/** ISO date text entry with an adjacent calendar button. Manual input remains
 * untouched until the user explicitly chooses a date; existing validation applies. */
@interface CLDateField : NSTextField
{
  NSPanel *_calendarPanel;
  NSDatePicker *_calendarPicker;
}
+ (CLDateField *) fieldInView: (NSView *)parent value: (NSString *)value frame: (NSRect)frame;
- (void) showCalendar: (id)sender;
- (void) chooseDate: (id)sender;
- (void) cancelCalendar: (id)sender;
- (void) selectToday: (id)sender;
@end
