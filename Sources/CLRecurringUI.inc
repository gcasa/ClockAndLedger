static NSArray *
CLHolidayDates (NSString *text)
{
  NSArray *parts = [text componentsSeparatedByCharactersInSet:
    [NSCharacterSet characterSetWithCharactersInString: @",; \n\r\t"]];
  NSMutableArray *dates = [NSMutableArray array];
  unsigned int i;
  for (i = 0; i < [parts count]; i++)
    if ([[parts objectAtIndex: i] length]) [dates addObject: [parts objectAtIndex: i]];
  return dates;
}

- (void) editRecurring: (id)sender
{
  NSDictionary *client = [self selectedRecord: _clientsTable];
  NSDictionary *schedule = [client objectForKey: @"recurring"];
  NSArray *labels = [NSArray arrayWithObjects: @"Enabled (Yes / No)", @"Next month YYYY-MM", @"Issue day (1–28)", @"Tax %", @"Holiday dates", nil];
  NSArray *values;
  NSDictionary *form;
  NSString *identifier, *error = nil;
  if (client == nil) { [self showError: @"Select a client first."]; return; }
  identifier = [[[client objectForKey: @"id"] copy] autorelease];
  values = [NSArray arrayWithObjects: [[schedule objectForKey: @"enabled"] boolValue] ? @"Yes" : @"No",
    [schedule objectForKey: @"nextMonth"] ?: [[CLLedger today] substringToIndex: 7],
    [[schedule objectForKey: @"day"] description] ?: @"1", [schedule objectForKey: @"tax"] ?: @"0",
    [[schedule objectForKey: @"holidays"] componentsJoinedByString: @", "] ?: @"", nil];
  while ((form = [self editForm: @"Monthly billing — issue next month; holidays: YYYY-MM-DD, …" labels: labels values: values]) != nil)
    {
      NSString *enabled = [[form objectForKey: @"Enabled (Yes / No)"] lowercaseString];
      NSString *day = [form objectForKey: @"Issue day (1–28)"];
      NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool: [enabled isEqual: @"yes"]], @"enabled",
        [form objectForKey: @"Next month YYYY-MM"], @"nextMonth",
        [NSNumber numberWithInt: [day intValue]], @"day", [form objectForKey: @"Tax %"], @"tax",
        CLHolidayDates ([form objectForKey: @"Holiday dates"]), @"holidays", nil];
      if (![enabled isEqual: @"yes"] && ![enabled isEqual: @"no"])
        error = @"Enabled must be Yes or No.";
      else if ([day length] == 0 || [day rangeOfCharacterFromSet: [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound)
        error = @"Issue day must be a whole number from 1 to 28.";
      else if ([_ledger saveRecurringForClient: identifier values: settings error: &error])
        {
          [self refresh];
          [_mailStatus setStringValue: @"Monthly billing saved. Keep the app running; missed months are processed when reopened. Invoices are created without sending email."];
          return;
        }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: [labels objectAtIndex: 0]],
        [form objectForKey: [labels objectAtIndex: 1]], day, [form objectForKey: @"Tax %"], [form objectForKey: @"Holiday dates"], nil];
    }
}

- (void) invoiceMonth: (id)sender
{
  NSString *identifier = [[[self selectedClient: _invoiceClient] copy] autorelease];
  NSDictionary *schedule = [[_ledger clientWithID: identifier] objectForKey: @"recurring"];
  NSArray *labels = [NSArray arrayWithObjects: @"Month YYYY-MM", @"Holiday dates", @"Tax %", @"Issued", nil];
  NSArray *values = [NSArray arrayWithObjects: [[CLLedger today] substringToIndex: 7],
    [[schedule objectForKey: @"holidays"] componentsJoinedByString: @", "] ?: @"", [_taxField stringValue], [CLLedger today], nil];
  NSDictionary *form;
  NSString *error = nil;
  if (identifier == nil) { [self showError: @"Select an invoice client first."]; return; }
  while ((form = [self editForm: @"Invoice monthly hours — excludes holiday dates (YYYY-MM-DD, …)" labels: labels values: values]) != nil)
    {
      if ([_ledger invoiceMonth: [form objectForKey: @"Month YYYY-MM"] client: identifier
        holidays: CLHolidayDates ([form objectForKey: @"Holiday dates"]) tax: [form objectForKey: @"Tax %"]
        issuedDate: [form objectForKey: @"Issued"] error: &error])
        { [self refresh]; return; }
      [self showError: error];
      values = [NSArray arrayWithObjects: [form objectForKey: @"Month YYYY-MM"], [form objectForKey: @"Holiday dates"],
        [form objectForKey: @"Tax %"], [form objectForKey: @"Issued"], nil];
    }
}
