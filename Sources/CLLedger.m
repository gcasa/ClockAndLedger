#import "CLLedger.h"
#import "CLQuickBooksImporter.h"

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

static BOOL
CLValidBusiness (id record)
{
  return CLFields (record, @"name,address,email,currency,notes", @"")
    && [[record objectForKey: @"name"] length] > 0
    && [[record objectForKey: @"currency"] length] == 3;
}

static BOOL
CLValidClient (id record)
{
  return CLFields (record, @"id,name,email,address", @"rate")
    && [[record objectForKey: @"id"] length] > 0
    && [[record objectForKey: @"name"] length] > 0
    && [[record objectForKey: @"rate"] longLongValue] <= 100000000000LL;
}

static BOOL
CLValidEntry (id record)
{
  return CLFields (record, @"id,clientID,date,description,invoiceID", @"seconds,rate")
    && [[record objectForKey: @"id"] length] > 0
    && CLValidDate ([record objectForKey: @"date"])
    && [[record objectForKey: @"seconds"] longLongValue] > 0
    && [[record objectForKey: @"seconds"] longLongValue] <= 31536000
    && [[record objectForKey: @"rate"] longLongValue] <= 100000000000LL;
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
  unsigned int i;
  id timer;
  if (!CLFields (data, @"", @"version,nextInvoice")
      || [[data objectForKey: @"version"] intValue] != 1
      || [[data objectForKey: @"nextInvoice"] longLongValue] < 1
      || [[data objectForKey: @"nextInvoice"] longLongValue] > 2147483646
      || !CLValidBusiness ([data objectForKey: @"business"]))
    return NO;
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
  for (i = 0; i < [invoices count]; i++)
    {
      id invoice = [invoices objectAtIndex: i];
      NSArray *lines;
      unsigned int j;
      if (!CLFields (invoice, @"id,date,dueDate,taxPercent", @"subtotal,tax,total,paid")
          || !CLValidClient ([invoice objectForKey: @"client"])
          || !CLValidBusiness ([invoice objectForKey: @"business"])
          || !CLValidDate ([invoice objectForKey: @"date"])
          || !CLValidDate ([invoice objectForKey: @"dueDate"])
          || CLDecimal ([invoice objectForKey: @"taxPercent"], 2) == nil
          || [invoiceIDs containsObject: [invoice objectForKey: @"id"]]
          || ![[invoice objectForKey: @"id"] isEqual: [NSString stringWithFormat: @"INV-%05u", i + 1]])
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
  if ([[data objectForKey: @"nextInvoice"] unsignedLongLongValue] != [invoices count] + 1)
    return NO;
  for (i = 0; i < [entries count]; i++)
    {
      id entry = [entries objectAtIndex: i];
      if (!CLValidEntry (entry)
          || ![clientIDs containsObject: [entry objectForKey: @"clientID"]]
          || [entryIDs containsObject: [entry objectForKey: @"id"]]
          || ([[entry objectForKey: @"invoiceID"] length] > 0
              && ![invoiceIDs containsObject: [entry objectForKey: @"invoiceID"]]))
        return NO;
      [entryIDs addObject: [entry objectForKey: @"id"]];
    }
  timer = [data objectForKey: @"timer"];
  if (timer != nil && (!CLFields (timer, @"clientID,date,description", @"rate")
      || ![[timer objectForKey: @"started"] isKindOfClass: [NSDate class]]
      || ![clientIDs containsObject: [timer objectForKey: @"clientID"]]
      || !CLValidDate ([timer objectForKey: @"date"])))
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
        }
      else
        {
          _data = [[NSMutableDictionary alloc] init];
          [_data setObject: [NSNumber numberWithInt: 1] forKey: @"version"];
          [_data setObject: [NSMutableArray array] forKey: @"clients"];
          [_data setObject: [NSMutableArray array] forKey: @"entries"];
          [_data setObject: [NSMutableArray array] forKey: @"invoices"];
          [_data setObject: [NSNumber numberWithInt: 1] forKey: @"nextInvoice"];
          [_data setObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Your business", @"name", @"", @"address", @"", @"email",
            @"USD", @"currency", @"Payment due within 30 days.", @"notes", nil]
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
  NSNumber *cents = [CLLedger centsFromString: rate];
  NSMutableDictionary *backup;
  NSMutableDictionary *client;
  if ([CLTrim (name) length] == 0 || cents == nil)
    return CLFail (error, @"Enter a client name and a valid hourly rate (up to two decimal places).");
  client = [self record: identifier in: @"clients"];
  if (identifier != nil && client == nil)
    return CLFail (error, @"The client no longer exists.");
  backup = [self backup];
  if (client == nil)
    {
      client = [NSMutableDictionary dictionary];
      [client setObject: CLIdentifier () forKey: @"id"];
      [[_data objectForKey: @"clients"] addObject: client];
    }
  [client setObject: CLTrim (name) forKey: @"name"];
  [client setObject: CLTrim (email) forKey: @"email"];
  [client setObject: address forKey: @"address"];
  [client setObject: cents forKey: @"rate"];
  return [self commit: backup error: error];
}

- (BOOL) deleteClient: (NSString *)identifier error: (NSString **)error
{
  unsigned int i;
  NSMutableDictionary *backup;
  NSDictionary *client = [self clientWithID: identifier];
  if (client == nil)
    return CLFail (error, @"Select a client first.");
  if ([[[self timer] objectForKey: @"clientID"] isEqual: identifier])
    return CLFail (error, @"Stop this client's timer first.");
  for (i = 0; i < [[self entries] count]; i++)
    if ([[[[self entries] objectAtIndex: i] objectForKey: @"clientID"] isEqual: identifier])
      return CLFail (error, @"This client has time records and cannot be deleted.");
  backup = [self backup];
  [[_data objectForKey: @"clients"] removeObject: client];
  return [self commit: backup error: error];
}

- (BOOL) addTimeForClient: (NSString *)identifier date: (NSString *)date
             description: (NSString *)description hours: (NSString *)hours
                   error: (NSString **)error
{
  NSDecimalNumber *duration = CLDecimal (hours, 4);
  NSDictionary *client = [self clientWithID: identifier];
  NSMutableDictionary *backup;
  NSMutableDictionary *entry;
  long long seconds = [[duration decimalNumberByMultiplyingBy:
    [NSDecimalNumber decimalNumberWithString: @"3600"]] longLongValue];
  if (client == nil || duration == nil || seconds < 1 || seconds > 31536000
      || !CLValidDate (date) || [CLTrim (description) length] == 0)
    return CLFail (error, @"Choose a client, enter a description, a valid YYYY-MM-DD date and positive hours (at least one second, at most 8760 hours).");
  backup = [self backup];
  entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    CLIdentifier (), @"id", identifier, @"clientID", date, @"date",
    CLTrim (description), @"description", [NSNumber numberWithLongLong: seconds], @"seconds",
    [client objectForKey: @"rate"], @"rate", @"", @"invoiceID", nil];
  [[_data objectForKey: @"entries"] addObject: entry];
  return [self commit: backup error: error];
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
  NSDictionary *client = [self clientWithID: identifier];
  NSMutableDictionary *backup;
  if ([self timer] != nil)
    return CLFail (error, @"A timer is already running. Stop it before starting another.");
  if (client == nil || [CLTrim (description) length] == 0)
    return CLFail (error, @"Choose a client and enter a description first.");
  backup = [self backup];
  [_data setObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
    identifier, @"clientID", CLTrim (description), @"description",
    [NSDate date], @"started", [client objectForKey: @"rate"], @"rate",
    [CLLedger today], @"date", nil] forKey: @"timer"];
  return [self commit: backup error: error];
}

- (BOOL) stopTimer: (NSString **)error
{
  NSMutableDictionary *entry;
  NSMutableDictionary *backup;
  NSTimeInterval elapsed;
  if ([self timer] == nil)
    return CLFail (error, @"There is no running timer.");
  elapsed = -[[[self timer] objectForKey: @"started"] timeIntervalSinceNow];
  if (elapsed < 0 || elapsed > 31536000)
    return CLFail (error, @"The system clock changed or the timer exceeds one year. Correct the clock before stopping the timer.");
  backup = [self backup];
  entry = [NSMutableDictionary dictionaryWithDictionary: [self timer]];
  [entry removeObjectForKey: @"started"];
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
  NSDictionary *client = [self clientWithID: identifier];
  NSDecimalNumber *percent = CLDecimal (tax, 2);
  NSMutableArray *lines = [NSMutableArray array];
  NSMutableDictionary *backup;
  NSMutableDictionary *invoice;
  NSString *invoiceID;
  long long subtotal = 0;
  long long taxCents;
  unsigned int i;
  int sequence;
  NSDecimalNumber *taxAmount;
  NSDecimalNumberHandler *rounding;

  if (client == nil || percent == nil
      || [percent compare: [NSDecimalNumber decimalNumberWithString: @"100"]] == NSOrderedDescending
      || !CLValidDate (dueDate) || [dueDate compare: [CLLedger today]] == NSOrderedAscending)
    return CLFail (error, @"Choose a client, a tax percentage from 0 to 100 and a valid due date on or after today (YYYY-MM-DD).");
  for (i = 0; i < [[self entries] count]; i++)
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
    invoiceID, @"id", [CLLedger today], @"date", dueDate, @"dueDate",
    [NSDictionary dictionaryWithDictionary: client], @"client",
    [NSDictionary dictionaryWithDictionary: [self business]], @"business",
    lines, @"lines", [percent stringValue], @"taxPercent",
    [NSNumber numberWithLongLong: subtotal], @"subtotal",
    [NSNumber numberWithLongLong: taxCents], @"tax",
    [NSNumber numberWithLongLong: subtotal + taxCents], @"total",
    [NSNumber numberWithBool: NO], @"paid", nil];
  for (i = 0; i < [lines count]; i++)
    [[self record: [[lines objectAtIndex: i] objectForKey: @"id"] in: @"entries"]
      setObject: invoiceID forKey: @"invoiceID"];
  [[_data objectForKey: @"invoices"] addObject: invoice];
  [_data setObject: [NSNumber numberWithInt: sequence + 1] forKey: @"nextInvoice"];
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
  return [source length] > 0 ? source : [invoice objectForKey: @"id"];
}

- (BOOL) saveBusiness: (NSDictionary *)business error: (NSString **)error
{
  NSMutableDictionary *backup;
  NSString *currency = [[business objectForKey: @"currency"] uppercaseString];
  NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString: @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"];
  if (!CLFields (business, @"name,email,address,currency,notes", @"")
      || [CLTrim ([business objectForKey: @"name"]) length] == 0 || [currency length] != 3
      || [currency rangeOfCharacterFromSet: [letters invertedSet]].location != NSNotFound)
    return CLFail (error, @"Enter a business name and a three-letter currency code, such as USD or EUR.");
  if (![[[self business] objectForKey: @"currency"] isEqual: currency] && ([[self entries] count] > 0 || [[self invoices] count] > 0))
    return CLFail (error, @"Currency cannot change after time has been recorded. Use a separate ledger for another currency.");
  if ([self timer] != nil && ![[[self business] objectForKey: @"currency"] isEqual: currency])
    return CLFail (error, @"Stop the running timer before changing currency.");
  backup = [self backup];
  [_data setObject: [NSMutableDictionary dictionaryWithDictionary: business] forKey: @"business"];
  [[_data objectForKey: @"business"] setObject: currency forKey: @"currency"];
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
@end
