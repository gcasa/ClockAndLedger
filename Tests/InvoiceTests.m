#import <AppKit/AppKit.h>
#import <PDFKit/PDFKit.h>
#import "CLInvoiceView.h"
#import "CLLedger.h"
#import "CLQuickBooksImporter.h"

/** Verify actual multi-page PDF output through AppKit's print pipeline. */
int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSMutableDictionary *invoice;
  NSDictionary *client;
  NSDictionary *business;
  NSMutableArray *lines = [NSMutableArray array];
  CLInvoiceView *view;
  NSRange pages;
  NSPrintInfo *info;
  NSPrintOperation *operation;
  PDFDocument *pdf;
  NSString *path = [[[NSFileManager defaultManager] currentDirectoryPath]
    stringByAppendingPathComponent: @"build/Invoice-pagination-test.pdf"];
  unsigned int i;
  int result = 0;
  [NSApplication sharedApplication];
  client = [NSDictionary dictionaryWithObjectsAndKeys: @"Example Client", @"name",
    @"123 Example Street\nExample City", @"address", @"billing@example.test", @"email", nil];
  business = [NSDictionary dictionaryWithObjectsAndKeys: @"Example Business", @"name",
    @"456 Sample Lane", @"address", @"hello@example.test", @"email", @"USD", @"currency",
    @"FINAL PAYMENT INSTRUCTIONS", @"notes", nil];
  for (i = 0; i < 80; i++)
    [lines addObject: [NSDictionary dictionaryWithObjectsAndKeys:
      @"2026-09-25", @"date", [NSString stringWithFormat:
        @"Service %u: A lengthy description that must wrap without clipping or losing any words at the printable page boundary.", i + 1], @"description",
      [NSNumber numberWithInt: 3600], @"seconds", [NSNumber numberWithInt: 10000], @"rate",
      [NSNumber numberWithInt: 10000], @"amount", nil]];
  {
    NSMutableDictionary *firstLine = [NSMutableDictionary dictionaryWithDictionary: [lines objectAtIndex: 0]];
    [firstLine setObject: @"2026-09-21" forKey: @"date"];
    [firstLine setObject: @"2026-09-27" forKey: @"periodEnd"];
    [firstLine setObject: @"week" forKey: @"periodKind"];
    [firstLine setObject: @"Design consulting" forKey: @"taskName"];
    [lines replaceObjectAtIndex: 0 withObject: firstLine];
  }
  invoice = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    @"INV-TEST", @"id", @"2026-09-25", @"date", @"2026-10-25", @"dueDate",
    client, @"client", business, @"business", lines, @"lines",
    @"0", @"taxPercent", [NSNumber numberWithInt: 800000], @"subtotal",
    [NSNumber numberWithInt: 0], @"tax", [NSNumber numberWithInt: 800000], @"total",
    [NSNumber numberWithBool: NO], @"paid", nil];
  {
    NSImage *logo = [[[NSImage alloc] initWithSize: NSMakeSize (160, 80)] autorelease];
    NSMutableDictionary *branded = [NSMutableDictionary dictionaryWithDictionary: business];
    [logo lockFocus];
    [[NSColor redColor] set];
    NSRectFill (NSMakeRect (0, 0, 160, 80));
    [logo unlockFocus];
    [branded setObject: [logo TIFFRepresentation] forKey: @"logoData"];
    [invoice setObject: branded forKey: @"business"];
  }
  view = [[CLInvoiceView alloc] initWithInvoice: invoice];
  if ([[view emailText] rangeOfString: @"Invoice INV-TEST"].location == NSNotFound
      || [[view emailText] rangeOfString: @"Service 80"].location == NSNotFound
      || [[view emailText] rangeOfString: @"FINAL PAYMENT INSTRUCTIONS"].location == NSNotFound
      || [[view emailText] rangeOfString: @"billing@example.test"].location == NSNotFound)
    result = 1;
  [view knowsPageRange: &pages];
  info = [[[NSPrintInfo sharedPrintInfo] copy] autorelease];
  [info setTopMargin: 30];
  [info setBottomMargin: 30];
  [info setLeftMargin: 30];
  [info setRightMargin: 30];
  [[info dictionary] setObject: NSPrintSaveJob forKey: NSPrintJobDisposition];
  [[info dictionary] setObject: path forKey: NSPrintSavePath];
  {
    NSMutableDictionary *settings = [[NSPrintInfo sharedPrintInfo] dictionary];
    NSDictionary *savedSettings = [[settings copy] autorelease];
    NSString *exportError = nil;
    /* A previous print job's page selection must not truncate attachments. */
    [settings setObject: [NSNumber numberWithBool: NO] forKey: NSPrintAllPages];
    [settings setObject: [NSNumber numberWithInt: 2] forKey: NSPrintFirstPage];
    [settings setObject: [NSNumber numberWithInt: 2] forKey: NSPrintLastPage];
    if (![view writePDFToPath: path error: &exportError])
      { NSLog (@"Export failed: %@", exportError); result = 1; }
    [settings setObject: [savedSettings objectForKey: NSPrintAllPages] ?: [NSNumber numberWithBool: YES] forKey: NSPrintAllPages];
    [settings setObject: [savedSettings objectForKey: NSPrintFirstPage] ?: [NSNumber numberWithInt: 1] forKey: NSPrintFirstPage];
    [settings setObject: [savedSettings objectForKey: NSPrintLastPage] ?: [NSNumber numberWithUnsignedInteger: pages.length] forKey: NSPrintLastPage];
  }
  pdf = [[PDFDocument alloc] initWithURL: [NSURL fileURLWithPath: path]];
  if (pdf == nil || [pdf pageCount] != pages.length || pages.length < 2
      || [[pdf string] rangeOfString: @"FINAL PAYMENT INSTRUCTIONS"].location == NSNotFound
      || [[pdf string] rangeOfString: @"Service 80"].location == NSNotFound
      || [[pdf string] rangeOfString: @"2026-09-27"].location == NSNotFound
      || [[pdf string] rangeOfString: @"Design consulting"].location == NSNotFound)
    result = 1;
  {
    NSImage *render = [[pdf pageAtIndex: 0] thumbnailOfSize: NSMakeSize (612, 792) forBox: kPDFDisplayBoxMediaBox];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData: [render TIFFRepresentation]];
    NSInteger x, y;
    NSUInteger redPixels = 0;
    for (y = 0; y < [bitmap pixelsHigh]; y++)
      for (x = 0; x < [bitmap pixelsWide]; x++)
        {
          NSColor *color = [[bitmap colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
          if ([color redComponent] > 0.8 && [color greenComponent] < 0.2 && [color blueComponent] < 0.2)
            redPixels++;
        }
    if (redPixels < 1000) result = 1;
    NSLog (@"Logo rendered in PDF: %lu red pixels", (unsigned long)redPixels);
  }
  NSLog (@"%@: printed %lu pages; final service and payment instructions preserved",
    result == 0 ? @"PASS" : @"FAIL", (unsigned long)[pdf pageCount]);
  [pdf release];
  [view release];
  {
    NSString *error = nil;
    NSDictionary *parsed = [CLQuickBooksImporter recordsFromData:
      [NSData dataWithContentsOfFile: @"Tests/Fixtures/Intuit-invoice-sales-tax.iif"]
      filename: @"invoice.iif" error: &error];
    NSMutableDictionary *imported = [NSMutableDictionary dictionaryWithDictionary:
      [[parsed objectForKey: @"invoices"] objectAtIndex: 0]];
    NSString *importedPath = [[[NSFileManager defaultManager] currentDirectoryPath]
      stringByAppendingPathComponent: @"build/QuickBooks-import-test.pdf"];
    NSString *printed;
    [imported setObject: business forKey: @"business"];
    [imported setObject: [[parsed objectForKey: @"clients"] objectAtIndex: 0] forKey: @"client"];
    [imported setObject: @"INV-00001" forKey: @"id"];
    view = [[CLInvoiceView alloc] initWithInvoice: imported];
    [[info dictionary] setObject: importedPath forKey: NSPrintSavePath];
    operation = [NSPrintOperation printOperationWithView: view printInfo: info];
    [operation setShowsPrintPanel: NO];
    [operation setShowsProgressPanel: NO];
    if (![operation runOperation])
      result = 1;
    pdf = [[PDFDocument alloc] initWithURL: [NSURL fileURLWithPath: importedPath]];
    printed = [pdf string];
    if (pdf == nil || [pdf pageCount] != 1
        || [printed rangeOfString: @"220.89"].location == NSNotFound
        || [printed rangeOfString: @"205.00"].location == NSNotFound
        || [printed rangeOfString: @"15.89"].location == NSNotFound
        || [printed rangeOfString: @"Tax (imported)"].location == NSNotFound
        || [printed rangeOfString: @"VERIFY PAYMENT"].location == NSNotFound
        || [printed rangeOfString: @"hours x"].location != NSNotFound)
      result = 1;
    NSLog (@"%@: imported invoice PDF preserves original amounts and review status",
      result == 0 ? @"PASS" : @"FAIL");
    [pdf release];
    [view release];
  }
  {
    NSMutableDictionary *termsClient = [NSMutableDictionary dictionaryWithDictionary: client];
    NSMutableDictionary *termsBusiness = [NSMutableDictionary dictionaryWithDictionary: business];
    NSArray *days = [NSArray arrayWithObjects: @15, @1, @0, nil];
    NSArray *expected = [NSArray arrayWithObjects: @"Payment due within 15 days.", @"Payment due within 1 day.", @"Payment due on receipt.", nil];
    [invoice setObject: termsClient forKey: @"client"];
    [invoice setObject: termsBusiness forKey: @"business"];
    for (i = 0; i < [days count]; i++)
      {
        NSString *text;
        [termsClient setObject: [days objectAtIndex: i] forKey: @"netDays"];
        [termsBusiness setObject: @"Payment due within 30 days.\nPay by bank transfer." forKey: @"notes"];
        view = [[CLInvoiceView alloc] initWithInvoice: invoice];
        text = [view emailText];
        if ([text rangeOfString: [expected objectAtIndex: i]].location == NSNotFound
            || [text rangeOfString: @"Payment due within 30 days."].location != NSNotFound
            || [text rangeOfString: @"Pay by bank transfer."].location == NSNotFound)
          result = 1;
        [view release];
      }
    [termsBusiness setObject: @"Custom instructions" forKey: @"notes"];
    view = [[CLInvoiceView alloc] initWithInvoice: invoice];
    if ([[view emailText] rangeOfString: @"Payment due on receipt."].location == NSNotFound
        || [[view emailText] rangeOfString: @"Custom instructions"].location == NSNotFound)
      result = 1;
    [view release];
    NSLog (@"%@: invoice footer uses saved client terms and preserves custom instructions", result == 0 ? @"PASS" : @"FAIL");
  }
  {
    unsigned int state;
    [invoice setObject: business forKey: @"business"]; /* No red logo in stamp checks. */
    for (state = 0; state < 3; state++)
      {
        NSString *stampPath = [[[NSFileManager defaultManager] currentDirectoryPath]
          stringByAppendingPathComponent: [NSString stringWithFormat: @"build/Invoice-stamp-%u.pdf", state]];
        NSString *exportError = nil;
        NSUInteger pageIndex;
        [invoice setObject: [NSNumber numberWithBool: state != 0] forKey: @"paid"];
        [invoice setObject: [NSNumber numberWithBool: state == 2] forKey: @"paymentUnverified"];
        view = [[CLInvoiceView alloc] initWithInvoice: invoice];
        [view knowsPageRange: &pages];
        if (![view writePDFToPath: stampPath error: &exportError]) result = 1;
        pdf = [[PDFDocument alloc] initWithURL: [NSURL fileURLWithPath: stampPath]];
        if (pdf == nil || [pdf pageCount] != pages.length) result = 1;
        for (pageIndex = 0; pageIndex < [pdf pageCount]; pageIndex++)
          {
            NSImage *render = [[pdf pageAtIndex: pageIndex] thumbnailOfSize: NSMakeSize (612, 792) forBox: kPDFDisplayBoxMediaBox];
            NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData: [render TIFFRepresentation]];
            NSInteger x, y;
            NSUInteger redPixels = 0;
            for (y = 0; y < [bitmap pixelsHigh]; y++)
              for (x = 0; x < [bitmap pixelsWide]; x++)
                {
                  NSColor *color = [[bitmap colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
                  if ([color redComponent] > [color greenComponent] + 0.12
                      && [color redComponent] > [color blueComponent] + 0.12) redPixels++;
                }
            if ((state == 1 && redPixels < 5000) || (state != 1 && redPixels != 0)) result = 1;
            if (state == 1 && pageIndex == 0)
              [[bitmap representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]]
                writeToFile: @"build/Invoice-paid-stamp.png" atomically: YES];
          }
        if ([[pdf string] rangeOfString: @"Service 80"].location == NSNotFound) result = 1;
        [pdf release]; [view release];
      }
    NSLog (@"%@: red stamp on every paid page, absent from unpaid and unverified invoices", result == 0 ? @"PASS" : @"FAIL");
  }
  {
    NSString *paymentPath = @"build/Invoice-partial-payment.pdf";
    NSString *exportError = nil;
    [invoice removeObjectForKey: @"paymentUnverified"];
    [invoice setObject: [NSNumber numberWithBool: NO] forKey: @"paid"];
    [invoice setObject: [NSArray arrayWithObject: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: 5000] forKey: @"amount"]] forKey: @"payments"];
    view = [[CLInvoiceView alloc] initWithInvoice: invoice];
    if (![view writePDFToPath: paymentPath error: &exportError]) result = 1;
    pdf = [[PDFDocument alloc] initWithURL: [NSURL fileURLWithPath: paymentPath]];
    if (!pdf || [[pdf string] rangeOfString: @"Received: USD 50.00"].location == NSNotFound || [[pdf string] rangeOfString: @"PARTIALLY PAID"].location == NSNotFound || [[pdf string] rangeOfString: @"Balance due:"].location == NSNotFound) result = 1;
    [pdf release]; [view release];
    NSLog (@"%@: partial payment and remaining balance included in PDF", result == 0 ? @"PASS" : @"FAIL");
  }
  [pool drain];
  return result;
}
