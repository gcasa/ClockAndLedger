#import <AppKit/AppKit.h>
#import "CLAppController.h"
#import "CLLedger.h"

static void Check (BOOL ok, NSString *label)
{
  if (!ok) { NSLog (@"FAIL: %@", label); exit (1); }
}

/* Refuse the journal write so approval tests can never reach Apple Mail. */
@interface CLReminderTestLedger : CLLedger
{
@public
  NSUInteger attempts;
}
@end
@implementation CLReminderTestLedger
- (BOOL) beginReminder: (NSString *)identifier stage: (NSString *)stage onDate: (NSString *)date error: (NSString **)error
{
  attempts++;
  if (error != NULL) *error = @"Simulated persistence failure";
  return NO;
}
@end

@interface CLReminderTestController : CLAppController
{
@public
  NSUInteger prompts;
  BOOL approve;
}
- (id) initWithLedger: (CLLedger *)ledger;
- (void) expireSnoozes;
@end
@implementation CLReminderTestController
- (id) initWithLedger: (CLLedger *)ledger
{
  self = [super init];
  if (self != nil) _ledger = [ledger retain];
  return self;
}
- (BOOL) confirmReminderForInvoice: (NSDictionary *)invoice stage: (NSString *)stage
{
  prompts++;
  Check (prompts < 5, @"No recursive prompts");
  [self checkReminders: nil];
  return approve;
}
- (void) expireSnoozes
{
  NSString *key;
  for (key in [_reminderSnoozes allKeys])
    [_reminderSnoozes setObject: [NSDate distantPast] forKey: key];
}
@end

int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  CLReminderTestLedger *ledger = [[CLReminderTestLedger alloc] initWithPath: [directory stringByAppendingPathComponent: @"Ledger.plist"] error: NULL];
  NSMutableDictionary *business = [NSMutableDictionary dictionaryWithDictionary: [ledger business]];
  NSString *clientID;
  CLReminderTestController *controller;
  [NSApplication sharedApplication];
  [business setObject: @"sender@example.test" forKey: @"email"];
  Check ([ledger saveBusiness: business error: NULL], @"Save sender");
  Check ([ledger saveClient: nil name: @"Client" email: @"client@example.test" address: @"" rate: @"100" error: NULL], @"Save client");
  clientID = [[[ledger clients] lastObject] objectForKey: @"id"];
  Check ([ledger invoiceClient: clientID hours: @"1" tax: @"0" dueDate: [CLLedger today] error: NULL], @"Create due invoice");
  Check ([ledger saveRemindersForClient: clientID enabled: YES daysBefore: @"3" message: @"" overdueMessage: @"" error: NULL], @"Enable reminders");
  controller = [[CLReminderTestController alloc] initWithLedger: ledger];
  [controller checkReminders: nil];
  Check (controller->prompts == 1 && ledger->attempts == 0, @"Decline never starts a send attempt");
  Check ([[[[ledger invoices] lastObject] objectForKey: @"reminders"] count] == 0, @"Decline does not change reminder history");
  [controller checkReminders: nil];
  Check (controller->prompts == 1, @"Snooze suppresses the next minute's alert");
  [controller expireSnoozes];
  controller->approve = YES;
  [controller checkReminders: nil];
  Check (controller->prompts == 2 && ledger->attempts == 1, @"Expired snooze prompts again; explicit approval reaches journal");
  [controller release];
  [ledger release];
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: reminder approval, reentrancy, snooze and persistence-failure checks (no mail sent)");
  [pool drain];
  return 0;
}
