.PHONY: dev build install run test clean generate

generate:
	xcodegen generate

# Debug build for development (bundle: com.flow.app.dev, data: ~/Library/Application Support/Flow-Dev/)
dev: generate
	xcodebuild -project Flow.xcodeproj -scheme Flow -configuration Debug -derivedDataPath build/dev -quiet
	mkdir -p dist
	rm -rf dist/Flow-Dev.app
	cp -R build/dev/Build/Products/Debug/Flow.app dist/Flow-Dev.app
	open dist/Flow-Dev.app

# Release build
build: generate
	xcodebuild archive -project Flow.xcodeproj -scheme Flow -configuration Release -archivePath build/Flow.xcarchive -quiet
	mkdir -p dist
	rm -rf dist/Flow.app
	cp -R build/Flow.xcarchive/Products/Applications/Flow.app dist/Flow.app

# Install release build to /Applications
install: build
	rm -rf /Applications/Flow.app
	cp -R dist/Flow.app /Applications/Flow.app
	@echo "Installed to /Applications/Flow.app"

# Build release and open
run: build
	open dist/Flow.app

test:
	cd Packages/AFCore && swift test --quiet
	cd Packages/AFCanvas && swift test --quiet
	cd Packages/AFAgent && swift test --quiet
	@echo "All tests passed."

clean:
	rm -rf build dist
	xcodebuild -project Flow.xcodeproj -scheme Flow clean -quiet 2>/dev/null || true
	@echo "Clean."
