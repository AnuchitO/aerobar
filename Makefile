# Makefile for AeroBar -- thin wrappers around Scripts/*.sh and swift(1).
#
# Usage:
#   make build      swift build (release)
#   make app        assemble AeroBar.app
#   make install    build the app and copy it to /Applications
#   make run        install (if needed) and launch AeroBar.app
#   make dev        swift run, for a quick local dev loop (no .app bundle)
#   make uninstall  remove /Applications/AeroBar.app
#   make clean      remove .build

APP_NAME  := AeroBar
DEST      := /Applications/$(APP_NAME).app

.PHONY: all build app install run dev uninstall clean help

all: install

build:
	swift build -c release

# Scripts/build-app.sh runs its own `swift build`, so `app` doesn't also
# depend on the `build` target -- that would just build twice.
app:
	Scripts/build-app.sh release

# Scripts/install.sh runs Scripts/build-app.sh itself, so `install`
# doesn't depend on `app` either -- same reasoning as above.
install:
	Scripts/install.sh

run: install
	open "$(DEST)"

dev:
	swift run

uninstall:
	rm -rf "$(DEST)"
	@echo "Removed $(DEST)"

clean:
	rm -rf .build

help:
	@echo "make build      - swift build (release)"
	@echo "make app        - assemble $(APP_NAME).app"
	@echo "make install    - build the app and copy it to /Applications"
	@echo "make run        - install (if needed) and launch $(APP_NAME).app"
	@echo "make dev        - swift run, for a quick local dev loop"
	@echo "make uninstall  - remove $(DEST)"
	@echo "make clean      - remove .build"
