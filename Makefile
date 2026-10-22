.PHONY: build run test app install clean

build:
	swift build

run: app
	open build/Jot.app

test:
	swift test

app:
	./scripts/bundle.sh release

install: app
	rm -rf /Applications/Jot.app && cp -R build/Jot.app /Applications/

clean:
	rm -rf .build build
