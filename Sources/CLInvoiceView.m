#import "CLInvoiceView.h"
#import "CLLedger.h"

static void
CLAppendRows (NSMutableArray *rows, NSString *text)
{
  NSArray *paragraphs = [text componentsSeparatedByString: @"\n"];
  unsigned int i;
  for (i = 0; i < [paragraphs count]; i++)
    {
      NSString *line = [paragraphs objectAtIndex: i];
      while ([line length] > 76)
        {
          unsigned int split = 76;
          while (split > 40 && [line characterAtIndex: split] != ' ')
            split--;
          if (split == 40)
            split = 76;
          [rows addObject: [line substringToIndex: split]];
          line = [line substringFromIndex: split];
          if ([line hasPrefix: @" "])
            line = [line substringFromIndex: 1];
        }
      [rows addObject: line];
    }
}

/* Vector artwork stays sharp in previews, printed pages and PDF attachments. */
static void
CLDrawPaidStamp (NSRect page)
{
  NSAffineTransform *transform = [NSAffineTransform transform];
  NSColor *ink = [NSColor colorWithCalibratedRed: 0.80 green: 0.04 blue: 0.04 alpha: 0.30];
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont boldSystemFontOfSize: 148], NSFontAttributeName, ink, NSForegroundColorAttributeName,
    [NSNumber numberWithInt: 8], NSKernAttributeName, nil];
  NSSize textSize = [@"PAID" sizeWithAttributes: attributes];
  NSBezierPath *border;
  [NSGraphicsContext saveGraphicsState];
  [NSBezierPath clipRect: page];
  [transform translateXBy: NSMidX (page) yBy: NSMidY (page)];
  [transform rotateByDegrees: -38];
  [transform concat];
  [ink set];
  border = [NSBezierPath bezierPathWithRoundedRect: NSMakeRect (-250, -96, 500, 192) xRadius: 10 yRadius: 10];
  [border setLineWidth: 8];
  [border stroke];
  border = [NSBezierPath bezierPathWithRoundedRect: NSMakeRect (-238, -84, 476, 168) xRadius: 4 yRadius: 4];
  [border setLineWidth: 2];
  [border stroke];
  [@"PAID" drawAtPoint: NSMakePoint (-textSize.width / 2, -textSize.height / 2) withAttributes: attributes];
  [NSGraphicsContext restoreGraphicsState];
}

@implementation CLInvoiceView

- (id) initWithInvoice: (NSDictionary *)invoice
{
  self = [super initWithFrame: NSMakeRect (0, 0, 520, 720)];
  if (self != nil)
    {
      NSMutableArray *rows = [NSMutableArray array];
      NSDictionary *business = [invoice objectForKey: @"business"];
      NSDictionary *client = [invoice objectForKey: @"client"];
      NSArray *lines = [invoice objectForKey: @"lines"];
      NSString *currency = [business objectForKey: @"currency"];
      unsigned int i;
      _invoice = [invoice copy];
      if ([business objectForKey: @"logoData"] != nil)
        _logo = [[NSImage alloc] initWithData: [business objectForKey: @"logoData"]];
      if (![_logo isValid] || [_logo size].width <= 0 || [_logo size].height <= 0)
        { [_logo release]; _logo = nil; }
      _rowsPerPage = _logo != nil ? 40 : 48;
      CLAppendRows (rows, [business objectForKey: @"name"]);
      CLAppendRows (rows, [business objectForKey: @"address"]);
      CLAppendRows (rows, [business objectForKey: @"email"]);
      CLAppendRows (rows, @"");
      CLAppendRows (rows, [NSString stringWithFormat: @"Issued: %@     Due: %@",
        [invoice objectForKey: @"date"], [[invoice objectForKey: @"dueDateUnverified"] boolValue] ? @"Not provided" : [invoice objectForKey: @"dueDate"]]);
      CLAppendRows (rows, @"");
      CLAppendRows (rows, @"BILL TO");
      CLAppendRows (rows, [client objectForKey: @"name"]);
      CLAppendRows (rows, [client objectForKey: @"address"]);
      CLAppendRows (rows, [client objectForKey: @"email"]);
      CLAppendRows (rows, @"");
      CLAppendRows (rows, @"SERVICES");
      CLAppendRows (rows, @"____________________________________________________________________________");
      for (i = 0; i < [lines count]; i++)
        {
          NSDictionary *line = [lines objectAtIndex: i];
          CLAppendRows (rows, [NSString stringWithFormat: @"%@  |  %@",
            [CLLedger dateLabelForEntry: line], [CLLedger workLabelForEntry: line]]);
          if ([[line objectForKey: @"importedAmount"] boolValue])
            CLAppendRows (rows, [NSString stringWithFormat: @"    Amount: %@ %@", currency,
              [CLLedger money: [line objectForKey: @"amount"]]]);
          else
            CLAppendRows (rows, [NSString stringWithFormat: @"    %.4f hours x %@ %@/hr                 %@ %@",
            [line objectForKey: @"hours"] != nil ? [[line objectForKey: @"hours"] doubleValue] : [[line objectForKey: @"seconds"] doubleValue] / 3600.0,
            currency, [CLLedger money: [line objectForKey: @"rate"]],
            currency, [CLLedger money: [line objectForKey: @"amount"]]]);
          CLAppendRows (rows, @"");
        }
      CLAppendRows (rows, @"____________________________________________________________________________");
      CLAppendRows (rows, [NSString stringWithFormat: @"%@:       %@ %@", [[invoice objectForKey: @"taxUnverified"] boolValue] ? @"Imported amount" : @"Subtotal", currency,
        [CLLedger money: [invoice objectForKey: @"subtotal"]]]);
      if ([[invoice objectForKey: @"taxUnverified"] boolValue])
        CLAppendRows (rows, @"Tax: not itemized in the export (included in imported amount)");
      else
        CLAppendRows (rows, [NSString stringWithFormat: @"Tax (%@):      %@ %@", [invoice objectForKey: @"sourceNumber"] != nil ? @"imported" : [[invoice objectForKey: @"taxPercent"] stringByAppendingString: @"%"],
        currency, [CLLedger money: [invoice objectForKey: @"tax"]]]);
      CLAppendRows (rows, [NSString stringWithFormat: @"TOTAL:          %@ %@", currency,
        [CLLedger money: [invoice objectForKey: @"total"]]]);
      CLAppendRows (rows, @"");
      CLAppendRows (rows, [[invoice objectForKey: @"paymentUnverified"] boolValue] ? @"Status: VERIFY PAYMENT IN QUICKBOOKS" : ([[invoice objectForKey: @"paid"] boolValue] ? @"Status: PAID" : @"Status: UNPAID"));
      {
        NSString *notes = [business objectForKey: @"notes"];
        NSInteger days = [CLLedger netDaysForClient: client];
        NSString *terms = days == 0 ? @"Payment due on receipt." :
          [NSString stringWithFormat: @"Payment due within %ld %@.", (long)days, days == 1 ? @"day" : @"days"];
        /* Replace the former default even in saved invoice snapshots, while
         * preserving any additional payment instructions. */
        if ([notes rangeOfString: @"Payment due within 30 days."].location != NSNotFound)
          notes = [notes stringByReplacingOccurrencesOfString: @"Payment due within 30 days." withString: terms];
        else if ([client objectForKey: @"netDays"] != nil)
          CLAppendRows (rows, terms);
        CLAppendRows (rows, notes);
      }
      _rows = [rows copy];
      _pageCount = MAX (1, (unsigned int)([_rows count] + _rowsPerPage - 1) / _rowsPerPage);
      [self setFrameSize: NSMakeSize (520, 720 * _pageCount)];
    }
  return self;
}

- (void) dealloc
{
  [_invoice release];
  [_rows release];
  [_logo release];
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) knowsPageRange: (NSRange *)range
{
  *range = NSMakeRange (1, _pageCount);
  return YES;
}

- (NSRect) rectForPage: (NSInteger)page
{
  return NSMakeRect (0, (page - 1) * 720, 520, 720);
}

- (void) drawRect: (NSRect)dirty
{
  NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont userFixedPitchFontOfSize: 10], NSFontAttributeName,
    [NSColor blackColor], NSForegroundColorAttributeName, nil];
  NSDictionary *heading = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont boldSystemFontOfSize: 19], NSFontAttributeName,
    [NSColor blackColor], NSForegroundColorAttributeName, nil];
  unsigned int page;
  [[NSColor whiteColor] set];
  NSRectFill (dirty);
  for (page = 0; page < _pageCount; page++)
    {
      unsigned int row;
      CGFloat top = page * 720;
      if (!NSIntersectsRect (dirty, NSMakeRect (0, top, 520, 720)))
        continue;
      /* Keep all invoice text readable over the translucent stamp. Unknown
       * imported payment states must never be represented as paid. */
      if ([[_invoice objectForKey: @"paid"] boolValue]
          && ![[_invoice objectForKey: @"paymentUnverified"] boolValue])
        CLDrawPaidStamp (NSMakeRect (0, top, 520, 720));
      [[NSString stringWithFormat: @"INVOICE  %@", [CLLedger invoiceNumber: _invoice]]
        drawAtPoint: NSMakePoint (12, top + 15) withAttributes: heading];
      if (_logo != nil)
        {
          NSSize size = [_logo size];
          CGFloat scale = MIN (180 / size.width, 85 / size.height);
          [_logo drawInRect: NSMakeRect (12, top + 55, size.width * scale, size.height * scale)
                  fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1
            respectFlipped: YES hints: nil];
        }
      for (row = 0; row < _rowsPerPage && page * _rowsPerPage + row < [_rows count]; row++)
        [[_rows objectAtIndex: page * _rowsPerPage + row]
          drawAtPoint: NSMakePoint (12, top + (_logo != nil ? 164 : 60) + row * 13) withAttributes: body];
      [[NSString stringWithFormat: @"%@  |  Page %u of %u",
        [CLLedger invoiceNumber: _invoice], page + 1, _pageCount]
        drawAtPoint: NSMakePoint (12, top + 697) withAttributes: body];
    }
}

- (NSString *) emailText
{
  return [NSString stringWithFormat: @"Invoice %@\n\n%@", [CLLedger invoiceNumber: _invoice],
    [_rows componentsJoinedByString: @"\n"]];
}

- (BOOL) writePDFToPath: (NSString *)path error: (NSString **)error
{
  NSPrintInfo *info = [[[NSPrintInfo sharedPrintInfo] copy] autorelease];
  NSPrintOperation *operation;
  BOOL ok = NO;
  [info setTopMargin: 30]; [info setBottomMargin: 30];
  [info setLeftMargin: 30]; [info setRightMargin: 30];
  [info setHorizontalPagination: NSFitPagination];
  [info setVerticalPagination: NSAutoPagination];
  [info setHorizontallyCentered: YES];
  [[info dictionary] setObject: [NSNumber numberWithBool: YES] forKey: NSPrintAllPages];
  [[info dictionary] setObject: [NSNumber numberWithInt: 1] forKey: NSPrintFirstPage];
  [[info dictionary] setObject: [NSNumber numberWithUnsignedInt: _pageCount] forKey: NSPrintLastPage];
  [[info dictionary] setObject: NSPrintSaveJob forKey: NSPrintJobDisposition];
  [[info dictionary] setObject: path forKey: NSPrintSavePath];
  operation = [NSPrintOperation printOperationWithView: self printInfo: info];
  [operation setShowsPrintPanel: NO];
  [operation setShowsProgressPanel: NO];
  @try { ok = [operation runOperation]; }
  @catch (NSException *exception)
    { if (error != NULL) *error = [exception reason]; return NO; }
  if (!ok || [[[NSFileManager defaultManager] attributesOfItemAtPath: path error: NULL] fileSize] == 0)
    { if (error != NULL) *error = @"Could not export the invoice PDF. No email was sent."; return NO; }
  return YES;
}

- (void) printInvoice: (id)sender
{
  NSPrintInfo *info = [[[NSPrintInfo sharedPrintInfo] copy] autorelease];
  NSPrintOperation *operation;
  [info setTopMargin: 30];
  [info setBottomMargin: 30];
  [info setLeftMargin: 30];
  [info setRightMargin: 30];
  [info setHorizontalPagination: NSFitPagination];
  [info setVerticalPagination: NSAutoPagination];
  [info setHorizontallyCentered: YES];
  operation = [NSPrintOperation printOperationWithView: self printInfo: info];
  [operation runOperation];
}
@end
