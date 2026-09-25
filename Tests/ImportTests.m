#import <Foundation/Foundation.h>
#import "CLLedger.h"
#import "CLQuickBooksImporter.h"

static unsigned int checks = 0;
static void
Check (BOOL condition, NSString *message)
{
  checks++;
  if (!condition)
    {
      NSLog (@"FAIL: %@", message);
      exit (1);
    }
}

static NSData *
Bytes (NSString *text)
{
  return [text dataUsingEncoding: NSUTF8StringEncoding];
}

static BOOL
Import (CLLedger *ledger, NSString *text, NSString *name, BOOL commit)
{
  NSString *error = nil;
  BOOL ok = [ledger importQuickBooksData: Bytes (text) filename: name commit: commit report: NULL error: &error];
  return ok;
}

/** Exercise import previews, atomic rollback, source identities, encoding,
 * billing safeguards, native file rejection and cross-platform persistence. */
int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *directory = [NSTemporaryDirectory () stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent: @"ledger.plist"];
  NSString *error = nil;
  NSString *report = nil;
  CLLedger *ledger = [[CLLedger alloc] initWithPath: path error: &error];
  NSDictionary *parsed;
  NSString *customers = @"﻿Customer full name,Email,Billing address,Hourly rate\r\n\"Acme, Inc.\",billing@example.test,\"12 Main St\nSuite \"\"A\"\"\",125.50\r\n";
  NSString *iif = @"!CUST\tNAME\tBADDR1\tEMAIL\nCUST\tExample\t123 Example Street\tmail@example.test\n!ACCNT\tNAME\nACCNT\tSales\n!TRNS\tTRNSTYPE\tDATE\tNAME\tAMOUNT\tDOCNUM\n!SPL\tTRNSTYPE\tDATE\tAMOUNT\tMEMO\tEXTRA\n!ENDTRNS\nTRNS\tINVOICE\t7/16/98\tExample\t220.89\tQB-100\nSPL\tINVOICE\t7/16/98\t-205\tConsultation\t\nSPL\tINVOICE\t7/16/98\t-15.89\tSales Tax\tAUTOSTAX\nENDTRNS\n";
  NSString *times = @"Customer,Date,Duration,Description,Billable status,Rate,Time ID\nExample,09/25/2026,1:30,Design,Billable,100,T1\nExample,2026-09-25,2.25,Meeting,Not Billable,100,T2\nExample,2026-09-25,0:15,Old work,Billed,100,T3\nExample,2026-09-25,1,Review,,100,T4\n";
  NSData *before;
  NSDictionary *invoice;
  NSString *timeID;
  NSMutableDictionary *business;
  NSUInteger i;
  NSArray *badCSVs = [NSArray arrayWithObjects:
    @"Name,Name\nA,B\n",
    @"Name,Rate\nA,-5\n",
    @"Name,Email\n\"unterminated,bad\n",
    @"Name\n\"A\"trailing\n",
    @"Name\nA,extra\n",
    @"Customer,Date,Hours\nA,2026-02-30,1\n",
    @"Customer,Date,Hours\nA,2026-09-25,1e3\n",
    @"Customer,Date,Duration\nA,2026-09-25,1:60\n",
    @"Customer,Date,Duration\nA,2026-09-25,0\n",
    @"Customer,Invoice number,Date,Total,Balance\nA,N1,2026-09-25,100,50\n",
    @"Customer,Invoice number,Date,Total,Balance,Status\nA,N1,2026-09-25,100,100,Paid\n",
    @"Customer,Invoice number,Date,Total\nA,N1,bad,100\n",
    @"Customer,Invoice number,Date,Total,Type\nA,N1,2026-09-25,100,Payment\n", nil];

  parsed = [CLQuickBooksImporter recordsFromData:
    [NSData dataWithContentsOfFile: @"Tests/Fixtures/Intuit-invoice-sales-tax.iif"]
    filename: @"sample.iif" error: &error];
  if (parsed == nil)
    NSLog (@"Sample error: %@", error);
  Check (parsed != nil, @"Intuit official IIF invoice sample parses");
  Check ([[[[parsed objectForKey: @"invoices"] objectAtIndex: 0] objectForKey: @"total"] intValue] == 22089,
    @"Intuit sample invoice amount preserved");
  Check ([ledger importQuickBooksData: Bytes (customers) filename: @"Customers.CSV" commit: NO report: &report error: &error], @"Customer preview");
  Check ([[ledger clients] count] == 0 && ![[NSFileManager defaultManager] fileExistsAtPath: path], @"Preview does not modify memory or disk");
  Check ([report rangeOfString: @"1 new clients"].location != NSNotFound, @"Preview includes counts");
  parsed = [CLQuickBooksImporter recordsFromData:
    Bytes (@"Customer,Invoice number,Date,Total\nA,QB-TAX,2026-09-25,100\n")
    filename: @"invoice.csv" error: &error];
  Check ([[[[parsed objectForKey: @"invoices"] objectAtIndex: 0] objectForKey: @"taxUnverified"] boolValue],
    @"Missing CSV tax is identified as unitemized, not inferred to be zero");
  Check (Import (ledger, customers, @"Customers.csv", YES), @"Quoted CSV and BOM import");
  Check ([[[[ledger clients] objectAtIndex: 0] objectForKey: @"address"] isEqual: @"12 Main St\nSuite \"A\""], @"Quoted newline and escaped quotes preserved");
  Check (Import (ledger, customers, @"Customers.csv", YES) && [[ledger clients] count] == 1, @"Customer import is idempotent");
  Check (Import (ledger, @"Name,Rate\n\"acme, inc.\",1\n", @"clients.csv", YES), @"Case insensitive name match");
  Check ([[[[ledger clients] objectAtIndex: 0] objectForKey: @"rate"] intValue] == 12550, @"Existing customer not overwritten");
  Check ([ledger importQuickBooksData: Bytes (iif) filename: @"example.iif" commit: YES report: &report error: &error], @"IIF clients and invoices");
  Check ([report rangeOfString: @"Skipped ACCNT: 1"].location != NSNotFound, @"Unsupported sections reported");
  invoice = [[ledger invoices] objectAtIndex: 0];
  Check ([[invoice objectForKey: @"subtotal"] intValue] == 20500 && [[invoice objectForKey: @"tax"] intValue] == 1589, @"Exact imported subtotal and tax");
  Check ([[invoice objectForKey: @"total"] intValue] == 22089, @"Exact imported total");
  Check ([[invoice objectForKey: @"date"] isEqual: @"1998-07-16"], @"Two digit IIF year");
  Check ([[CLLedger invoiceNumber: invoice] isEqual: @"QB-100"], @"Original invoice number preserved");
  Check ([[invoice objectForKey: @"paymentUnverified"] boolValue], @"Missing payment state flagged");
  Check ([[invoice objectForKey: @"dueDateUnverified"] boolValue], @"Missing due date flagged");
  Check ([[ledger entries] count] == 0, @"Imported invoices do not fabricate unbilled time");
  Check (Import (ledger, iif, @"renamed.iif", YES) && [[ledger invoices] count] == 1, @"Repeat invoice import skipped across filenames");
  invoice = [[ledger invoices] objectAtIndex: 0];
  Check ([ledger setInvoice: [invoice objectForKey: @"id"] paid: NO error: &error], @"Confirm unpaid state");
  Check (![[invoice objectForKey: @"paymentUnverified"] boolValue] && ![[invoice objectForKey: @"paid"] boolValue], @"Unpaid confirmation removes unknown flag");
  Check (Import (ledger, iif, @"again.iif", YES), @"Reimport preserves reviewed payment state");
  before = [NSData dataWithContentsOfFile: path];
  Check (!Import (ledger, [iif stringByReplacingOccurrencesOfString: @"Consultation" withString: @"Changed"], @"conflict.iif", YES), @"Source identity conflict rejected");
  Check ([before isEqual: [NSData dataWithContentsOfFile: path]], @"Conflict makes no disk change");
  Check (Import (ledger, times, @"time.csv", YES) && [[ledger entries] count] == 4, @"Import mixed billing time");
  Check ([[[[ledger entries] objectAtIndex: 0] objectForKey: @"seconds"] intValue] == 5400, @"H:MM duration exact");
  Check ([CLLedger isUnbilledEntry: [[ledger entries] objectAtIndex: 0]], @"Billable entry eligible");
  for (i = 1; i < 4; i++)
    Check (![CLLedger isUnbilledEntry: [[ledger entries] objectAtIndex: i]], @"Other billing states excluded");
  Check (Import (ledger, times, @"time.csv", YES) && [[ledger entries] count] == 4, @"Time stable IDs deduplicate");
  timeID = [[[[ledger entries] objectAtIndex: 3] objectForKey: @"id"] copy];
  Check ([ledger reviewImportedTime: timeID rate: @"125" billable: YES error: &error], @"Review uncertain time");
  Check ([CLLedger isUnbilledEntry: [[ledger entries] objectAtIndex: 3]], @"Reviewed time becomes eligible");
  Check (![ledger reviewImportedTime: [[[ledger entries] objectAtIndex: 2] objectForKey: @"id"] rate: @"1" billable: YES error: &error], @"Previously billed time locked");
  Check (Import (ledger, times, @"time.csv", YES), @"Reimport keeps local time review");
  Check ([[[[ledger entries] objectAtIndex: 3] objectForKey: @"rate"] intValue] == 12500, @"Reviewed rate preserved");
  Check ([ledger invoiceClient: [[[ledger clients] objectAtIndex: 1] objectForKey: @"id"] tax: @"0" dueDate: @"2099-01-01" error: &error], @"Invoice only eligible imported time");
  Check ([[[[ledger invoices] lastObject] objectForKey: @"total"] intValue] == 27500, @"Nonbillable and already billed amounts excluded");
  Check (Import (ledger, @"!TIMEACT\tDATE\tJOB\tDURATION\tNOTE\tBILLINGSTATUS\nTIMEACT\t9/25/2026\tExample\t1:00\tNeeds rate\t1\n", @"time.iif", YES), @"IIF time import");
  Check ([[[[ledger entries] lastObject] objectForKey: @"externalBilling"] isEqual: @"Review required"], @"Missing rate requires review");
  Check (Import (ledger, @"Customer,Date,Hours,Description,Rate,Billable status\nExample,2026-09-25,1,Same,100,Billable\nExample,2026-09-25,1,Same,100,Billable\n", @"repeat.csv", YES), @"Identical separate rows preserved");
  Check ([[ledger entries] count] == 7, @"Both identical time rows present");
  Check (Import (ledger, @"Customer,Date,Hours,Description,Rate,Billable status\nExample,2026-09-25,1,Same,100,Billable\nExample,2026-09-25,1,Same,100,Billable\n", @"repeat.csv", YES) && [[ledger entries] count] == 7, @"Occurrence based duplicate detection");
  Check (Import (ledger, @"Customer,Invoice number,Date,Due date,Total,Tax,Open balance,Status\nExample,CSV-1,2026-09-01,2026-10-01,108,8,0,Paid\n", @"invoices.csv", YES), @"CSV summary invoice import");
  Check ([[[[ledger invoices] lastObject] objectForKey: @"paid"] boolValue], @"CSV paid status");
  Check ([[[[ledger invoices] lastObject] objectForKey: @"subtotal"] intValue] == 10000, @"CSV tax separated");
  for (i = 0; i < [badCSVs count]; i++)
    Check (!Import (ledger, [badCSVs objectAtIndex: i], @"bad.csv", YES), @"Malformed CSV rejected");
  Check (!Import (ledger, [iif stringByReplacingOccurrencesOfString: @"220.89" withString: @"999"], @"bad.iif", YES), @"Unbalanced invoice rejected");
  Check (!Import (ledger, [iif substringToIndex: [iif length] - 8], @"bad.iif", YES), @"Missing ENDTRNS rejected");
  Check (!Import (ledger, @"!ENDTRNS\nENDTRNS\n", @"bad.iif", YES), @"Orphan transaction terminator rejected");
  Check (!Import (ledger, @"!SPL\tAMOUNT\nSPL\t-1\n", @"bad.iif", YES), @"Orphan split rejected");
  before = [NSData dataWithContentsOfFile: path];
  Check (!Import (ledger, @"Name,Rate\nValid New Client,10\nInvalid Client,bad\n", @"bad.csv", YES), @"Mixed valid/invalid file is all or nothing");
  Check ([before isEqual: [NSData dataWithContentsOfFile: path]] && [[ledger clients] count] == 2, @"Malformed import leaves existing data untouched");
  Check (!Import (ledger, @"Name,Currency\nNew Client,EUR\n", @"bad.csv", YES), @"Currency mismatch rejected");
  Check ([[ledger clients] count] == 2, @"Currency mismatch rolls back staged clients");
  Check (!Import (ledger, @"Name\nTest\n", @"company.qbw", YES), @"Native QBW rejected");
  Check (!Import (ledger, @"Name\nTest\n", @"backup.qbb", YES), @"Native QBB rejected");
  Check (!Import (ledger, @"Name\nTest\n", @"bank.qbo", YES), @"Bank QBO rejected");
  parsed = [CLQuickBooksImporter recordsFromData: [@"Name\nCafé\n" dataUsingEncoding: NSWindowsCP1252StringEncoding] filename: @"encoded.csv" error: &error];
  Check ([[[[parsed objectForKey: @"clients"] objectAtIndex: 0] objectForKey: @"name"] isEqual: @"Café"], @"Windows-1252 encoding");
  parsed = [CLQuickBooksImporter recordsFromData: [@"Name\nCafé\n" dataUsingEncoding: NSUnicodeStringEncoding] filename: @"encoded.csv" error: &error];
  Check ([[[[parsed objectForKey: @"clients"] objectAtIndex: 0] objectForKey: @"name"] isEqual: @"Café"], @"UTF-16 BOM encoding");
  business = [NSMutableDictionary dictionaryWithDictionary: [ledger business]];
  [business setObject: @"EUR" forKey: @"currency"];
  Check (![ledger saveBusiness: business error: &error], @"Currency remains locked");
  [ledger release];
  ledger = [[CLLedger alloc] initWithPath: path error: &error];
  Check (ledger != nil && [[ledger invoices] count] == 3 && [[ledger entries] count] == 7, @"Imported records survive reopen");
  Check (Import (ledger, iif, @"reopen.iif", YES) && [[ledger invoices] count] == 3, @"Deduplication survives reopen");
  [ledger release];
  {
    NSString *blocked = [directory stringByAppendingPathComponent: @"blocked"];
    [@"file" writeToFile: blocked atomically: YES encoding: NSUTF8StringEncoding error: NULL];
    ledger = [[CLLedger alloc] initWithPath: [blocked stringByAppendingPathComponent: @"ledger.plist"] error: &error];
    Check (!Import (ledger, iif, @"save-failure.iif", YES), @"Import write failure reported");
    Check ([[ledger clients] count] == 0 && [[ledger invoices] count] == 0, @"Write failure rolls back entire import");
    [ledger release];
  }
  [timeID release];
  [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
  NSLog (@"PASS: %u QuickBooks import checks", checks);
  [pool drain];
  return 0;
}
