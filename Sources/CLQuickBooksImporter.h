#import <Foundation/Foundation.h>

/** Reads QuickBooks text exports without changing the ledger. Native company
 * databases and backups are deliberately rejected with export instructions. */
@interface CLQuickBooksImporter : NSObject
/** Parse UTF-8, UTF-16 BOM or Windows-1252 IIF/CSV data into normalized client,
 * time and invoice records. Unsupported IIF sections are listed in warnings;
 * malformed supported records fail the entire import with a record number. */
+ (NSDictionary *) recordsFromData: (NSData *)data filename: (NSString *)filename
                            error: (NSString **)error;
@end
