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
	# Motores locales embarcados: la app instalada no depende de builds de dev
	mkdir -p $(BUNDLE)/Contents/Resources/bin
	@if [ -x native/beto-stream ]; then cp native/beto-stream $(BUNDLE)/Contents/Resources/bin/; fi
	@if [ -x $(HOME)/transcribe.cpp/build/bin/transcribe-cli ]; then \
		cp $(HOME)/transcribe.cpp/build/bin/transcribe-cli $(BUNDLE)/Contents/Resources/bin/; fi
	@if [ -x $(HOME)/llama.cpp-static/build/bin/llama-server ]; then \
		cp $(HOME)/llama.cpp-static/build/bin/llama-server $(BUNDLE)/Contents/Resources/bin/; fi
	@if [ -x $(HOME)/whisper.cpp/build/bin/whisper-cli ]; then \
		cp $(HOME)/whisper.cpp/build/bin/whisper-cli $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/whisper-server $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libwhisper.1.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-cpu.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-blas.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-metal.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-base.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		install_name_tool -delete_rpath $(HOME)/whisper.cpp/build/bin $(BUNDLE)/Contents/Resources/bin/whisper-cli 2>/dev/null || true; \
		install_name_tool -delete_rpath $(HOME)/whisper.cpp/build/bin $(BUNDLE)/Contents/Resources/bin/whisper-server 2>/dev/null || true; \
		install_name_tool -add_rpath @executable_path $(BUNDLE)/Contents/Resources/bin/whisper-cli 2>/dev/null || true; \
		install_name_tool -add_rpath @executable_path $(BUNDLE)/Contents/Resources/bin/whisper-server 2>/dev/null || true; fi
	@IDENTITY=$$(security find-certificate -c "BetoDicta Self Signed" >/dev/null 2>&1 && echo "BetoDicta Self Signed" || echo "-"); \
	echo "Firmando con: $$IDENTITY"; \
	codesign --force --deep --sign "$$IDENTITY" $(BUNDLE)
	@echo "Listo: $(BUNDLE)"

# Instalador DMG (requiere: brew install create-dmg)
dmg: bundle
	rm -f build/BetoDicta-*.dmg
	@V=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist); \
	create-dmg \
		--volname "BetoDicta $$V" \
		--window-size 560 400 \
		--icon-size 110 \
		--icon "BetoDicta.app" 140 160 \
		--app-drop-link 420 160 \
		--add-file "LÉEME primero.txt" packaging/LEEME-primero.txt 280 300 \
		"build/BetoDicta-$$V.dmg" "$(BUNDLE)" && \
	echo "DMG listo: build/BetoDicta-$$V.dmg"

install: bundle
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app
	@echo "Instalado en /Applications/$(APP).app"

clean:
	rm -rf build

# Publica release en GitHub con DMG versionado + estable (para el tap Homebrew:
# releases/latest/download/BetoDicta.dmg). Uso: make release
release: dmg
	@V=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist); \
	cp "build/BetoDicta-$$V.dmg" "build/BetoDicta.dmg"; \
	gh release create "v$$V" --title "BetoDicta $$V" \
		"build/BetoDicta-$$V.dmg" "build/BetoDicta.dmg" && \
	echo "Release v$$V publicado (con DMG estable para brew)"
