#import <Foundation/Foundation.h>
@class CLLedger;

/** Read-only reporting. Monetary totals are integer cents and currencies never mix. */
@interface CLReporting : NSObject
+ (NSDictionary *) reportForLedger: (CLLedger *)ledger from: (NSString *)start to: (NSString *)end currency: (NSString *)currency today: (NSString *)today;
+ (NSString *) csvForRows: (NSArray *)rows keys: (NSArray *)keys titles: (NSArray *)titles moneyKeys: (NSArray *)moneyKeys;
+ (BOOL) date: (NSString *)date from: (NSString *)start to: (NSString *)end;
@end
