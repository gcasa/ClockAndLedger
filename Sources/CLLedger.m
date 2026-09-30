#import "CLLedger.h"
#import "CLQuickBooksImporter.h"
#include <math.h>

static BOOL
CLFail (NSString **error, NSString *message)
{
  if (error != NULL)
    *error = message;
  return NO;
}

static NSString *
CLTrim (NSString *value)
{
  return [value stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSDecimalNumber *
CLDecimal (NSString *text, unsigned int places)
{
  NSString *value = CLTrim (text);
  unsigned int i;
  unsigned int decimals = 0;
  BOOL dot = NO;
  BOOL digit = NO;

  if ([value length] == 0 || [value length] > 15)
    return nil;
  for (i = 0; i < [value length]; i++)
    {
      unichar c = [value characterAtIndex: i];
      if (c == '.' && !dot)
        dot = YES;
      else if (c >= '0' && c <= '9')
        {
          digit = YES;
          if (dot)
            decimals++;
        }
      else
        return nil;
    }
  if (!digit || decimals > places)
    return nil;
  return [NSDecimalNumber decimalNumberWithString: value
    locale: [NSDictionary dictionaryWithObject: @"." forKey: NSLocaleDecimalSeparator]];
}

static BOOL
CLValidDate (NSString *value)
{
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  NSDate *date;
  if (![value isKindOfClass: [NSString class]]) return NO;
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  [formatter setLenient: NO];
  date = [formatter dateFromString: value];
  return date != nil && [[formatter stringFromDate: date] isEqualToString: value];
}

static NSString *
CLIdentifier (void)
{
  return [[NSProcessInfo processInfo] globallyUniqueString];
}

/* Validate persisted records before any UI or mutation can consume them. */
static BOOL
CLFields (id record, NSString *stringKeys, NSString *numberKeys)
{
  NSArray *keys;
  unsigned int i;
  if (![record isKindOfClass: [NSDictionary class]])
    return NO;
  keys = [stringKeys componentsSeparatedByString: @","];
  for (i = 0; i < [keys count]; i++)
    if ([[keys objectAtIndex: i] length] > 0
        && ![[record objectForKey: [keys objectAtIndex: i]] isKindOfClass: [NSString class]])
      return NO;
  keys = [numberKeys componentsSeparatedByString: @","];
  for (i = 0; i < [keys count]; i++)
    {
      id value;
      if ([[keys objectAtIndex: i] length] == 0)
        continue;
      value = [record objectForKey: [keys objectAtIndex: i]];
      if (![value isKindOfClass: [NSNumber class]] || [value longLongValue] < 0
          || [value doubleValue] != (double)[value longLongValue])
        return NO;
    }
  return YES;
}

static long long
CLStartingNumber (NSDictionary *business)
{
  id value = [business objectForKey: @"startingInvoiceNumber"];
  NSString *text;
  if (value == nil) return 1;
  if (![value isKindOfClass: [NSString class]]) return -1;
  text = CLTrim (value);
  if ([text length] == 0) return 1;
  if ([text length] > 10 || [text rangeOfCharacterFromSet:
      [[NSCharacterSet characterSetWithCharactersInString: @"0123456789"] invertedSet]].location != NSNotFound)
    return -1;
  return [text longLongValue] >= 1 && [text longLongValue] < 2147483646 ? [text longLongValue] : -1;
}

static BOOL
CLValidBusiness (id record)
{
  return CLFields (record, @"name,address,email,currency,notes", @"")
    && [[record objectForKey: @"name"] length] > 0
    && [[record objectForKey: @"currency"] length] == 3
    && CLStartingNumber (record) > 0
    && ([record objectForKey: @"logoData"] == nil
        || ([[record objectForKey: @"logoData"] isKindOfClass: [NSData class]]
            && [[record objectForKey: @"logoData"] length] <= 5 * 1024 * 1024));
}

static BOOL
CLValidClient (id record)
{
  return CLFields (record, @"id,name,email,address", @"rate")
    && [[record objectForKey: @"id"] length] > 0
    && [[record objectForKey: @"name"] length] > 0
    && CLStartingNumber (record) > 0
    && (([record objectForKey: @"autoReminders"] == nil && [record objectForKey: @"reminderDays"] == nil
         && [record objectForKey: @"reminderMessage"] == nil && [record objectForKey: @"overdueMessage"] == nil)
        || (CLFields (record, @"reminderMessage,overdueMessage", @"autoReminders,reminderDays")
            && [[record objectForKey: @"autoReminders"] intValue] <= 1
            && [[record objectForKey: @"reminderDays"] integerValue] <= 36500))
    && ([record objectForKey: @"nextClientInvoiceNumber"] == nil
        || (CLFields (record, @"", @"nextClientInvoiceNumber")
            && [[record objectForKey: @"startingInvoiceNumber"] length] > 0
            && [[record objectForKey: @"nextClientInvoiceNumber"] longLongValue] > CLStartingNumber (record)
            && [[record objectForKey: @"nextClientInvoiceNumber"] longLongValue] <= 2147483646))
    && [[record objectForKey: @"rate"] longLongValue] <= 100000000000LL
    && ([record objectForKey: @"netDays"] == nil
        || (CLFields (record, @"", @"netDays") && [[record objectForKey: @"netDays"] integerValue] <= 36500));
}

static BOOL
CLValidEntry (id record)
{
  if ([record isKindOfClass: [NSDictionary class]] && [record objectForKey: @"periodKind"] != nil)
    {
      NSDictionary *period;
      if (!CLFields (record, @"date,periodKind,periodEnd", @""))
        return NO;
      period = [CLLedger periodContainingDate: [record objectForKey: @"date"] kind: [record objectForKey: @"periodKind"] error: NULL];
      if (period == nil || ![[period objectForKey: @"start"] isEqual: [record objectForKey: @"date"]]
          || ![[period objectForKey: @"end"] isEqual: [record objectForKey: @"periodEnd"]])
        return NO;
    }
  if ([record isKindOfClass: [NSDictionary class]] && [record objectForKey: @"hours"] != nil)
    {
      NSDecimalNumber *hours;
      if (!CLFields (record, @"hours", @""))
        return NO;
      hours = CLDecimal ([record objectForKey: @"hours"], 4);
      if (hours == nil || [hours compare: [NSDecimalNumber zero]] != NSOrderedDescending
          || [hours compare: [NSDecimalNumber decimalNumberWithString: @"8760"]] == NSOrderedDescending)
        return NO;
    }
  return CLFields (record, @"id,clientID,date,description,invoiceID", @"seconds,rate")
    && [[record objectForKey: @"id"] length] > 0
    && CLValidDate ([record objectForKey: @"date"])
    && [[record objectForKey: @"seconds"] longLongValue] > 0
    && [[record objectForKey: @"seconds"] longLongValue] <= 31536000
    && [[record objectForKey: @"rate"] longLongValue] <= 100000000000LL;
}

static BOOL
CLValidInvoiceID (id identifier, long long start, long long next)
{
  long long number;
  if (![identifier isKindOfClass: [NSString class]] || ![identifier hasPrefix: @"INV-"]
      || [identifier length] > 14) return NO;
  number = [[identifier substringFromIndex: 4] longLongValue];
  return number >= start && number < next
    && [identifier isEqual: [NSString stringWithFormat: @"INV-%05lld", number]];
}

static BOOL
CLValidReminderHistory (id history)
{
  NSEnumerator *keys;
  NSString *key;
  if (history == nil) return YES;
  if (![history isKindOfClass: [NSDictionary class]]) return NO;
  keys = [history keyEnumerator];
  while ((key = [keys nextObject]) != nil)
    {
      NSDictionary *attempt = [history objectForKey: key];
      NSString *status;
      if (![key isEqual: @"due"] && ![key isEqual: @"overdue"]) return NO;
      if (!CLFields (attempt, @"status,date,detail", @"") || !CLValidDate ([attempt objectForKey: @"date"])) return NO;
      status = [attempt objectForKey: @"status"];
      if (![status isEqual: @"pending"] && ![status isEqual: @"submitted"] && ![status isEqual: @"review"]) return NO;
    }
  return YES;
}

/* Date-only UTC arithmetic avoids daylight-saving offsets in reminder windows. */
static NSInteger
CLDaysUntil (NSString *date, NSString *due)
{
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  return (NSInteger)llround ([[formatter dateFromString: due] timeIntervalSinceDate: [formatter dateFromString: date]] / 86400.0);
}

static BOOL
CLValidLedger (id data)
{
  NSArray *clients;
  NSArray *entries;
  NSArray *invoices;
  NSMutableSet *clientIDs = [NSMutableSet set];
  NSMutableSet *invoiceIDs = [NSMutableSet set];
  NSMutableSet *entryIDs = [NSMutableSet set];
  NSMutableDictionary *taskClients = [NSMutableDictionary dictionary];
  NSArray *tasks;
  unsigned int i;
  id timer;
  if (!CLFields (data, @"", @"version,nextInvoice")
      || [[data objectForKey: @"version"] intValue] != 1
      || [[data objectForKey: @"nextInvoice"] longLongValue] < 1
      || [[data objectForKey: @"nextInvoice"] longLongValue] > 2147483646
      || !CLValidBusiness ([data objectForKey: @"business"]))
    return NO;
  {
    id reserved = [data objectForKey: @"reservedInvoiceNumbers"];
    if (reserved != nil && ![reserved isKindOfClass: [NSArray class]]) return NO;
    for (i = 0; i < [reserved count]; i++)
      if (![[reserved objectAtIndex: i] isKindOfClass: [NSString class]]) return NO;
  }
  clients = [data objectForKey: @"clients"];
  entries = [data objectForKey: @"entries"];
  invoices = [data objectForKey: @"invoices"];
  if (![clients isKindOfClass: [NSArray class]] || ![entries isKindOfClass: [NSArray class]]
      || ![invoices isKindOfClass: [NSArray class]])
    return NO;
  for (i = 0; i < [clients count]; i++)
    {
      id client = [clients objectAtIndex: i];
      if (!CLValidClient (client) || [clientIDs containsObject: [client objectForKey: @"id"]])
        return NO;
      [clientIDs addObject: [client objectForKey: @"id"]];
    }
  tasks = [data objectForKey: @"tasks"];
  if (tasks != nil && ![tasks isKindOfClass: [NSArray class]])
    return NO;
  for (i = 0; i < [tasks count]; i++)
    {
      NSDictionary *task = [tasks objectAtIndex: i];
      if (!CLFields (task, @"id,clientID,name", @"rate,archived")
          || [[task objectForKey: @"id"] length] == 0
          || [[task objectForKey: @"name"] length] == 0
          || [[task objectForKey: @"rate"] longLongValue] > 100000000000LL
          || ![clientIDs containsObject: [task objectForKey: @"clientID"]]
          || [taskClients objectForKey: [task objectForKey: @"id"]] != nil)
        return NO;
      [taskClients setObject: [task objectForKey: @"clientID"] forKey: [task objectForKey: @"id"]];
    }
  for (i = 0; i < [invoices count]; i++)
    {
      id invoice = [invoices objectAtIndex: i];
      NSArray *lines;
      unsigned int j;
      if (!CLFields (invoice, @"id,date,dueDate,taxPercent", @"subtotal,tax,total,paid")
          || ([invoice objectForKey: @"displayNumber"] != nil
              && !CLValidInvoiceID ([invoice objectForKey: @"displayNumber"], 1, 2147483646))
          || !CLValidClient ([invoice objectForKey: @"client"])
          || !CLValidBusiness ([invoice objectForKey: @"business"])
          || !CLValidDate ([invoice objectForKey: @"date"])
          || !CLValidDate ([invoice objectForKey: @"dueDate"])
          || !CLValidReminderHistory ([invoice objectForKey: @"reminders"])
          || CLDecimal ([invoice objectForKey: @"taxPercent"], 2) == nil
          || [invoiceIDs containsObject: [invoice objectForKey: @"id"]]
          || !CLValidInvoiceID ([invoice objectForKey: @"id"], CLStartingNumber ([data objectForKey: @"business"]), [[data objectForKey: @"nextInvoice"] longLongValue]))
        return NO;
      [invoiceIDs addObject: [invoice objectForKey: @"id"]];
      lines = [invoice objectForKey: @"lines"];
      if (![lines isKindOfClass: [NSArray class]] || [lines count] == 0)
        return NO;
      for (j = 0; j < [lines count]; j++)
        if ((!CLValidEntry ([lines objectAtIndex: j])
             && !(CLFields ([lines objectAtIndex: j], @"date,description", @"amount,importedAmount")
                  && [[[lines objectAtIndex: j] objectForKey: @"importedAmount"] boolValue]
                  && CLValidDate ([[lines objectAtIndex: j] objectForKey: @"date"])))
            || !CLFields ([lines objectAtIndex: j], @"", @"amount"))
          return NO;
    }
  {
    NSArray *deleted = [data objectForKey: @"deletedInvoiceIDs"];
    NSMutableSet *used = [NSMutableSet setWithSet: invoiceIDs];
    if (deleted != nil && ![deleted isKindOfClass: [NSArray class]]) return NO;
    for (i = 0; i < [deleted count]; i++)
      {
        id identifier = [deleted objectAtIndex: i];
        if (!CLValidInvoiceID (identifier, CLStartingNumber ([data objectForKey: @"business"]),
            [[data objectForKey: @"nextInvoice"] longLongValue]) || [used containsObject: identifier])
          return NO;
        [used addObject: identifier];
      }
    if ([[data objectForKey: @"nextInvoice"] unsignedLongLongValue]
        != [used count] + CLStartingNumber ([data objectForKey: @"business"])) return NO;
  }
  for (i = 0; i < [entries count]; i++)
    {
      id entry = [entries objectAtIndex: i];
      if (!CLValidEntry (entry)
          || ![clientIDs containsObject: [entry objectForKey: @"clientID"]]
          || [entryIDs containsObject: [entry objectForKey: @"id"]]
          || ([[entry objectForKey: @"invoiceID"] length] > 0
              && ![invoiceIDs containsObject: [entry objectForKey: @"invoiceID"]]))
        return NO;
      if ([entry objectForKey: @"taskID"] != nil
          && (!CLFields (entry, @"taskID,taskName", @"")
              || ![[taskClients objectForKey: [entry objectForKey: @"taskID"]] isEqual: [entry objectForKey: @"clientID"]]))
        return NO;
      [entryIDs addObject: [entry objectForKey: @"id"]];
    }
  timer = [data objectForKey: @"timer"];
  if (timer != nil && (!CLFields (timer, @"clientID,date,description", @"rate")
      || ![[timer objectForKey: @"started"] isKindOfClass: [NSDate class]]
      || ![clientIDs containsObject: [timer objectForKey: @"clientID"]]
      || !CLValidDate ([timer objectForKey: @"date"])))
    return NO;
  if ([timer objectForKey: @"startedEpoch"] != nil
      && (![[timer objectForKey: @"startedEpoch"] isKindOfClass: [NSNumber class]]
          || !isfinite ([[timer objectForKey: @"startedEpoch"] doubleValue])))
    return NO;
  if ([timer objectForKey: @"taskID"] != nil
      && (!CLFields (timer, @"taskID,taskName", @"")
          || ![[taskClients objectForKey: [timer objectForKey: @"taskID"]] isEqual: [timer objectForKey: @"clientID"]]))
    return NO;
  return YES;
}

@interface CLLedger (Private)
- (NSMutableDictionary *) record: (NSString *)identifier in: (NSString *)collection;
- (NSMutableDictionary *) backup;
- (BOOL) commit: (NSMutableDictionary *)backup error: (NSString **)error;
@end

@implementation CLLedger

- (id) initWithPath: (NSString *)path error: (NSString **)error
{
  self = [super init];
  if (self != nil)
    {
      _path = [path copy];
      if ([[NSFileManager defaultManager] fileExistsAtPath: path])
        {
          NSData *bytes = [NSData dataWithContentsOfFile: path];
          id plist = nil;
          if (bytes != nil)
            plist = [NSPropertyListSerialization propertyListWithData: bytes
              options: NSPropertyListMutableContainersAndLeaves format: NULL error: NULL];
          if (!CLValidLedger (plist))
            {
              CLFail (error, @"The ledger cannot be read or has an unsupported format. Restore a backup; the file has not been changed.");
              [self release];
              return nil;
            }
          _data = [plist retain];
          if ([_data objectForKey: @"tasks"] == nil)
            [_data setObject: [NSMutableArray array] forKey: @"tasks"];
        }
      else
        {
          _data = [[NSMutableDictionary alloc] init];
          [_data setObject: [NSNumber numberWithInt: 1] forKey: @"version"];
          [_data setObject: [NSMutableArray array] forKey: @"clients"];
          [_data setObject: [NSMutableArray array] forKey: @"tasks"];
          [_data setObject: [NSMutableArray array] forKey: @"entries"];
          [_data setObject: [NSMutableArray array] forKey: @"invoices"];
          [_data setObject: [NSNumber numberWithInt: 1] forKey: @"nextInvoice"];
          [_data setObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Your business", @"name", @"", @"address", @"", @"email",
            @"USD", @"currency", @"", @"notes", nil]
            forKey: @"business"];
        }
    }
  return self;
}

- (void) dealloc
{
  [_path release];
  [_data release];
  [super dealloc];
}

- (NSArray *) clients
{
  return [_data objectForKey: @"clients"];
}
- (NSArray *) entries
{
  return [_data objectForKey: @"entries"];
}
- (NSArray *) invoices
{
  return [_data objectForKey: @"invoices"];
}
- (NSDictionary *) business
{
  return [_data objectForKey: @"business"];
}
- (NSDictionary *) timer
{
  return [_data objectForKey: @"timer"];
}

- (NSMutableDictionary *) record: (NSString *)identifier in: (NSString *)collection
{
  NSArray *records = [_data objectForKey: collection];
  unsigned int i;
  for (i = 0; i < [records count]; i++)
    if ([[[records objectAtIndex: i] objectForKey: @"id"] isEqual: identifier])
      return [records objectAtIndex: i];
  return nil;
}

- (NSDictionary *) clientWithID: (NSString *)identifier
{
  return [self record: identifier in: @"clients"];
}

- (NSMutableDictionary *) backup
{
  NSData *bytes = [NSPropertyListSerialization dataWithPropertyList: _data
    format: NSPropertyListXMLFormat_v1_0 options: 0 error: NULL];
  return [NSPropertyListSerialization propertyListWithData: bytes
    options: NSPropertyListMutableContainersAndLeaves format: NULL error: NULL];
}

- (BOOL) commit: (NSMutableDictionary *)backup error: (NSString **)error
{
  NSError *failure = nil;
  NSData *bytes = [NSPropertyListSerialization dataWithPropertyList: _data
    format: NSPropertyListXMLFormat_v1_0 options: 0 error: &failure];
  NSString *directory = [_path stringByDeletingLastPathComponent];
  BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath: directory
    withIntermediateDirectories: YES attributes: nil error: &failure];
  if (ok && bytes != nil)
    ok = [bytes writeToFile: _path options: NSDataWritingAtomic error: &failure];
  else
    ok = NO;
  if (!ok)
    {
      [_data release];
      _data = [backup retain];
      return CLFail (error, [NSString stringWithFormat: @"Could not save the ledger: %@. The change was rolled back.", [failure localizedDescription]]);
    }
  return YES;
}

+ (NSNumber *) centsFromString: (NSString *)string
{
  NSDecimalNumber *value = CLDecimal (string, 2);
  if (value == nil || [value compare: [NSDecimalNumber decimalNumberWithString: @"1000000000"]] == NSOrderedDescending)
    return nil;
  return [NSNumber numberWithLongLong:
    [[value decimalNumberByMultiplyingBy: [NSDecimalNumber decimalNumberWithString: @"100"]] longLongValue]];
}

+ (NSString *) money: (NSNumber *)cents
{
  long long value = [cents longLongValue];
  return [NSString stringWithFormat: @"%lld.%02lld", value / 100, value % 100];
}

+ (NSString *) today
{
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  return [formatter stringFromDate: [NSDate date]];
}

+ (NSNumber *) amountForSeconds: (NSNumber *)seconds rate: (NSNumber *)rate
{
  NSDecimalNumber *duration = [NSDecimalNumber decimalNumberWithString: [seconds stringValue]];
  NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString: [rate stringValue]];
  NSDecimalNumberHandler *rounding = [NSDecimalNumberHandler
    decimalNumberHandlerWithRoundingMode: NSRoundPlain scale: 0
    raiseOnExactness: NO raiseOnOverflow: YES raiseOnUnderflow: YES raiseOnDivideByZero: YES];
  NSDecimalNumber *value = [[duration decimalNumberByMultiplyingBy: price]
    decimalNumberByDividingBy: [NSDecimalNumber decimalNumberWithString: @"3600"]];
  return [NSNumber numberWithLongLong: [[value decimalNumberByRoundingAccordingToBehavior: rounding] longLongValue]];
}

- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate error: (NSString **)error
{
  return [self saveClient: identifier name: name email: email address: address rate: rate
    netDays: [NSString stringWithFormat: @"%ld", (long)[CLLedger netDaysForClient: [self clientWithID: identifier]]] error: error];
}

+ (NSInteger) netDaysForClient: (NSDictionary *)client
{
  return [client objectForKey: @"netDays"] == nil ? 30 : [[client objectForKey: @"netDays"] integerValue];
}

- (NSString *) dueDateForClient: (NSString *)identifier invoiceDate: (NSString *)date
{
  NSDictionary *client = [self clientWithID: identifier];
  NSCalendar *calendar;
  NSDateFormatter *formatter;
  NSDateComponents *offset;
  if (client == nil || !CLValidDate (date)) return nil;
  calendar = [[[NSCalendar alloc] initWithCalendarIdentifier: NSGregorianCalendar] autorelease];
  [calendar setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  formatter = [[[NSDateFormatter alloc] init] autorelease];
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setCalendar: calendar];
  [formatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  offset = [[[NSDateComponents alloc] init] autorelease];
  [offset setDay: [CLLedger netDaysForClient: client]];
  return [formatter stringFromDate: [calendar dateByAddingComponents: offset
    toDate: [formatter dateFromString: date] options: 0]];
}

- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate netDays: (NSString *)netDays error: (NSString **)error
{
  return [self saveClient: identifier name: name email: email address: address rate: rate netDays: netDays
    startingInvoiceNumber: [[self clientWithID: identifier] objectForKey: @"startingInvoiceNumber"] error: error];
}

- (BOOL) saveClient: (NSString *)identifier name: (NSString *)name
             email: (NSString *)email address: (NSString *)address
              rate: (NSString *)rate netDays: (NSString *)netDays
 startingInvoiceNumber: (NSString *)startingNumber error: (NSString **)error
{
  NSNumber *cents = [CLLedger centsFromString: rate];
  NSString *startText = CLTrim (startingNumber != nil ? startingNumber : @"");
  long long start = CLStartingNumber ([NSDictionary dictionaryWithObject: startText forKey: @"startingInvoiceNumber"]);
  NSString *days = CLTrim (netDays);
  NSMutableDictionary *backup;
  NSMutableDictionary *client;
  if ([days length] == 0 || [days length] > 5
      || [days rangeOfCharacterFromSet: [[NSCharacterSet characterSetWithCharactersInString: @"0123456789"] invertedSet]].location != NSNotFound
      || [days integerValue] > 36500)
    return CLFail (error, @"Enter net payment days as a whole number from 0 to 36500 (0 means due on receipt).");
  if ([CLTrim (name) length] == 0 || cents == nil)
    return CLFail (error, @"Enter a client name and a valid hourly rate (up to two decimal places).");
  client = [self record: identifier in: @"clients"];
  if (identifier != nil && client == nil)
    return CLFail (error, @"The client no longer exists.");
  if (start < 1)
    return CLFail (error, @"Enter a starting invoice number from 1 to 2147483645, or leave it blank to use business numbering.");
  if ([client objectForKey: @"nextClientInvoiceNumber"] != nil
      && ([startText length] == 0 || start != CLStartingNumber (client)))
    return CLFail (error, @"This client's starting invoice number cannot change after its custom numbering has been used.");
  backup = [self backup];
  if (client == nil)
    {
      client = [NSMutableDictionary dictionary];
      [client setObject: CLIdentifier () forKey: @"id"];
      [[_data objectForKey: @"clients"] addObject: client];
    }
  [client setObject: [startText length] == 0 ? @"" : [NSString stringWithFormat: @"%lld", start] forKey: @"startingInvoiceNumber"];
  [client setObject: CLTrim (name) forKey: @"name"];
  [client setObject: CLTrim (email) forKey: @"email"];
  [client setObject: address forKey: @"address"];
  [client setObject: cents forKey: @"rate"];
  [client setObject: [NSNumber numberWithInteger: [days integerValue]] forKey: @"netDays"];
  return [self commit: backup error: error];
}

- (BOOL) deleteClient: (NSString *)identifier error: (NSString **)error
{
  unsigned int i;
  NSMutableDictionary *backup;
  NSDictionary *client = [self clientWithID: identifier];
  if (client == nil)
    return CLFail (error, @"Select a client first.");
  if ([[self tasksForClient: identifier includeArchived: YES] count] > 0)
    return CLFail (error, @"This client has tasks and cannot be deleted. Its task history is preserved.");
  if ([[[self timer] objectForKey: @"clientID"] isEqual: identifier])
    return CLFail (error, @"Stop this client's timer first.");
  for (i = 0; i < [[self entries] count]; i++)
    if ([[[[self entries] objectAtIndex: i] objectForKey: @"clientID"] isEqual: identifier])
      return CLFail (error, @"This client has time records and cannot be deleted.");
  for (i = 0; i < [[self invoices] count]; i++)
    if ([[[[[self invoices] objectAtIndex: i] objectForKey: @"client"] objectForKey: @"id"] isEqual: identifier])
      return CLFail (error, @"This client has invoices and cannot be deleted.");
  backup = [self backup];
  [[_data objectForKey: @"clients"] removeObject: client];
  return [self commit: backup error: error];
}

- (BOOL) addTimeForClient: (NSString *)identifier date: (NSString *)date
             description: (NSString *)description hours: (NSString *)hours
                   error: (NSString **)error
{
  return [self addTimeForClient: identifier task: nil date: date period: @"day"
    description: description hours: hours error: error];
}

- (BOOL) deleteEntry: (NSString *)identifier error: (NSString **)error
{
  NSDictionary *entry = [self record: identifier in: @"entries"];
  NSMutableDictionary *backup;
  if (entry == nil)
    return CLFail (error, @"Select a time entry first.");
  if ([[entry objectForKey: @"invoiceID"] length] != 0
      || [[entry objectForKey: @"externalBilling"] isEqual: @"Billed in QuickBooks"])
    return CLFail (error, @"Invoiced time is locked and cannot be deleted.");
  backup = [self backup];
  [[_data objectForKey: @"entries"] removeObject: entry];
  return [self commit: backup error: error];
}

- (BOOL) startTimerForClient: (NSString *)identifier
               description: (NSString *)description error: (NSString **)error
{
  return [self startTimerForClient: identifier task: nil description: description error: error];
}

- (BOOL) stopTimer: (NSString **)error
{
  NSMutableDictionary *entry;
  NSMutableDictionary *backup;
  NSTimeInterval elapsed;
  if ([self timer] == nil)
    return CLFail (error, @"There is no running timer.");
  elapsed = [self timerElapsed];
  if (elapsed < 0 || elapsed > 31536000)
    return CLFail (error, @"The system clock changed or the timer exceeds one year. Correct the clock before stopping the timer.");
  backup = [self backup];
  entry = [NSMutableDictionary dictionaryWithDictionary: [self timer]];
  [entry removeObjectForKey: @"started"];
  [entry removeObjectForKey: @"startedEpoch"];
  [entry setObject: CLIdentifier () forKey: @"id"];
  [entry setObject: @"" forKey: @"invoiceID"];
  [entry setObject: [NSNumber numberWithLongLong: MAX (1, (long long)elapsed)] forKey: @"seconds"];
  [[_data objectForKey: @"entries"] addObject: entry];
  [_data removeObjectForKey: @"timer"];
  return [self commit: backup error: error];
}

- (BOOL) invoiceClient: (NSString *)identifier tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error
{
  return [self invoiceClient: identifier hours: nil tax: tax dueDate: dueDate error: error];
}

- (BOOL) invoiceClient: (NSString *)identifier hours: (NSString *)hours tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error
{
  return [self invoiceClient: identifier task: nil hours: hours tax: tax dueDate: dueDate error: error];
}

- (BOOL) invoiceClient: (NSString *)identifier task: (NSString *)taskID
                hours: (NSString *)hours tax: (NSString *)tax
              dueDate: (NSString *)dueDate error: (NSString **)error
{
  return [self invoiceClient: identifier task: taskID hours: hours tax: tax
    issuedDate: [CLLedger today] dueDate: dueDate error: error];
}

- (BOOL) invoiceClient: (NSString *)identifier task: (NSString *)taskID
                hours: (NSString *)hours tax: (NSString *)tax
           issuedDate: (NSString *)issuedDate dueDate: (NSString *)dueDate error: (NSString **)error
{
  NSDictionary *client = [self clientWithID: identifier];
  NSDictionary *task = [self record: taskID in: @"tasks"];
  NSDictionary *rateSource = task != nil ? task : client;
  NSDecimalNumber *percent = CLDecimal (tax, 2);
  NSMutableArray *lines = [NSMutableArray array];
  NSMutableDictionary *backup;
  NSMutableDictionary *invoice;
  NSString *invoiceID;
  long long subtotal = 0;
  long long taxCents;
  unsigned int i;
  int sequence;
  long long displaySequence;
  NSString *displayNumber;
  NSMutableSet *usedNumbers;
  BOOL customNumbering;
  NSDecimalNumber *taxAmount;
  NSDecimalNumberHandler *rounding;

  if (taskID != nil && (hours == nil || task == nil || [[task objectForKey: @"archived"] boolValue]
      || ![[task objectForKey: @"clientID"] isEqual: identifier]))
    return CLFail (error, @"Choose an active task belonging to this client for direct billing.");
  if (!CLValidDate (issuedDate))
    return CLFail (error, @"Enter a valid issued date (YYYY-MM-DD).");
  if (dueDate == nil)
    dueDate = [self dueDateForClient: identifier invoiceDate: issuedDate];
  if (client == nil || percent == nil
      || [percent compare: [NSDecimalNumber decimalNumberWithString: @"100"]] == NSOrderedDescending
      || !CLValidDate (dueDate) || [dueDate compare: issuedDate] == NSOrderedAscending)
    return CLFail (error, @"Choose a client, a tax percentage from 0 to 100 and a valid due date on or after the issued date (YYYY-MM-DD).");
  if (hours != nil)
    {
      NSDecimalNumber *duration = CLDecimal (hours, 4);
      NSDecimalNumber *amount;
      NSMutableDictionary *line;
      if (duration == nil || [duration compare: [NSDecimalNumber zero]] != NSOrderedDescending
          || [duration compare: [NSDecimalNumber decimalNumberWithString: @"8760"]] == NSOrderedDescending)
        return CLFail (error, @"Enter hours greater than zero and at most 8760, using up to four decimal places.");
      rounding = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode: NSRoundPlain
        scale: 0 raiseOnExactness: NO raiseOnOverflow: YES raiseOnUnderflow: YES raiseOnDivideByZero: YES];
      amount = [duration decimalNumberByMultiplyingBy:
        [NSDecimalNumber decimalNumberWithDecimal: [[rateSource objectForKey: @"rate"] decimalValue]]];
      subtotal = [[amount decimalNumberByRoundingAccordingToBehavior: rounding] longLongValue];
      line = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        CLIdentifier (), @"id", identifier, @"clientID", issuedDate, @"date",
        @"Professional services", @"description", @"", @"invoiceID",
        [duration stringValue], @"hours",
        [NSNumber numberWithLongLong: MAX (1, [[duration decimalNumberByMultiplyingBy:
          [NSDecimalNumber decimalNumberWithString: @"3600"]] longLongValue])], @"seconds",
        [rateSource objectForKey: @"rate"], @"rate", [NSNumber numberWithLongLong: subtotal], @"amount", nil];
      if (task != nil)
        {
          [line setObject: taskID forKey: @"taskID"];
          [line setObject: [task objectForKey: @"name"] forKey: @"taskName"];
          [line setObject: @"" forKey: @"description"];
        }
      [lines addObject: line];
    }
  for (i = 0; hours == nil && i < [[self entries] count]; i++)
    {
      NSDictionary *entry = [[self entries] objectAtIndex: i];
      if ([[entry objectForKey: @"clientID"] isEqual: identifier]
          && [CLLedger isUnbilledEntry: entry])
        {
          NSMutableDictionary *line = [NSMutableDictionary dictionaryWithDictionary: entry];
          NSNumber *amount = [CLLedger amountForSeconds: [entry objectForKey: @"seconds"] rate: [entry objectForKey: @"rate"]];
          [line setObject: amount forKey: @"amount"];
          [lines addObject: line];
          subtotal += [amount longLongValue];
        }
    }
  if ([lines count] == 0)
    return CLFail (error, @"This client has no unbilled time. Stop any running timer before invoicing it.");
  if ([[_data objectForKey: @"nextInvoice"] intValue] >= 2147483646)
    return CLFail (error, @"The invoice number limit has been reached.");
  customNumbering = [[client objectForKey: @"startingInvoiceNumber"] length] > 0;
  displaySequence = customNumbering ? ([client objectForKey: @"nextClientInvoiceNumber"] != nil
    ? [[client objectForKey: @"nextClientInvoiceNumber"] longLongValue] : CLStartingNumber (client))
    : [[_data objectForKey: @"nextInvoice"] longLongValue];
  usedNumbers = [NSMutableSet setWithArray: [_data objectForKey: @"reservedInvoiceNumbers"] ?: [NSArray array]];
  [usedNumbers addObjectsFromArray: [_data objectForKey: @"deletedInvoiceIDs"] ?: [NSArray array]];
  for (i = 0; i < [[self invoices] count]; i++)
    [usedNumbers addObject: [CLLedger invoiceNumber: [[self invoices] objectAtIndex: i]]];
  do {
    if (displaySequence >= 2147483646)
      return CLFail (error, @"The invoice number limit has been reached.");
    displayNumber = [NSString stringWithFormat: @"INV-%05lld", displaySequence++];
  } while ([usedNumbers containsObject: displayNumber]);
  backup = [self backup];
  sequence = [[_data objectForKey: @"nextInvoice"] intValue];
  invoiceID = [NSString stringWithFormat: @"INV-%05d", sequence];
  rounding = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode: NSRoundPlain
    scale: 0 raiseOnExactness: NO raiseOnOverflow: YES raiseOnUnderflow: YES raiseOnDivideByZero: YES];
  taxAmount = [[[NSDecimalNumber decimalNumberWithString: [NSString stringWithFormat: @"%lld", subtotal]]
    decimalNumberByMultiplyingBy: percent]
    decimalNumberByDividingBy: [NSDecimalNumber decimalNumberWithString: @"100"]];
  taxCents = [[taxAmount decimalNumberByRoundingAccordingToBehavior: rounding] longLongValue];
  invoice = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    invoiceID, @"id", issuedDate, @"date", dueDate, @"dueDate",
    [NSDictionary dictionaryWithDictionary: client], @"client",
    [NSDictionary dictionaryWithDictionary: [self business]], @"business",
    lines, @"lines", [percent stringValue], @"taxPercent",
    [NSNumber numberWithLongLong: subtotal], @"subtotal",
    [NSNumber numberWithLongLong: taxCents], @"tax",
    [NSNumber numberWithLongLong: subtotal + taxCents], @"total",
    [NSNumber numberWithBool: NO], @"paid", nil];
  [invoice setObject: displayNumber forKey: @"displayNumber"];
  if (customNumbering)
    [[self record: identifier in: @"clients"] setObject: [NSNumber numberWithLongLong: displaySequence] forKey: @"nextClientInvoiceNumber"];
  if ([_data objectForKey: @"reservedInvoiceNumbers"] == nil)
    [_data setObject: [NSMutableArray array] forKey: @"reservedInvoiceNumbers"];
  [[_data objectForKey: @"reservedInvoiceNumbers"] addObject: displayNumber];
  for (i = 0; hours == nil && i < [lines count]; i++)
    [[self record: [[lines objectAtIndex: i] objectForKey: @"id"] in: @"entries"]
      setObject: invoiceID forKey: @"invoiceID"];
  [[_data objectForKey: @"invoices"] addObject: invoice];
  [_data setObject: [NSNumber numberWithInt: sequence + 1] forKey: @"nextInvoice"];
  return [self commit: backup error: error];
}

- (BOOL) hasIssuedInvoices
{
  return [[_data objectForKey: @"nextInvoice"] longLongValue] > CLStartingNumber ([self business]);
}

- (BOOL) deleteInvoice: (NSString *)identifier error: (NSString **)error
{
  NSDictionary *invoice = [self record: identifier in: @"invoices"];
  NSMutableDictionary *backup;
  unsigned int i;
  if (invoice == nil)
    return CLFail (error, @"Select an invoice first.");
  backup = [self backup];
  /* Retain only its number so deletion never permits number reuse. */
  if ([_data objectForKey: @"deletedInvoiceIDs"] == nil)
    [_data setObject: [NSMutableArray array] forKey: @"deletedInvoiceIDs"];
  [[_data objectForKey: @"deletedInvoiceIDs"] addObject: identifier];
  if ([_data objectForKey: @"reservedInvoiceNumbers"] == nil)
    [_data setObject: [NSMutableArray array] forKey: @"reservedInvoiceNumbers"];
  if (![[_data objectForKey: @"reservedInvoiceNumbers"] containsObject: [CLLedger invoiceNumber: invoice]])
    [[_data objectForKey: @"reservedInvoiceNumbers"] addObject: [CLLedger invoiceNumber: invoice]];
  for (i = 0; i < [[self entries] count]; i++)
    {
      NSMutableDictionary *entry = [[self entries] objectAtIndex: i];
      if ([[entry objectForKey: @"invoiceID"] isEqual: identifier])
        [entry setObject: @"" forKey: @"invoiceID"];
    }
  [[_data objectForKey: @"invoices"] removeObject: invoice];
  return [self commit: backup error: error];
}

- (BOOL) togglePaid: (NSString *)identifier error: (NSString **)error
{
  NSDictionary *invoice = [self record: identifier in: @"invoices"];
  return [self setInvoice: identifier paid: ![[invoice objectForKey: @"paid"] boolValue] error: error];
}

- (BOOL) setInvoice: (NSString *)identifier paid: (BOOL)paid error: (NSString **)error
{
  NSMutableDictionary *invoice = [self record: identifier in: @"invoices"];
  NSMutableDictionary *backup;
  if (invoice == nil)
    return CLFail (error, @"Select an invoice first.");
  backup = [self backup];
  [invoice removeObjectForKey: @"paymentUnverified"];
  [invoice setObject: [NSNumber numberWithBool: paid] forKey: @"paid"];
  return [self commit: backup error: error];
}

+ (NSString *) invoiceNumber: (NSDictionary *)invoice
{
  NSString *source = [invoice objectForKey: @"sourceNumber"];
  if ([source length] > 0) return source;
  return [invoice objectForKey: @"displayNumber"] ?: [invoice objectForKey: @"id"];
}

- (BOOL) saveBusiness: (NSDictionary *)business error: (NSString **)error
{
  NSMutableDictionary *backup;
  NSString *currency = [[business objectForKey: @"currency"] uppercaseString];
  long long start = CLStartingNumber (business);
  BOOL issued = [self hasIssuedInvoices];
  NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString: @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"];
  if (start < 1)
    return CLFail (error, @"Enter a starting invoice number from 1 to 2147483645, or leave it blank for 1.");
  if ([self hasIssuedInvoices] && start != CLStartingNumber ([self business]))
    return CLFail (error, @"The starting number cannot change after an invoice has been issued or imported.");
  if ([business objectForKey: @"logoData"] != nil
      && (![[business objectForKey: @"logoData"] isKindOfClass: [NSData class]]
          || [[business objectForKey: @"logoData"] length] > 5 * 1024 * 1024))
    return CLFail (error, @"Choose a logo no larger than 5 MB.");
  if (!CLFields (business, @"name,email,address,currency,notes", @"")
      || [CLTrim ([business objectForKey: @"name"]) length] == 0 || [currency length] != 3
      || [currency rangeOfCharacterFromSet: [letters invertedSet]].location != NSNotFound)
    return CLFail (error, @"Enter a business name and a three-letter currency code, such as USD or EUR.");
  if (![[[self business] objectForKey: @"currency"] isEqual: currency] && ([[self entries] count] > 0 || [self hasIssuedInvoices]))
    return CLFail (error, @"Currency cannot change after time has been recorded. Use a separate ledger for another currency.");
  if ([self timer] != nil && ![[[self business] objectForKey: @"currency"] isEqual: currency])
    return CLFail (error, @"Stop the running timer before changing currency.");
  backup = [self backup];
  [_data setObject: [NSMutableDictionary dictionaryWithDictionary: business] forKey: @"business"];
  [[_data objectForKey: @"business"] setObject: currency forKey: @"currency"];
  [[_data objectForKey: @"business"] setObject: [NSString stringWithFormat: @"%lld", start] forKey: @"startingInvoiceNumber"];
  if (!issued)
    [_data setObject: [NSNumber numberWithLongLong: start] forKey: @"nextInvoice"];
  return [self commit: backup error: error];
}

+ (BOOL) isUnbilledEntry: (NSDictionary *)entry
{
  NSString *billing = [entry objectForKey: @"externalBilling"];
  return [[entry objectForKey: @"invoiceID"] length] == 0
    && (billing == nil || [billing isEqual: @"Billable"]);
}

- (BOOL) reviewImportedTime: (NSString *)identifier rate: (NSString *)rate
                 billable: (BOOL)billable error: (NSString **)error
{
  NSMutableDictionary *entry = [self record: identifier in: @"entries"];
  NSNumber *cents = [CLLedger centsFromString: rate];
  NSMutableDictionary *backup;
  if (entry == nil || [entry objectForKey: @"externalBilling"] == nil || cents == nil)
    return CLFail (error, @"Select imported time and enter a valid hourly rate.");
  if ([[entry objectForKey: @"invoiceID"] length] > 0
      || [[entry objectForKey: @"externalBilling"] isEqual: @"Billed in QuickBooks"])
    return CLFail (error, @"Previously billed time cannot be changed.");
  backup = [self backup];
  [entry setObject: cents forKey: @"rate"];
  [entry setObject: billable ? @"Billable" : @"Not billable" forKey: @"externalBilling"];
  return [self commit: backup error: error];
}

- (BOOL) importQuickBooksData: (NSData *)bytes filename: (NSString *)filename
                     commit: (BOOL)shouldCommit report: (NSString **)report
                      error: (NSString **)error
{
  NSDictionary *parsed = [CLQuickBooksImporter recordsFromData: bytes filename: filename error: error];
  NSMutableDictionary *original;
  NSMutableDictionary *working;
  NSMutableDictionary *byName = [NSMutableDictionary dictionary];
  NSMutableDictionary *bySource = [NSMutableDictionary dictionary];
  NSMutableDictionary *occurrences = [NSMutableDictionary dictionary];
  NSMutableArray *warnings;
  NSMutableArray *details = [NSMutableArray array];
  NSArray *kinds = [NSArray arrayWithObjects: @"clients", @"time", @"invoices", nil];
  NSUInteger addedClients = 0;
  NSUInteger addedTime = 0;
  NSUInteger addedInvoices = 0;
  NSUInteger skipped = 0;
  NSUInteger i;
  NSUInteger kind;
  BOOL ok = YES;
  if (parsed == nil)
    return NO;
  warnings = [NSMutableArray arrayWithArray: [parsed objectForKey: @"warnings"]];
  working = [[self backup] retain];
  original = _data;
  _data = working;
  for (i = 0; i < [[self clients] count]; i++)
    {
      NSDictionary *client = [[self clients] objectAtIndex: i];
      NSString *name = [[client objectForKey: @"name"] lowercaseString];
      if ([byName objectForKey: name] != nil)
        {
          ok = CLFail (error, @"Existing clients have duplicate names. Give them distinct full names before importing.");
          break;
        }
      [byName setObject: client forKey: name];
    }
  for (kind = 1; kind < 3; kind++)
    {
      NSArray *records = kind == 1 ? [self entries] : [self invoices];
      for (i = 0; i < [records count]; i++)
        {
          NSDictionary *record = [records objectAtIndex: i];
          if ([record objectForKey: @"sourceKey"] != nil)
            [bySource setObject: record forKey: [record objectForKey: @"sourceKey"]];
        }
    }
  for (kind = 0; kind < [kinds count] && ok; kind++)
    {
      NSArray *records = [parsed objectForKey: [kinds objectAtIndex: kind]];
      for (i = 0; i < [records count] && ok; i++)
        {
          NSDictionary *source = [records objectAtIndex: i];
          NSString *name = [source objectForKey: kind == 0 ? @"name" : @"clientName"];
          NSString *nameKey = [name lowercaseString];
          NSString *currency = [source objectForKey: @"currency"];
          NSMutableDictionary *client = [byName objectForKey: nameKey];
          NSMutableDictionary *record;
          NSString *key;
          NSDictionary *existing;
          if (currency != nil && ![currency isEqual: [[self business] objectForKey: @"currency"]])
            {
              ok = CLFail (error, [NSString stringWithFormat: @"Currency %@ does not match ledger currency %@. No records imported.", currency, [[self business] objectForKey: @"currency"]]);
              break;
            }
          if (client == nil)
            {
              client = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                CLIdentifier (), @"id", name, @"name", @"", @"email", @"", @"address",
                [NSNumber numberWithInt: 0], @"rate", nil];
              if (kind == 0)
                [client addEntriesFromDictionary: source];
              [[_data objectForKey: @"clients"] addObject: client];
              [byName setObject: client forKey: nameKey];
              addedClients++;
              [details addObject: [NSString stringWithFormat: @"Customer: %@", name]];
            }
          else if (kind == 0)
            {
              skipped++;
              [details addObject: [NSString stringWithFormat: @"Existing customer kept unchanged: %@", name]];
            }
          if (kind == 0)
            continue;
          if (kind == 2)
            key = [[NSArray arrayWithObjects: @"QB invoice", nameKey, [source objectForKey: @"sourceNumber"], nil] description];
          else if ([[source objectForKey: @"externalID"] length] > 0)
            key = [[NSArray arrayWithObjects: @"QB time ID", nameKey, [source objectForKey: @"externalID"], nil] description];
          else
            {
              NSString *identity = [[NSArray arrayWithObjects: @"QB time", nameKey,
                [source objectForKey: @"date"], [source objectForKey: @"seconds"],
                [source objectForKey: @"description"], [source objectForKey: @"employee"], nil] description];
              NSUInteger occurrence = [[occurrences objectForKey: identity] unsignedIntegerValue] + 1;
              [occurrences setObject: [NSNumber numberWithUnsignedInteger: occurrence] forKey: identity];
              key = [identity stringByAppendingFormat: @" occurrence %lu", (unsigned long)occurrence];
            }
          existing = [bySource objectForKey: key];
          if (existing != nil)
            {
              if (![[existing objectForKey: @"sourcePayload"] isEqual: source])
                ok = CLFail (error, [NSString stringWithFormat: @"An imported %@ for %@ has the same identity but different data. Resolve the conflict in the export before importing. Nothing was saved.", kind == 1 ? @"time entry" : @"invoice", name]);
              else
                skipped++;
              continue;
            }
          record = [NSMutableDictionary dictionaryWithDictionary: source];
          [record removeObjectForKey: @"clientName"];
          [record setObject: key forKey: @"sourceKey"];
          [record setObject: source forKey: @"sourcePayload"];
          if (kind == 1)
            {
              [record setObject: CLIdentifier () forKey: @"id"];
              [record setObject: [client objectForKey: @"id"] forKey: @"clientID"];
              [record setObject: @"" forKey: @"invoiceID"];
              if ([record objectForKey: @"rate"] == nil)
                {
                  [record setObject: [client objectForKey: @"rate"] forKey: @"rate"];
                  if ([[record objectForKey: @"externalBilling"] isEqual: @"Billable"])
                    [record setObject: @"Review required" forKey: @"externalBilling"];
                  [warnings addObject: [NSString stringWithFormat: @"Time for %@ on %@ has no exported rate; review its rate before billing.", name, [source objectForKey: @"date"]]];
                }
              [[_data objectForKey: @"entries"] addObject: record];
              addedTime++;
              [details addObject: [NSString stringWithFormat: @"Time: %@ / %@ / %.4f h / %@ / rate %@",
                name, [record objectForKey: @"date"], [[record objectForKey: @"seconds"] doubleValue] / 3600,
                [record objectForKey: @"externalBilling"], [CLLedger money: [record objectForKey: @"rate"]]]];
            }
          else
            {
              int sequence = [[_data objectForKey: @"nextInvoice"] intValue];
              if (sequence >= 2147483646)
                { ok = CLFail (error, @"The invoice number limit has been reached."); break; }
              [record setObject: [NSString stringWithFormat: @"INV-%05d", sequence] forKey: @"id"];
              [record setObject: [NSDictionary dictionaryWithDictionary: client] forKey: @"client"];
              [record setObject: [NSDictionary dictionaryWithDictionary: [self business]] forKey: @"business"];
              [[_data objectForKey: @"invoices"] addObject: record];
              [_data setObject: [NSNumber numberWithInt: sequence + 1] forKey: @"nextInvoice"];
              addedInvoices++;
              [details addObject: [NSString stringWithFormat: @"Invoice %@: %@ / %@ / total %@ / %@",
                [source objectForKey: @"sourceNumber"], name, [source objectForKey: @"date"],
                [CLLedger money: [source objectForKey: @"total"]],
                [[source objectForKey: @"paymentUnverified"] boolValue] ? @"Payment status needs review"
                  : ([[source objectForKey: @"paid"] boolValue] ? @"Paid" : @"Unpaid")]];
              if ([[source objectForKey: @"taxUnverified"] boolValue])
                [warnings addObject: [NSString stringWithFormat: @"Invoice %@ has no separate tax amount; its full total is retained as a summary amount.", [source objectForKey: @"sourceNumber"]]];
              if ([[source objectForKey: @"dueDateUnverified"] boolValue])
                [warnings addObject: [NSString stringWithFormat: @"Invoice %@ has no due date; its issue date is stored as a placeholder and it will not be marked overdue.", [source objectForKey: @"sourceNumber"]]];
            }
          [bySource setObject: record forKey: key];
        }
    }
  if (ok && !CLValidLedger (_data))
    ok = CLFail (error, @"Imported records failed ledger validation. Nothing was saved.");
  if (ok && report != NULL)
    *report = [NSString stringWithFormat:
      @"%@\n\n%lu new clients, %lu time entries, %lu invoices.\n%lu existing records skipped or preserved.\n\nAmounts without currency are assumed to be %@. One QuickBooks company per ledger.\nImported invoices use your current business details.\nInvoices with unknown payment status are excluded from outstanding totals until reviewed.\n\n%@\n\n%@",
      shouldCommit ? @"Import complete" : @"Review QuickBooks import",
      (unsigned long)addedClients, (unsigned long)addedTime, (unsigned long)addedInvoices,
      (unsigned long)skipped, [[self business] objectForKey: @"currency"],
      [warnings count] > 0 ? [warnings componentsJoinedByString: @"\n"] : @"No unsupported records found.",
      [details componentsJoinedByString: @"\n"]];
  if (!ok || !shouldCommit)
    {
      [_data release];
      _data = original;
      return ok;
    }
  ok = [self commit: original error: error];
  [original release];
  return ok;
}

+ (NSDictionary *) periodContainingDate: (NSString *)date kind: (NSString *)kind error: (NSString **)error
{
  NSDateFormatter *formatter;
  NSCalendar *calendar;
  NSDate *anchor;
  NSDate *start;
  NSDate *end;
  NSDateComponents *parts;
  NSDateComponents *offset;
  NSMutableArray *dates = [NSMutableArray array];
  NSDate *cursor;
  if (!CLValidDate (date) || (![kind isEqual: @"day"] && ![kind isEqual: @"week"] && ![kind isEqual: @"month"]))
    {
      CLFail (error, @"Choose Day, Week or Month and enter a valid YYYY-MM-DD date within that period.");
      return nil;
    }
  /* Calendar-only arithmetic uses UTC so DST never changes a date or day count. */
  calendar = [[[NSCalendar alloc] initWithCalendarIdentifier: NSGregorianCalendar] autorelease];
  [calendar setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  formatter = [[[NSDateFormatter alloc] init] autorelease];
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setCalendar: calendar];
  [formatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  anchor = [formatter dateFromString: date];
  parts = [calendar components: NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSWeekdayCalendarUnit fromDate: anchor];
  offset = [[[NSDateComponents alloc] init] autorelease];
  start = anchor;
  if ([kind isEqual: @"week"])
    {
      [offset setDay: -(([parts weekday] + 5) % 7)];
      start = [calendar dateByAddingComponents: offset toDate: anchor options: 0];
      [offset setDay: 6];
    }
  else if ([kind isEqual: @"month"])
    {
      [offset setDay: 1 - [parts day]];
      start = [calendar dateByAddingComponents: offset toDate: anchor options: 0];
      [offset setMonth: 1];
      [offset setDay: -1];
    }
  else
    [offset setDay: 0];
  end = [calendar dateByAddingComponents: offset toDate: start options: 0];
  [offset setMonth: 0];
  [offset setDay: 1];
  for (cursor = start; [cursor compare: end] != NSOrderedDescending;
       cursor = [calendar dateByAddingComponents: offset toDate: cursor options: 0])
    [dates addObject: [formatter stringFromDate: cursor]];
  return [NSDictionary dictionaryWithObjectsAndKeys: [formatter stringFromDate: start], @"start",
    [formatter stringFromDate: end], @"end", dates, @"dates", kind, @"kind", nil];
}

+ (NSString *) dateLabelForEntry: (NSDictionary *)entry
{
  NSString *end = [entry objectForKey: @"periodEnd"];
  NSString *start = [entry objectForKey: @"date"];
  return end != nil && ![end isEqual: start] ? [NSString stringWithFormat: @"%@ – %@", start, end] : start;
}

+ (NSString *) workLabelForEntry: (NSDictionary *)entry
{
  NSString *task = [entry objectForKey: @"taskName"];
  NSString *description = [entry objectForKey: @"description"];
  return [task length] > 0 && ![task isEqual: description]
    ? [NSString stringWithFormat: @"%@: %@", task, description] : description;
}

- (NSArray *) tasksForClient: (NSString *)identifier includeArchived: (BOOL)includeArchived
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *tasks = [_data objectForKey: @"tasks"];
  NSUInteger i;
  for (i = 0; i < [tasks count]; i++)
    {
      NSDictionary *task = [tasks objectAtIndex: i];
      if ([[task objectForKey: @"clientID"] isEqual: identifier]
          && (includeArchived || ![[task objectForKey: @"archived"] boolValue]))
        [result addObject: task];
    }
  return result;
}

- (BOOL) saveTask: (NSString *)identifier client: (NSString *)clientID
            name: (NSString *)name rate: (NSString *)rate error: (NSString **)error
{
  NSMutableDictionary *task = [self record: identifier in: @"tasks"];
  NSNumber *cents = [CLLedger centsFromString: rate];
  NSArray *tasks = [self tasksForClient: clientID includeArchived: YES];
  NSMutableDictionary *backup;
  NSUInteger i;
  if ([self clientWithID: clientID] == nil || [CLTrim (name) length] == 0 || cents == nil)
    return CLFail (error, @"Choose a client, enter a task name and a valid nonnegative hourly rate.");
  if (identifier != nil && (task == nil || ![[task objectForKey: @"clientID"] isEqual: clientID]))
    return CLFail (error, @"This task does not belong to the selected client.");
  for (i = 0; i < [tasks count]; i++)
    {
      NSDictionary *other = [tasks objectAtIndex: i];
      if (![[other objectForKey: @"id"] isEqual: identifier]
          && [[other objectForKey: @"name"] caseInsensitiveCompare: CLTrim (name)] == NSOrderedSame)
        return CLFail (error, @"This client already has a task with that name, including archived tasks.");
    }
  backup = [self backup];
  if (task == nil)
    {
      task = [NSMutableDictionary dictionaryWithObjectsAndKeys: CLIdentifier (), @"id",
        clientID, @"clientID", [NSNumber numberWithBool: NO], @"archived", nil];
      [[_data objectForKey: @"tasks"] addObject: task];
    }
  [task setObject: CLTrim (name) forKey: @"name"];
  [task setObject: cents forKey: @"rate"];
  return [self commit: backup error: error];
}

- (BOOL) toggleTaskArchived: (NSString *)identifier error: (NSString **)error
{
  NSMutableDictionary *task = [self record: identifier in: @"tasks"];
  NSMutableDictionary *backup;
  if (task == nil)
    return CLFail (error, @"Select a task first.");
  backup = [self backup];
  [task setObject: [NSNumber numberWithBool: ![[task objectForKey: @"archived"] boolValue]] forKey: @"archived"];
  return [self commit: backup error: error];
}

- (BOOL) addTimeForClient: (NSString *)identifier task: (NSString *)taskID
                    date: (NSString *)date period: (NSString *)kind
             description: (NSString *)description hours: (NSString *)hours
                   error: (NSString **)error
{
  NSDictionary *period = [CLLedger periodContainingDate: date kind: kind error: error];
  NSDictionary *row;
  if (period == nil)
    return NO;
  row = [NSDictionary dictionaryWithObjectsAndKeys: [period objectForKey: @"start"], @"date",
    [period objectForKey: @"end"], @"periodEnd", kind, @"periodKind",
    description, @"description", hours, @"hours", nil];
  return [self addTimeRows: [NSArray arrayWithObject: row] client: identifier task: taskID error: error];
}

- (BOOL) addTimeRows: (NSArray *)rows client: (NSString *)identifier
               task: (NSString *)taskID error: (NSString **)error
{
  NSDictionary *client = [self clientWithID: identifier];
  NSDictionary *task = [self record: taskID in: @"tasks"];
  NSMutableArray *entries = [NSMutableArray array];
  NSMutableDictionary *backup;
  NSUInteger i;
  if (client == nil || (taskID != nil && (task == nil
      || ![[task objectForKey: @"clientID"] isEqual: identifier]
      || [[task objectForKey: @"archived"] boolValue])))
    return CLFail (error, @"Choose a client and one of its active tasks (or the client default rate).");
  for (i = 0; i < [rows count]; i++)
    {
      NSDictionary *row = [rows objectAtIndex: i];
      NSDecimalNumber *duration;
      long long seconds;
      NSString *description;
      NSMutableDictionary *entry;
      if (!CLFields (row, @"date,hours,description", @""))
        return CLFail (error, @"Each timesheet row needs a date, hours and description.");
      if ([CLTrim ([row objectForKey: @"hours"]) length] == 0)
        continue;
      duration = CLDecimal ([row objectForKey: @"hours"], 4);
      if (duration == nil || !CLValidDate ([row objectForKey: @"date"]))
        return CLFail (error, [NSString stringWithFormat: @"Invalid hours or date for %@. Use nonnegative decimal hours with at most four decimal places.", [row objectForKey: @"date"]]);
      if ([duration compare: [NSDecimalNumber zero]] == NSOrderedSame)
        continue;
      seconds = [[duration decimalNumberByMultiplyingBy: [NSDecimalNumber decimalNumberWithString: @"3600"]] longLongValue];
      description = CLTrim ([row objectForKey: @"description"]);
      if ([description length] == 0 && task != nil)
        description = [task objectForKey: @"name"];
      if (seconds < 1 || seconds > 31536000 || [description length] == 0)
        return CLFail (error, @"Enter positive hours (at least one second, at most 8760 hours) and a description, or select a task.");
      entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        CLIdentifier (), @"id", identifier, @"clientID", [row objectForKey: @"date"], @"date",
        description, @"description", [NSNumber numberWithLongLong: seconds], @"seconds",
        [(task != nil ? task : client) objectForKey: @"rate"], @"rate", @"", @"invoiceID", nil];
      if (task != nil)
        {
          [entry setObject: taskID forKey: @"taskID"];
          [entry setObject: [task objectForKey: @"name"] forKey: @"taskName"];
        }
      if ([row objectForKey: @"periodKind"] != nil)
        {
          NSDictionary *period = [CLLedger periodContainingDate: [row objectForKey: @"date"] kind: [row objectForKey: @"periodKind"] error: error];
          if (period == nil || ![[period objectForKey: @"start"] isEqual: [row objectForKey: @"date"]]
              || ![[period objectForKey: @"end"] isEqual: [row objectForKey: @"periodEnd"]])
            return CLFail (error, @"The time entry has an invalid period range.");
          [entry setObject: [row objectForKey: @"periodKind"] forKey: @"periodKind"];
          [entry setObject: [row objectForKey: @"periodEnd"] forKey: @"periodEnd"];
        }
      [entries addObject: entry];
    }
  if ([entries count] == 0)
    return CLFail (error, @"Enter hours for at least one date. Blank and zero-hour days are skipped.");
  backup = [self backup];
  [[_data objectForKey: @"entries"] addObjectsFromArray: entries];
  return [self commit: backup error: error];
}

- (BOOL) startTimerForClient: (NSString *)identifier task: (NSString *)taskID
               description: (NSString *)description error: (NSString **)error
{
  NSDictionary *client = [self clientWithID: identifier];
  NSDictionary *task = [self record: taskID in: @"tasks"];
  NSMutableDictionary *backup;
  NSMutableDictionary *timer;
  if ([self timer] != nil)
    return CLFail (error, @"A timer is already running. Stop it before starting another.");
  if (client == nil || (taskID != nil && (task == nil
      || ![[task objectForKey: @"clientID"] isEqual: identifier]
      || [[task objectForKey: @"archived"] boolValue])))
    return CLFail (error, @"Choose a client and one of its active tasks.");
  if ([CLTrim (description) length] == 0 && task != nil)
    description = [task objectForKey: @"name"];
  if ([CLTrim (description) length] == 0)
    return CLFail (error, @"Enter a description or choose a task first.");
  backup = [self backup];
  timer = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    identifier, @"clientID", CLTrim (description), @"description", [NSDate date], @"started",
    [NSNumber numberWithDouble: [[NSDate date] timeIntervalSince1970]], @"startedEpoch",
    [(task != nil ? task : client) objectForKey: @"rate"], @"rate", [CLLedger today], @"date", nil];
  if (task != nil)
    {
      [timer setObject: taskID forKey: @"taskID"];
      [timer setObject: [task objectForKey: @"name"] forKey: @"taskName"];
    }
  [_data setObject: timer forKey: @"timer"];
  return [self commit: backup error: error];
}
- (NSTimeInterval) timerElapsed
{
  NSNumber *epoch = [[self timer] objectForKey: @"startedEpoch"];
  if ([self timer] == nil)
    return 0;
  if (epoch != nil)
    return [[NSDate date] timeIntervalSince1970] - [epoch doubleValue];
  return -[[[self timer] objectForKey: @"started"] timeIntervalSinceNow];
}


+ (BOOL) validEmailAddress: (NSString *)email
{
  NSArray *parts;
  if (![email isKindOfClass: [NSString class]] || [email length] > 254
      || [email rangeOfCharacterFromSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound
      || [email rangeOfCharacterFromSet: [NSCharacterSet characterSetWithCharactersInString: @",;<>\"\\"]].location != NSNotFound)
    return NO;
  parts = [email componentsSeparatedByString: @"@"];
  return [parts count] == 2 && [[parts objectAtIndex: 0] length] > 0 && [[parts objectAtIndex: 1] length] > 0;
}

+ (NSInteger) reminderDaysForClient: (NSDictionary *)client
{
  return [client objectForKey: @"reminderDays"] == nil ? 3 : [[client objectForKey: @"reminderDays"] integerValue];
}

+ (NSString *) defaultReminderMessage: (BOOL)overdue
{
  return overdue
    ? @"Hello {client},\n\nInvoice {invoice} for {total} was due on {dueDate} and remains unpaid. Please arrange payment promptly and confirm when we can expect it. If you have already paid, please send the payment details so we can reconcile our records."
    : @"Hello {client},\n\nThis is a friendly reminder that payment of {total} for invoice {invoice} is due on {dueDate}. The invoice PDF is attached. Thank you for your business. If you have already paid, please let us know.";
}

- (BOOL) saveRemindersForClient: (NSString *)identifier enabled: (BOOL)enabled
                   daysBefore: (NSString *)days message: (NSString *)message
               overdueMessage: (NSString *)overdue error: (NSString **)error
{
  NSMutableDictionary *client = [self record: identifier in: @"clients"];
  NSMutableDictionary *backup;
  NSString *value = CLTrim (days);
  if (client == nil) return CLFail (error, @"Select a client first.");
  if ([value length] == 0 || [value length] > 5 || [value integerValue] > 36500
      || [value rangeOfCharacterFromSet: [[NSCharacterSet characterSetWithCharactersInString: @"0123456789"] invertedSet]].location != NSNotFound)
    return CLFail (error, @"Enter whole reminder days from 0 to 36500. Zero sends on the due date.");
  if (enabled && (![CLLedger validEmailAddress: [client objectForKey: @"email"]]
      || ![CLLedger validEmailAddress: [[self business] objectForKey: @"email"]]))
    return CLFail (error, @"Set valid client and business email addresses before enabling automatic reminders. The business email must be configured in Apple Mail.");
  if (message == nil || overdue == nil || [message length] > 10000 || [overdue length] > 10000)
    return CLFail (error, @"Reminder messages must be at most 10000 characters each.");
  backup = [self backup];
  [client setObject: [NSNumber numberWithBool: enabled] forKey: @"autoReminders"];
  [client setObject: [NSNumber numberWithInteger: [value integerValue]] forKey: @"reminderDays"];
  [client setObject: CLTrim (message) forKey: @"reminderMessage"];
  [client setObject: CLTrim (overdue) forKey: @"overdueMessage"];
  return [self commit: backup error: error];
}

- (NSString *) paymentMessageForInvoice: (NSDictionary *)invoice onDate: (NSString *)date
{
  NSDictionary *client = [self clientWithID: [[invoice objectForKey: @"client"] objectForKey: @"id"]] ?: [invoice objectForKey: @"client"];
  BOOL overdue = ![[invoice objectForKey: @"paid"] boolValue]
    && ![[invoice objectForKey: @"paymentUnverified"] boolValue]
    && ![[invoice objectForKey: @"dueDateUnverified"] boolValue]
    && [[invoice objectForKey: @"dueDate"] compare: date] == NSOrderedAscending;
  NSString *message = [client objectForKey: overdue ? @"overdueMessage" : @"reminderMessage"];
  NSDictionary *values;
  NSEnumerator *keys;
  NSString *key;
  if ([[invoice objectForKey: @"paid"] boolValue]) return @"Thank you for your payment. Your paid invoice is attached.";
  if ([[invoice objectForKey: @"paymentUnverified"] boolValue] || [[invoice objectForKey: @"dueDateUnverified"] boolValue])
    return @"Please find your invoice attached. Please contact us to confirm the payment details.";
  if ([CLTrim (message) length] == 0) message = [CLLedger defaultReminderMessage: overdue];
  values = [NSDictionary dictionaryWithObjectsAndKeys:
    [client objectForKey: @"name"], @"{client}", [CLLedger invoiceNumber: invoice], @"{invoice}",
    [invoice objectForKey: @"dueDate"], @"{dueDate}",
    [NSString stringWithFormat: @"%@ %@", [[invoice objectForKey: @"business"] objectForKey: @"currency"],
      [CLLedger money: [invoice objectForKey: @"total"]]], @"{total}", nil];
  keys = [values keyEnumerator];
  while ((key = [keys nextObject]) != nil)
    message = [message stringByReplacingOccurrencesOfString: key withString: [values objectForKey: key]];
  return message;
}

- (NSString *) reminderStageForInvoice: (NSDictionary *)invoice onDate: (NSString *)date
{
  NSDictionary *client = [self clientWithID: [[invoice objectForKey: @"client"] objectForKey: @"id"]];
  NSDictionary *history = [invoice objectForKey: @"reminders"];
  NSEnumerator *attempts = [history objectEnumerator];
  NSDictionary *attempt;
  NSInteger days;
  NSString *stage;
  if (client == nil || ![[client objectForKey: @"autoReminders"] boolValue]
      || [[invoice objectForKey: @"paid"] boolValue] || [[invoice objectForKey: @"total"] longLongValue] <= 0
      || [[invoice objectForKey: @"paymentUnverified"] boolValue] || [[invoice objectForKey: @"dueDateUnverified"] boolValue]
      || !CLValidDate (date) || !CLValidDate ([invoice objectForKey: @"dueDate"])
      || [[invoice objectForKey: @"date"] compare: date] == NSOrderedDescending
      || ![CLLedger validEmailAddress: [client objectForKey: @"email"]]
      || ![CLLedger validEmailAddress: [[self business] objectForKey: @"email"]]) return nil;
  while ((attempt = [attempts nextObject]) != nil)
    if (![[attempt objectForKey: @"status"] isEqual: @"submitted"]) return nil;
  days = CLDaysUntil (date, [invoice objectForKey: @"dueDate"]);
  stage = days < 0 ? @"overdue" : @"due";
  if (days > [CLLedger reminderDaysForClient: client] || [history objectForKey: stage] != nil) return nil;
  return stage;
}

- (BOOL) beginReminder: (NSString *)identifier stage: (NSString *)stage
               onDate: (NSString *)date error: (NSString **)error
{
  NSMutableDictionary *invoice = [self record: identifier in: @"invoices"];
  NSMutableDictionary *backup;
  if (invoice == nil || ![[self reminderStageForInvoice: invoice onDate: date] isEqual: stage])
    return CLFail (error, @"This invoice is no longer eligible for that reminder.");
  backup = [self backup];
  if ([invoice objectForKey: @"reminders"] == nil)
    [invoice setObject: [NSMutableDictionary dictionary] forKey: @"reminders"];
  [[invoice objectForKey: @"reminders"] setObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
    @"pending", @"status", date, @"date", @"Check Mail before retrying an interrupted send.", @"detail", nil] forKey: stage];
  return [self commit: backup error: error];
}

- (BOOL) finishReminder: (NSString *)identifier stage: (NSString *)stage
             submitted: (BOOL)submitted detail: (NSString *)detail error: (NSString **)error
{
  NSMutableDictionary *invoice = [self record: identifier in: @"invoices"];
  NSMutableDictionary *attempt = [[invoice objectForKey: @"reminders"] objectForKey: stage];
  NSMutableDictionary *backup;
  if (attempt == nil) return CLFail (error, @"The reminder attempt no longer exists.");
  backup = [self backup];
  [attempt setObject: submitted ? @"submitted" : @"review" forKey: @"status"];
  [attempt setObject: detail ?: @"" forKey: @"detail"];
  return [self commit: backup error: error];
}

- (BOOL) resolveReminder: (NSString *)identifier stage: (NSString *)stage
              submitted: (BOOL)submitted error: (NSString **)error
{
  NSMutableDictionary *invoice = [self record: identifier in: @"invoices"];
  NSDictionary *attempt = [[invoice objectForKey: @"reminders"] objectForKey: stage];
  NSMutableDictionary *backup;
  if (attempt == nil || [[attempt objectForKey: @"status"] isEqual: @"submitted"])
    return CLFail (error, @"There is no unresolved reminder for this invoice.");
  if (submitted) return [self finishReminder: identifier stage: stage submitted: YES detail: @"Confirmed by user in Mail." error: error];
  backup = [self backup];
  [[invoice objectForKey: @"reminders"] removeObjectForKey: stage];
  return [self commit: backup error: error];
}

+ (NSString *) reminderStatusForInvoice: (NSDictionary *)invoice
{
  NSDictionary *history = [invoice objectForKey: @"reminders"];
  NSEnumerator *attempts = [history objectEnumerator];
  NSDictionary *attempt;
  while ((attempt = [attempts nextObject]) != nil)
    if (![[attempt objectForKey: @"status"] isEqual: @"submitted"]) return @"Review email";
  if ([history objectForKey: @"overdue"] != nil) return @"Overdue: submitted";
  if ([history objectForKey: @"due"] != nil) return @"Reminder: submitted";
  return @"";
}

@end
