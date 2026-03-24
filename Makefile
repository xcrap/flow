.PHONY: build run test clean generate

generate:
	xcodegen generate

build: generate
	xcodebuild archive -project Flow.xcodeproj -scheme Flow -configuration Release -archivePath build/Flow.xcarchive -quiet
	mkdir -p dist
	rm -rf dist/Flow.app
	cp -R build/Flow.xcarchive/Products/Applications/Flow.app dist/Flow.app

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
