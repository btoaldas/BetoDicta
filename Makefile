APP = BetoDicta
BUNDLE = build/$(APP).app

all: bundle

SOURCES := $(wildcard Sources/BetoDicta/*.swift)

build/release/$(APP): $(SOURCES) Package.swift
	swift build -c release --build-path build

bundle: build/release/$(APP)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp build/release/$(APP) $(BUNDLE)/Contents/MacOS/
	cp Info.plist $(BUNDLE)/Contents/
	mkdir -p $(BUNDLE)/Contents/Resources
	cp -R Resources/ $(BUNDLE)/Contents/Resources/
	codesign --force --deep --sign "BetoDicta Self Signed" $(BUNDLE)
	@echo "Listo: $(BUNDLE)"

install: bundle
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app
	@echo "Instalado en /Applications/$(APP).app"

clean:
	rm -rf build
