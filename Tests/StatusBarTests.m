#import <Cocoa/Cocoa.h>
#import "CLAppController.h"
#import "CLLedger.h"

static unsigned int checks;
static void Check (BOOL ok, NSString *message)
{
  checks++;
  if (!ok) { NSLog (@"FAIL: %@", message); exit (1); }
}

@interface CLAppController (StatusTests)
- (void) setupStatusItem;
- (void) updateStatusItem: (id)sender;
- (void) menuNeedsUpdate: (NSMenu *)menu;
- (void) startStatusTimer: (id)sender;
- (void) showMainWindow: (id)sender;
@end

@interface CLStatusTestController : CLAppController
- (id) initWithLedger: (CLLedger *)ledger;
- (NSMenu *) statusMenu;
- (void) verifyRunning: (BOOL)running;
- (void) closeWindow;
- (BOOL) windowVisible;
@end
@implementation CLStatusTestController
- (id) initWithLedger: (CLLedger *)ledger
{
  self = [super init];
  if (self != nil)
    {
      _ledger = [ledger retain];
      _window = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, 200, 100)
        styleMask: NSTitledWindowMask | NSClosableWindowMask backing: NSBackingStoreBuffered defer: NO];
      [_window setReleasedWhenClosed: NO];
      [self setupStatusItem];
    }
  return self;
}
- (void) refresh { [self updateStatusItem: nil]; }
- (void) showError: (NSString *)error { Check (error == nil, error); }
- (NSDictionary *) editForm: (NSString *)title labels: (NSArray *)labels values: (NSArray *)values
{
  return [NSDictionary dictionaryWithObject: @"Menu bar work" forKey: @"Description"];
}
- (NSMenu *) statusMenu { return [_statusItem menu]; }
- (void) closeWindow { [_window close]; }
- (BOOL) windowVisible { return [_window isVisible]; }
- (void) verifyRunning: (BOOL)running
{
  [self updateStatusItem: nil];
  Check ([_statusStop isEnabled] == running, @"Stop availability follows timer");
  Check ([_statusStart isEnabled] == (!running && [[_ledger clients] count] > 0), @"Start availability follows timer and clients");
  Check ([[[_statusItem button] title] containsString: @":"] == running, @"Elapsed time appears while running");
  if (running) Check ([[_statusSummary title] containsString: @"Client"], @"Menu identifies running client");
}
@end

int main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"Ledger.plist"];
  CLLedger *ledger;
  CLLedger *reopened;
  CLStatusTestController *controller;
  NSString *clientID;
  NSMenu *menu, *taskMenu;
  NSMenuItem *start;
  [NSApplication sharedApplication];
  ledger = [[CLLedger alloc] initWithPath: path error: NULL];
  Check (ledger != nil, @"Temporary ledger opens");
  controller = [[CLStatusTestController alloc] initWithLedger: ledger];
  menu = [controller statusMenu];
  [controller menuNeedsUpdate: menu];
  [controller verifyRunning: NO];
  [ledger saveClient: nil name: @"Client" email: @"" address: @"" rate: @"50" error: NULL];
  clientID = [[[ledger clients] lastObject] objectForKey: @"id"];
  [ledger saveTask: nil client: clientID name: @"Design" rate: @"90" error: NULL];
  [ledger saveTask: nil client: clientID name: @"Archived" rate: @"10" error: NULL];
  [ledger toggleTaskArchived: [[[ledger tasksForClient: clientID includeArchived: YES] lastObject] objectForKey: @"id"] error: NULL];
  [controller menuNeedsUpdate: menu];
  start = [menu itemAtIndex: 2];
  taskMenu = [[[start submenu] itemAtIndex: 0] submenu];
  Check ([taskMenu numberOfItems] == 2, @"Offers default rate and active task, excludes archived task");
  [controller showMainWindow: nil];
  [controller closeWindow];
  Check (![controller windowVisible] && ![controller applicationShouldTerminateAfterLastWindowClosed: NSApp], @"Closing window keeps app alive");
  [controller startStatusTimer: [taskMenu itemAtIndex: 1]];
  Check ([[[ledger timer] objectForKey: @"taskName"] isEqual: @"Design"], @"Menu selection starts intended task");
  Check ([[[ledger timer] objectForKey: @"rate"] intValue] == 9000, @"Menu timer snapshots task rate");
  Check (![controller windowVisible], @"Starting task keeps main window closed");
  [controller verifyRunning: YES];
  reopened = [[CLLedger alloc] initWithPath: path error: NULL];
  Check ([reopened timer] != nil, @"Menu timer persists across restart");
  [reopened release];
  [controller startStatusTimer: [taskMenu itemAtIndex: 0]];
  Check ([[[ledger timer] objectForKey: @"taskName"] isEqual: @"Design"], @"Second start cannot replace live timer");
  [controller stopTimer: nil];
  Check ([ledger timer] == nil && [[ledger entries] count] == 1, @"Stopping records time once");
  [controller verifyRunning: NO];
  [controller startStatusTimer: [taskMenu itemAtIndex: 0]];
  Check ([[[ledger timer] objectForKey: @"description"] isEqual: @"Menu bar work"], @"Default-rate timer uses entered description");
  [controller stopTimer: nil];
  [controller showMainWindow: nil];
  Check ([controller windowVisible], @"Open menu action restores closed window");
  [controller applicationWillTerminate: nil];
  [controller closeWindow];
  [controller release];
  [ledger release];
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: %u menu bar checks", checks);
  [pool drain];
  return 0;
}
