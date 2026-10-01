# macOS convenience build; GNUstep uses GNUmakefile (make -f GNUmakefile).
CC = clang
CFLAGS = -std=gnu89 -fno-objc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -ISources
SOURCES = Sources/main.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m Sources/CLReporting.m Sources/CLAppController.m Sources/CLInvoiceView.m Sources/CLInvoiceMailer.m Sources/CLDateField.m Sources/CLInvoiceEditor.m
APP = build/ClockAndLedger.app

.PHONY: all macos run test docs clean
all: macos
macos: $(APP)/Contents/MacOS/ClockAndLedger
$(APP)/Contents/MacOS/ClockAndLedger: $(SOURCES) $(wildcard Sources/*.h) $(wildcard Sources/*.inc) Resources/Info.plist Resources/ClockAndLedger.icns Resources/InvoiceMail.applescript
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	$(CC) $(CFLAGS) $(SOURCES) -framework Cocoa -o $@
	cp Resources/InvoiceMail.applescript $(APP)/Contents/Resources/InvoiceMail.applescript
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/ClockAndLedger.icns $(APP)/Contents/Resources/ClockAndLedger.icns
run: macos
	open $(APP)
test:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/LedgerTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/LedgerTests
	./build/LedgerTests
docs:
	mkdir -p Documentation/API
	autogsdoc -Project ClockAndLedger -DocumentationDirectory Documentation/API Sources/*.h Sources/*.m
clean:
	rm -rf build

.PHONY: test-print
test-print:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/InvoiceTests.m Sources/CLInvoiceView.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Cocoa -framework PDFKit -o build/InvoiceTests
	./build/InvoiceTests

.PHONY: test-import
test-import:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/ImportTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/ImportTests
	./build/ImportTests

.PHONY: icons
icons:
	./Scripts/build-icons.sh

.PHONY: test-time
test-time:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/TimeEntryTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/TimeEntryTests
	./build/TimeEntryTests

.PHONY: test-reminders
test-reminders:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/ReminderTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/ReminderTests
	./build/ReminderTests

.PHONY: test-ui
test-ui:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/InvoiceUITests.m Sources/CLInvoiceEditor.m Sources/CLDateField.m Sources/CLReporting.m Sources/CLAppController.m Sources/CLInvoiceMailer.m Sources/CLInvoiceView.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Cocoa -o build/InvoiceUITests
	./build/InvoiceUITests

.PHONY: test-edit
test-edit:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/InvoiceEditTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/InvoiceEditTests
	./build/InvoiceEditTests

.PHONY: test-finance
test-finance:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/FinanceTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/FinanceTests
	./build/FinanceTests

.PHONY: test-status
test-status:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/StatusBarTests.m $(filter-out Sources/main.m,$(SOURCES)) -framework Cocoa -o build/StatusBarTests
	./build/StatusBarTests

.PHONY: test-reminder-ui
test-reminder-ui:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/ReminderUITests.m $(filter-out Sources/main.m,$(SOURCES)) -framework Cocoa -o build/ReminderUITests
	./build/ReminderUITests

.PHONY: test-reports test-browsing
test-reports:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/ReportingTests.m Sources/CLReporting.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/ReportingTests
	./build/ReportingTests
test-browsing:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/BrowsingTests.m $(filter-out Sources/main.m,$(SOURCES)) -framework Cocoa -o build/BrowsingTests
	./build/BrowsingTests

.PHONY: test-recurring
test-recurring:
	mkdir -p build
	$(CC) $(CFLAGS) Tests/RecurringTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -framework Foundation -o build/RecurringTests
	./build/RecurringTests
