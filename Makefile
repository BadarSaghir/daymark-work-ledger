FLUTTER ?= flutter
DART ?= dart

.PHONY: get format format-check analyze test check build-linux build-apk build-ios clean

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

build-apk:
	$(FLUTTER) build apk --release

build-ios:
	$(FLUTTER) build ios --release --no-codesign

clean:
	$(FLUTTER) clean
