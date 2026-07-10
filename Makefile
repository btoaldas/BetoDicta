APP = BetoDicta
BUNDLE = build/$(APP).app

all: bundle

build/release/$(APP): Sources/BetoDicta/main.swift Package.swift
	swift build -c release --build-path build

bundle: build/release/$(APP)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp build/release/$(APP) $(BUNDLE)/Contents/MacOS/
	cp Info.plist $(BUNDLE)/Contents/
	codesign --force --deep --sign - $(BUNDLE)
	@echo "Listo: $(BUNDLE)"

install: bundle
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app
	@echo "Instalado en /Applications/$(APP).app"

clean:
	rm -rf build
