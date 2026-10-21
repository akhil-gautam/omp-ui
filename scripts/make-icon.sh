#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# The icon is drawn from the same geometry the title bar uses, so the two can
# never drift apart.
SET=".build/AppIcon.iconset"
rm -rf "$SET"
mkdir -p "$SET" Resources
swiftc -O -parse-as-library -o .build/make-icon scripts/make-icon.swift Sources/OMPApp/BrandGeometry.swift
.build/make-icon "$SET"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
printf '%s\n' "Resources/AppIcon.icns"
