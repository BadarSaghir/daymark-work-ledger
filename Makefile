FLUTTER ?= flutter
DART ?= dart

.PHONY: get format format-check analyze test check build-linux build-windows \
	build-apk build-aab build-ios build-macos clean

get:
	$(FLUTTER) pub get

format:
	$(DART) format lib test

format-check:
	$(DART) format --output=none --set-exit-if-changed lib test

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

check: format-check analyze test

build-linux:
	$(FLUTTER) build linux --release

build-windows:
	$(FLUTTER) build windows --release

build-apk:
	$(FLUTTER) build apk --release

build-aab:
	$(FLUTTER) build appbundle --release

build-ios:
	$(FLUTTER) build ios --release --no-codesign

build-macos:
	$(FLUTTER) build macos --release

clean:
	$(FLUTTER) clean
