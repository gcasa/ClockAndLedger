# macOS convenience build; GNUstep uses GNUmakefile (make -f GNUmakefile).
CC = clang
CFLAGS = -std=gnu89 -fno-objc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -ISources
SOURCES = Sources/main.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m Sources/CLAppController.m Sources/CLInvoiceView.m
APP = build/ClockAndLedger.app

.PHONY: all macos run test docs clean
all: macos
macos: $(APP)/Contents/MacOS/ClockAndLedger
$(APP)/Contents/MacOS/ClockAndLedger: $(SOURCES) $(wildcard Sources/*.h) Resources/Info.plist Resources/ClockAndLedger.icns
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	$(CC) $(CFLAGS) $(SOURCES) -framework Cocoa -o $@
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
