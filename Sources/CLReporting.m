#import "CLReporting.h"
#import "CLLedger.h"

static void CLAdd (NSMutableDictionary *row, NSString *key, long long amount)
{
  [row setObject: [NSNumber numberWithLongLong: [[row objectForKey: key] longLongValue] + amount] forKey: key];
}
static NSMutableDictionary *CLGroup (NSMutableDictionary *groups, NSString *identifier, NSString *label)
{
  NSMutableDictionary *row = [groups objectForKey: identifier];
  if (!row)
    {
      row = [NSMutableDictionary dictionaryWithObjectsAndKeys: label ?: @"Unknown", @"name", identifier, @"id", nil];
      [groups setObject: row forKey: identifier];
    }
  return row;
}
static NSArray *CLSortedGroups (NSDictionary *groups)
{
  return [[groups allValues] sortedArrayUsingDescriptors: [NSArray arrayWithObject:
    [[[NSSortDescriptor alloc] initWithKey: @"name" ascending: YES selector: @selector(localizedCaseInsensitiveCompare:)] autorelease]]];
}
@implementation CLReporting
+ (BOOL) date: (NSString *)date from: (NSString *)start to: (NSString *)end
{
  return [date length] == 10 && [date compare: start] != NSOrderedAscending && [date compare: end] != NSOrderedDescending;
}
+ (NSDictionary *) reportForLedger: (CLLedger *)ledger from: (NSString *)start to: (NSString *)end currency: (NSString *)currency today: (NSString *)today
{
  NSMutableDictionary *summary = [NSMutableDictionary dictionary];
  NSMutableDictionary *months = [NSMutableDictionary dictionary], *clients = [NSMutableDictionary dictionary];
  NSMutableDictionary *categories = [NSMutableDictionary dictionary], *time = [NSMutableDictionary dictionary];
  NSMutableArray *receivables = [NSMutableArray array];
  NSDictionary *invoice, *payment, *expense, *entry;
  NSArray *appPerformance, *appMonthly;
  for (invoice in [ledger invoices])
    {
      NSString *clientID = [invoice objectForKey: @"clientID"] ?: [[invoice objectForKey: @"client"] objectForKey: @"id"] ?: @"unknown";
      NSMutableDictionary *client;
      long long balance;
      if (![[[invoice objectForKey: @"business"] objectForKey: @"currency"] isEqual: currency]) continue;
      client = CLGroup (clients, clientID, [[invoice objectForKey: @"client"] objectForKey: @"name"]);
      if ([self date: [invoice objectForKey: @"date"] from: start to: end])
        { CLAdd (summary, @"billed", [[invoice objectForKey: @"total"] longLongValue]); CLAdd (client, @"billed", [[invoice objectForKey: @"total"] longLongValue]); }
      if ([[invoice objectForKey: @"paymentUnverified"] boolValue])
        { CLAdd (summary, @"unverified", 1); continue; }
      if (![invoice objectForKey: @"payments"] && [[invoice objectForKey: @"paid"] boolValue])
        CLAdd (summary, @"undated", 1);
      for (payment in [invoice objectForKey: @"payments"])
        if ([self date: [payment objectForKey: @"date"] from: start to: end])
          {
            long long amount = [[payment objectForKey: @"amount"] longLongValue];
            NSString *month = [[payment objectForKey: @"date"] substringToIndex: 7];
            CLAdd (summary, @"received", amount); CLAdd (client, @"received", amount);
            CLAdd (CLGroup (months, month, month), @"received", amount);
          }
      balance = [[CLLedger balanceForInvoice: invoice] longLongValue];
      CLAdd (summary, @"outstanding", balance); CLAdd (client, @"outstanding", balance);
      if (balance > 0)
        {
          NSString *due = [invoice objectForKey: @"dueDate"];
          BOOL known = ![[invoice objectForKey: @"dueDateUnverified"] boolValue] && [due length] == 10;
          BOOL overdue = known && [due compare: today] == NSOrderedAscending;
          NSMutableDictionary *row = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [invoice objectForKey: @"id"], @"id", [CLLedger invoiceNumber: invoice], @"name",
            [[invoice objectForKey: @"client"] objectForKey: @"name"] ?: @"Unknown", @"client",
            known ? due : @"Unknown", @"dueDate", [NSNumber numberWithLongLong: balance], @"outstanding",
            overdue ? @"Overdue" : (known ? @"Not overdue" : @"Review due date"), @"status", nil];
          [receivables addObject: row];
          if (overdue) CLAdd (summary, @"overdue", balance);
        }
    }
  for (expense in [ledger expenses])
    if ([[expense objectForKey: @"currency"] isEqual: currency] && [self date: [expense objectForKey: @"date"] from: start to: end])
      {
        long long amount = [[expense objectForKey: @"amount"] longLongValue];
        NSString *month = [[expense objectForKey: @"date"] substringToIndex: 7];
        NSString *category = [expense objectForKey: @"category"] ?: @"Uncategorized";
        CLAdd (summary, @"expenses", amount); CLAdd (CLGroup (months, month, month), @"expenses", amount);
        CLAdd (CLGroup (categories, category, category), @"expenses", amount);
        CLAdd (CLGroup (categories, category, category), @"count", 1);
      }
  if ([[[ledger business] objectForKey: @"currency"] isEqual: currency])
    for (entry in [ledger entries])
      {
        BOOL billable = [CLLedger isBillableEntry: entry];
        long long amount = [[CLLedger amountForSeconds: [entry objectForKey: @"seconds"] rate: [entry objectForKey: @"rate"]] longLongValue];
        if ([CLLedger isUnbilledEntry: entry]) CLAdd (summary, @"unbilled", amount);
        if ([self date: [entry objectForKey: @"date"] from: start to: end])
          {
            NSString *clientID = [entry objectForKey: @"clientID"];
            NSMutableDictionary *row = CLGroup (time, clientID, [[ledger clientWithID: clientID] objectForKey: @"name"]);
            NSString *key = billable ? @"billableSeconds" : @"nonbillableSeconds";
            CLAdd (summary, key, [[entry objectForKey: @"seconds"] longLongValue]);
            CLAdd (row, key, [[entry objectForKey: @"seconds"] longLongValue]);
            if (billable) CLAdd (row, @"value", amount);
          }
      }
#include "CLAppRevenueReporting.inc"
  {
    NSMutableDictionary *row;
    CLAdd (summary, @"net", [[summary objectForKey: @"received"] longLongValue] - [[summary objectForKey: @"expenses"] longLongValue]);
    for (row in [months allValues]) CLAdd (row, @"net", [[row objectForKey: @"received"] longLongValue] - [[row objectForKey: @"expenses"] longLongValue]);
    for (row in [time allValues])
      {
        [row setObject: [NSNumber numberWithDouble: [[row objectForKey: @"billableSeconds"] doubleValue] / 3600] forKey: @"billableHours"];
        [row setObject: [NSNumber numberWithDouble: [[row objectForKey: @"nonbillableSeconds"] doubleValue] / 3600] forKey: @"nonbillableHours"];
      }
  }
  return [NSDictionary dictionaryWithObjectsAndKeys: summary, @"summary", CLSortedGroups (months), @"monthly",
    CLSortedGroups (clients), @"clients", CLSortedGroups (categories), @"categories", CLSortedGroups (time), @"time", receivables, @"receivables", appPerformance, @"apps", appMonthly, @"appMonthly", nil];
}
+ (NSString *) csvForRows: (NSArray *)rows keys: (NSArray *)keys titles: (NSArray *)titles moneyKeys: (NSArray *)moneyKeys
{
  NSMutableString *csv = [NSMutableString string];
  NSMutableArray *all = [NSMutableArray arrayWithObject: titles];
  NSDictionary *row; NSArray *values; NSUInteger rowIndex = 0;
  for (row in rows)
    {
      NSMutableArray *values = [NSMutableArray array]; NSString *key;
      for (key in keys)
        {
          id value = [row objectForKey: key] ?: @"";
          if ([moneyKeys containsObject: key] && !([[NSArray arrayWithObjects: @"sales", @"refunds", @"fees", nil] containsObject: key] && ![value isKindOfClass: [NSNumber class]])) value = [CLLedger money: value];
          [values addObject: [value description]];
        }
      [all addObject: values];
    }
  for (values in all)
    {
      NSMutableArray *quoted = [NSMutableArray array]; NSString *value; NSUInteger columnIndex = 0;
      for (value in values)
        {
          BOOL numeric = rowIndex > 0 && ([moneyKeys containsObject: [keys objectAtIndex: columnIndex]] ||
            [[[rows objectAtIndex: rowIndex - 1] objectForKey: [keys objectAtIndex: columnIndex]] isKindOfClass: [NSNumber class]]);
          if (!numeric && [value length] && [@"=+-@\t\r\n" rangeOfString: [value substringToIndex: 1]].location != NSNotFound) value = [@"'" stringByAppendingString: value];
          [quoted addObject: [NSString stringWithFormat: @"\"%@\"", [value stringByReplacingOccurrencesOfString: @"\"" withString: @"\"\""]]];
          columnIndex++;
        }
      [csv appendFormat: @"%@\r\n", [quoted componentsJoinedByString: @","]];
      rowIndex++;
    }
  return csv;
}
@end
