.PHONY: build run test clean generate

generate:
	xcodegen generate

build: generate
	xcodebuild -project Flow.xcodeproj -scheme Flow -configuration Release -derivedDataPath build build -quiet

run: build
	open build/Build/Products/Release/Flow.app

test:
	cd Packages/AFCore && swift test --quiet
	cd Packages/AFCanvas && swift test --quiet
	cd Packages/AFAgent && swift test --quiet
	@echo "All tests passed."

clean:
	rm -rf build
	xcodebuild -project Flow.xcodeproj -scheme Flow clean -quiet 2>/dev/null || true
	@echo "Clean."
