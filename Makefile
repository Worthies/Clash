# Clash Desktop - Makefile
# This Makefile provides targets for installing prerequisites and building Clash for multiple platforms

# Default configuration
project_name := Clash
platform := all
mode := debug
output_dir := build/dist
archive_dir := $(output_dir)/archives
mirror := default
proxy :=
clean := false
verbose := false
skip_tests := false
skip_pub_get := false
generate_icons := false
open := false
archive_name :=
version :=

# Mirror URLs
flutter_mirror_default := https://storage.googleapis.com/flutter_infra_release/releases
flutter_mirror_china := https://storage.flutter-io.cn/flutter_infra_release/releases
pub_hosted_default := https://pub.dev
pub_hosted_china := https://pub.flutter-io.cn

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
CYAN := \033[0;36m
NC := \033[0m # No Color

# Logging functions
define log_info
	echo "$(BLUE)[INFO]$(NC) $(1)"
endef

define log_success
	echo "$(GREEN)[SUCCESS]$(NC) $(1)"
endef

define log_warning
	echo "$(YELLOW)[WARNING]$(NC) $(1)"
endef

define log_error
	echo "$(RED)[ERROR]$(NC) $(1)"
endef

# Detect OS
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    OS := macos
else ifeq ($(UNAME_S),Linux)
    OS := linux
else ifeq ($(findstring MINGW32_NT,$(UNAME_S)),MINGW32_NT)
    OS := windows
else ifeq ($(findstring MSYS_NT,$(UNAME_S)),MSYS_NT)
    OS := windows
else ifeq ($(findstring CYGWIN_NT,$(UNAME_S)),CYGWIN_NT)
    OS := windows
else
    OS := unknown
endif
# Flutter settings
FLUTTER_VERSION := 3.35.4
FLUTTER_CHANNEL := stable


# Set Flutter environment variables based on mirror
ifeq ($(mirror),china)
    export FLUTTER_STORAGE_BASE_URL := $(flutter_mirror_china)
    export PUB_HOSTED_URL := $(pub_hosted_china)
    mirror_flag :=
else
    mirror_flag :=
endif

# Set proxy environment variables
ifdef proxy
    export HTTP_PROXY := $(proxy)
    export HTTPS_PROXY := $(proxy)
    export http_proxy := $(proxy)
    export https_proxy := $(proxy)
    proxy_flag :=
endif

# Prerequisites installation
# OS-specific prerequisite installation
ifeq ($(OS),linux)
.PHONY: install-prerequisites
install-prerequisites: install-linux-deps install-flutter install-android-sdk setup-project
else ifeq ($(OS),macos)
.PHONY: install-prerequisites
install-prerequisites: install-macos-deps install-flutter install-android-sdk setup-project
else ifeq ($(OS),windows)
.PHONY: install-prerequisites
install-prerequisites: install-windows-deps install-flutter install-android-sdk setup-project
else
.PHONY: install-prerequisites
install-prerequisites:
	@$(call log_error,Unsupported OS: $(OS))
	@exit 1
endif

.PHONY: install-linux-deps
install-linux-deps:
	@$(call log_info,Installing Linux build dependencies...)
	@which apt-get >/dev/null 2>&1 && { \
		sudo apt-get update && \
		sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev build-essential curl git unzip xz-utils zip libglu1-mesa; \
	} || which dnf >/dev/null 2>&1 && { \
		sudo dnf install -y clang cmake ninja-build gtk3-devel xz-devel gcc-c++ curl git unzip xz zip mesa-libGLU; \
	} || which pacman >/dev/null 2>&1 && { \
		sudo pacman -Syu --noconfirm clang cmake ninja gtk3 base-devel curl git unzip xz zip glu; \
	} || { \
		$(call log_error,No supported package manager found); \
		exit 1; \
	}
	@$(call log_success,Linux dependencies installed!)

.PHONY: install-macos-deps
install-macos-deps:
	@$(call log_info,Installing macOS build dependencies...)
	@which brew >/dev/null 2>&1 || { \
		$(call log_info,Installing Homebrew...); \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
	}
	@xcode-select -p >/dev/null 2>&1 || { \
		$(call log_info,Installing Xcode Command Line Tools...); \
		xcode-select --install; \
	}
	@which pod >/dev/null 2>&1 || sudo gem install cocoapods
	@$(call log_success,macOS dependencies installed!)

.PHONY: install-windows-deps
install-windows-deps:
	@$(call log_info,Installing Windows build dependencies...)
	@powershell -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; \
		[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; \
		iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" || { \
		$(call log_error,Failed to install Chocolatey); \
		exit 1; \
	}
	@powershell -Command "choco install git -y" || { \
		$(call log_error,Failed to install Git); \
		exit 1; \
	}
	@$(call log_success,Windows dependencies installed!)

.PHONY: install-flutter
install-flutter:
	@$(call log_info,Installing Flutter SDK...)
	@which flutter >/dev/null 2>&1 && { \
		$(call log_info,Flutter already installed); \
		flutter --version; \
	} || { \
		$(call log_info,Downloading Flutter SDK...); \
		cd /tmp && \
		# Fallback simple download for environments where the more advanced installer failed
		curl -L $(if $(findstring china,$(mirror)),$(flutter_mirror_china),$(flutter_mirror_default))/stable/$(OS)/flutter_$(OS)_$(FLUTTER_VERSION)-stable.tar.xz -o flutter.tar.xz && \
		tar xf flutter.tar.xz && \
		mkdir -p ~/flutter && \
		mv flutter/* ~/flutter/ && \
		rm -rf flutter flutter.tar.xz; \
		export PATH="$$PATH:$$HOME/flutter/bin"; \
		echo 'export PATH="$$PATH:$$HOME/flutter/bin"' >> ~/.bashrc; \
		echo 'export PATH="$$PATH:$$HOME/flutter/bin/cache/dart-sdk/bin"' >> ~/.bashrc; \
	}
	@flutter config --enable-windows-desktop --enable-macos-desktop --enable-linux-desktop
	@flutter doctor -v
	@$(call log_success,Flutter installed!)

.PHONY: install-android-sdk
install-android-sdk:
	@$(call log_info,Setting up Android development environment...)
	@[ -n "$$ANDROID_HOME" ] && { \
		$(call log_success,Android SDK already configured); \
	} || { \
		$(call log_info,Android Studio installation required); \
		$(call log_info,Please install Android Studio from: https://developer.android.com/studio); \
	}

.PHONY: setup-project
setup-project:
	@$(call log_info,Setting up Buddy project configuration...)
	@if [ ! -f .env ]; then \
		$(call log_info,Creating .env configuration file...); \
		echo "# Buddy Configuration File" > .env; \
		echo "# Add your LLM API keys and configurations here" >> .env; \
		echo "" >> .env; \
		echo "# OpenAI Configuration" >> .env; \
		echo "OPENAI_API_KEY=your_openai_api_key_here" >> .env; \
		echo "OPENAI_API_BASE=https://api.openai.com/v1" >> .env; \
		echo "" >> .env; \
		echo "# DeepSeek Configuration" >> .env; \
		echo "DEEPSEEK_API_KEY=your_deepseek_api_key_here" >> .env; \
		echo "DEEPSEEK_API_BASE=https://api.deepseek.com/v1" >> .env; \
		echo "" >> .env; \
		echo "# Kimi Configuration" >> .env; \
		echo "KIMI_API_KEY=your_kimi_api_key_here" >> .env; \
		echo "" >> .env; \
		echo "# Vector Database Configuration" >> .env; \
		echo "VECTOR_DB_PATH=./data/vector_db" >> .env; \
		echo "" >> .env; \
		echo "# Application Settings" >> .env; \
		echo "DEBUG_MODE=false" >> .env; \
		echo "LOG_LEVEL=info" >> .env; \
		$(call log_success,.env file created!); \
		$(call log_warning,Please edit the .env file with your API keys); \
	fi
	@if [ -f pubspec.yaml ]; then \
		$(call log_info,Installing Flutter dependencies...); \
		flutter pub get; \
		$(call log_success,Flutter dependencies installed!); \
	fi
	@$(call log_success,Project setup complete!)

# Build targets
.PHONY: build
# Top-level build target is defined later to compose platform builds

# Check prerequisites
.PHONY: prerequisites
prerequisites:
	@which flutter >/dev/null 2>&1 || { $(call log_error,Flutter not found. Run 'make install-prerequisites' first.); exit 1; }
	@which dart >/dev/null 2>&1 || { $(call log_error,Dart not found. Run 'make install-prerequisites' first.); exit 1; }
	@[ -f pubspec.yaml ] || { $(call log_error,pubspec.yaml not found. Run from project root.); exit 1; }

# Initialize build environment
.PHONY: install-deps
install-deps: prerequisites
	@$(call log_info,Initializing build environment...)
	@mkdir -p $(output_dir) $(archive_dir)
	@if [ "$(skip_pub_get)" != "true" ]; then \
		$(call log_info,Getting Flutter dependencies...); \
		flutter pub get; \
	fi
	@$(call log_success,Build environment initialized)

# Generate icons
.PHONY: icons
icons:
	@$(call log_info,Generating application icons...)
	@if grep -q flutter_launcher_icons pubspec.yaml && [ -f assets/icons/app_icon.png ]; then \
		dart run flutter_launcher_icons; \
		$(call log_success,Icons generated!); \
	else \
		$(call log_warning,flutter_launcher_icons not configured or icon source missing); \
	fi

# Run tests
.PHONY: test
test: prerequisites
	@if [ "$(skip_tests)" != "true" ]; then \
		$(call log_info,Running tests...); \
		flutter test; \
		$(call log_success,Tests passed!); \
	else \
		$(call log_warning,Skipping tests); \
	fi

# Platform-specific build targets
build: install-deps $(if $(filter true,$(generate_icons)),icons) test build-$(OS) launch

.PHONY: build-all
build-all: build-windows build-macos build-linux build-android build-ios build-web

.PHONY: build-windows
build-windows:
	@if [ "$(OS)" = "windows" ]; then \
		$(call log_info,Building Windows executable...); \
		mkdir -p $(output_dir)/windows; \
		flutter build windows --$(mode) $(if $(filter true,$(verbose)),--verbose); \
		cp -r build/windows/x64/runner/$(mode)/* $(output_dir)/windows/; \
		$(call create_archive,windows,zip); \
		$(call log_success,Windows build complete!); \
	else \
		$(call log_warning,Windows builds only supported on Windows); \
	fi

.PHONY: build-macos
build-macos:
	@if [ "$(OS)" = "macos" ]; then \
		$(call log_info,Building macOS app bundle...); \
		mkdir -p $(output_dir)/macos; \
		flutter build macos --$(mode) $(if $(filter true,$(verbose)),--verbose); \
		cp -r build/macos/Build/Products/$(shell echo $(mode) | sed 's/^./\U&/')/* $(output_dir)/macos/; \
		$(call create_archive,macos,zip); \
		$(call log_success,macOS build complete!); \
	else \
		$(call log_warning,macOS builds only supported on macOS); \
	fi

.PHONY: build-linux
build-linux:
	@if [ "$(OS)" = "linux" ]; then \
		$(call log_info,Building Linux executable...); \
		mkdir -p $(output_dir)/linux; \
		CMAKE_INSTALL_COMPONENT="Bundle" CMAKE_INSTALL_PREFIX="$(PWD)/$(output_dir)/linux" flutter build linux --$(mode) $(if $(filter true,$(verbose)),--verbose); \
		if [ -d "build/linux/x64/$(mode)/bundle" ]; then \
			cp -r build/linux/x64/$(mode)/bundle/* $(output_dir)/linux/ 2>/dev/null || true; \
			$(call create_archive,linux,tar.gz); \
			$(call log_success,Linux build complete!); \
		else \
			$(call log_error,Linux build failed - bundle directory not found); \
			exit 1; \
		fi; \
	else \
		$(call log_warning,Linux builds only supported on Linux); \
	fi

.PHONY: package-deb
package-deb: build-linux
	@$(call log_info,Packaging Debian .deb using tools/package_deb.sh)
	@mkdir -p $(output_dir)/deb
	@chmod +x tools/package_deb.sh || true
	@# Default to git describe for version; caller can set VERSION env var
	@VERSION=$${version:-$$(git describe --tags --always --dirty 2>/dev/null || echo "nightly-$$(date -u +%Y%m%d%H%M)" )} && \
		./tools/package_deb.sh "$${VERSION}" && \
		mv build/deb/*.deb $(output_dir)/deb/ || true
	@$(call log_success,Debian package created in $(output_dir)/deb)

.PHONY: build-android
build-android:
	@$(call log_info,Building Android APK and AAB...); \
	mkdir -p $(output_dir)/android; \
	if [ -n "$(proxy)" ]; then \
		$(call log_info,Configuring Gradle proxy settings...); \
		cp android/gradle.properties android/gradle.properties.backup; \
		echo "systemProp.http.proxyHost=$$(echo $(proxy) | cut -d: -f1)" >> android/gradle.properties; \
		echo "systemProp.http.proxyPort=$$(echo $(proxy) | cut -d: -f2)" >> android/gradle.properties; \
		echo "systemProp.https.proxyHost=$$(echo $(proxy) | cut -d: -f1)" >> android/gradle.properties; \
		echo "systemProp.https.proxyPort=$$(echo $(proxy) | cut -d: -f2)" >> android/gradle.properties; \
	fi; \
	flutter build apk --$(mode) $(if $(filter true,$(verbose)),--verbose); \
	flutter build appbundle --$(mode) $(if $(filter true,$(verbose)),--verbose); \
	if [ -n "$(proxy)" ]; then \
		$(call log_info,Restoring original Gradle configuration...); \
		mv android/gradle.properties.backup android/gradle.properties; \
	fi; \
	if [ -f build/app/outputs/flutter-apk/app-$(mode).apk ]; then \
		cp build/app/outputs/flutter-apk/app-$(mode).apk $(output_dir)/android/; \
		$(call log_success,APK copied successfully); \
	else \
		$(call log_warning,APK not found at expected location); \
	fi; \
	if [ -f build/app/outputs/bundle/$(mode)/app-$(mode).aab ]; then \
		cp build/app/outputs/bundle/$(mode)/app-$(mode).aab $(output_dir)/android/; \
		$(call log_success,AAB copied successfully); \
	else \
		$(call log_warning,AAB not found at expected location); \
	fi; \
	if [ -d "$(output_dir)/android" ] && [ "$$(ls -A $(output_dir)/android)" ]; then \
		$(call create_archive,android,zip); \
	else \
		$(call log_warning,No files to archive); \
	fi; \
	$(call log_success,Android build complete!)

.PHONY: build-ios
build-ios:
	@if [ "$(OS)" = "macos" ]; then \
		$(call log_info,Building iOS app...); \
		mkdir -p $(output_dir)/ios; \
		flutter build ios --$(mode) $(if $(filter true,$(verbose)),--verbose) --no-codesign; \
		cp -r build/ios/iphoneos/* $(output_dir)/ios/; \
		$(call create_archive,ios,zip); \
		$(call log_success,iOS build complete!); \
	else \
		$(call log_warning,iOS builds only supported on macOS); \
	fi

.PHONY: build-web
build-web:
	@$(call log_info,Building Web application...); \
	mkdir -p $(output_dir)/web; \
	flutter build web --$(mode) $(if $(filter true,$(verbose)),--verbose); \
	cp -r build/web/* $(output_dir)/web/; \
	@$(call create_archive,web,zip); \
	@$(call log_success,Web build complete!)

# Archive creation function
define create_archive
	$(call log_info,Creating $(1) archive...); \
	archive_name="$(if $(archive_name),$(archive_name)-$(1).$(2),$(project_name)-$(1)-$(mode).$(2))"; \
	archive_path="$(archive_dir)/$$archive_name"; \
	mkdir -p $(archive_dir); \
	case "$(2)" in \
		zip) (cd $(output_dir)/$(1) && zip -r "$$archive_path" .) ;; \
		tar.gz) tar -czf "$$archive_path" -C $(output_dir)/$(1) . ;; \
		*) $(call log_error,Unknown archive type: $(2)); exit 1 ;; \
	esac; \
	$(call log_success,Archive created: $$archive_path)
endef

# Debug target with mirror and proxy support
.PHONY: debug
debug: prerequisites
	@echo ""
	@echo "============================================="
	@echo "     Buddy Debug Run                         "
	@echo "============================================="
	@echo ""
	@$(call log_info,Running Flutter app in debug mode)
	@$(call log_info,Mirror: $(mirror))
ifdef proxy
	@$(call log_info,Proxy: $(proxy))
endif
	@echo ""
	@flutter run --debug $(mirror_flag) $(proxy_flag) $(if $(filter true,$(verbose)),--verbose)

# Clean target
.PHONY: clean
clean:
	@$(call log_info,Cleaning build artifacts...)
	@rm -rf build $(output_dir)
	@flutter clean >/dev/null 2>&1 || true
	@$(call log_success,Clean complete!)

# Launch executable if requested
.PHONY: launch
launch:
	@if [ "$(open)" = "yes" -o "$(open)" = "true" ]; then \
		$(call log_info,Launching $(project_name) for $(OS)...); \
		case "$(OS)" in \
			"windows") \
				[ -f $(output_dir)/windows/$(project_name).exe ] && $(output_dir)/windows/$(project_name).exe & ;; \
			"linux") \
				[ -f $(output_dir)/linux/$(project_name) ] && $(output_dir)/linux/$(project_name) & ;; \
			"macos") \
				[ -d $(output_dir)/macos/$(project_name).app ] && open $(output_dir)/macos/$(project_name).app & ;; \
			*) \
				$(call log_warning,No executable found for $(OS) platform); \
		esac; \
	else \
		$(call log_info,Skipping launch (use open=yes to enable)); \
	fi
