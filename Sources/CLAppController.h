#import <AppKit/AppKit.h>
@class CLLedger, CLInvoiceMailer;

/** Native application controller. Uses classic AppKit controls, explicit
 * reference counting and target/action; no nibs or Objective-C 2 features. */
@interface CLAppController : NSObject
{
  CLLedger *_ledger;
  NSTableView *_financeTable;
  NSPopUpButton *_financeMode;
  NSWindow *_window;
  NSTabView *_workspaceTabs;
  NSTableView *_dashboardTable;
  NSTableView *_reportTable;
  NSPopUpButton *_dashboardPeriod;
  NSPopUpButton *_dashboardCurrency;
  NSPopUpButton *_reportCurrency;
  NSPopUpButton *_reportMode;
  NSTextField *_reportStart;
  NSTextField *_reportEnd;
  NSTextField *_reportNote;
  NSTextField *_dashboardNote;
  NSArray *_dashboardCards;
  NSDictionary *_dashboardReport;
  NSDictionary *_reportData;
  NSTableView *_clientsTable;
  NSTableView *_timeTable;
  NSTableView *_tasksTable;
  NSPopUpButton *_tasksClient;
  NSPopUpButton *_timeTask;
  NSPopUpButton *_periodChoice;
  NSPopUpButton *_entryMode;
  NSButton *_nonbillableTime;
  NSTextField *_periodDate;
  NSTextField *_periodLabel;
  NSTableView *_invoicesTable;
  NSPopUpButton *_timeClient;
  NSPopUpButton *_invoiceClient;
  NSPopUpButton *_invoiceTask;
  NSTextField *_taskField;
  NSTextField *_timerLabel;
  NSTextField *_summaryLabel;
  NSTextField *_invoiceHours;
  NSTextField *_timesheetTotal;
  NSTextField *_invoiceRate;
  NSTextField *_taxField;
  NSTextField *_dueField;
  NSTextField *_issuedField;
  NSTextField *_dialogIssuedField;
  NSTextField *_dialogDueField;
  NSString *_dialogInvoiceClientID;
  NSMutableDictionary *_businessFields;
  NSData *_businessLogoData;
  NSImageView *_businessLogoPreview;
#ifdef __APPLE__
  NSStatusItem *_statusItem;
  NSMenuItem *_statusSummary;
  NSMenuItem *_statusStart;
  NSMenuItem *_statusStop;
  NSMenuItem *_statusDock;
  NSTimer *_statusPulse;
#endif
  NSTimer *_pulse;
  NSTimer *_reminderPulse;
  CLInvoiceMailer *_mailer;
  BOOL _mailStarting;
  BOOL _reminderPromptActive;
  NSMutableDictionary *_reminderSnoozes;
  NSString *_mailInvoiceID;
  NSString *_mailStage;
  NSTextField *_mailStatus;
  id _backgroundActivity;
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
/** Refresh task choices when the time-entry client changes. */
- (void) timeClientChanged: (id)sender;
/** Refresh the selected client's task list. */
- (void) tasksClientChanged: (id)sender;
/** Add a task and hourly rate for the selected client. */
- (void) addTask: (id)sender;
/** Edit a task name/rate without changing historical time. */
- (void) editTask: (id)sender;
/** Archive or restore the selected task. */
- (void) archiveTask: (id)sender;
/** Update the date-range explanation for daily, weekly or monthly entry. */
- (void) periodChanged: (id)sender;
/** Add a day/week/month total or open the daily timesheet for that period. */
- (void) addTime: (id)sender;
/** Delete selected unbilled time after confirmation. */
- (void) deleteTime: (id)sender;
/** Edit the selected uninvoiced time entry. */
- (void) editTime: (id)sender;
/** Start timing the selected client and description. */
- (void) startTimer: (id)sender;
/** Stop and record the current timer. */
- (void) stopTimer: (id)sender;
/** Update the displayed billing rate. */
- (void) invoiceClientChanged: (id)sender;
/** Convert the selected timesheet client's unbilled time to an invoice. */
- (void) invoiceTimesheet: (id)sender;
- (void) controlTextDidChange: (NSNotification *)notification;
- (void) invoiceTaskChanged: (id)sender;
- (void) editClientReminders: (id)sender;
- (void) checkReminders: (id)sender;
- (void) reviewReminder: (id)sender;
- (BOOL) applicationShouldHandleReopen: (NSApplication *)application hasVisibleWindows: (BOOL)visible;
/** Open an Apple Mail draft with a payment message and invoice PDF attachment. */
- (void) emailInvoice: (id)sender;
/** Create an invoice from a raw number of hours. */
- (void) createInvoice: (id)sender;
- (void) editInvoice: (id)sender;
/** Display the selected invoice in a printable preview. */
- (void) previewInvoice: (id)sender;
/** Print the selected invoice with the system print panel. */
- (void) printInvoice: (id)sender;
/** Warn and confirm before permanently deleting the selected invoice. */
- (void) deleteInvoice: (id)sender;
/** Mark an invoice paid or unpaid. */
- (void) togglePaid: (id)sender;
- (void) chooseBusinessLogo: (id)sender;
- (void) removeBusinessLogo: (id)sender;
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
