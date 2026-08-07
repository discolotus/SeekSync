.PHONY: run test build icon app release test-packaged-app

SWIFT_CACHE = CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/module-cache SWIFTPM_MODULECACHE_OVERRIDE=$(CURDIR)/.build/module-cache

run:
	mkdir -p .build/module-cache
	$(SWIFT_CACHE) swift run --disable-sandbox SeekSyncPrototype

test:
	mkdir -p .build/module-cache
	$(SWIFT_CACHE) swift test --disable-sandbox

build:
	mkdir -p .build/module-cache
	$(SWIFT_CACHE) swift build --disable-sandbox

icon:
	./scripts/generate_app_icon.sh

app:
	./scripts/package_app.sh

release:
	./scripts/package_release.sh

test-packaged-app:
	./scripts/smoke_test_packaged_app.sh
