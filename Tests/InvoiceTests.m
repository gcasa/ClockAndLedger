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
  operation = [NSPrintOperation printOperationWithView: view printInfo: info];
  [operation setShowsPrintPanel: NO];
  [operation setShowsProgressPanel: NO];
  if (![operation runOperation])
    result = 1;
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
  [pool drain];
  return result;
}
