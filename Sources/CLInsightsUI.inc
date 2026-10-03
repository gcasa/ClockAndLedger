- (NSArray *) reportKeys
{
  switch ([_reportMode indexOfSelectedItem])
    {
      case 1: return [NSArray arrayWithObjects: @"name", @"billed", @"received", @"outstanding", nil];
      case 2: return [NSArray arrayWithObjects: @"name", @"count", @"expenses", nil];
      case 3: return [NSArray arrayWithObjects: @"name", @"billableHours", @"nonbillableHours", @"value", nil];
      case 4: return [NSArray arrayWithObjects: @"name", @"client", @"dueDate", @"outstanding", @"status", nil];
      case 5: return [NSArray arrayWithObjects: @"name", @"proceeds", @"expenses", @"earnings", @"received", @"unsettled", @"developmentHours", @"sales", @"refunds", @"fees", nil];
      case 6: return [NSArray arrayWithObjects: @"name", @"proceeds", @"expenses", @"earnings", @"received", @"developmentHours", nil];
      default: return [NSArray arrayWithObjects: @"name", @"received", @"expenses", @"net", nil];
    }
}
- (NSArray *) reportTitles
{
  switch ([_reportMode indexOfSelectedItem])
    {
      case 1: return [NSArray arrayWithObjects: @"Client", @"Billed incl. tax", @"Received", @"Outstanding now", nil];
      case 2: return [NSArray arrayWithObjects: @"Expense category", @"Transactions", @"Expenses", nil];
      case 3: return [NSArray arrayWithObjects: @"Client", @"Billable hours", @"Nonbillable hours", @"Billable value", nil];
      case 4: return [NSArray arrayWithObjects: @"Invoice", @"Client", @"Due date", @"Balance due now", @"Status", nil];
      case 5: return [NSArray arrayWithObjects: @"App", @"Net proceeds", @"Expenses", @"Net earnings", @"Cash allocated", @"Unsettled now", @"Dev hours", @"Gross sales", @"Refunds", @"Fees", nil];
      case 6: return [NSArray arrayWithObjects: @"Month / app", @"Net proceeds", @"Expenses", @"Net earnings", @"Cash allocated", @"Dev hours", nil];
      default: return [NSArray arrayWithObjects: @"Month", @"Received", @"Expenses", @"Net cash movement", nil];
    }
}
- (void) configureReportColumns
{
  NSArray *keys = [self reportKeys], *titles = [self reportTitles];
  NSTableColumn *column; NSUInteger i;
  [_reportTable setSortDescriptors: [NSArray array]];
  for (column in [[[_reportTable tableColumns] copy] autorelease]) [_reportTable removeTableColumn: column];
  for (i = 0; i < [keys count]; i++)
    {
      NSString *key = [keys objectAtIndex: i];
      column = [[[NSTableColumn alloc] initWithIdentifier: key] autorelease];
      [[column headerCell] setStringValue: [titles objectAtIndex: i]];
      [column setWidth: i == 0 ? 280 : ([keys count] == 5 ? 155 : 210)];
      [column setEditable: NO]; [[column dataCell] setFont: [NSFont systemFontOfSize: 13]];
      if (![[NSArray arrayWithObjects: @"name", @"client", @"dueDate", @"status", nil] containsObject: key]) [[column dataCell] setAlignment: NSRightTextAlignment];
      [column setSortDescriptorPrototype: [[[NSSortDescriptor alloc] initWithKey: key ascending: YES] autorelease]];
      [_reportTable addTableColumn: column];
    }
}
- (NSPopUpButton *) insightPopupIn: (NSView *)view frame: (NSRect)frame titles: (NSArray *)titles
{
  NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame: frame pullsDown: NO] autorelease];
  [popup addItemsWithTitles: titles]; [popup setTarget: self]; [popup setAction: @selector(refreshInsights:)];
  [view addSubview: popup]; return popup;
}
- (void) buildInsightsIn: (NSTabView *)tabs
{
  NSView *view = [self tab: @"Dashboard" in: tabs];
  NSMutableArray *cards = [NSMutableArray array];
  NSArray *titles = [NSArray arrayWithObjects: @"MONEY RECEIVED", @"EXPENSES", @"NET CASH MOVEMENT", @"OUTSTANDING NOW", nil];
  NSUInteger i;
  CLLabel (view, @"Your business at a glance", NSMakeRect (18, 500, 900, 30), 22);
  CLLabel (view, @"Cash activity, open invoices and the work behind them.", NSMakeRect (18, 473, 900, 24), 13);
  _dashboardPeriod = [self insightPopupIn: view frame: NSMakeRect (18, 435, 210, 28) titles: [NSArray arrayWithObjects: @"All dates", @"This month", @"Last month", @"This year", nil]];
  [_dashboardPeriod selectItemAtIndex: 1];
  _dashboardCurrency = [self insightPopupIn: view frame: NSMakeRect (242, 435, 130, 28) titles: [NSArray array]];
  CLLabel (view, @"Amounts are grouped by currency.", NSMakeRect (390, 435, 530, 26), 12);
  for (i = 0; i < 4; i++)
    {
      CLMetricCard *card = [[[CLMetricCard alloc] initWithFrame: NSMakeRect (18 + i * 237, 328, 224, 94)] autorelease];
      NSTextField *value;
      [view addSubview: card];
      CLLabel (card, [titles objectAtIndex: i], NSMakeRect (12, 47, 206, 20), 10);
      value = CLLabel (card, @"0.00", NSMakeRect (12, 9, 206, 36), 24);
      [value setSelectable: YES];
      [[value cell] setLineBreakMode: NSLineBreakByTruncatingTail];
      [cards addObject: value];
    }
  _dashboardCards = [cards copy];
  _dashboardNote = CLLabel (view, @"", NSMakeRect (18, 266, 940, 52), 12);
  [[_dashboardNote cell] setWraps: YES];
  _dashboardTable = [self tableIn: view columns: [NSArray arrayWithObjects: @"name", @"received", @"expenses", @"net", nil]
    widths: [NSArray arrayWithObjects: [NSNumber numberWithInt: 220], [NSNumber numberWithInt: 220], [NSNumber numberWithInt: 220], [NSNumber numberWithInt: 230], nil]];
  [[_dashboardTable enclosingScrollView] setFrame: NSMakeRect (18, 62, 940, 194)];
  {
    NSArray *headers = [NSArray arrayWithObjects: @"Month", @"Received", @"Expenses", @"Net cash movement", nil];
    for (i = 0; i < [headers count]; i++) [[[[_dashboardTable tableColumns] objectAtIndex: i] headerCell] setStringValue: [headers objectAtIndex: i]];
  }
  CLLabel (view, @"Receipts use payment dates; expenses use transaction dates. Net cash movement is not accounting profit.\nOutstanding, overdue and unbilled totals are current across all dates. Active timers are excluded.", NSMakeRect (18, 6, 940, 48), 11);

  view = [self tab: @"Reports" in: tabs];
  CLLabel (view, @"Understand the numbers", NSMakeRect (18, 500, 900, 30), 22);
  CLLabel (view, @"Choose a report and inclusive date range, then export the results to CSV.", NSMakeRect (18, 472, 940, 24), 13);
  _reportMode = [self insightPopupIn: view frame: NSMakeRect (18, 422, 230, 28) titles: [NSArray arrayWithObjects: @"Monthly cash flow", @"Client billing & receipts", @"Expense categories", @"Time by client", @"Current receivables", @"App performance", @"Apps by month", nil]];
  _reportCurrency = [self insightPopupIn: view frame: NSMakeRect (254, 422, 110, 28) titles: [NSArray array]];
  CLLabel (view, @"From", NSMakeRect (380, 425, 48, 24), 12);
  CLLabel (view, @"To", NSMakeRect (610, 425, 32, 24), 12);
  _reportStart = [CLDateField fieldInView: view value: [[[CLLedger today] substringToIndex: 4] stringByAppendingString: @"-01-01"] frame: NSMakeRect (430, 424, 170, 26)];
  _reportEnd = [CLDateField fieldInView: view value: [CLLedger today] frame: NSMakeRect (647, 424, 170, 26)];
  CLButton (view, @"Apply", NSMakeRect (835, 420, 114, 32), self, @selector(refreshInsights:));
  _reportTable = [self tableIn: view columns: [NSArray array] widths: [NSArray array]];
  [[_reportTable enclosingScrollView] setFrame: NSMakeRect (18, 100, 940, 300)];
  [self configureReportColumns];
  _reportNote = CLLabel (view, @"", NSMakeRect (18, 46, 940, 48), 11);
  [[_reportNote cell] setWraps: YES];
  CLButton (view, @"Export Report CSV…", NSMakeRect (12, 8, 200, 32), self, @selector(exportReport:));
}
- (void) fillReportCurrencies: (NSPopUpButton *)popup
{
  NSString *previous = [[popup titleOfSelectedItem] copy];
  NSMutableSet *currencies = [NSMutableSet setWithObject: [[_ledger business] objectForKey: @"currency"] ?: @"USD"];
  NSDictionary *record;
  for (record in [_ledger invoices]) [currencies addObject: [[record objectForKey: @"business"] objectForKey: @"currency"]];
  for (record in [_ledger accounts]) [currencies addObject: [record objectForKey: @"currency"]];
  for (record in [_ledger expenses]) [currencies addObject: [record objectForKey: @"currency"]];
  for (record in [_ledger appRevenue]) [currencies addObject: [record objectForKey: @"currency"]];
  [popup removeAllItems]; [popup addItemsWithTitles: [[currencies allObjects] sortedArrayUsingSelector: @selector(compare:)]];
  [popup selectItemWithTitle: previous ?: [[_ledger business] objectForKey: @"currency"]]; [previous release];
}
- (void) refreshInsights: (id)sender
{
  NSDictionary *period, *summary;
  NSArray *keys = [NSArray arrayWithObjects: @"received", @"expenses", @"net", @"outstanding", nil];
  NSUInteger i;
  NSString *currency, *start, *end, *detail;
  if (!_dashboardTable) return;
  [self fillReportCurrencies: _dashboardCurrency]; [self fillReportCurrencies: _reportCurrency];
  period = [self browsePeriod: [_dashboardPeriod indexOfSelectedItem]];
  [_dashboardReport release];
  _dashboardReport = [[CLReporting reportForLedger: _ledger from: [period objectForKey: @"start"] to: [period objectForKey: @"end"] currency: [_dashboardCurrency titleOfSelectedItem] today: [CLLedger today]] retain];
  summary = [_dashboardReport objectForKey: @"summary"];
  for (i = 0; i < [keys count]; i++)
    {
      NSTextField *field = [_dashboardCards objectAtIndex: i];
      [field setStringValue: [CLLedger money: [summary objectForKey: [keys objectAtIndex: i]] ?: [NSNumber numberWithInt: 0]]];
      [field setToolTip: [NSString stringWithFormat: @"%@ %@", [_dashboardCurrency titleOfSelectedItem], [field stringValue]]];
    }
  [_dashboardNote setStringValue: [NSString stringWithFormat:
    @"%.2f billable hours  •  %.2f nonbillable hours in this period  •  %@ billed (incl. tax)\n%@ overdue now  •  %@ unbilled now  •  %ld undated paid / %ld unverified invoices excluded from cash totals",
    [[summary objectForKey: @"billableSeconds"] doubleValue] / 3600, [[summary objectForKey: @"nonbillableSeconds"] doubleValue] / 3600,
    [CLLedger money: [summary objectForKey: @"billed"] ?: [NSNumber numberWithInt: 0]], [CLLedger money: [summary objectForKey: @"overdue"] ?: [NSNumber numberWithInt: 0]],
    [CLLedger money: [summary objectForKey: @"unbilled"] ?: [NSNumber numberWithInt: 0]], (long)[[summary objectForKey: @"undated"] integerValue], (long)[[summary objectForKey: @"unverified"] integerValue]]];
  [_dashboardTable reloadData];
  currency = [_reportCurrency titleOfSelectedItem]; start = [_reportStart stringValue]; end = [_reportEnd stringValue];
  {
    BOOL usesDates = [_reportMode indexOfSelectedItem] != 4;
    NSView *child;
    [_reportStart setEnabled: usesDates]; [_reportEnd setEnabled: usesDates];
    for (child in [[_reportStart superview] subviews])
      if ([child isKindOfClass: [NSButton class]] &&
          ([(NSButton *)child target] == _reportStart || [(NSButton *)child target] == _reportEnd))
        [(NSButton *)child setEnabled: usesDates];
  }
  [_reportData release]; _reportData = nil;
  if (sender == _reportMode) { [_reportTable deselectAll: nil]; [self configureReportColumns]; }
  if ([_reportMode indexOfSelectedItem] != 4 && (![CLLedger periodContainingDate: start kind: @"day" error: NULL] ||
      ![CLLedger periodContainingDate: end kind: @"day" error: NULL] || [start compare: end] == NSOrderedDescending))
    { [_reportNote setStringValue: @"Enter valid From and To dates (YYYY-MM-DD), with From on or before To, then click Apply."]; [_reportTable reloadData]; return; }
  _reportData = [[CLReporting reportForLedger: _ledger from: start to: end currency: currency today: [CLLedger today]] retain];
  summary = [_reportData objectForKey: @"summary"];
  detail = [_reportMode indexOfSelectedItem] == 4 ? @"Current balances across ALL dates; the date range does not apply. Unverified payments are excluded." :
    ([_reportMode indexOfSelectedItem] == 3 ? @"Time uses the entry START date (whole period totals; no prorating). Active timers are excluded. Value uses recorded rates." :
    ([_reportMode indexOfSelectedItem] == 1 ? @"Billed includes tax by issue date; receipts use payment dates. Outstanding is the CURRENT balance across all dates." :
    @"Receipts use payment dates; expenses use transaction dates. Net cash movement is not accounting profit."));
  if ([_reportMode indexOfSelectedItem] >= 5)
    detail = @"Proceeds: period end; cash: deposit date; costs: expense date. Earnings = proceeds − costs, before owner labor. Shared costs stay separate. Unsettled is current; dev hours are currency-independent. Blank breakdowns are unknown.";
  [_reportNote setStringValue: [NSString stringWithFormat: @"%@ • %@. %@\n%ld undated paid and %ld unverified invoices excluded from cash totals. Click a column heading to sort.", currency, [_reportMode indexOfSelectedItem] == 4 ? @"Current recorded balances" : [NSString stringWithFormat: @"%@ to %@", start, end], detail,
    (long)[[summary objectForKey: @"undated"] integerValue], (long)[[summary objectForKey: @"unverified"] integerValue]]];
  [_reportTable reloadData];
}
- (void) exportReport: (id)sender
{
  NSSavePanel *panel;
  NSMutableArray *rows = [NSMutableArray array]; NSDictionary *record;
  NSMutableArray *keys, *titles;
  /* Apply pending dates before export so the exported range matches the controls. */
  [self refreshInsights: nil];
  if (!_reportData) { [self showError: @"Choose a valid report date range before exporting."]; return; }
  keys = [NSMutableArray arrayWithArray: [self reportKeys]]; titles = [NSMutableArray arrayWithArray: [self reportTitles]];
  [keys addObjectsFromArray: [NSArray arrayWithObjects: @"currency", @"from", @"to", @"basis", nil]];
  [titles addObjectsFromArray: [NSArray arrayWithObjects: @"Currency", @"From (inclusive)", @"To (inclusive)", @"Basis / exclusions", nil]];
  for (record in [(CLRecordTable *)_reportTable visibleRecords])
    {
      NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary: record];
      [row setObject: [_reportCurrency titleOfSelectedItem] forKey: @"currency"];
      [row setObject: [_reportMode indexOfSelectedItem] == 4 ? @"All dates" : [_reportStart stringValue] forKey: @"from"];
      [row setObject: [_reportMode indexOfSelectedItem] == 4 ? [CLLedger today] : [_reportEnd stringValue] forKey: @"to"];
      [row setObject: [_reportNote stringValue] forKey: @"basis"]; [rows addObject: row];
    }
  panel = [NSSavePanel savePanel]; [panel setNameFieldStringValue: [NSString stringWithFormat: @"%@-%@.csv", [_reportMode titleOfSelectedItem], [_reportCurrency titleOfSelectedItem]]];
  if ([panel runModal] == NSOKButton && ![[CLReporting csvForRows: rows keys: keys titles: titles moneyKeys: [NSArray arrayWithObjects: @"received", @"expenses", @"net", @"billed", @"outstanding", @"value", @"proceeds", @"earnings", @"unsettled", @"sales", @"refunds", @"fees", nil]] writeToURL: [panel URL] atomically: YES encoding: NSUTF8StringEncoding error: NULL])
    [self showError: @"The report could not be saved. Choose a writable folder."];
}
