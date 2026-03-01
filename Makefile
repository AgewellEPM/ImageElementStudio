.PHONY: all build test lint clean

all: build test

build:
	swift build

test:
	swift test

lint:
	@if command -v swiftlint > /dev/null 2>&1; then \
		swiftlint lint; \
	else \
		echo "SwiftLint is not installed. Install with: brew install swiftlint"; \
	fi

clean:
	swift package clean
