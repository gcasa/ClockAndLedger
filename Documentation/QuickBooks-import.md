# Importing QuickBooks data

Choose **Clock & Ledger → Import QuickBooks…** (Command-I), or open the
**Business** tab and click **Import QuickBooks…**. Choose a file, read the record
preview and warnings, then click **Import Records**. Cancel leaves the ledger
unchanged. A malformed supported record aborts the whole import. A successful
import is saved in one atomic write; a failed write rolls it back.

Use one QuickBooks company and one currency per ledger. Set the business details
and currency before importing. Imported invoice snapshots use the business
information currently saved in Clock & Ledger. Amounts with no currency column
are assumed to use the ledger currency; explicitly mismatched currencies are
rejected. Keep your original export and a ledger backup.

## Supported files

| File | Support |
| --- | --- |
| `.iif` | Customer/job lists (`CUST`), time (`TIMEACT`), and invoice transactions (`TRNS` / `SPL` / `ENDTRNS`). |
| `.csv` | Customer lists, time entries, and invoice **summary** reports with the headers below. |
| `.qbw` | Native QuickBooks company database: open it in QuickBooks and export IIF/CSV first. |
| `.qbb` | Native QuickBooks backup: restore it in QuickBooks, then export IIF/CSV. |
| `.qbo`, `.qbx`, `.qbm`, `.xlsx`, other formats | Not decoded. Export the relevant data as IIF/CSV first. A QBO bank-download file is not a QuickBooks Online company backup. |

QBW/QBB decoding is not implemented. Selecting one displays export instructions
without changing the ledger. IIF is a text interchange format, distinct from
QuickBooks' native databases and backups. See Intuit's
[file format guide](https://quickbooks.intuit.com/learn-support/en-us/help-article/banking/file-types-extensions-used-quickbooks-desktop/L3vuO2X4c_US_en_US).

In QuickBooks Desktop, customer lists can be exported using **File → Utilities →
Export → Lists to IIF Files**. Transaction export availability depends on the
QuickBooks edition and export tool; use an invoice-only CSV summary report if
an IIF transaction export is unavailable. In QuickBooks Online, export the
relevant list/report and save as CSV if it is delivered as an Excel workbook.
The importer does not connect to your Intuit account.

## IIF details

Headers beginning with `!` determine field positions; the importer does not
assume fixed column order. Customer:Job names are retained in full. Customer
fields `NAME`, `EMAIL`, `BADDR1`…`BADDR5` are read; optional `RATE` / `HOURLY RATE`
sets the default hourly rate. A missing customer rate starts at zero.

Time uses `DATE`, `JOB`, `DURATION`, `NOTE` (or `ITEM`), `EMP`, and `BILLINGSTATUS`.
Durations accept `H:MM`, `H:MM:SS`, or decimal hours. Billing status 1 is billable,
0 is nonbillable, and 2 is already billed. Missing status is **Review required**.
An optional `TIMEACTID` supplies a stable source identity. Standard IIF time does
not normally supply a rate; without `RATE`, the client's current rate is shown
as a suggestion, and billable time is held for review.

Invoice `TRNS` records require `TRNSTYPE=INVOICE`, `NAME`, `DATE`, `DOCNUM` and a
nonnegative `AMOUNT`. `DUEDATE` is optional. Negative `SPL` amounts become positive
invoice charges. Tax splits are recognized by `EXTRA=AUTOSTAX`, or by matching
`INVITEM` entries declared as `COMPTAX` / `TAX`. All split charges plus tax must
equal the original total exactly. Imported item amounts remain amounts; they
are not converted into invented hours or rates. Positive splits (discounts or
credits), negative invoice totals, and partial payments are not supported.

The importer reports skipped account, inventory, employee, vendor and other
list records, and skipped non-invoice transactions. It uses item declarations
only to recognize tax; it does not create an inventory catalog. Payment
transactions are not applied to invoices. `CLEAR` means cleared/reconciled,
not paid, so it is not used to infer payment status.

## CSV headers

The first nonblank record must contain column names, with no report title or
preamble. Export **one kind of record per file**. Remove report totals, subtotals
and footers before importing. Column names are case-insensitive; extra columns
are not imported. Quoted commas, escaped double quotes and multiline fields are
supported. CSV is comma-delimited; semicolon-delimited files must be converted.

| Kind | Required headers | Optional headers |
| --- | --- | --- |
| Customers | `Name`, `Customer`, `Customer full name`, `Full name`, or `Display name` | `Email` / `Email address`, `Billing address` / `Address`, `Billing address line 1`…`5`, `Hourly rate` / `Rate`, `Currency` |
| Time | `Customer` / `Client` / `Customer full name`, `Date`, `Hours` / `Duration` | `Description` / `Note` / `Memo`, `Rate` / `Hourly rate`, `Billable status` / `Billing status`, `Time ID` / `ID`, `Employee`, `Currency` |
| Invoice summaries | `Customer` / `Client` / `Name`, `Invoice number` / `Invoice no` / `Num` / `No.`, `Date` / `Invoice date`, `Total` / `Amount` / `Invoice total` | `Due date`, `Tax` / `Tax amount`, `Open balance` / `Balance`, `Status`, `Memo` / `Description`, `Currency`, `Transaction type` / `Type` (must be Invoice) |

One CSV invoice row represents one complete invoice, not a line item. It imports
as a summary line, with tax separated if supplied. Do not use item-detail or
multi-row invoice reports. If `Tax` is absent, the total is retained as a single
summary amount; tax is not inferred.

Amounts must be nonnegative plain decimals such as `1234.50`, with at most two
decimal places. Remove currency symbols and thousands separators. Dates accept
`YYYY-MM-DD` or US `M/D/YYYY`; two-digit years map to 1970–2069. Day/month/year
exports must be converted to ISO first. Decimal hours accept up to four places
and are truncated to whole seconds, matching manual time entry.

Text files may use UTF-8 (with/without BOM), UTF-16 with BOM, or Windows-1252.
Files are limited to 20 MB.

## Review safeguards and repeat imports

- Existing customers match by case-insensitive **full name**. Their saved contact
  details and rates are preserved. Duplicate existing client names block import
  so the app never guesses which client to use.
- Imported invoices retain their original number for display and printing, plus
  a unique local ID. Their original total, tax and date are preserved. Their
  line items do not create billable time records.
- An invoice without payment information is marked **Review payment** and is
  excluded from paid/outstanding totals until confirmed with **Toggle Paid /
  Unpaid**. CSV `Status` accepts Paid, Unpaid, Open or Overdue. An open balance
  must equal zero or the full total; partial payments and conflicting status
  information are rejected.
- An invoice without a due date displays **Not provided** and is not classified
  as overdue. The issue date is stored only as an internal placeholder.
- Time with missing status or rate is excluded from new invoices until explicitly
  reviewed using **Time → Review Imported Time**. Already billed and nonbillable
  time is excluded. Already billed time cannot be changed back to billable.
- Invoice identity is customer full name + original invoice number. Time uses a
  stable Time ID when supplied; otherwise it uses customer, date, duration,
  description, employee and the occurrence number among identical rows.
- Identical reimports are skipped, even after the source file is renamed or the
  app restarts. Local payment/rate reviews are preserved. A matching identity
  with changed source data is rejected rather than silently overwriting it.
- Without stable time IDs, distinct work with identical details across separate
  exports cannot be distinguished from repeated data. Use stable IDs or import
  non-overlapping datasets. Changing identity fields can create a new record.
  This does not deduplicate against manually entered time/invoices.

## Samples and verification

`Tests/Fixtures/` includes small CSV examples and Intuit's published sample
invoice IIF. The latter is from Intuit's
[IIF sample documentation](https://quickbooks.intuit.com/learn-support/en-us/help-article/list-management/iif-overview-import-kit-sample-files-headers/L5CZIpJne_US_en_US)
and [invoice-with-tax archive](https://http-download.intuit.com/http.intuit/OpenCms/sites/default/QBSupportSite/executables/IIF/invoice_sales_tax_charged.zip).

Run `make -f Makefile test-import` on macOS. The Docker GNUstep build also runs
these tests. They cover parsing, source identities, previews, save rollback,
malformed files, original totals, billing exclusions, and persistence.
