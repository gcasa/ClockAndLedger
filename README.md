# Clock & Ledger

A native, local-first desktop time and invoice tracker written in classic
Objective-C. Runs on GNUstep and macOS AppKit. No browser, server, subscription,
ARC, properties, blocks, object literals, subscripting, or fast enumeration.
Source uses GNU C brace/indentation conventions and autogsdoc API comments.

## What works

- Create and edit clients, addresses, email and default hourly rates.
- Start/stop one live timer; it survives restarts and includes time while the
  application is closed or the computer sleeps.
- Enter an individual date, a weekly/monthly total, or daily hours in a weekly
  or monthly timesheet. Edit uninvoiced entries and record nonbillable lunch or breaks.
- Define tasks per client with separate hourly rates; edit, archive and restore
  tasks while preserving the rates and names on existing time/invoices.
- Bill a raw number of hours using an active client task's current rate, with no timesheet required.
- Optionally convert a client's unbilled timesheet hours into an invoice at their recorded rates.
- Open an Apple Mail draft with an invoice PDF, complete invoice text, and a per-client payment reminder.
- Preserve original time rates and invoice snapshots when client/business
  details change. Billed time is locked against deletion or duplicate billing.
- Set a tax percentage and due date; mark invoices paid/unpaid and see overdue
  status, unbilled charges, outstanding balances and paid totals.
- Preview and print invoices with wrapping and multiple pages. Use the native
  print dialog's PDF/file output when provided by the platform/backend.
- Import QuickBooks IIF and CSV exports with a review step, duplicate detection
  and atomic saving. [Supported formats and export instructions](Documentation/QuickBooks-import.md).
- Save business/payment details and copy the ledger using **Back Up Ledger**.

This is an initial time-billing application, not a complete accounting suite.
It does not yet include bank feeds, payroll, inventory, projects, credit notes,
invoice voiding, or multi-user/cloud sync. Expenses, receipts, partial payments,
invoice editing, search/filtering, dashboards and reports are supported.

## Build on GNUstep

On Debian/Ubuntu, install the GNUstep development tools and a GUI backend:

```sh
sudo apt-get install build-essential gobjc gnustep-make \
  libgnustep-base-dev libgnustep-gui-dev gnustep-back0.29-cairo
. /usr/share/GNUstep/Makefiles/GNUstep.sh
make -f GNUmakefile
openapp ./ClockAndLedger.app
```

The backend package name may differ by distribution/version. An X11 desktop
session and configured printing backend are needed to run/print. The source
uses Objective-C 1.0 language features with current Foundation/AppKit APIs;
it does not target historic NeXTSTEP SDKs.

Build and ledger tests were verified with GCC 12, the traditional GNU Objective-C
runtime, GNUstep Base 1.28 and GUI 0.29 on Debian Bookworm (ARM64).
The Linux GUI and a physical printer have not been exercised here.

## Build on macOS

Requires Xcode or Command Line Tools with the macOS SDK. Explicitly select
`Makefile`, because GNU make prefers `GNUmakefile` when both exist:

```sh
make -f Makefile macos
make -f Makefile run
```

The app is created at `build/ClockAndLedger.app`. It is a local unsigned build.

## First use

1. Open **Business**, enter your business and payment details, choose a
   currency, then save. All monetary values use two decimal places.
2. Open **Clients** and add a client with their hourly rate and **Net payment days** (default 30; 0 means due on receipt). Invoice due dates are calculated by adding these calendar days to the issue date, for both direct billing and timesheet invoices. You can override the due date before issuing an invoice. Changing client terms does not change existing invoices. In the same client editor, **Starting invoice #** optionally starts a client sequence (for example, 500 gives `INV-00500`). Blank uses business numbering. Both billing workflows advance the client sequence and skip numbers already used, including deleted invoices. Once the client sequence has been used, its starting number is fixed; existing invoices keep their numbers.
3. In **Client Tasks**, select a client and add work types such as Design,
   Development or Support, each with its own hourly rate.
4. Optionally open **Timesheets**, choose the client and task (or **Client default**), and enter
   optional notes. Start/stop the timer, or choose **Day**, **Week** or **Month**,
   enter a date within that period, choose an entry method and click **Add Time…**.
   **One total for period** creates one entry for the entire range.
   To fill in missed work, click **Add Missing Entry…** next to the task selector,
   choose the work date, enter decimal hours and a description, and save. This adds
   a single daily entry for the selected client and task, regardless of the period
   or entry method. You can also change billability in this dialog.
   Check **Nonbillable time (lunch, breaks, etc.)** before **Add Time…** to record
   manual hours that count toward total time but never appear on invoices. This also
   applies to every row saved in **Daily timesheet**; timers remain billable.
   Select an entry and click **Edit Entry…** (or double-click it) to change its date,
   day/week/month period, description, hours, hourly rate, or billability. Its client
   and task stay attached. Already invoiced entries are locked. Editing imported
   time also explicitly reviews its rate and billability.
   **Daily timesheet** opens a row for every date; enter decimal hours
   (`1.5` means 1 hour 30 minutes) and leave unused days blank or zero.
   A description is required when using the client default rate.
5. Open **Invoices**, choose the client and an active **Task**, and enter **Hours**,
   tax percentage, **Issued** date and due date, then **Create Invoice**. The issued
   date defaults to today; changing it recalculates the due date using the client’s
   net payment days. You can still override the due date. Billing uses the displayed
   task rate and does not consume or create timesheet entries. Alternatively,
   in **Timesheets**, review the selected client's total and available hours and
   use **Create Invoice…** to convert all their unbilled time at its recorded rates.
   A running timer is excluded until stopped. Converted entries cannot be billed again.
6. Preview/print the invoice, or click **Email Invoice…** to open an Apple Mail
   draft addressed to the client's current email. The payment message appears
   above the invoice text and the complete PDF is attached. Review and send the
   draft in Mail. The **Business** email should match an enabled Mail account.
   Use **Mark Paid / Unpaid** when payment is received.

Rates and amounts use `.` as the decimal separator. Dates use `YYYY-MM-DD`.
Tax is a user-entered percentage, not a jurisdiction-specific tax calculation.
Direct invoice hours accept up to four decimal places and are billed exactly as
entered (up to 8760 hours per invoice). Timesheet hours accept up to four decimal places and are truncated to whole
seconds. Charges use exact decimal math and round half-up to cents per line;
tax rounds once on the subtotal. Displayed hours are rounded to four places.
Currency cannot change after any time is recorded; separate currencies require
separate ledger files. Make a backup before replacing any ledger file.

## Storage and recovery

Every successful change is saved atomically as an XML property list. Failed
writes report an error and restore the in-memory ledger to its previous state.
Invalid/unsupported ledger files are refused rather than overwritten. The app
uses a directory lock to guard against opening the ledger in two instances.
After a crash, use **Recover lock** only after closing all other copies.

The file lives in the platform's user Application Support directory under
`ClockAndLedger/Ledger.plist`:

- macOS: `~/Library/Application Support/ClockAndLedger/Ledger.plist`
- GNUstep: typically `~/GNUstep/Library/ApplicationSupport/ClockAndLedger/Ledger.plist`
  (depends on the configured GNUstep filesystem layout).

Backups include all clients, time, invoices, settings and any running timer.
To restore: quit every copy of the app, copy the backup to the ledger path,
then reopen the app. A restored running timer continues from its saved start
time. Data is stored locally in plaintext; backup copies use the same format.

## Tests

macOS model tests:

```sh
make -f Makefile test test-import test-time test-reminders test-edit
```

Native macOS print-pipeline test (writes an 80-entry, multi-page sample PDF
under `build/`, without sending anything to a printer):

```sh
make -f Makefile test-print test-ui
```

GNUstep model tests, after sourcing `GNUstep.sh`:

```sh
gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
  Tests/LedgerTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -o /tmp/LedgerTests \
  $(gnustep-config --base-libs)
/tmp/LedgerTests
```

Or build and test GNUstep inside an isolated Debian container:

```sh
docker build -f Tests/Dockerfile -t clockandledger-test .
```

Tests cover decimal validation/rounding, invalid dates/durations, rate and
invoice snapshots, duplicate billing, locked billed time, payment status,
recovered timers, sequential numbering, write rollback and corrupt files.
Task/calendar tests also cover leap years, Monday–Sunday week boundaries,
daylight-saving changes, task ownership, historical rate snapshots, archived
tasks, restart recovery, legacy ledgers and atomic timesheet writes.
Model tests use temporary directories and never touch the application's ledger.

## Source and documentation

- `Sources/CLQuickBooksImporter.*`: IIF/CSV parsing and source validation.
- `Sources/CLLedger.*`: validation, persistence, timing and invoice accounting.
- `Sources/CLAppController.*`: native menus, tabs, tables and editors.
- `Sources/CLInvoiceView.*`: shared preview and paginated print renderer.
- `Sources/main.m`: application bootstrap and manual memory management.
- `Tests/`: model checks, macOS PDF-print test and GNUstep build environment.

With `autogsdoc` installed, generate HTML API documentation:

```sh
make -f Makefile docs
```

Documentation goes to `Documentation/API/`. Public interfaces contain `/** … */`
comments consumed by [autogsdoc](https://www.gnustep.org/resources/documentation/Developer/BaseTools/autogsdoc.html).
Printing uses GNUstep's public
[NSPrintOperation API](https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSPrintOperation.html).

## Application icon

Both builds include the clock-and-ledger icon. GNUstep packages a transparent
PNG and generates the `NSIcon` and desktop launcher entries; macOS packages a
multi-resolution ICNS. Artwork, the generation prompt, and regeneration
instructions are in [Resources/Artwork/README.md](Resources/Artwork/README.md).

## Time periods and task rates

Weeks run Monday–Sunday; months use their actual calendar dates, including
February 29 in leap years. The date field takes any `YYYY-MM-DD` within the
chosen week or month, and the resolved range appears below it.

A timesheet uses one client and one task/rate for all its entered days. Repeat
for other tasks as needed. Blank and zero-hour days are omitted. Every populated
row is validated before saving, so one invalid row saves nothing and leaves the
form available for correction. Each save **adds** time; it does not replace an
earlier timesheet. Period totals and daily entries are alternative ways to
record work: avoid entering the same work through both methods.

Time entries preserve their task name, rate and date/range at recording time;
timers capture these when started. Renaming a task or changing its rate affects
future work only. Archive tasks to remove them from new-entry choices; restore
them in **Client Tasks** when needed. Archived tasks remain visible on past time
and invoices, and an already-running timer can still be stopped.

Invoices include each entry's task and date range and charge a weekly/monthly
total exactly once. Existing ledgers and imported time without task assignments
continue using their stored rates. New timers persist an absolute numeric start
time as well as a date to avoid timezone-dependent date decoding in GNUstep.

### Business branding and invoice numbers

In **Business**, choose a PNG, JPEG, TIFF or icon image (up to 5 MB), then save your business details. The logo appears on invoice previews and printed/PDF pages, with its proportions preserved. Logo bytes are stored in the ledger and each issued invoice, so moving the original image or replacing/removing your logo does not change older invoices. Email drafts include the branded, multipage invoice PDF as an attachment.

Set **Starting invoice number** before issuing or importing your first invoice. Leaving it blank starts at 1 (`INV-00001`); entering 500 starts at `INV-00500`, followed by `INV-00501`. The starting number is fixed once invoices exist. Existing ledgers keep their numbering, and imported invoices keep displaying their original QuickBooks numbers.

To delete an invoice, select it in **Invoices** and click **Delete Invoice…**. The confirmation defaults to Cancel and warns that deletion cannot be undone. Confirming removes the invoice and its payment status from the ledger totals and returns linked time entries to unbilled status. Standalone invoices do not create time entries when deleted. Deleted invoice numbers remain reserved, even if every invoice is deleted. Printed/emailed copies and QuickBooks records are unaffected; deleting a paid invoice does not refund payment.


## Client payment reminders and background email (macOS)

In **Clients**, select a client and choose **Email Reminders…**. Configure
**Days before due** (default 3; 0 means the due date), the friendly **Payment
reminder**, and the separate **Overdue reminder**. Blank messages use built-in
wording; overdue wording asks for prompt payment and a payment date. Templates
support `{client}`, `{invoice}`, `{total}`, and `{dueDate}`. These current client
settings also control the message above the invoice in manually opened drafts.
Paid invoices use a thank-you message instead of a payment demand.

Turn on **Send reminders through Apple Mail** to enable scheduled reminders for
that client. Before each send, the app plays the system alert sound and asks for
approval, showing the recipient and message. Choose **Send Reminder** to send or
**Remind Me in 1 Hour** to postpone without sending. Postponements last for the
current app session; restarting may ask again. This is off by default. Set valid client and business email
addresses first, and configure the business address in an enabled Apple Mail
account. On first use, allow the app to control Mail in macOS Automation
permissions. No email passwords are stored in the ledger.

The invoice list shows **Days until payment**: days remaining, **0** on the due
date, and **+n** for n days overdue. Paid, zero-balance, and unverified invoices
show an em dash. The count refreshes every minute.

While running, the app checks once per minute and, with approval, submits at most one friendly
reminder per invoice within the configured window, then one separate overdue
reminder after its due date. If the app first sees an invoice when it is already
late, only the overdue reminder is sent. Both include the complete invoice PDF.
Paid, zero-total, and unverified imported invoices are excluded. New settings
apply to existing eligible unpaid invoices as well as future invoices.

Closing the main window leaves the app running in the background. On macOS,
click the **◷ menu bar icon** and choose **Start Timer → client → task** to begin
tracking without opening the main window. **Client default** prompts for a work
description and uses the client's rate. The menu bar displays elapsed time while
running; its menu identifies the active client and work. **Stop Timer & Save Time**
records the elapsed time in Timesheets. Only one timer can run at a time, shared
with the main window, and archived tasks are excluded from the menu.

On macOS, the app starts with its main window hidden. Choose
**Open Clock & Ledger** from the menu, or click its Dock icon, to open
the window. Choose **Hide Dock Icon** in the menu bar menu to keep the app out
of the Dock and Command-Tab switcher; **Show Dock Icon** restores it. This setting
is remembered across launches. You can still open the window and control timers
from the menu bar while the Dock icon is hidden.

A running timer persists across app restarts and includes elapsed
sleep/closed-app time until explicitly stopped. Run `make -f Makefile test-status`
for the menu bar regression checks.

**Quit** stops checks, and nothing is sent while the Mac
is asleep or the app is not running; the next check catches up when it resumes.
The app does not install a login item. Apple Mail may queue messages while
offline: “submitted” means Mail accepted the message, not that the recipient
has received it. Check Mail for delivery failures or bounce notices.

Attempts are saved before handing mail to Apple Mail to avoid repeated sends
after a crash. Errors and interrupted attempts show **Review email** in the
invoice table. Select the invoice and click **Review Email…**, inspect Mail's
Drafts, Outbox and Sent, then either confirm submission or explicitly allow a
retry. Remove any stale draft before retrying. Turning off automatic reminders
stops future checks for that client; it cannot recall messages already handed
to Mail. Temporary PDF and message files are retained under
`~/Library/Caches/ClockAndLedger/MailExports` so queued messages and drafts can
still access their attachments.

Direct invoices now require an active task from **Client Tasks**. Select it in
**Invoices** and enter hours: the displayed task rate is snapshotted with the
task name when the invoice is issued. Later task edits do not alter the invoice.
Timesheet invoices continue to use each time entry's recorded task and rate.
Apple Mail delivery is macOS-only; the ledger, task billing and reminder policy
tests also build under GNUstep.

The **Issued** date is saved on the invoice and shown in the invoice list, PDF,
and email text. Past and future dates are supported; the due date must be on or
after the issued date. Timesheet invoice creation also has an Issued field;
changing it calculates the due date from that client's terms while preserving
the time entries' original work dates. Reminder timing follows the saved dates.

Paid invoices display a large, translucent red diagonal **PAID** stamp on every
page in previews, printed output and PDF email attachments. Marking an invoice
unpaid removes the stamp from newly generated output. Unverified imported
payment states are not stamped.

Every editable date has a calendar button alongside the text box: the timesheet
period date and the Issued and Due date fields in both invoice creation flows.
Type `YYYY-MM-DD` directly or choose a day in the calendar. **Today** selects the
current day, **Choose** applies it, and **Cancel** keeps the existing text.
Calendar selections update due dates and timesheet period summaries just like
manual entry. Dates shown on fixed daily timesheet rows remain tied to the
selected period.


## Editing an invoice

Select an invoice in **Invoices** and click **Edit Invoice…**. The Invoice tab
edits the displayed number, issue and due dates, tax percentage or tax amount,
and payment status. Client and Business tabs edit the invoice's name, email,
address, payment terms, currency, instructions and logo without changing the
saved profiles. Date fields support typing and calendars. Changing the issue
date or net days recalculates the due date; an explicit due date remains editable.

In Line Items, add, edit or remove services, including their dates/date range,
task name, description, hours and rate. Leave Amount override blank to calculate
hours × rate, or enter a fixed amount. Subtotal and total are recalculated from
lines and tax. Clear Tax amount override to calculate tax from its percentage.
Changing currency changes the label, not the amounts; totals are grouped by
currency in the main summary.

**Cancel** discards the draft. **Save Invoice** persists the edits atomically.
Invoice numbers must remain unique, and previous numbers stay reserved. The
internal invoice ID stays stable. Retained timesheet lines stay billed at their
original recorded time/rate; removing one releases that time for billing again.
Edited client contact details are used for future invoice emails and reminder
messages. Sent reminder history is retained to avoid duplicate automatic emails.
A pending email must finish or be reviewed before the invoice can be edited.
Previously sent emails and PDFs are unchanged; generate a new copy after editing.

### Company finances

Use **Company Finances → Bank accounts → Add** to record the bank, account number,
routing/IBAN details, currency, and opening balance. The opening balance is the
balance **before the transactions you record here**; entering today's balance and
also recording its historical transactions would count them twice. Each account's
current ledger balance is opening balance + assigned invoice payments − expenses.
Accounts keep their own currency. This is local bookkeeping, not a bank connection.

Select an invoice and choose **Record Payment** to enter the actual amount received,
date, destination account, and reference. Multiple payments are supported. Partial
payments leave the remaining amount due; overpayments show a credit. PDFs and reminder
messages reflect the remaining balance. Review or correct payments in **Company
Finances → Invoice payments**. Existing paid invoices appear as legacy, unassigned
payments: edit one to record its actual amount, date, and bank account. That replaces
the assumed full payment rather than adding a duplicate. Unassigned payments count
toward invoice settlement but do not change a bank balance. Invoices with recorded
payments cannot be deleted until those payments are removed, and their status is
calculated from payments when editing invoice totals.

Use **Expenses & receipts** to record company payments with date, vendor, category,
amount, bank account, reference, and business purpose/notes. **Attach Receipt** embeds
one PDF or image (up to 20 MB) per expense; a replacement attachment replaces the old
one. **Export / Open Receipt** saves a copy. **Export CSV** exports all expense records
for filtering by year/category in a spreadsheet or sharing with your accountant.
Dates support both manual entry and the calendar picker.

Bank details and receipts are stored locally in the ledger and included in ledger
backups. Account numbers are masked in the list; the ledger and backup files are
not encrypted by the app. Do not store online banking passwords in these fields.

Run `make -f Makefile test-finance` for bookkeeping regression tests.


## Search, filters and sorting

Every Clients, Client Tasks, Timesheets, Invoices and Company Finances list has
its own search field. Search matches displayed columns and notes, ignoring case
and accents. Clear the search with its × button. Click a column heading to sort;
click again to reverse the order. Monetary values and hours sort numerically,
and dates sort chronologically. Selection follows the same record when sorting
or refreshing; if a filter hides it, selection is cleared.

- **Client Tasks:** show all, active or archived tasks for the selected client.
- **Timesheets:** filter by client, unbilled, billed, nonbillable or imported time
  needing review.
- **Invoices:** filter by client, outstanding, overdue, paid (including overpaid),
  partial, overpaid, or records needing payment/due-date review. An overdue partial
  invoice appears in both relevant filters.
- **Company Finances:** search each account/expense/payment view; expenses can
  be filtered by whether a receipt is attached.
- Time, invoices, expenses and payments support **All dates**, **This month**,
  **Last month** and **This year**. Dates refer to entry start, invoice issue,
  expense or payment date. Undated legacy payments appear only under All dates.

List filters affect browsing only. The timesheet entry controls still choose
where new time is recorded, and **Create Invoice** still bills all of that
client's eligible unbilled time. List filters do not select invoice line items.

## Dashboard and reports

**Dashboard** opens with this month's money received, expenses, net cash
movement and current outstanding balance, plus billable/nonbillable hours,
billed totals, overdue balances, unbilled work and monthly cash activity.
Choose a period and currency. Currencies are never combined or converted.

**Reports** offers five sortable reports and **Export Report CSV**:

- **Monthly cash flow:** actual recorded receipts, expenses and their difference.
- **Client billing & receipts:** billed totals including tax by issue date,
  receipts by payment date, and current outstanding balance per client.
- **Expense categories:** transaction counts and totals by category.
- **Time by client:** billable/nonbillable hours and billable value at recorded rates.
- **Current receivables:** open invoice balances, due dates and overdue status.
  This is a current view across all dates, so date controls are disabled.

For period reports, enter inclusive From/To dates and click **Apply**. Export
also applies pending dates and uses the displayed sort order. CSV files include
currency, date range and calculation notes; spreadsheet formula-like text is
escaped. Reporting never changes ledger records.

Receipts are grouped by the actual payment date, not the invoice issue date.
Undated legacy paid invoices and unverified payment states are excluded from
cash totals and counted in the explanatory note. Unverified payment states are
also excluded from receivables. Outstanding and overdue use current recorded
balances, independent of the report period; overpayment credits do not reduce
other invoices' balances. Unknown due dates are identified for review.

Net cash movement is receipts minus recorded expenses, not accounting profit.
Opening bank balances are not income. Time is reported in the ledger currency,
excludes active timers, and assigns a weekly/monthly total wholly to its start
date rather than guessing how it was distributed across days.

Regression checks: `make -f Makefile test-reports test-browsing`.


## Monthly and recurring invoicing

In **Clients**, select a client and open **Recurring Billing…**. Set Enabled to
Yes, enter the **Next month YYYY-MM** to bill (for example `2026-09`), an
**Issue day** from 1 to 28, a tax percentage, and any **Holiday dates** to exclude.
With September and issue day 5, the app issues September's invoice on October 5.
The next billing month advances after each successful run and is shown when you
reopen the settings. Set Enabled to No to pause it.

Holiday dates are an explicit list of `YYYY-MM-DD` values separated by commas,
spaces or newlines. Maintain the list for your business, including observed
holidays and future years. No national holiday calendar is assumed. Weekends
remain eligible when billable time was recorded. An empty list excludes no dates.

Checks run once per minute while the app is running, including with its window
closed. After reopening or waking, it catches up completed months using their
scheduled issue dates and the client's payment terms. The app does not run while
quit or asleep. Each month produces at most one scheduled invoice; empty months
advance without creating an invoice. Invoice creation and schedule advancement
save together, so failed saves and restarts do not cause duplicate billing.
Deleting a scheduled invoice does not reset the schedule. Late entries for an
already processed month can be billed with **Invoice Month…**.

In **Invoices**, select a client and choose **Invoice Month…** for one-off billing.
Enter the month, holiday dates, tax and issue date. Holidays default to that
client's saved recurring list. This bills only eligible unbilled time in that
month at its recorded rates, across all tasks. It excludes nonbillable time,
holiday dates, already billed time and unverified imported time. Due dates use
the client's net payment terms. List search and filters do not alter this selection.

Daily time is selected by its recorded date. Weekly/monthly totals are accepted
only when wholly inside the month and containing no excluded holiday. If a total
crosses a month boundary or holiday, billing stops for that client: replace the
aggregate with accurate daily entries, then retry. Hours are never prorated or
guessed. A running timer starting on or before the month's end also blocks billing
until stopped and reviewed. Errors appear in the Invoices status message; other
clients' schedules continue. Corrected schedules retry on the next check.

Scheduled billing creates invoices without sending email. Existing manual email
and approved payment-reminder behavior remains available.

Regression checks: `make -f Makefile test-recurring`.

## Owned apps and App Store revenue

**Apps & Revenue** tracks owned apps, manual or imported revenue, bank payouts,
payout allocations and noninvoiceable development hours. Assign expenses to an
app in Company Finances, then use **Reports → App performance** or **Apps by
month** to compare proceeds, expenses, earnings and hours. Actual bank payouts
also appear in dashboard cash flow; proceeds are not counted again as cash.

The importer supports standard Apple financial CSV/TSV reports and a normalized
CSV template, with review, duplicate detection and atomic saves. Apps' SKU and
subscription/product IDs map reports to the right app. Optional gross sales,
refunds and fees can be recorded without inventing missing breakdowns.

[Workflow, payout reconciliation, import formats and limitations](Documentation/App-revenue.md).
[Example revenue CSV](Documentation/App-revenue-template.csv).

Regression checks: `make -f Makefile test-app-revenue test-app-revenue-ui`.
