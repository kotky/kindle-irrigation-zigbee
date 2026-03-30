# kindle-irrigation-zigbee

Autonomous irrigation system using Zigbee soil sensors and water valves, with a live dashboard on a jailbroken Kindle e-ink display.

## Architecture

```
Zigbee devices (soil sensors + valves)
    ↓ (Zigbee radio via USB coordinator)
Zigbee2MQTT  ←→  Mosquitto MQTT broker  ← (public port 1883, password protected)
    ↓ (MQTT auto-discovery)
Home Assistant (port 8123)
  ├── Automations: moisture-based irrigation, rain blocking, battery alerts
  ├── Blueprint: irrigation_zone (one instance per zone)
  └── Lovelace: "kindle" dashboard view
    ↓ (HTTP screenshot on demand)
puppet service (port 10000)
    ↓ (600×800 grayscale PNG)
Kindle — wget + eips every 90s

+ Nginx (port 80)
    └── /admin  → Zone management UI (add/remove zones via browser)
```

## Devices

| Item | AliExpress ID | Z2M Model |
|------|--------------|-----------|
| Soil moisture sensor | 1005011801061136 | Tuya TS0601_soil |
| Water valve | 1005009336429185 | Tuya TS0601_water_valve |

## Prerequisites

- Linux host (Raspberry Pi 4 or similar)
- Docker + Docker Compose v2
- Zigbee USB coordinator (e.g. SONOFF Zigbee 3.0 USB Dongle) at `/dev/ttyUSB0`
- Jailbroken Kindle with WiFi + SSH access

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/kotky/kindle-irrigation-zigbee.git
cd kindle-irrigation-zigbee
cp .env.example .env
```

Edit `.env`:
```
HA_TOKEN=         # fill in after step 3
MQTT_USER=irrigation
MQTT_PASSWORD=    # choose a strong password
TZ=Europe/Zagreb  # your timezone
```

### 2. Generate MQTT password file

```bash
source .env
docker run --rm eclipse-mosquitto:2 \
  mosquitto_passwd -b /dev/stdout "$MQTT_USER" "$MQTT_PASSWORD" \
  > mosquitto/config/passwd
```

### 3. Start core services and create HA account

```bash
docker compose up -d mosquitto zigbee2mqtt homeassistant
```

Open `http://HOST:8123` → create your Home Assistant account.

### 4. Generate a long-lived HA token

HA → Profile (bottom-left avatar) → Security → Long-Lived Access Tokens → **Create Token** → copy it.

Edit `.env` and set `HA_TOKEN=<paste token here>`.

Also fill in `homeassistant/secrets.yaml` with the same MQTT credentials as in `.env`.

### 5. Start remaining services

```bash
docker compose up -d
```

The `puppet` service builds from source on first run (takes ~5 minutes).

### 6. Pair Zigbee devices

Open `http://HOST:8080` (Zigbee2MQTT UI):
1. Click **Permit join**
2. Hold the pairing button on each device until the LED blinks
3. Set a friendly name for each device (e.g. `zone1_soil`, `zone1_valve`)
4. Turn permit join **off** when done
5. Set `permit_join: false` in `zigbee2mqtt/configuration.yaml` and restart:
   ```bash
   docker compose restart zigbee2mqtt
   ```

### 7. Assign zones

Open `http://HOST/admin`:
1. Select soil sensor + valve from the dropdowns (populated from HA auto-discovery)
2. Enter zone name and moisture threshold (default 30%)
3. Click **Add Zone**

Repeat for each zone.

### 8. Create the Kindle dashboard in HA

HA → Settings → Dashboards → **Add Dashboard**:
- Name: `Kindle`
- URL path: `kindle`

Add cards for each zone's entities (soil moisture gauge, valve switch, battery level, rain boolean). Use a high-contrast theme for best e-ink readability.

### 9. Set up Kindle

Edit `kindle/update.sh` and set `SERVER_IP` to your host machine's LAN IP, then:

```bash
# Replace 192.168.1.XXX with your Kindle's IP (Settings → Device Info → WiFi)
scp kindle/update.sh root@192.168.1.XXX:/mnt/us/
ssh root@192.168.1.XXX 'sh /mnt/us/update.sh &'
```

The dashboard appears on screen and refreshes every 90 seconds.

---

## Adding a New Zone

1. Pair the new sensor and valve in Z2M UI (port 8080), set friendly names
2. Go to `http://HOST/admin` → Add Zone → select devices → save
3. In HA: open the `kindle` dashboard → add cards for the new zone's entities

No service restarts required.

---

## Automation Logic

| Automation | Trigger | Condition | Action |
|---|---|---|---|
| Irrigation (blueprint, one per zone) | Soil moisture < threshold | Not raining + 06:00–20:00 | Open valve → wait N min → close |
| Rain detection | `sensor.precipitation` > 0.5 mm | — | Set `rain_detected = on` |
| Rain clear | Daily at 12:00 | — | Set `rain_detected = off` |
| Low battery | Any battery sensor < 20% | — | HA persistent notification |

---

## Service Ports

| Service | Port | Notes |
|---|---|---|
| Home Assistant | 8123 | Main UI + REST API |
| Zigbee2MQTT | 8080 | Device pairing + MQTT debug |
| Mosquitto | 1883 | MQTT broker — password protected, publicly accessible |
| puppet | 10000 | On-demand HA dashboard screenshots for Kindle |
| Nginx | 80 | Admin UI at `/admin` |

---

## Verification

```bash
# MQTT — see live device messages
docker exec mosquitto mosquitto_sub -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t '#' -v

# Test puppet screenshot
curl "http://localhost:10000/?url=/lovelace/kindle&viewport=600x800" -o test.png
file test.png   # PNG image data, 600 x 800

# Test HA API via nginx proxy
curl http://localhost/ha-api/states/input_boolean.rain_detected

# Simulate low soil moisture to trigger irrigation automation
docker exec mosquitto mosquitto_pub \
  -u "$MQTT_USER" -P "$MQTT_PASSWORD" \
  -t zigbee2mqtt/zone1_soil \
  -m '{"soil_moisture": 15, "battery": 85}'
```
