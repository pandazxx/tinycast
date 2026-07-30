# Agent image for Tinycast: the minimal codex-slack base plus a Swift toolchain, so the
# Foundation-only harnesses in Tools/ can be compiled and run inside the container.
#
# This CANNOT build Tinycast.app. That needs Xcode's macOS SDK and the SwiftUI macro plugin,
# which Apple ships only for macOS — so the app build, and every harness that reaches AppKit,
# Combine, SQLite3 or Darwin, belongs on a macos-26 GitHub Actions runner.
#
# Verified in a container built from this file — 3 of the 7 harnesses in Tools/ run here:
#   calc-test   -> 426 passed, 0 failed
#   fuzz-test   -> ALL PASSED
#   emoji-test  -> all checks passed (2054 records)
# The other 4 fail by design rather than by accident, and no amount of image work fixes them:
#   ranking-test / custom-command-test — their sources import Combine, absent on Linux
#   scopes-test   — SearchScopes uses abbreviatingWithTildeInPath, Darwin-only Foundation
#   clipboard-test — needs the SQLite3 module
#
# `xcodegen generate` also runs here, and reproduces the committed project.pbxproj byte for byte.

ARG BASE_IMAGE=ghcr.io/pandazxx/codex-slack-agent-minimal:v4.19-rc16
ARG SWIFT_VERSION=6.3.3
# swift.org publishes no Debian 13 build; the Debian 12 tarball runs fine on trixie's glibc 2.41.
ARG SWIFT_PLATFORM=debian12
ARG SWIFT_SHA256=19e0c78cad5418ad48bfa87aa20c53ac9ac9996d1695d04dd94f7c7ea4eb133f
ARG XCODEGEN_VERSION=2.46.0

# ---------------------------------------------------------------------------------------------
# Builder: unpacks the full toolchain, builds XcodeGen, then prunes. Pruning happens here so the
# final image COPYs an already-slim tree — deleting in a later layer would not shrink the image,
# and this way the 1 GB tarball is still only downloaded once.
# ---------------------------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS builder

ARG SWIFT_VERSION
ARG SWIFT_PLATFORM
ARG SWIFT_SHA256
ARG XCODEGEN_VERSION

USER root

# Toolchain dependencies, each established by running it and reading the failure: swift needs
# libncurses.so.6, ld.lld needs libxml2.so.2, and linking needs binutils plus gcc's crt*.o and
# the libc headers.
RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils \
    gcc \
    libc6-dev \
    libcurl4 \
    libncurses6 \
    libxml2 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    url="https://download.swift.org/swift-${SWIFT_VERSION}-release/${SWIFT_PLATFORM}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-${SWIFT_PLATFORM}.tar.gz"; \
    curl -fsSL "$url" -o /tmp/swift.tar.gz; \
    echo "${SWIFT_SHA256}  /tmp/swift.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/swift; \
    tar xzf /tmp/swift.tar.gz -C /opt/swift --strip-components=1; \
    rm /tmp/swift.tar.gz; \
    /opt/swift/usr/bin/swiftc --version

# XcodeGen regenerates the committed Tinycast.xcodeproj after project.yml changes or new source
# files. A failure is tolerated rather than fatal: a broken build here would block the whole
# workspace, and everything else in this image is independently useful.
RUN set -eux; \
    mkdir -p /out; \
    export PATH="/opt/swift/usr/bin:$PATH"; \
    if git clone -q --depth 1 --branch "${XCODEGEN_VERSION}" \
         https://github.com/yonaskolb/XcodeGen.git /tmp/XcodeGen \
       && swift build -c release --package-path /tmp/XcodeGen --scratch-path /tmp/xcg-build; then \
      cp /tmp/xcg-build/release/xcodegen /out/xcodegen; \
      cp -r /tmp/XcodeGen/SettingPresets /out/SettingPresets; \
      echo "xcodegen ${XCODEGEN_VERSION} built"; \
    else \
      echo "WARNING: XcodeGen ${XCODEGEN_VERSION} failed to build — image ships without it."; \
    fi; \
    rm -rf /tmp/XcodeGen /tmp/xcg-build

# Drop the IDE / debugger / SwiftPM halves: 3.3 GB down to ~1.7 GB. Re-verified after pruning —
# both working harnesses still compile and pass. lib/swift is kept in full; the xcodegen binary
# and every harness link against it at runtime.
RUN set -eux; \
    cd /opt/swift/usr; \
    rm -rf lib/swift_static lib/liblldb.so* lib/libsourcekitdInProc.so \
           lib/libSwiftSourceKitPlugin.so lib/libLTO.so* lib/libclang.so* \
           lib/libclang-cpp.so* share/docc; \
    rm -f bin/lldb* bin/sourcekit-lsp bin/docc bin/clangd bin/swift-package* \
          bin/swift-build* bin/swift-test bin/swift-run bin/swift-sdk \
          bin/swift-experimental-sdk bin/swift-build-sdk-interfaces bin/swift-format \
          bin/swift-api-digester bin/swift-symbolgraph-extract

# ---------------------------------------------------------------------------------------------
# Final image
# ---------------------------------------------------------------------------------------------
FROM ${BASE_IMAGE}

USER root

# Same set as the builder — these are the toolchain's runtime and link-time dependencies, not
# build-only. jq and ripgrep are for the agent's own use.
RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils \
    gcc \
    libc6-dev \
    libcurl4 \
    libncurses6 \
    libxml2 \
    jq \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/swift /opt/swift
COPY --from=builder /out/ /tmp/xcg/

# The xcodegen binary alone is not enough. Without SettingPresets it still exits 0, but silently
# emits a project stripped of ~98 inherited build settings, SDKROOT among them. It resolves them
# against `Bundle.main.bundlePath/../share/xcodegen`, which for /usr/local/bin/xcodegen means
# /usr/local/share/xcodegen — hence that path below.
# Keep comments out of the RUN body: an indented comment inside a line continuation breaks the
# instruction, which is what silently reverted this image to the bare base once already.
RUN set -eux; \
    ln -s /opt/swift/usr/bin/swift /usr/local/bin/swift; \
    ln -s /opt/swift/usr/bin/swiftc /usr/local/bin/swiftc; \
    if [ -x /tmp/xcg/xcodegen ]; then \
      install -m 0755 /tmp/xcg/xcodegen /usr/local/bin/xcodegen; \
      mkdir -p /usr/local/share/xcodegen; \
      cp -r /tmp/xcg/SettingPresets /usr/local/share/xcodegen/SettingPresets; \
      test -f /usr/local/share/xcodegen/SettingPresets/base.yml; \
      xcodegen --version; \
    fi; \
    rm -rf /tmp/xcg; \
    swiftc --version

# XcodeGen reads the current user via NSUserName(); on Linux that consults $USER, which the
# runtime does not set, and it aborts with "Couldn't find current username" before writing.
ENV USER=appuser

USER appuser
