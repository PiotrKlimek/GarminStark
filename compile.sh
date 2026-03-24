#!/bin/bash
set -e

# Załaduj .env jeśli istnieje
[ -f "$(dirname "$0")/.env" ] && source "$(dirname "$0")/.env"

# Generuj Version.mc z datą kompilacji
BUILD_DATE=$(date +"%Y-%m-%d %H:%M")
cat > "$(dirname "$0")/source/Version.mc" <<EOF
const APP_VERSION = "${BUILD_DATE}";
EOF

docker build -t garmin-build "$(dirname "$0")" --quiet

docker run --rm \
    -v "$(dirname "$0"):/project" \
    -v garmin-sdk:/opt/connectiq-sdk \
    -v garmin-devices:/opt/connectiq-devices \
    -e DEVICE="${DEVICE:-fenix7pro}" \
    garmin-build
