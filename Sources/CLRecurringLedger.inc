/* Monthly billing shares the normal invoice transaction and rate snapshots. */
- (BOOL) saveRecurringForClient: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error
{
  NSMutableDictionary *client = [self record: identifier in: @"clients"];
  NSMutableDictionary *backup;
  if (client == nil || !CLValidSchedule (values) || values == nil)
    return CLFail (error, @"Enter a billing month (YYYY-MM), day 1–28, tax 0–100 and holiday dates (YYYY-MM-DD).");
  backup = [self backup];
  [client setObject: [NSMutableDictionary dictionaryWithDictionary: values] forKey: @"recurring"];
  return [self commit: backup error: error];
}

- (NSSet *) monthlyEntryIDs: (NSString *)month client: (NSString *)identifier
                  holidays: (NSArray *)holidays error: (NSString **)error
{
  NSDictionary *period;
  NSMutableSet *identifiers = [NSMutableSet set];
  unsigned int i, j;
  NSString *start, *end;
  if (![month isKindOfClass: [NSString class]] || [month length] != 7
      || ![holidays isKindOfClass: [NSArray class]] || [self clientWithID: identifier] == nil)
    { CLFail (error, @"Choose a client, month (YYYY-MM) and holiday dates."); return nil; }
  period = [CLLedger periodContainingDate: [month stringByAppendingString: @"-01"] kind: @"month" error: error];
  if (period == nil) return nil;
  start = [period objectForKey: @"start"]; end = [period objectForKey: @"end"];
  for (j = 0; j < [holidays count]; j++)
    if (!CLValidDate ([holidays objectAtIndex: j]))
      { CLFail (error, @"Holiday dates must use YYYY-MM-DD."); return nil; }
  /* An unfinished timer could otherwise arrive after the month is closed. */
  if ([[[self timer] objectForKey: @"clientID"] isEqual: identifier]
      && [[[self timer] objectForKey: @"date"] compare: end] != NSOrderedDescending)
    { CLFail (error, @"Stop and review this client's running timer before monthly billing."); return nil; }
  for (i = 0; i < [[self entries] count]; i++)
    {
      NSDictionary *entry = [[self entries] objectAtIndex: i];
      NSString *date = [entry objectForKey: @"date"];
      NSString *last = [entry objectForKey: @"periodEnd"] ?: date;
      BOOL holiday = NO;
      if (![[entry objectForKey: @"clientID"] isEqual: identifier] || ![CLLedger isUnbilledEntry: entry]
          || [date compare: end] == NSOrderedDescending || [last compare: start] == NSOrderedAscending) continue;
      for (j = 0; j < [holidays count]; j++)
        if ([[holidays objectAtIndex: j] compare: date] != NSOrderedAscending
            && [[holidays objectAtIndex: j] compare: last] != NSOrderedDescending) holiday = YES;
      if ([date compare: start] == NSOrderedAscending || [last compare: end] == NSOrderedDescending
          || (holiday && ![date isEqual: last]))
        {
          CLFail (error, [NSString stringWithFormat: @"Time %@ overlaps a month boundary or holiday. Replace this period total with daily entries before billing %@.",
            [CLLedger dateLabelForEntry: entry], month]);
          return nil;
        }
      if (!holiday) [identifiers addObject: [entry objectForKey: @"id"]];
    }
  return identifiers;
}

- (BOOL) invoiceMonth: (NSString *)month client: (NSString *)identifier holidays: (NSArray *)holidays
                 tax: (NSString *)tax issuedDate: (NSString *)issuedDate error: (NSString **)error
{
  NSSet *identifiers = [self monthlyEntryIDs: month client: identifier holidays: holidays error: error];
  if (identifiers == nil) return NO;
  if ([identifiers count] == 0) return CLFail (error, @"No eligible unbilled hours in this month after holiday exclusions.");
  return [self issueClient: identifier task: nil hours: nil tax: tax issuedDate: issuedDate dueDate: nil
    entryIDs: identifiers advanceMonth: nil error: error];
}

- (NSArray *) runRecurringOnDate: (NSString *)date
{
  NSMutableArray *errors = [NSMutableArray array];
  NSArray *clients = [NSArray arrayWithArray: [self clients]];
  unsigned int i;
  if (!CLValidDate (date)) return [NSArray arrayWithObject: @"Invalid recurring billing date."];
  for (i = 0; i < [clients count]; i++)
    {
      NSString *identifier = [[clients objectAtIndex: i] objectForKey: @"id"];
      unsigned int processed = 0;
      while (processed++ < 1200)
        {
          NSDictionary *client = [self clientWithID: identifier];
          NSDictionary *schedule = [client objectForKey: @"recurring"];
          NSString *month, *next, *issue, *error = nil;
          NSSet *identifiers;
          BOOL saved;
          if (![[schedule objectForKey: @"enabled"] boolValue]) break;
          month = [schedule objectForKey: @"nextMonth"];
          next = CLNextMonth (month);
          issue = [NSString stringWithFormat: @"%@-%02d", next, [[schedule objectForKey: @"day"] intValue]];
          if ([issue compare: date] == NSOrderedDescending) break;
          identifiers = [self monthlyEntryIDs: month client: identifier holidays: [schedule objectForKey: @"holidays"] error: &error];
          if (identifiers == nil) saved = NO;
          else if ([identifiers count] == 0)
            {
              NSMutableDictionary *backup = [self backup];
              NSMutableDictionary *updatedSchedule = [NSMutableDictionary dictionaryWithDictionary: schedule];
              [updatedSchedule setObject: next forKey: @"nextMonth"];
              [[self record: identifier in: @"clients"] setObject: updatedSchedule forKey: @"recurring"];
              saved = [self commit: backup error: &error];
            }
          else saved = [self issueClient: identifier task: nil hours: nil tax: [schedule objectForKey: @"tax"]
            issuedDate: issue dueDate: nil entryIDs: identifiers advanceMonth: next error: &error];
          if (!saved)
            {
              [errors addObject: [NSString stringWithFormat: @"%@: %@", [[clients objectAtIndex: i] objectForKey: @"name"], error]];
              break;
            }
        }
    }
  return errors;
}
