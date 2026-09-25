#import <AppKit/AppKit.h>

/** Read-only invoice rendering shared by preview and native printing.
 * Long fields wrap and overflow onto explicitly paginated sheets. */
@interface CLInvoiceView : NSView
{
  NSDictionary *_invoice;
  NSArray *_rows;
  unsigned int _pageCount;
}
/** Create a printable view from an issued invoice snapshot. */
- (id) initWithInvoice: (NSDictionary *)invoice;
/** Run the native print dialog for this invoice. */
- (void) printInvoice: (id)sender;
@end
