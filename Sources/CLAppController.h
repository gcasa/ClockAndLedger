#import <AppKit/AppKit.h>
@class CLLedger;

/** Native application controller. Uses classic AppKit controls, explicit
 * reference counting and target/action; no nibs or Objective-C 2 features. */
@interface CLAppController : NSObject
{
  CLLedger *_ledger;
  NSWindow *_window;
  NSTableView *_clientsTable;
  NSTableView *_timeTable;
  NSTableView *_invoicesTable;
  NSPopUpButton *_timeClient;
  NSPopUpButton *_invoiceClient;
  NSTextField *_taskField;
  NSTextField *_timerLabel;
  NSTextField *_summaryLabel;
  NSTextField *_taxField;
  NSTextField *_dueField;
  NSMutableDictionary *_businessFields;
  NSTimer *_pulse;
  NSPanel *_dialog;
  BOOL _dialogAccepted;
  NSDistributedLock *_lock;
  BOOL _ownsLock;
}
/** Initialize UI and ledger after the application has launched. */
- (void) applicationDidFinishLaunching: (NSNotification *)notification;
/** Release the single-writer lock when the application quits. */
- (void) applicationWillTerminate: (NSNotification *)notification;
/** Keep running timers durable when the last window is closed. */
- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)application;
/** Add a new client using a modal editor. */
- (void) addClient: (id)sender;
/** Edit the selected client's contact details and default rate. */
- (void) editClient: (id)sender;
/** Delete an unused client after confirmation. */
- (void) deleteClient: (id)sender;
/** Add a dated manual time entry. */
- (void) addTime: (id)sender;
/** Delete selected unbilled time after confirmation. */
- (void) deleteTime: (id)sender;
/** Start timing the selected client and description. */
- (void) startTimer: (id)sender;
/** Stop and record the current timer. */
- (void) stopTimer: (id)sender;
/** Create an invoice for the chosen client's unbilled time. */
- (void) createInvoice: (id)sender;
/** Display the selected invoice in a printable preview. */
- (void) previewInvoice: (id)sender;
/** Print the selected invoice with the system print panel. */
- (void) printInvoice: (id)sender;
/** Mark an invoice paid or unpaid. */
- (void) togglePaid: (id)sender;
/** Save the business form. */
- (void) saveBusiness: (id)sender;
/** Choose an export, review its records and save an atomic QuickBooks import. */
- (void) importQuickBooks: (id)sender;
/** Assign a rate and billability to imported time that needs review. */
- (void) reviewImportedTime: (id)sender;
/** Copy the current on-disk ledger to a user-selected backup path. */
- (void) backupLedger: (id)sender;
/** Update the timer display once per second. */
- (void) tick: (id)sender;
/** Accept the current editor. */
- (void) acceptDialog: (id)sender;
/** Cancel the current editor. */
- (void) cancelDialog: (id)sender;
@end
