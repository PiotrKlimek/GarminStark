#!/bin/bash
set -e

SDK_DIR="/opt/connectiq-sdk"
DEVICES_DIR="/opt/connectiq-devices"
SDK_BASE_URL="https://developer.garmin.com/downloads/connect-iq/sdks"
SDK_FEED="${SDK_BASE_URL}/sdks.json"
DEVICES_REPO_API="https://api.github.com/repos/matco/connectiq-tester"
DEVICE="${DEVICE:-fenix7pro}"
OUTPUT_DIR="/project/output"
KEY_FILE="/project/developer_key.der"

# ── 1. Zainstaluj SDK (jeśli jeszcze nie ma) ───────────────────────────────
if [ ! -f "${SDK_DIR}/bin/monkeyc" ]; then
    echo "Pobieram listę wersji SDK z Garmin..."
    sdk_filename=$(curl -sf "$SDK_FEED" \
        | grep -o '"linux": *"[^"]*"' \
        | tail -1 \
        | grep -o '"[^"]*\.zip"' \
        | tr -d '"')

    if [ -z "$sdk_filename" ]; then
        echo "BŁĄD: Nie udało się pobrać listy SDK z Garmin."
        exit 1
    fi

    sdk_url="${SDK_BASE_URL}/${sdk_filename}"
    sdk_version=$(echo "$sdk_filename" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    echo "Pobieram Connect IQ SDK ${sdk_version}..."

    curl -L --progress-bar -o /tmp/connectiq-sdk.zip "$sdk_url"

    echo "Rozpakowuję SDK..."
    mkdir -p "$SDK_DIR"
    unzip -q /tmp/connectiq-sdk.zip -d "$SDK_DIR"

    if [ ! -f "${SDK_DIR}/bin/monkeyc" ]; then
        subdir=$(find "$SDK_DIR" -name "monkeyc" -type f | head -1 | xargs dirname | xargs dirname)
        if [ -n "$subdir" ] && [ "$subdir" != "$SDK_DIR" ]; then
            mv "$subdir"/* "$SDK_DIR"/
        fi
    fi

    chmod +x "${SDK_DIR}"/bin/*
    rm /tmp/connectiq-sdk.zip
    echo "SDK ${sdk_version} zainstalowany."
fi

# ── 2. Pobierz profile urządzeń (jeśli jeszcze nie ma) ────────────────────
if [ ! -d "${DEVICES_DIR}/${DEVICE}" ]; then
    echo "Pobieram profile urządzeń (może chwilę potrwać ~90MB)..."
    blob_sha=$(curl -sf "${DEVICES_REPO_API}/git/trees/master?recursive=1" \
        | jq -r '.tree[] | select(.path == "devices.zip") | .sha')
    curl -L --progress-bar \
        -H "Accept: application/vnd.github.raw" \
        -o /tmp/devices.zip \
        "${DEVICES_REPO_API}/git/blobs/${blob_sha}"

    echo "Rozpakowuję profile urządzeń..."
    mkdir -p "$DEVICES_DIR"
    unzip -q /tmp/devices.zip -d "$DEVICES_DIR"
    rm /tmp/devices.zip
    echo "Profile urządzeń zainstalowane ($(ls $DEVICES_DIR | wc -l) urządzeń)."
fi

# ── 3. Wygeneruj klucz dewelopera (jeśli nie ma) ──────────────────────────
if [ ! -f "$KEY_FILE" ]; then
    echo "Generuję klucz dewelopera..."
    openssl genrsa -out /project/developer_key.pem 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in /project/developer_key.pem \
        -out "$KEY_FILE" -nocrypt
    echo "Klucz zapisany: developer_key.der  <-- zachowaj go!"
fi

# ── 4. Kompiluj ───────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
echo "Kompiluję dla: $DEVICE"

echo 'const STARK_VARG_VIN = "UDUEX1AE8SA005799";' > /project/source/VinConfig.mc
monkeyc \
    -o "$OUTPUT_DIR/StarkBattery.prg" \
    -f /project/monkey.jungle \
    -y "$KEY_FILE" \
    -d "$DEVICE" \
    --override-devices-json "$DEVICES_DIR" \
    --warn

# TYMCZASOWO wyłączone — wrócimy gdy fenix7pro będzie sprawdzony
# echo 'const STARK_VARG_VIN = "UDUEX1AE7SA005907";' > /project/source/VinConfig.mc
# monkeyc \
#     -o "$OUTPUT_DIR/StarkBattery_KM.prg" \
#     -f /project/monkey_km.jungle \
#     -y "$KEY_FILE" \
#     -d "instinct2" \
#     --override-devices-json "$DEVICES_DIR" \
#     --warn

# echo 'const STARK_VARG_VIN = "UDUEX1AE9SA003348";' > /project/source/VinConfig.mc
# monkeyc \
#     -o "$OUTPUT_DIR/StarkBattery_MP.prg" \
#     -f /project/monkey_mp.jungle \
#     -y "$KEY_FILE" \
#     -d "instinct3amoled50mm" \
#     --override-devices-json "$DEVICES_DIR" \
#     --warn

echo 'const STARK_VARG_VIN = "UDUEX1AE8SA005799";' > /project/source-df/VinConfig.mc
monkeyc \
    -o "$OUTPUT_DIR/StarkBatteryDF.prg" \
    -f /project/monkey_df.jungle \
    -y "$KEY_FILE" \
    -d "fenix7pro" \
    --override-devices-json "$DEVICES_DIR" \
    --warn

# TYMCZASOWO wyłączone — wrócimy gdy fenix7pro będzie sprawdzony
# echo 'const STARK_VARG_VIN = "UDUEX1AE7SA005907";' > /project/source-df/VinConfig.mc
# monkeyc \
#     -o "$OUTPUT_DIR/StarkBatteryDF_KM.prg" \
#     -f /project/monkey_df_km.jungle \
#     -y "$KEY_FILE" \
#     -d "instinct2" \
#     --override-devices-json "$DEVICES_DIR" \
#     --warn

# echo 'const STARK_VARG_VIN = "UDUEX1AE9SA003348";' > /project/source-df/VinConfig.mc
# monkeyc \
#     -o "$OUTPUT_DIR/StarkBatteryDF_MP.prg" \
#     -f /project/monkey_df_mp.jungle \
#     -y "$KEY_FILE" \
#     -d "instinct3amoled50mm" \
#     --override-devices-json "$DEVICES_DIR" \
#     --warn

echo ""
echo "Gotowe!"
echo "  output/StarkBattery.prg   (VIN: UDUEX1AE8SA005799)"
echo "  output/StarkBatteryDF.prg (VIN: UDUEX1AE8SA005799)"
