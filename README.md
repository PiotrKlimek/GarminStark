# StarkBattery — Garmin Watch App

Aplikacja na zegarki Garmin wyświetlająca stan baterii motocykla elektrycznego **Stark Varg** bezpośrednio na ekranie zegarka przez Bluetooth Low Energy — bez telefonu ani pośrednich serwisów.

Protokół BLE oparty na [svag-mini](https://github.com/b1naryth1ef/svag-mini).

---

## Warianty

| Plik wyjściowy         | Zegarek               | VIN                 |
|------------------------|-----------------------|---------------------|
| `StarkBattery.prg`     | Fenix 7 Pro           | `UDUEX1AE8SA005799` |
| `StarkBattery_KM.prg`  | Instinct 2            | `UDUEX1AE7SA005907` |
| `StarkBattery_MP.prg`  | Instinct 3 AMOLED 50mm | `UDUEX1AE9SA003348` |

---

## Wymagania

- Docker

---

## Kompilacja

```bash
cp .env.example .env        # opcjonalnie, domyślnie DEVICE=fenix7pro
bash compile.sh
```

Skrypt buduje wszystkie trzy warianty jednocześnie. Pliki `.prg` trafiają do `output/`.

---

## Wgrywanie na zegarek

Przez **Garmin Express** lub sideloading (tryb deweloperski w zegarku).

---

## Dodawanie nowego wariantu

1. Dodaj VIN i suffix do `entrypoint.sh` (dwa miejsca: zapis `VinConfig.mc` + wywołanie `monkeyc`)
2. Stwórz `manifest_XX.jungle` z nowym `project.manifest = manifest_XX.xml`
3. Stwórz `manifest_XX.xml` na wzór istniejących — zmień `id` (32 hex), `name`, `<iq:product>`
4. Dodaj `<string id="AppNameXX">StarkBattery_XX</string>` do `resources/strings/strings.xml`

Dostępne ID urządzeń Garmin: katalog `garmin-devices` w wolumenie Docker lub `ls` po pierwszej kompilacji.

---

## Protokół BLE

| Rola             | UUID                                   |
|------------------|----------------------------------------|
| Battery Service  | `00006000-5374-6172-4b20-467574757265` |
| Battery SOC char | `00006004-5374-6172-4b20-467574757265` |

- Characteristic mode: **NOTIFY**
- Format: uint16 little-endian (wartość 0–100, procenty)
- UUID tworzone przez `BluetoothLowEnergy.stringToUuid()` — wymagane przez Connect IQ runtime

---

## Struktura

```
source/
  StarkVargApp.mc       — AppBase, rejestracja profilu BLE
  BleManager.mc         — scan, połączenie, notyfikacje, state machine
  StarkVargView.mc      — rysowanie ekranu (splash / scanning / connected / timeout)
  StarkVargDelegate.mc  — obsługa przycisków
  VinConfig.mc          — generowany przez compile.sh (nie commitowany)
  Version.mc            — generowany przez compile.sh (nie commitowany)
resources/
  strings/strings.xml   — teksty UI + nazwy wariantów
  drawables/            — ikona launchera
manifest.xml            — Fenix 7 Pro
manifest_km.xml         — Instinct 2
manifest_mp.xml         — Instinct 3 AMOLED 50mm
monkey.jungle           — konfiguracja buildu (Fenix 7 Pro)
monkey_km.jungle        — konfiguracja buildu (Instinct 2)
monkey_mp.jungle        — konfiguracja buildu (Instinct 3)
Dockerfile              — środowisko kompilacji (Connect IQ SDK)
entrypoint.sh           — logika buildu wewnątrz kontenera
compile.sh              — uruchamia Docker i buduje wszystkie warianty
.env.example            — przykładowa konfiguracja środowiska
docs/                   — specyfikacja i plan implementacji
```
