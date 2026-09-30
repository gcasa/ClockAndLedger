static BOOL CLValidFinance (NSDictionary *data)
{
  NSArray *accounts = [data objectForKey: @"accounts"], *expenses = [data objectForKey: @"expenses"];
  NSMutableDictionary *currencies = [NSMutableDictionary dictionary];
  NSMutableSet *ids = [NSMutableSet set];
  NSDictionary *record, *invoice;
  unsigned long long transactionCount = 0;
  if ((accounts && ![accounts isKindOfClass: [NSArray class]]) || (expenses && ![expenses isKindOfClass: [NSArray class]])) return NO;
  for (record in accounts)
    {
      if (![record isKindOfClass: [NSDictionary class]]) return NO;
      NSNumber *opening = [record objectForKey: @"openingBalance"];
      NSString *currency = [record objectForKey: @"currency"];
      if (!CLFields (record, @"id,name,bank,number,routing,currency,notes", @"") || ![[record objectForKey: @"id"] length] || [ids containsObject: [record objectForKey: @"id"]] || ![opening isKindOfClass: [NSNumber class]] || !isfinite ([opening doubleValue]) || [opening doubleValue] != [opening longLongValue] || ([opening longLongValue] < -100000000000LL || [opening longLongValue] > 100000000000LL) || [currency length] != 3 || [currency rangeOfCharacterFromSet: [[NSCharacterSet characterSetWithCharactersInString: @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet]].location != NSNotFound) return NO;
      [ids addObject: [record objectForKey: @"id"]]; [currencies setObject: currency forKey: [record objectForKey: @"id"]];
    }
  for (record in expenses)
    {
      if (![record isKindOfClass: [NSDictionary class]]) return NO;
      NSData *receipt = [record objectForKey: @"receiptData"];
      if (!CLFields (record, @"id,date,vendor,category,notes,reference,accountID,currency", @"amount") || !CLValidDate ([record objectForKey: @"date"]) || [ids containsObject: [record objectForKey: @"id"]] || [[record objectForKey: @"amount"] longLongValue] <= 0 || [[record objectForKey: @"amount"] longLongValue] > 100000000000LL || ![[currencies objectForKey: [record objectForKey: @"accountID"]] isEqual: [record objectForKey: @"currency"]]) return NO;
      if (receipt && (![receipt isKindOfClass: [NSData class]] || [receipt length] > 20 * 1024 * 1024 || ![[record objectForKey: @"receiptName"] isKindOfClass: [NSString class]])) return NO;
      [ids addObject: [record objectForKey: @"id"]]; transactionCount++;
    }
  for (invoice in [data objectForKey: @"invoices"])
    {
      NSArray *payments = [invoice objectForKey: @"payments"];
      long long received = 0;
      if (!payments) continue;
      if (![payments isKindOfClass: [NSArray class]] || [payments count] > 10000) return NO;
      for (record in payments)
        {
          if (!CLFields (record, @"id,date,accountID,reference", @"amount") || !CLValidDate ([record objectForKey: @"date"]) || [ids containsObject: [record objectForKey: @"id"]] || [[record objectForKey: @"amount"] longLongValue] <= 0 || [[record objectForKey: @"amount"] longLongValue] > 100000000000LL) return NO;
          if ([[record objectForKey: @"accountID"] length] && ![[currencies objectForKey: [record objectForKey: @"accountID"]] isEqual: [[invoice objectForKey: @"business"] objectForKey: @"currency"]]) return NO;
          [ids addObject: [record objectForKey: @"id"]]; received += [[record objectForKey: @"amount"] longLongValue]; transactionCount++;
        }
      if ([[invoice objectForKey: @"paymentUnverified"] boolValue] || [[invoice objectForKey: @"paid"] boolValue] != (received >= [[invoice objectForKey: @"total"] longLongValue])) return NO;
    }
  /* Bound aggregate arithmetic, well below signed 64-bit cents. */
  return transactionCount <= 1000000;
}
