/** Lists retain independent search, status, date and client filters. */
- (NSArray *) rawRowsForTable: (NSTableView *)table
{
  if (table == _dashboardTable) return [_dashboardReport objectForKey: @"monthly"] ?: [NSArray array];
  if (table == _reportTable)
    {
      NSArray *keys = [NSArray arrayWithObjects: @"monthly", @"clients", @"categories", @"time", @"receivables", nil];
      NSInteger index = [_reportMode indexOfSelectedItem];
      return [_reportData objectForKey: [keys objectAtIndex: MAX (0, index)]] ?: [NSArray array];
    }
  if (table == _financeTable) return [self financeRows];
  if (table == _clientsTable) return [_ledger clients];
  if (table == _timeTable) return [_ledger entries];
  if (table == _tasksTable) return [_ledger tasksForClient: [self selectedClient: _tasksClient] includeArchived: YES];
  return [_ledger invoices];
}

- (NSDictionary *) browsePeriod: (NSInteger)index
{
  NSString *today = [CLLedger today];
  if (index == 1) return [CLLedger periodContainingDate: today kind: @"month" error: NULL];
  if (index == 2)
    {
      NSInteger year = [[today substringToIndex: 4] integerValue], month = [[today substringWithRange: NSMakeRange (5, 2)] integerValue] - 1;
      if (month == 0) { month = 12; year--; }
      return [CLLedger periodContainingDate: [NSString stringWithFormat: @"%04ld-%02ld-01", (long)year, (long)month] kind: @"month" error: NULL];
    }
  if (index == 3) return [NSDictionary dictionaryWithObjectsAndKeys:
    [[today substringToIndex: 4] stringByAppendingString: @"-01-01"], @"start",
    [[today substringToIndex: 4] stringByAppendingString: @"-12-31"], @"end", nil];
  return [NSDictionary dictionaryWithObjectsAndKeys: @"0001-01-01", @"start", @"9999-12-31", @"end", nil];
}

- (void) setupBrowsing
{
  NSArray *tables = [NSArray arrayWithObjects: _clientsTable, _tasksTable, _timeTable, _invoicesTable, _financeTable, nil];
  CLRecordTable *table;
  for (table in tables)
    {
      NSScrollView *scroll = [table enclosingScrollView]; NSView *view = [scroll superview];
      NSRect frame = [scroll frame]; CGFloat y = NSMaxY (frame) - 30;
      NSArray *statuses = nil;
      frame.size.height -= 42; [scroll setFrame: frame];
      table->search = [[[NSSearchField alloc] initWithFrame: NSMakeRect (18, y, 260, 26)] autorelease];
      [[table->search cell] setPlaceholderString: @"Search this list"];
      [table->search setDelegate: (id)self];
      [table->search setTarget: self]; [table->search setAction: @selector(browseChanged:)];
      [table->search setAutoresizingMask: NSViewMinYMargin]; [view addSubview: table->search];
      table->statusFilter = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (286, y - 1, 160, 28)] autorelease];
      if (table == _tasksTable) statuses = [NSArray arrayWithObjects: @"All tasks", @"Active", @"Archived", nil];
      else if (table == _timeTable) statuses = [NSArray arrayWithObjects: @"All time", @"Unbilled", @"Billed", @"Nonbillable", @"Needs review", nil];
      else if (table == _invoicesTable) statuses = [NSArray arrayWithObjects: @"All invoices", @"Outstanding", @"Overdue", @"Paid", @"Partial", @"Overpaid", @"Needs review", nil];
      else if (table == _financeTable) statuses = [NSArray arrayWithObjects: @"All records", @"Has receipt", @"Missing receipt", nil];
      else statuses = [NSArray arrayWithObject: @"All clients"];
      [table->statusFilter addItemsWithTitles: statuses];
      [table->statusFilter setEnabled: [statuses count] > 1];
      [table->statusFilter setTarget: self]; [table->statusFilter setAction: @selector(browseChanged:)];
      [table->statusFilter setAutoresizingMask: NSViewMinYMargin]; [view addSubview: table->statusFilter];
      table->dateFilter = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (452, y - 1, 150, 28)] autorelease];
      [table->dateFilter addItemsWithTitles: [NSArray arrayWithObjects: @"All dates", @"This month", @"Last month", @"This year", nil]];
      [table->dateFilter setEnabled: table != _clientsTable && table != _tasksTable];
      [table->dateFilter setToolTip: @"Filters by entry start, invoice issue, expense or payment date. Period totals use their start date."];
      [table->dateFilter setTarget: self]; [table->dateFilter setAction: @selector(browseChanged:)];
      [table->dateFilter setAutoresizingMask: NSViewMinYMargin]; [view addSubview: table->dateFilter];
      if (table == _timeTable || table == _invoicesTable)
        {
          table->clientFilter = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect (608, y - 1, 220, 28)] autorelease];
          [table->clientFilter setTarget: self]; [table->clientFilter setAction: @selector(browseChanged:)];
          [table->clientFilter setAutoresizingMask: NSViewMinYMargin]; [view addSubview: table->clientFilter];
        }
      table->resultCount = CLLabel (view, @"", NSMakeRect (836, y, 112, 24), 11);
      [table->resultCount setAutoresizingMask: NSViewMinYMargin];
    }
}

- (void) browseChanged: (id)sender
{
  NSArray *tables = [NSArray arrayWithObjects: _clientsTable ?: (id)[NSNull null], _tasksTable ?: (id)[NSNull null],
    _timeTable ?: (id)[NSNull null], _invoicesTable ?: (id)[NSNull null], _financeTable ?: (id)[NSNull null], nil];
  id candidate;
  for (candidate in tables)
    if ([candidate isKindOfClass: [CLRecordTable class]])
      {
        CLRecordTable *table = candidate;
        if (sender == table->search || sender == table->statusFilter || sender == table->dateFilter || sender == table->clientFilter)
          [table reloadData];
      }
}

- (id) sortValueForRecord: (NSDictionary *)record key: (NSString *)key table: (NSTableView *)table
{
  if (table == _reportTable || table == _dashboardTable) return [record objectForKey: key] ?: [NSNumber numberWithInt: 0];
  if ([key isEqual: @"hours"]) return [record objectForKey: @"seconds"];
  if ([key isEqual: @"rate"] || [key isEqual: @"total"]) return [record objectForKey: key];
  if ([key isEqual: @"amount"])
    {
      if (table == _timeTable) return [CLLedger isBillableEntry: record] ? [CLLedger amountForSeconds: [record objectForKey: @"seconds"] rate: [record objectForKey: @"rate"]] : [NSNumber numberWithInt: 0];
      if (table == _financeTable && [_financeMode indexOfSelectedItem] == 0) return [_ledger balanceForAccount: [record objectForKey: @"id"]];
      return [record objectForKey: key] ?: [NSNumber numberWithInt: 0];
    }
  /* Dates sort chronologically even when the displayed value is a date range. */
  if ([key isEqual: @"date"]) return [record objectForKey: key] ?: @"";
  if ([key isEqual: @"paymentDays"])
    {
      NSString *value = [CLLedger paymentDaysForInvoice: record onDate: [CLLedger today]];
      if ([value isEqual: @"—"]) return [NSNumber numberWithInteger: NSIntegerMax];
      return [NSNumber numberWithInteger: [value hasPrefix: @"+"] ? -[value integerValue] : [value integerValue]];
    }
  return [self valueForRecord: record column: key table: table] ?: @"";
}

- (NSArray *) browseRowsForTable: (CLRecordTable *)table
{
  NSArray *raw = [self rawRowsForTable: table];
  NSMutableArray *decorated = [NSMutableArray array], *result = [NSMutableArray array];
  NSString *query = [[table->search stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *status = [table->statusFilter titleOfSelectedItem];
  NSString *clientID;
  NSDictionary *period = [self browsePeriod: [table->dateFilter indexOfSelectedItem]];
  NSSortDescriptor *sort = [[table sortDescriptors] count] ? [[table sortDescriptors] objectAtIndex: 0] : nil;
  NSDictionary *record; NSUInteger index = 0;
  BOOL ascending = sort ? [sort ascending] : YES;
  if (table->clientFilter)
    {
      NSString *previous = [[[table->clientFilter selectedItem] representedObject] copy];
      NSDictionary *client;
      [table->clientFilter removeAllItems]; [table->clientFilter addItemWithTitle: @"All clients"];
      for (client in [_ledger clients])
        {
          NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: [client objectForKey: @"name"] action: NULL keyEquivalent: @""] autorelease];
          [item setRepresentedObject: [client objectForKey: @"id"]]; [[table->clientFilter menu] addItem: item];
          if ([[client objectForKey: @"id"] isEqual: previous]) [table->clientFilter selectItem: item];
        }
      [previous release];
    }
  clientID = [[table->clientFilter selectedItem] representedObject];
  if (table == _financeTable)
    {
      BOOL expenses = [_financeMode indexOfSelectedItem] == 1;
      [table->statusFilter setEnabled: expenses];
      [table->dateFilter setEnabled: [_financeMode indexOfSelectedItem] != 0];
      if (!expenses) { [table->statusFilter selectItemAtIndex: 0]; status = [table->statusFilter titleOfSelectedItem]; }
    }
  for (record in raw)
    {
      BOOL matches = YES;
      if ([clientID length]) matches = [[record objectForKey: @"clientID"] isEqual: clientID] || [[[record objectForKey: @"client"] objectForKey: @"id"] isEqual: clientID];
      if ([table->dateFilter isEnabled] && [table->dateFilter indexOfSelectedItem] > 0)
        matches = matches && [CLReporting date: [record objectForKey: @"date"] from: [period objectForKey: @"start"] to: [period objectForKey: @"end"]];
      if (table == _tasksTable && [table->statusFilter indexOfSelectedItem] > 0)
        matches = matches && ([[record objectForKey: @"archived"] boolValue] == [status isEqual: @"Archived"]);
      if (table == _timeTable)
        {
          if ([status isEqual: @"Unbilled"]) matches = matches && [CLLedger isUnbilledEntry: record];
          if ([status isEqual: @"Needs review"]) matches = matches && [[record objectForKey: @"externalBilling"] isEqual: @"Review required"];
          if ([status isEqual: @"Nonbillable"]) matches = matches && ![CLLedger isBillableEntry: record];
          if ([status isEqual: @"Billed"]) matches = matches && [CLLedger isBillableEntry: record] &&
            ([[record objectForKey: @"invoiceID"] length] || [[record objectForKey: @"externalBilling"] isEqual: @"Billed in QuickBooks"]);
        }
      if (table == _invoicesTable)
        {
          BOOL verified = ![[record objectForKey: @"paymentUnverified"] boolValue];
          long long received = [[CLLedger receivedForInvoice: record] longLongValue], total = [[record objectForKey: @"total"] longLongValue];
          long long due = [[CLLedger balanceForInvoice: record] longLongValue];
          if ([status isEqual: @"Outstanding"]) matches = matches && verified && due > 0;
          if ([status isEqual: @"Overdue"]) matches = matches && verified && due > 0 && ![[record objectForKey: @"dueDateUnverified"] boolValue] && [(NSString *)[record objectForKey: @"dueDate"] compare: [CLLedger today]] == NSOrderedAscending;
          if ([status isEqual: @"Paid"]) matches = matches && verified && due == 0;
          if ([status isEqual: @"Partial"]) matches = matches && verified && received > 0 && due > 0;
          if ([status isEqual: @"Overpaid"]) matches = matches && verified && received > total;
          if ([status isEqual: @"Needs review"]) matches = matches && (!verified || [[record objectForKey: @"dueDateUnverified"] boolValue]);
        }
      if (table == _financeTable && [_financeMode indexOfSelectedItem] == 1 && [table->statusFilter indexOfSelectedItem] > 0)
        matches = matches && (([record objectForKey: @"receiptData"] != nil) == [status isEqual: @"Has receipt"]);
      if (matches && [query length])
        {
          NSTableColumn *column; NSMutableString *text = [NSMutableString string];
          for (column in [table tableColumns]) [text appendFormat: @"%@ ", [self valueForRecord: record column: [column identifier] table: table] ?: @""];
          [text appendString: [record objectForKey: @"notes"] ?: @""];
          matches = [text rangeOfString: query options: NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
        }
      if (matches) [decorated addObject: [NSDictionary dictionaryWithObjectsAndKeys: record, @"record",
        sort ? ([self sortValueForRecord: record key: [sort key] table: table] ?: @"") : [NSNumber numberWithUnsignedInteger: index], @"sort",
        [NSNumber numberWithUnsignedInteger: index], @"index", nil]];
      index++;
    }
  for (record in [decorated sortedArrayUsingFunction: CLCompareBrowseRows context: &ascending]) [result addObject: [record objectForKey: @"record"]];
  return result;
}

- (void) tableView: (NSTableView *)table sortDescriptorsDidChange: (NSArray *)oldDescriptors
{
  [table reloadData];
}
