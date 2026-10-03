#import "CLQuickBooksImporter.h"
#import "CLLedger.h"

static id
QBError (NSString **error, NSUInteger row, NSString *message)
{
  if (error != NULL)
    *error = [NSString stringWithFormat: @"Record %lu: %@", (unsigned long)row, message];
  return nil;
}

static NSString *
QBTrim (NSString *value)
{
  return [value stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *
QBValue (NSDictionary *record, NSString *aliases)
{
  NSArray *keys = [aliases componentsSeparatedByString: @"|"];
  NSUInteger i;
  for (i = 0; i < [keys count]; i++)
    {
      NSString *value = [record objectForKey: [keys objectAtIndex: i]];
      if ([value length] > 0)
        return value;
    }
  return @"";
}

/* Parse quoted delimiters, escaped quotes, embedded newlines, and CRLF. */
static NSArray *
QBRows (NSString *text, unichar separator, NSString **error)
{
  NSMutableArray *rows = [NSMutableArray array];
  NSMutableArray *row = [NSMutableArray array];
  NSMutableString *field = [NSMutableString string];
  BOOL quoted = NO;
  BOOL closed = NO;
  NSUInteger i;
  for (i = 0; i <= [text length]; i++)
    {
      unichar c = i < [text length] ? [text characterAtIndex: i] : '\n';
      if (quoted)
        {
          if (i == [text length])
            return QBError (error, [rows count] + 1, @"Unclosed quoted field.");
          if (c == '"')
            {
              if (i + 1 < [text length] && [text characterAtIndex: i + 1] == '"')
                {
                  [field appendString: @"\""];
                  i++;
                }
              else
                {
                  quoted = NO;
                  closed = YES;
                }
            }
          else
            [field appendFormat: @"%C", c];
        }
      else if (c == separator || c == '\n' || c == '\r')
        {
          [row addObject: [NSString stringWithString: field]];
          [field setString: @""];
          closed = NO;
          if (c != separator)
            {
              if ([[row componentsJoinedByString: @""] length] > 0)
                [rows addObject: [NSArray arrayWithArray: row]];
              [row removeAllObjects];
              if (c == '\r' && i + 1 < [text length] && [text characterAtIndex: i + 1] == '\n')
                i++;
            }
        }
      else if (c == '"' && [field length] == 0 && !closed)
        quoted = YES;
      else if (closed || c == '"')
        return QBError (error, [rows count] + 1, @"Unexpected character near a quoted field.");
      else
        [field appendFormat: @"%C", c];
    }
  return rows;
}

static NSDictionary *
QBRecord (NSArray *header, NSArray *values, NSUInteger start, NSUInteger row, BOOL ignoreExtra, NSString **error)
{
  NSMutableDictionary *record = [NSMutableDictionary dictionary];
  NSUInteger i;
  for (i = start; i < MAX ([header count], [values count]); i++)
    {
      NSString *key = i < [header count] ? [QBTrim ([header objectAtIndex: i]) uppercaseString] : @"";
      NSString *value = i < [values count] ? QBTrim ([values objectAtIndex: i]) : @"";
      if ([key length] == 0)
        {
          if ([value length] > 0 && !ignoreExtra)
            return QBError (error, row, @"Data has no matching column header.");
          continue;
        }
      if ([record objectForKey: key] != nil)
        return QBError (error, row, @"Duplicate column header.");
      [record setObject: value forKey: key];
    }
  return record;
}

/* ISO dates and US QuickBooks dates. Two-digit years use 1970-2069. */
static NSString *
QBDate (NSString *text)
{
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  NSArray *formats = [NSArray arrayWithObjects: @"yyyy-MM-dd", @"M/d/yyyy", @"M/d/yy", nil];
  NSUInteger i;
  [formatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
  [formatter setLenient: NO];
  [formatter setDateFormat: @"yyyy-MM-dd"];
  [formatter setTwoDigitStartDate: [formatter dateFromString: @"1970-01-01"]];
  for (i = 0; i < [formats count]; i++)
    {
      NSDate *date;
      NSString *roundtrip;
      [formatter setDateFormat: [formats objectAtIndex: i]];
      date = [formatter dateFromString: text];
      if (date == nil)
        continue;
      roundtrip = [formatter stringFromDate: date];
      /* Allow zero-padded month/day, but reject normalized impossible dates. */
      if ([text rangeOfString: @"/"].location != NSNotFound)
        {
          NSArray *a = [text componentsSeparatedByString: @"/"];
          NSArray *b = [roundtrip componentsSeparatedByString: @"/"];
          if ([a count] != 3 || [b count] != 3
              || [[a objectAtIndex: 0] intValue] != [[b objectAtIndex: 0] intValue]
              || [[a objectAtIndex: 1] intValue] != [[b objectAtIndex: 1] intValue]
              || ![[a objectAtIndex: 2] isEqual: [b objectAtIndex: 2]])
            continue;
        }
      else if (![text isEqual: roundtrip])
        continue;
      [formatter setDateFormat: @"yyyy-MM-dd"];
      return [formatter stringFromDate: date];
    }
  return nil;
}

static NSNumber *
QBMoney (NSString *text)
{
  /* Currency symbols and grouping are rejected rather than guessed. */
  return [CLLedger centsFromString: text];
}

static NSNumber *
QBSeconds (NSString *text)
{
  NSArray *parts = [text componentsSeparatedByString: @":"];
  NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString: @"0123456789"];
  long long seconds;
  NSUInteger i;
  if ([parts count] == 2 || [parts count] == 3)
    {
      for (i = 0; i < [parts count]; i++)
        if ([[parts objectAtIndex: i] length] == 0 || [[parts objectAtIndex: i] length] > 6
            || [[parts objectAtIndex: i] rangeOfCharacterFromSet: [digits invertedSet]].location != NSNotFound)
          return nil;
      if ([[parts objectAtIndex: 1] intValue] > 59
          || ([parts count] == 3 && [[parts objectAtIndex: 2] intValue] > 59))
        return nil;
      seconds = [[parts objectAtIndex: 0] longLongValue] * 3600
        + [[parts objectAtIndex: 1] intValue] * 60;
      if ([parts count] == 3)
        seconds += [[parts objectAtIndex: 2] intValue];
    }
  else
    {
      NSUInteger dots = 0;
      NSUInteger decimals = 0;
      BOOL digit = NO;
      if ([text length] == 0 || [text length] > 12)
        return nil;
      for (i = 0; i < [text length]; i++)
        {
          unichar c = [text characterAtIndex: i];
          if (c == '.')
            dots++;
          else if (c >= '0' && c <= '9')
            {
              digit = YES;
              if (dots > 0)
                decimals++;
            }
          else
            return nil;
        }
      if (!digit || dots > 1 || decimals > 4)
        return nil;
      seconds = [[[NSDecimalNumber decimalNumberWithString: text]
        decimalNumberByMultiplyingBy: [NSDecimalNumber decimalNumberWithString: @"3600"]] longLongValue];
    }
  return seconds > 0 && seconds <= 31536000 ? [NSNumber numberWithLongLong: seconds] : nil;
}

static NSDictionary *
QBClient (NSDictionary *record, NSUInteger row, NSString **error)
{
  NSString *name = QBValue (record, @"NAME|CUSTOMER|CUSTOMER FULL NAME|FULL NAME|DISPLAY NAME");
  NSString *rateText = QBValue (record, @"HOURLY RATE|RATE");
  NSNumber *rate = QBMoney ([rateText length] > 0 ? rateText : @"0");
  NSMutableArray *address = [NSMutableArray array];
  NSUInteger i;
  NSString *single = QBValue (record, @"BILLING ADDRESS|ADDRESS");
  if ([name length] == 0 || rate == nil)
    return QBError (error, row, @"Customer requires a name and a nonnegative hourly rate with at most two decimals.");
  for (i = 1; i <= 5; i++)
    {
      NSString *line = QBValue (record, [NSString stringWithFormat: @"BADDR%lu|BILLING ADDRESS LINE %lu", (unsigned long)i, (unsigned long)i]);
      if ([line length] > 0)
        [address addObject: line];
    }
  return [NSDictionary dictionaryWithObjectsAndKeys: name, @"name",
    QBValue (record, @"EMAIL|EMAIL ADDRESS|E-MAIL"), @"email",
    [single length] > 0 ? single : [address componentsJoinedByString: @"\n"], @"address",
    rate, @"rate", nil];
}

static NSDictionary *
QBTime (NSDictionary *record, BOOL iif, NSUInteger row, NSString **error)
{
  NSString *name = QBValue (record, @"JOB|CUSTOMER|CLIENT|CUSTOMER FULL NAME");
  NSString *date = QBDate (QBValue (record, @"DATE"));
  NSNumber *seconds = QBSeconds (QBValue (record, @"DURATION|HOURS"));
  NSString *rateText = QBValue (record, @"RATE|HOURLY RATE");
  NSNumber *rate = [rateText length] > 0 ? QBMoney (rateText) : nil;
  NSString *status = [QBValue (record, @"BILLINGSTATUS|BILLABLE STATUS|BILLING STATUS") uppercaseString];
  NSString *billing = @"Review required";
  NSString *note = QBValue (record, @"NOTE|DESCRIPTION|MEMO|ITEM");
  NSMutableDictionary *result;
  if ([name length] == 0 || date == nil || seconds == nil || ([rateText length] > 0 && rate == nil))
    return QBError (error, row, @"Time requires customer, valid date, positive hours or H:MM duration, and a valid rate if supplied.");
  if ([status isEqual: @"BILLABLE"] || [status isEqual: @"UNBILLED"] || (iif && [status isEqual: @"1"]))
    billing = @"Billable";
  else if ([status isEqual: @"NOTBILLABLE"] || [status isEqual: @"NOT BILLABLE"]
           || [status isEqual: @"NON-BILLABLE"] || (iif && [status isEqual: @"0"]))
    billing = @"Not billable";
  else if ([status isEqual: @"HASBEENBILLED"] || [status isEqual: @"BILLED"] || (iif && [status isEqual: @"2"]))
    billing = @"Billed in QuickBooks";
  else if ([status length] > 0)
    return QBError (error, row, @"Unrecognized time billing status. Use Billable, Not Billable or Billed.");
  result = [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"clientName", date, @"date",
    seconds, @"seconds", [note length] > 0 ? note : @"Imported QuickBooks time", @"description",
    billing, @"externalBilling", QBValue (record, @"TIMEACTID|TIME ID|ID"), @"externalID",
    QBValue (record, @"EMP|EMPLOYEE|NAME"), @"employee", nil];
  if (rate != nil)
    [result setObject: rate forKey: @"rate"];
  return result;
}

static NSDictionary *
QBInvoice (NSDictionary *record, NSArray *splits, BOOL iif, NSSet *taxItems,
           NSUInteger row, NSString **error)
{
  NSString *name = QBValue (record, @"NAME|CUSTOMER|CLIENT|CUSTOMER FULL NAME");
  NSString *number = QBValue (record, @"DOCNUM|INVOICE NO|INVOICE NUMBER|NUM|NO.");
  NSString *date = QBDate (QBValue (record, @"DATE|INVOICE DATE"));
  NSString *dueText = QBValue (record, @"DUEDATE|DUE DATE");
  NSString *due = [dueText length] > 0 ? QBDate (dueText) : date;
  NSNumber *total = QBMoney (QBValue (record, @"AMOUNT|TOTAL|INVOICE TOTAL"));
  NSString *balanceText = QBValue (record, @"OPEN BALANCE|BALANCE");
  NSString *status = [QBValue (record, @"STATUS") uppercaseString];
  NSMutableArray *lines = [NSMutableArray array];
  long long tax = 0;
  long long subtotal = 0;
  NSUInteger i;
  BOOL paid = NO;
  BOOL known = NO;
  NSMutableDictionary *invoice;
  if ([name length] == 0 || [number length] == 0 || date == nil || due == nil || total == nil)
    return QBError (error, row, @"Invoice requires customer, invoice number, valid date/due date and nonnegative total. Dates must be ISO or US month/day/year.");
  if ([balanceText length] > 0)
    {
      NSNumber *balance = QBMoney (balanceText);
      if (balance == nil || ([balance longLongValue] != 0 && ![balance isEqual: total]))
        return QBError (error, row, @"Partial payments are not supported. Import invoices with zero balance or the full original balance.");
      known = YES;
      paid = [balance longLongValue] == 0;
    }
  if ([status length] > 0)
    {
      BOOL statusPaid = [status isEqual: @"PAID"];
      if (!statusPaid && ![status isEqual: @"UNPAID"] && ![status isEqual: @"OPEN"] && ![status isEqual: @"OVERDUE"])
        return QBError (error, row, @"Unsupported invoice status. Use Paid, Unpaid, Open or Overdue.");
      if (known && paid != statusPaid)
        return QBError (error, row, @"Invoice status conflicts with its open balance.");
      paid = statusPaid;
      known = YES;
    }
  if (iif)
    {
      if ([splits count] == 0)
        return QBError (error, row, @"Invoice has no SPL lines.");
      for (i = 0; i < [splits count]; i++)
        {
          NSDictionary *split = [splits objectAtIndex: i];
          NSString *amountText = QBValue (split, @"AMOUNT");
          NSNumber *amount;
          NSString *description = QBValue (split, @"MEMO|INVITEM|ACCNT");
          BOOL isTax = [[QBValue (split, @"EXTRA") uppercaseString] isEqual: @"AUTOSTAX"]
            || [taxItems containsObject: [QBValue (split, @"INVITEM") lowercaseString]];
          if ([QBValue (split, @"TRNSTYPE") length] > 0
              && ![[QBValue (split, @"TRNSTYPE") uppercaseString] isEqual: @"INVOICE"])
            return QBError (error, row, @"Invoice contains a split of another transaction type.");
          if ([amountText hasPrefix: @"-"])
            amountText = [amountText substringFromIndex: 1];
          else if (![QBMoney (amountText) isEqual: [NSNumber numberWithInt: 0]])
            return QBError (error, row, @"Positive invoice split (discount/credit) is not supported.");
          amount = QBMoney (amountText);
          if (amount == nil)
            return QBError (error, row, @"Invalid invoice split amount.");
          if (isTax)
            tax += [amount longLongValue];
          else
            {
              subtotal += [amount longLongValue];
              [lines addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                date, @"date", [description length] > 0 ? description : @"Imported invoice item", @"description",
                amount, @"amount", [NSNumber numberWithBool: YES], @"importedAmount", nil]];
            }
        }
      if (subtotal + tax != [total longLongValue])
        return QBError (error, row, @"Invoice splits and tax do not balance to the original total.");
    }
  else
    {
      NSString *taxText = QBValue (record, @"TAX|TAX AMOUNT");
      NSNumber *taxNumber = QBMoney ([taxText length] > 0 ? taxText : @"0");
      if (taxNumber == nil || [taxNumber longLongValue] > [total longLongValue])
        return QBError (error, row, @"Invalid invoice tax amount.");
      tax = [taxNumber longLongValue];
      subtotal = [total longLongValue] - tax;
      [lines addObject: [NSDictionary dictionaryWithObjectsAndKeys:
        date, @"date", [NSString stringWithFormat: @"Imported QuickBooks invoice %@ — %@", number,
          QBValue (record, @"MEMO|DESCRIPTION")], @"description",
        [NSNumber numberWithLongLong: subtotal], @"amount",
        [NSNumber numberWithBool: YES], @"importedAmount", nil]];
    }
  if ([lines count] == 0)
    return QBError (error, row, @"Invoice contains no supported service or item lines.");
  invoice = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    name, @"clientName", number, @"sourceNumber", date, @"date", due, @"dueDate",
    lines, @"lines", total, @"total", [NSNumber numberWithLongLong: subtotal], @"subtotal",
    [NSNumber numberWithLongLong: tax], @"tax", @"0", @"taxPercent",
    [NSNumber numberWithBool: paid], @"paid", [NSNumber numberWithBool: !known], @"paymentUnverified",
    [NSNumber numberWithBool: [dueText length] == 0], @"dueDateUnverified", nil];
  if (!iif && [QBValue (record, @"TAX|TAX AMOUNT") length] == 0)
    [invoice setObject: [NSNumber numberWithBool: YES] forKey: @"taxUnverified"];
  return invoice;
}

@implementation CLQuickBooksImporter
+ (NSArray *) delimitedRows: (NSString *)text separator: (unichar)separator error: (NSString **)error
{ return QBRows (text, separator, error); }

+ (NSDictionary *) recordsFromData: (NSData *)data filename: (NSString *)filename error: (NSString **)error
{
  NSString *extension = [[filename pathExtension] lowercaseString];
  BOOL iif = [extension isEqual: @"iif"];
  NSString *text;
  NSArray *rows;
  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  NSMutableArray *clients = [NSMutableArray array];
  NSMutableArray *times = [NSMutableArray array];
  NSMutableArray *invoices = [NSMutableArray array];
  NSMutableArray *warnings = [NSMutableArray array];
  NSMutableDictionary *ignored = [NSMutableDictionary dictionary];
  NSMutableSet *taxItems = [NSMutableSet set];
  NSDictionary *transaction = nil;
  NSMutableArray *splits = nil;
  NSUInteger transactionRow = 0;
  NSUInteger i;
  NSString *csvKind = nil;
  if (!iif && ![extension isEqual: @"csv"])
    return QBError (error, 0, @"Choose a QuickBooks .iif or .csv text export. QBW company files, QBB backups and QBO bank files cannot be opened directly. Export the needed lists/reports from QuickBooks first.");
  if ([data length] == 0 || [data length] > 20 * 1024 * 1024)
    return QBError (error, 0, @"The file is empty or larger than the 20 MB import limit.");
  text = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
  if ([data length] >= 2)
    {
      const unsigned char *bytes = [data bytes];
      if ((bytes[0] == 255 && bytes[1] == 254) || (bytes[0] == 254 && bytes[1] == 255))
        text = [[[NSString alloc] initWithData: data encoding: NSUnicodeStringEncoding] autorelease];
    }
  if (text == nil)
    text = [[[NSString alloc] initWithData: data encoding: NSWindowsCP1252StringEncoding] autorelease];
  if ([text length] > 0 && [text characterAtIndex: 0] == 0xfeff)
    text = [text substringFromIndex: 1];
  if (text == nil || [text rangeOfString: [NSString stringWithFormat: @"%C", (unichar)0]].location != NSNotFound)
    return QBError (error, 0, @"The file is not a supported text encoding.");
  rows = QBRows (text, iif ? '\t' : ',', error);
  if (rows == nil || [rows count] == 0)
    return rows == nil ? nil : QBError (error, 0, @"No records found.");
  for (i = 0; i < [rows count]; i++)
    {
      NSArray *values = [rows objectAtIndex: i];
      NSString *type = iif ? [[values objectAtIndex: 0] uppercaseString] : csvKind;
      NSDictionary *record;
      id parsed = nil;
      if (!iif && i == 0)
        {
          NSDictionary *columns = QBRecord (values, values, 0, 1, NO, error);
          if (columns == nil)
            return nil;
          if ([QBValue (columns, @"INVOICE NO|INVOICE NUMBER|NUM|NO.") length] > 0)
            csvKind = @"INVOICE";
          else if ([QBValue (columns, @"HOURS|DURATION") length] > 0)
            csvKind = @"TIMEACT";
          else if ([QBValue (columns, @"NAME|CUSTOMER|CUSTOMER FULL NAME|FULL NAME|DISPLAY NAME") length] > 0)
            csvKind = @"CUST";
          else
            return QBError (error, 1, @"CSV must start with column headers for customers, time or invoice summaries. See Documentation/QuickBooks-import.md for supported columns.");
          [headers setObject: values forKey: csvKind];
          continue;
        }
      if (iif && [type hasPrefix: @"!"])
        {
          [headers setObject: values forKey: [type substringFromIndex: 1]];
          continue;
        }
      if ([type isEqual: @"ENDTRNS"])
        {
          if (transaction == nil)
            return QBError (error, i + 1, @"ENDTRNS without a transaction.");
          if ([[QBValue (transaction, @"TRNSTYPE") uppercaseString] isEqual: @"INVOICE"])
            {
              parsed = QBInvoice (transaction, splits, YES, taxItems, transactionRow, error);
              if (parsed == nil)
                return nil;
              if ([QBValue (transaction, @"CURRENCY") length] > 0)
                {
                  NSMutableDictionary *withCurrency = [NSMutableDictionary dictionaryWithDictionary: parsed];
                  [withCurrency setObject: [QBValue (transaction, @"CURRENCY") uppercaseString] forKey: @"currency"];
                  parsed = withCurrency;
                }
              [invoices addObject: parsed];
            }
          transaction = nil;
          splits = nil;
          continue;
        }
      if ([headers objectForKey: type] == nil)
        return QBError (error, i + 1, @"Record has no matching IIF header.");
      record = QBRecord ([headers objectForKey: type], values, iif ? 1 : 0, i + 1,
        iif && ![type isEqual: @"CUST"] && ![type isEqual: @"TIMEACT"]
          && ![type isEqual: @"TRNS"] && ![type isEqual: @"SPL"], error);
      if (record == nil)
        return nil;
      if (transaction != nil && ![type isEqual: @"SPL"] && ![type isEqual: @"TRNS"])
        return QBError (error, i + 1, @"Unexpected record inside a transaction.");
      if ([type isEqual: @"CUST"])
        {
          parsed = QBClient (record, i + 1, error);
          if (parsed == nil)
            return nil;
          [clients addObject: parsed];
        }
      else if ([type isEqual: @"TIMEACT"])
        {
          parsed = QBTime (record, iif, i + 1, error);
          if (parsed == nil)
            return nil;
          [times addObject: parsed];
        }
      else if ([type isEqual: @"INVOICE"])
        {
          NSString *transactionType = [QBValue (record, @"TRANSACTION TYPE|TYPE") uppercaseString];
          if ([transactionType length] > 0 && ![transactionType isEqual: @"INVOICE"])
            return QBError (error, i + 1, @"CSV contains a non-invoice transaction. Export an invoice-only report.");
          parsed = QBInvoice (record, nil, NO, taxItems, i + 1, error);
          if (parsed == nil)
            return nil;
          [invoices addObject: parsed];
        }
      else if ([type isEqual: @"TRNS"])
        {
          if (transaction != nil)
            return QBError (error, i + 1, @"Missing ENDTRNS before the next transaction.");
          transaction = record;
          transactionRow = i + 1;
          splits = [NSMutableArray array];
          if (![[QBValue (record, @"TRNSTYPE") uppercaseString] isEqual: @"INVOICE"])
            {
              NSString *key = [@"Transaction: " stringByAppendingString: QBValue (record, @"TRNSTYPE")];
              [ignored setObject: [NSNumber numberWithUnsignedInteger: [[ignored objectForKey: key] unsignedIntegerValue] + 1] forKey: key];
            }
        }
      else if ([type isEqual: @"SPL"])
        {
          if (transaction == nil)
            return QBError (error, i + 1, @"SPL outside a transaction.");
          [splits addObject: record];
        }
      else
        {
          if ([type isEqual: @"INVITEM"])
            {
              NSString *itemType = [QBValue (record, @"INVITEMTYPE") uppercaseString];
              if ([itemType isEqual: @"COMPTAX"] || [itemType isEqual: @"TAX"])
                [taxItems addObject: [QBValue (record, @"NAME") lowercaseString]];
            }
          if (![type isEqual: @"HDR"])
            [ignored setObject: [NSNumber numberWithUnsignedInteger: [[ignored objectForKey: type] unsignedIntegerValue] + 1] forKey: type];
        }
      if (parsed != nil && [QBValue (record, @"CURRENCY") length] > 0)
        {
          NSMutableDictionary *withCurrency = [NSMutableDictionary dictionaryWithDictionary: parsed];
          NSMutableArray *target = [type isEqual: @"CUST"] ? clients : ([type isEqual: @"TIMEACT"] ? times : invoices);
          [withCurrency setObject: [QBValue (record, @"CURRENCY") uppercaseString] forKey: @"currency"];
          [target replaceObjectAtIndex: [target count] - 1 withObject: withCurrency];
        }
    }
  if (transaction != nil)
    return QBError (error, transactionRow, @"Transaction is missing ENDTRNS.");
  {
    NSArray *keys = [[ignored allKeys] sortedArrayUsingSelector: @selector(compare:)];
    for (i = 0; i < [keys count]; i++)
      [warnings addObject: [NSString stringWithFormat: @"Skipped %@: %@ record(s).", [keys objectAtIndex: i], [ignored objectForKey: [keys objectAtIndex: i]]]];
  }
  if ([clients count] + [times count] + [invoices count] == 0)
    return QBError (error, 0, [NSString stringWithFormat: @"No supported customer, time or invoice records. %@", [warnings componentsJoinedByString: @" "]]);
  return [NSDictionary dictionaryWithObjectsAndKeys: clients, @"clients", times, @"time",
    invoices, @"invoices", warnings, @"warnings", nil];
}
@end
