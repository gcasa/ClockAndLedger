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
            [line objectForKey: @"date"], [line objectForKey: @"description"]]);
          if ([[line objectForKey: @"importedAmount"] boolValue])
            CLAppendRows (rows, [NSString stringWithFormat: @"    Amount: %@ %@", currency,
              [CLLedger money: [line objectForKey: @"amount"]]]);
          else
            CLAppendRows (rows, [NSString stringWithFormat: @"    %.4f hours x %@ %@/hr                 %@ %@",
            [[line objectForKey: @"seconds"] doubleValue] / 3600.0,
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
      CLAppendRows (rows, [business objectForKey: @"notes"]);
      _rows = [rows copy];
      _pageCount = MAX (1, (unsigned int)([_rows count] + 47) / 48);
      [self setFrameSize: NSMakeSize (520, 720 * _pageCount)];
    }
  return self;
}

- (void) dealloc
{
  [_invoice release];
  [_rows release];
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
      [[NSString stringWithFormat: @"INVOICE  %@", [CLLedger invoiceNumber: _invoice]]
        drawAtPoint: NSMakePoint (12, top + 15) withAttributes: heading];
      for (row = 0; row < 48 && page * 48 + row < [_rows count]; row++)
        [[_rows objectAtIndex: page * 48 + row]
          drawAtPoint: NSMakePoint (12, top + 60 + row * 13) withAttributes: body];
      [[NSString stringWithFormat: @"%@  |  Page %u of %u",
        [CLLedger invoiceNumber: _invoice], page + 1, _pageCount]
        drawAtPoint: NSMakePoint (12, top + 697) withAttributes: body];
    }
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
