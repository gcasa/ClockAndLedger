#import <Foundation/Foundation.h>
#import "CLLedger.h"
static int checks;
static void Check (BOOL ok, NSString *label) { checks++; if (!ok) { NSLog (@"FAIL: %@", label); exit (1); } }
int main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [dir stringByAppendingPathComponent: @"ledger.plist"], *error = nil;
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: &error];
  NSMutableDictionary *account = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"Checking", @"name", @"Example Bank", @"bank", @"1234", @"number", @"5678", @"routing", @"USD", @"currency", @"100.00", @"openingBalance", @"Baseline before recorded transactions", @"notes", nil];
  NSMutableDictionary *payment, *expense, *draft;
  NSString *aid, *iid, *pid, *eid;
  NSDictionary *invoice;
  Check ([ledger saveAccount: nil values: account error: &error], @"Save account"); aid = [[[[ledger accounts] lastObject] objectForKey: @"id"] copy];
  Check ([[ledger balanceForAccount: aid] longLongValue] == 10000, @"Opening balance");
  Check (![ledger saveAccount: nil values: account error: &error], @"Reject duplicate account names");
  Check ([[CLLedger money: [NSNumber numberWithInt: -51]] isEqual: @"-0.51"], @"Negative balance formatting");
  Check ([ledger saveClient: nil name: @"Client" email: @"client@example.test" address: @"" rate: @"100" error: &error], @"Client fixture");
  Check ([ledger invoiceClient: [[[ledger clients] lastObject] objectForKey: @"id"] hours: @"1" tax: @"0" dueDate: @"2099-01-01" error: &error], @"Invoice fixture");
  invoice = [[ledger invoices] lastObject]; iid = [[invoice objectForKey: @"id"] copy];
  payment = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"2026-09-30", @"date", aid, @"accountID", @"60", @"amount", @"Deposit", @"reference", nil];
  Check ([ledger savePayment: nil invoice: iid values: payment error: &error], @"Record partial payment");
  pid = [[[[invoice objectForKey: @"payments"] lastObject] objectForKey: @"id"] copy];
  Check (![[invoice objectForKey: @"paid"] boolValue], @"Underpayment remains unpaid");
  Check ([[CLLedger balanceForInvoice: invoice] longLongValue] == 4000, @"Remaining amount");
  Check ([[ledger balanceForAccount: aid] longLongValue] == 16000, @"Balance uses actual receipt");
  Check ([[ledger paymentMessageForInvoice: invoice onDate: @"2026-09-30"] rangeOfString: @"40.00"].location != NSNotFound, @"Reminder requests remaining amount");
  Check (![ledger setInvoice: iid paid: YES error: &error], @"Prevent status bypass");
  Check (![ledger deleteInvoice: iid error: &error], @"Protect invoice with payments");
  [payment setObject: @"110" forKey: @"amount"];
  Check ([ledger savePayment: pid invoice: iid values: payment error: &error], @"Correct payment to overpayment");
  Check ([[invoice objectForKey: @"paid"] boolValue], @"Overpayment marks invoice paid");
  Check ([[CLLedger balanceForInvoice: invoice] longLongValue] == 0 && [[CLLedger receivedForInvoice: invoice] longLongValue] == 11000, @"Retain actual overpaid amount");
  Check ([[ledger balanceForAccount: aid] longLongValue] == 21000, @"No duplicate after editing payment");
  draft = [NSMutableDictionary dictionaryWithDictionary: [ledger editValuesForInvoice: invoice]];
  [draft setObject: @"EUR" forKey: @"currency"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Prevent currency conversion of booked payments");
  [draft setObject: @"USD" forKey: @"currency"]; [draft setObject: @"Unpaid" forKey: @"status"];
  Check (![ledger updateInvoice: iid values: draft error: &error], @"Invoice editor cannot clear payment history");
  [draft setObject: @"Paid" forKey: @"status"]; [draft setObject: @"Updated client" forKey: @"client_name"];
  Check ([ledger updateInvoice: iid values: draft error: &error], @"Other invoice fields remain editable");
  expense = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"2026-09-30", @"date", @"Office shop", @"vendor", @"Supplies", @"category", @"Printer paper for business", @"notes", @"Card 123", @"reference", aid, @"accountID", @"25.50", @"amount", [@"Receipt fixture" dataUsingEncoding: NSUTF8StringEncoding], @"receiptData", @"receipt.pdf", @"receiptName", nil];
  Check ([ledger saveExpense: nil values: expense error: &error], @"Save expense and receipt"); eid = [[[[ledger expenses] lastObject] objectForKey: @"id"] copy];
  Check ([[ledger balanceForAccount: aid] longLongValue] == 18450, @"Expenses reduce balance");
  [expense setObject: @"35.50" forKey: @"amount"];
  Check ([ledger saveExpense: eid values: expense error: &error], @"Edit expense");
  Check ([[ledger balanceForAccount: aid] longLongValue] == 17450, @"Expense edit replaces amount");
  [payment setObject: @"bad-date" forKey: @"date"];
  Check (![ledger savePayment: nil invoice: iid values: payment error: &error], @"Reject invalid dates");
  [payment setObject: @"2026-09-30" forKey: @"date"]; [payment setObject: @"0" forKey: @"amount"];
  Check (![ledger savePayment: nil invoice: iid values: payment error: &error], @"Reject zero payments");
  [payment setObject: @"10" forKey: @"amount"]; [payment setObject: @"missing" forKey: @"accountID"];
  Check (![ledger savePayment: nil invoice: iid values: payment error: &error], @"Reject unknown accounts");
  [account setObject: @"Euro" forKey: @"name"]; [account setObject: @"EUR" forKey: @"currency"];
  Check ([ledger saveAccount: nil values: account error: &error], @"Separate currency account");
  [payment setObject: [[[ledger accounts] lastObject] objectForKey: @"id"] forKey: @"accountID"];
  Check (![ledger savePayment: nil invoice: iid values: payment error: &error], @"Reject mismatched payment currency");
  [payment setObject: @"" forKey: @"accountID"];
  Check ([ledger savePayment: nil invoice: iid values: payment error: &error], @"Unassigned payment allowed");
  Check ([[ledger balanceForAccount: aid] longLongValue] == 17450, @"Unassigned payment never enters a bank account");
  [ledger release]; ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil, @"Reopen bookkeeping ledger");
  Check ([[[[ledger expenses] lastObject] objectForKey: @"receiptData"] isEqual: [expense objectForKey: @"receiptData"]], @"Receipt survives reopen");
  Check ([[ledger balanceForAccount: aid] longLongValue] == 17450, @"Balance survives reopen");
  Check ([ledger deletePayment: pid invoice: iid error: &error], @"Remove mistaken payment");
  Check ([[CLLedger balanceForInvoice: [[ledger invoices] lastObject]] longLongValue] == 9000, @"Deletion reopens balance due");
  Check ([ledger deleteExpense: eid error: &error], @"Remove expense");
  Check ([[ledger balanceForAccount: aid] longLongValue] == 10000, @"Removed transactions restore opening balance");
  {
    NSData *before = [NSData dataWithContentsOfFile: path];
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath: path withIntermediateDirectories: NO attributes: nil error: NULL];
    Check (![ledger saveExpense: nil values: expense error: &error], @"Write failure reported");
    Check ([[ledger expenses] count] == 0 && [[ledger balanceForAccount: aid] longLongValue] == 10000, @"Atomic rollback restores balances");
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL]; [before writeToFile: path atomically: YES];
  }
  {
    CLLedger *legacy = [[CLLedger alloc] initWithPath: [dir stringByAppendingPathComponent: @"legacy.plist"] error: NULL];
    NSDictionary *bill; NSString *billID;
    NSMutableDictionary *edit;
    [legacy saveClient: nil name: @"Legacy" email: @"" address: @"" rate: @"100" error: NULL];
    [legacy invoiceClient: [[[legacy clients] lastObject] objectForKey: @"id"] hours: @"1" tax: @"0" dueDate: @"2099-01-01" error: NULL];
    bill = [[legacy invoices] lastObject]; billID = [bill objectForKey: @"id"];
    Check ([legacy setInvoice: billID paid: YES error: &error], @"Legacy paid invoice fixture");
    Check ([[CLLedger receivedForInvoice: bill] longLongValue] == 10000, @"Legacy paid invoices retain assumed full receipt");
    [payment setObject: @"80" forKey: @"amount"];
    Check ([legacy savePayment: nil invoice: billID values: payment error: &error], @"Assign legacy actual payment");
    Check ([[CLLedger receivedForInvoice: bill] longLongValue] == 8000 && [[CLLedger balanceForInvoice: bill] longLongValue] == 2000, @"Legacy assignment replaces assumed receipt");
    [payment setObject: @"30" forKey: @"amount"];
    Check ([legacy savePayment: nil invoice: billID values: payment error: &error], @"Add second payment");
    Check ([[bill objectForKey: @"paid"] boolValue] && [[CLLedger receivedForInvoice: bill] longLongValue] == 11000, @"Multiple payments accumulate");
    edit = [NSMutableDictionary dictionaryWithDictionary: [legacy editValuesForInvoice: bill]];
    { NSMutableDictionary *line = [NSMutableDictionary dictionaryWithDictionary: [[edit objectForKey: @"lines"] objectAtIndex: 0]];
      [line setObject: @"2" forKey: @"hours"]; [edit setObject: [NSArray arrayWithObject: line] forKey: @"lines"]; }
    Check ([legacy updateInvoice: billID values: edit error: &error], @"Edit total after payment");
    Check (![[bill objectForKey: @"paid"] boolValue] && [[CLLedger balanceForInvoice: bill] longLongValue] == 9000, @"Increased total restores remaining balance without altering receipts");
    [legacy release];
  }
  {
    NSMutableDictionary *bad = [NSPropertyListSerialization propertyListWithData: [NSData dataWithContentsOfFile: path] options: NSPropertyListMutableContainersAndLeaves format: NULL error: NULL];
    [[[[bad objectForKey: @"invoices"] lastObject] objectForKey: @"payments"] addObject: @"bad"];
    [bad writeToFile: path atomically: YES];
    Check ([[[CLLedger alloc] initWithPath: path error: &error] autorelease] == nil, @"Reject corrupt payment records");
  }
  [ledger release]; [aid release]; [iid release]; [pid release]; [eid release];
  [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
  NSLog (@"PASS: %d finance checks", checks); [pool drain]; return 0;
}
