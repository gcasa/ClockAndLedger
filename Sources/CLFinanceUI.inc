- (NSArray *) financeRows
{
  NSInteger mode = [_financeMode indexOfSelectedItem];
  NSMutableArray *rows = [NSMutableArray array];
  NSDictionary *invoice, *payment;
  if (mode == 0) return [_ledger accounts];
  if (mode == 1) return [_ledger expenses];
  for (invoice in [_ledger invoices])
    {
      for (payment in [invoice objectForKey: @"payments"])
        { NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary: payment];
          [row setObject: [invoice objectForKey: @"id"] forKey: @"invoiceID"];
          [row setObject: [CLLedger invoiceNumber: invoice] forKey: @"vendor"];
          [row setObject: [[invoice objectForKey: @"business"] objectForKey: @"currency"] forKey: @"currency"];
          [rows addObject: row]; }
      if (![invoice objectForKey: @"payments"] && [[invoice objectForKey: @"paid"] boolValue] && ![[invoice objectForKey: @"paymentUnverified"] boolValue])
        [rows addObject: [NSDictionary dictionaryWithObjectsAndKeys: [invoice objectForKey: @"id"], @"invoiceID", [CLLedger invoiceNumber: invoice], @"vendor", @"Unrecorded", @"date", @"Legacy paid — edit to assign", @"reference", [invoice objectForKey: @"total"], @"amount", [[invoice objectForKey: @"business"] objectForKey: @"currency"], @"currency", nil]];
    }
  return rows;
}
- (void) financeChanged: (id)sender
{
  BOOL accounts = [_financeMode indexOfSelectedItem] == 0;
  [[[_financeTable tableColumnWithIdentifier: @"amount"] headerCell] setStringValue: accounts ? @"Current balance" : @"Amount"];
  [[[_financeTable tableColumnWithIdentifier: @"vendor"] headerCell] setStringValue: accounts ? @"Bank" : ([_financeMode indexOfSelectedItem] == 1 ? @"Vendor / payee" : @"Invoice")];
  [_financeTable reloadData];
}
- (NSDictionary *) financeSelection
{
  NSArray *rows = [self financeRows]; NSInteger row = [_financeTable selectedRow];
  return row >= 0 && (NSUInteger)row < [rows count] ? [rows objectAtIndex: row] : nil;
}
- (void) editPaymentForInvoice: (NSDictionary *)invoice payment: (NSDictionary *)payment
{
  NSString *error = nil;
  NSString *amount = [CLLedger money: payment ? [payment objectForKey: @"amount"] : ([invoice objectForKey: @"payments"] == nil && [[invoice objectForKey: @"paid"] boolValue] ? [invoice objectForKey: @"total"] : [CLLedger balanceForInvoice: invoice])];
  NSArray *labels = [NSArray arrayWithObjects: @"Date", @"Amount received", @"Bank account", @"Reference / notes", nil];
  NSArray *values = [NSArray arrayWithObjects: payment ? [payment objectForKey: @"date"] : [CLLedger today], amount, [payment objectForKey: @"accountID"] ?: @"", [payment objectForKey: @"reference"] ?: @"", nil];
  NSDictionary *form;
  if (!invoice) { [self showError: @"Select an invoice first."]; return; }
  do {
    form = [self editForm: [NSString stringWithFormat: @"Payment for %@ (%@)", [CLLedger invoiceNumber: invoice], [[invoice objectForKey: @"business"] objectForKey: @"currency"]] labels: labels values: values];
    if (!form) return;
    if ([_ledger savePayment: [payment objectForKey: @"id"] invoice: [invoice objectForKey: @"id"] values: [NSDictionary dictionaryWithObjectsAndKeys: [form objectForKey: @"Date"], @"date", [form objectForKey: @"Amount received"], @"amount", [form objectForKey: @"Bank account"], @"accountID", [form objectForKey: @"Reference / notes"], @"reference", nil] error: &error]) break;
    [self showError: error]; values = [form objectsForKeys: labels notFoundMarker: @""];
  } while (YES);
  [self refresh];
}
- (void) financeAdd: (id)sender { [self financeEditRecord: nil]; }
- (void) financeEdit: (id)sender
{
  NSDictionary *record = [self financeSelection];
  if (!record) { [self showError: @"Select a record first."]; return; }
  [self financeEditRecord: record];
}
- (void) financeEditRecord: (NSDictionary *)record
{
  NSInteger mode = [_financeMode indexOfSelectedItem];
  NSArray *labels, *keys;
  NSMutableArray *values = [NSMutableArray array];
  NSDictionary *form; NSString *key, *error = nil;
  if (mode == 2)
    {
      NSDictionary *invoice;
      if (!record)
        {
          NSDictionary *choice = [self editForm: @"Record invoice payment" labels: [NSArray arrayWithObject: @"Invoice"] values: [NSArray arrayWithObject: @""]];
          if (!choice) return;
          for (invoice in [_ledger invoices]) if ([[invoice objectForKey: @"id"] isEqual: [choice objectForKey: @"Invoice"]])
            { [self editPaymentForInvoice: invoice payment: nil]; return; }
          [self showError: @"Select an invoice first."]; return;
        }
      for (invoice in [_ledger invoices]) if ([[invoice objectForKey: @"id"] isEqual: [record objectForKey: @"invoiceID"]])
        { [self editPaymentForInvoice: invoice payment: [record objectForKey: @"id"] ? record : nil]; return; }
      return;
    }
  labels = mode == 0 ? [NSArray arrayWithObjects: @"Account name", @"Bank name", @"Account number", @"Routing / IBAN", @"Currency", @"Opening balance", @"Notes", nil] : [NSArray arrayWithObjects: @"Date", @"Vendor / payee", @"Category", @"Amount paid", @"Bank account", @"Reference", @"Business purpose / notes", nil];
  keys = mode == 0 ? [NSArray arrayWithObjects: @"name", @"bank", @"number", @"routing", @"currency", @"openingBalance", @"notes", nil] : [NSArray arrayWithObjects: @"date", @"vendor", @"category", @"amount", @"accountID", @"reference", @"notes", nil];
  for (key in keys)
    { id value = [record objectForKey: key];
      if ([key isEqual: @"openingBalance"] || [key isEqual: @"amount"]) value = [CLLedger money: value ?: [NSNumber numberWithInt: 0]];
      if (!value) value = [key isEqual: @"date"] ? [CLLedger today] : ([key isEqual: @"currency"] ? [[_ledger business] objectForKey: @"currency"] : @"");
      [values addObject: value]; }
  do {
    NSMutableDictionary *updated = [NSMutableDictionary dictionary]; NSUInteger i;
    form = [self editForm: mode == 0 ? @"Bank account — opening balance before recorded transactions" : @"Company expense / payment" labels: labels values: values];
    if (!form) return;
    for (i=0; i<[keys count]; i++) [updated setObject: [form objectForKey: [labels objectAtIndex: i]] forKey: [keys objectAtIndex: i]];
    if ([record objectForKey: @"receiptData"]) { [updated setObject: [record objectForKey: @"receiptData"] forKey: @"receiptData"]; [updated setObject: [record objectForKey: @"receiptName"] forKey: @"receiptName"]; }
    if (mode == 0 ? [_ledger saveAccount: [record objectForKey: @"id"] values: updated error: &error] : [_ledger saveExpense: [record objectForKey: @"id"] values: updated error: &error]) break;
    [self showError: error]; values = [NSMutableArray arrayWithArray: [form objectsForKeys: labels notFoundMarker: @""]];
  } while (YES);
  [self refresh];
}
- (void) financeDelete: (id)sender
{
  NSDictionary *record = [self financeSelection]; NSString *error = nil;
  NSInteger mode = [_financeMode indexOfSelectedItem];
  if (!record || mode == 0) { [self showError: @"Select an expense or recorded payment. Bank accounts are retained for bookkeeping."]; return; }
  if (![record objectForKey: @"id"]) { [self showError: @"Edit this legacy payment to record its details first."]; return; }
  if (NSRunAlertPanel (@"Delete financial record?", @"This removes the record and updates the account and invoice balances. Attached receipts will also be removed.", @"Cancel", @"Delete", nil) != NSAlertAlternateReturn) return;
  if (mode == 1) [_ledger deleteExpense: [record objectForKey: @"id"] error: &error];
  else [_ledger deletePayment: [record objectForKey: @"id"] invoice: [record objectForKey: @"invoiceID"] error: &error];
  [self showError: error]; [self refresh];
}
- (void) financeReceipt: (id)sender
{
  NSDictionary *record = [self financeSelection]; NSString *error = nil;
  NSMutableDictionary *updated; NSOpenPanel *panel; NSData *bytes;
  if ([_financeMode indexOfSelectedItem] != 1 || !record) { [self showError: @"Select an expense first."]; return; }
  panel = [NSOpenPanel openPanel]; [panel setAllowsMultipleSelection: NO]; [panel setCanChooseDirectories: NO];
  [panel setAllowedFileTypes: [NSArray arrayWithObjects: @"pdf", @"png", @"jpg", @"jpeg", @"heic", @"tiff", nil]];
  if ([panel runModal] != NSOKButton) return;
  if ([[[[NSFileManager defaultManager] attributesOfItemAtPath: [[panel URL] path] error: NULL] objectForKey: NSFileSize] unsignedLongLongValue] > 20 * 1024 * 1024) { [self showError: @"Receipt must be 20 MB or less."]; return; }
  bytes = [NSData dataWithContentsOfURL: [panel URL]];
  if (!bytes) { [self showError: @"The receipt could not be read."]; return; }
  updated = [NSMutableDictionary dictionaryWithDictionary: record];
  [updated setObject: [CLLedger money: [record objectForKey: @"amount"]] forKey: @"amount"];
  [updated setObject: bytes forKey: @"receiptData"]; [updated setObject: [[[panel URL] path] lastPathComponent] forKey: @"receiptName"];
  [_ledger saveExpense: [record objectForKey: @"id"] values: updated error: &error]; [self showError: error]; [self refresh];
}
- (void) financeOpenReceipt: (id)sender
{
  NSDictionary *record = [self financeSelection]; NSSavePanel *panel;
  if ([_financeMode indexOfSelectedItem] != 1 || ![record objectForKey: @"receiptData"]) { [self showError: @"Select an expense with a receipt."]; return; }
  panel = [NSSavePanel savePanel]; [panel setNameFieldStringValue: [[record objectForKey: @"receiptName"] lastPathComponent]];
  if ([panel runModal] == NSOKButton)
    { if ([[record objectForKey: @"receiptData"] writeToURL: [panel URL] atomically: YES]) [[NSWorkspace sharedWorkspace] openURL: [panel URL]];
      else [self showError: @"Could not export the receipt."]; }
}

- (void) financeExport: (id)sender
{
  NSSavePanel *panel = [NSSavePanel savePanel];
  NSMutableString *csv = [NSMutableString stringWithString: @"Date,Vendor,Category,Currency,Amount,Account,Reference,Business purpose,Receipt\r\n"];
  NSDictionary *expense, *account;
  [panel setNameFieldStringValue: @"Company-expenses.csv"];
  for (expense in [_ledger expenses])
    {
      NSString *accountName = @"", *value;
      NSArray *values; NSMutableArray *quoted = [NSMutableArray array];
      for (account in [_ledger accounts]) if ([[account objectForKey: @"id"] isEqual: [expense objectForKey: @"accountID"]]) accountName = [account objectForKey: @"name"];
      values = [NSArray arrayWithObjects: [expense objectForKey: @"date"], [expense objectForKey: @"vendor"], [expense objectForKey: @"category"], [expense objectForKey: @"currency"], [CLLedger money: [expense objectForKey: @"amount"]], accountName, [expense objectForKey: @"reference"], [expense objectForKey: @"notes"], [expense objectForKey: @"receiptName"] ?: @"", nil];
      for (value in values)
        {
          if ([value length] && [@"=+-@\t\r\n" rangeOfString: [value substringToIndex: 1]].location != NSNotFound) value = [@"'" stringByAppendingString: value];
          [quoted addObject: [NSString stringWithFormat: @"\"%@\"", [value stringByReplacingOccurrencesOfString: @"\"" withString: @"\"\""]]];
        }
      [csv appendFormat: @"%@\r\n", [quoted componentsJoinedByString: @","]];
    }
  if ([panel runModal] == NSOKButton && ![csv writeToURL: [panel URL] atomically: YES encoding: NSUTF8StringEncoding error: NULL]) [self showError: @"Could not export expenses."];
}
