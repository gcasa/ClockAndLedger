/* Company bookkeeping; included in CLLedger's implementation. */
- (NSArray *) accounts { return [_data objectForKey: @"accounts"] ?: [NSArray array]; }
- (NSArray *) expenses { return [_data objectForKey: @"expenses"] ?: [NSArray array]; }
+ (NSNumber *) receivedForInvoice: (NSDictionary *)invoice
{
  NSArray *payments = [invoice objectForKey: @"payments"];
  long long total = 0;
  NSDictionary *payment;
  if (payments == nil) return [NSNumber numberWithLongLong: [[invoice objectForKey: @"paid"] boolValue] && ![[invoice objectForKey: @"paymentUnverified"] boolValue] ? [[invoice objectForKey: @"total"] longLongValue] : 0];
  for (payment in payments) total += [[payment objectForKey: @"amount"] longLongValue];
  return [NSNumber numberWithLongLong: total];
}
+ (NSNumber *) balanceForInvoice: (NSDictionary *)invoice
{
  return [NSNumber numberWithLongLong: MAX (0, [[invoice objectForKey: @"total"] longLongValue] - [[self receivedForInvoice: invoice] longLongValue])];
}
- (NSNumber *) balanceForAccount: (NSString *)identifier
{
  long long balance = [[[self record: identifier in: @"accounts"] objectForKey: @"openingBalance"] longLongValue];
  NSDictionary *invoice, *payment, *expense;
  for (invoice in [self invoices]) for (payment in [invoice objectForKey: @"payments"])
    if ([[payment objectForKey: @"accountID"] isEqual: identifier]) balance += [[payment objectForKey: @"amount"] longLongValue];
  for (expense in [self expenses]) if ([[expense objectForKey: @"accountID"] isEqual: identifier]) balance -= [[expense objectForKey: @"amount"] longLongValue];
  return [NSNumber numberWithLongLong: balance];
}
- (BOOL) saveAccount: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error
{
  NSString *opening = [values objectForKey: @"openingBalance"];
  BOOL negative = [opening hasPrefix: @"-"];
  NSNumber *amount = [CLLedger centsFromString: negative ? [opening substringFromIndex: 1] : opening];
  NSMutableDictionary *record, *backup;
  NSDictionary *existing;
  NSString *currency = [[values objectForKey: @"currency"] uppercaseString];
  if (!CLFields (values, @"name,bank,number,routing,currency,openingBalance,notes", @"") || amount == nil || ![CLTrim ([values objectForKey: @"name"]) length] || [currency length] != 3 || [currency rangeOfCharacterFromSet: [[NSCharacterSet characterSetWithCharactersInString: @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet]].location != NSNotFound)
    return CLFail (error, @"Enter an account name, three-letter currency and valid opening balance.");
  for (existing in [self accounts]) if (![[existing objectForKey: @"id"] isEqual: identifier] && [[existing objectForKey: @"name"] caseInsensitiveCompare: CLTrim ([values objectForKey: @"name"])] == NSOrderedSame)
    return CLFail (error, @"Account names must be unique.");
  existing = [self record: identifier in: @"accounts"];
  if (identifier && !existing) return CLFail (error, @"Account not found.");
  if (existing && ![[existing objectForKey: @"currency"] isEqual: currency]) return CLFail (error, @"Create a separate account for a different currency.");
  backup = [self backup]; record = [NSMutableDictionary dictionaryWithDictionary: values];
  [record setObject: identifier ?: CLIdentifier () forKey: @"id"];
  [record setObject: CLTrim ([values objectForKey: @"name"]) forKey: @"name"];
  [record setObject: currency forKey: @"currency"];
  [record setObject: [NSNumber numberWithLongLong: [amount longLongValue] * (negative ? -1 : 1)] forKey: @"openingBalance"];
  if (![_data objectForKey: @"accounts"]) [_data setObject: [NSMutableArray array] forKey: @"accounts"];
  if (existing) [[_data objectForKey: @"accounts"] removeObject: existing];
  [[_data objectForKey: @"accounts"] addObject: record];
  return [self commit: backup error: error];
}
- (BOOL) saveExpense: (NSString *)identifier values: (NSDictionary *)values error: (NSString **)error
{
  NSNumber *amount = [CLLedger centsFromString: [values objectForKey: @"amount"]];
  NSDictionary *account = [self record: [values objectForKey: @"accountID"] in: @"accounts"];
  NSMutableDictionary *record, *backup;
  NSDictionary *existing = [self record: identifier in: @"expenses"];
  NSData *receipt = [values objectForKey: @"receiptData"];
  if (!CLFields (values, @"date,vendor,category,notes,reference,accountID,amount", @"") || !CLValidDate ([values objectForKey: @"date"]) || ![CLTrim ([values objectForKey: @"vendor"]) length] || ![CLTrim ([values objectForKey: @"category"]) length] || [amount longLongValue] <= 0 || !account)
    return CLFail (error, @"Enter a valid date, vendor, category, positive amount and bank account.");
  if (receipt && (![receipt isKindOfClass: [NSData class]] || [receipt length] > 20 * 1024 * 1024 || ![[values objectForKey: @"receiptName"] isKindOfClass: [NSString class]])) return CLFail (error, @"Receipt must be a file of 20 MB or less.");
  if (identifier && !existing) return CLFail (error, @"Expense not found.");
  backup = [self backup]; record = [NSMutableDictionary dictionaryWithDictionary: values];
  [record setObject: identifier ?: CLIdentifier () forKey: @"id"]; [record setObject: amount forKey: @"amount"];
  [record setObject: [account objectForKey: @"currency"] forKey: @"currency"];
  if (![_data objectForKey: @"expenses"]) [_data setObject: [NSMutableArray array] forKey: @"expenses"];
  if (existing) [[_data objectForKey: @"expenses"] removeObject: existing];
  [[_data objectForKey: @"expenses"] addObject: record];
  return [self commit: backup error: error];
}
- (BOOL) deleteExpense: (NSString *)identifier error: (NSString **)error
{
  NSDictionary *record = [self record: identifier in: @"expenses"];
  NSMutableDictionary *backup;
  if (!record) return CLFail (error, @"Select an expense.");
  backup = [self backup]; [[_data objectForKey: @"expenses"] removeObject: record]; return [self commit: backup error: error];
}
- (BOOL) savePayment: (NSString *)identifier invoice: (NSString *)invoiceID values: (NSDictionary *)values error: (NSString **)error
{
  NSMutableDictionary *invoice = [self record: invoiceID in: @"invoices"];
  NSDictionary *account = [self record: [values objectForKey: @"accountID"] in: @"accounts"];
  NSNumber *amount = [CLLedger centsFromString: [values objectForKey: @"amount"]];
  NSMutableDictionary *backup, *record;
  NSMutableArray *payments;
  NSUInteger index;
  if (!invoice || !CLFields (values, @"date,accountID,amount,reference", @"") || !CLValidDate ([values objectForKey: @"date"]) || [amount longLongValue] <= 0 || ([[values objectForKey: @"accountID"] length] && !account)) return CLFail (error, @"Enter a valid payment date, positive amount and account (or Unassigned).");
  if (account && ![[account objectForKey: @"currency"] isEqual: [[invoice objectForKey: @"business"] objectForKey: @"currency"]]) return CLFail (error, @"The account currency must match the invoice.");
  payments = [NSMutableArray arrayWithArray: [invoice objectForKey: @"payments"] ?: [NSArray array]];
  index = NSNotFound;
  if (identifier) { NSUInteger i; for (i=0; i<[payments count]; i++) if ([[[payments objectAtIndex: i] objectForKey: @"id"] isEqual: identifier]) index=i;
    if (index == NSNotFound) return CLFail (error, @"Payment not found."); }
  if ([payments count] >= 10000) return CLFail (error, @"Payment limit reached.");
  record = [NSMutableDictionary dictionaryWithDictionary: values];
  [record setObject: identifier ?: CLIdentifier () forKey: @"id"]; [record setObject: amount forKey: @"amount"];
  if (index == NSNotFound) [payments addObject: record]; else [payments replaceObjectAtIndex: index withObject: record];
  backup = [self backup]; [invoice setObject: payments forKey: @"payments"];
  [invoice removeObjectForKey: @"paymentUnverified"];
  [invoice setObject: [NSNumber numberWithBool: [[CLLedger receivedForInvoice: invoice] longLongValue] >= [[invoice objectForKey: @"total"] longLongValue]] forKey: @"paid"];
  return [self commit: backup error: error];
}
- (BOOL) deletePayment: (NSString *)identifier invoice: (NSString *)invoiceID error: (NSString **)error
{
  NSMutableDictionary *invoice = [self record: invoiceID in: @"invoices"];
  NSMutableArray *payments = [NSMutableArray arrayWithArray: [invoice objectForKey: @"payments"] ?: [NSArray array]];
  NSUInteger i;
  for (i=0; i<[payments count]; i++) if ([[[payments objectAtIndex: i] objectForKey: @"id"] isEqual: identifier])
    { NSMutableDictionary *backup = [self backup]; [payments removeObjectAtIndex: i]; [invoice setObject: payments forKey: @"payments"];
      [invoice setObject: [NSNumber numberWithBool: [[CLLedger receivedForInvoice: invoice] longLongValue] >= [[invoice objectForKey: @"total"] longLongValue]] forKey: @"paid"]; return [self commit: backup error: error]; }
  return CLFail (error, @"Select a recorded payment.");
}
