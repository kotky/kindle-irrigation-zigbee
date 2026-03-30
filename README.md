# kindle-irrigation-zigbee

Autonomous irrigation system using Zigbee soil sensors and water valves, with a live dashboard on a jailbroken Kindle e-ink display.

## Architecture

```
Soyo M4 Air — HA OS generic-x86-64 (bare metal)
├── Addon: Mosquitto Broker     ← local only (no public port needed with NetBird)
├── Addon: Zigbee2MQTT          ← USB passthrough /dev/ttyUSB0
├── Addon: puppet               ← balloob, port 10000, Kindle screenshots
├── Addon: Ollama               ← SirUli/homeassistant-ollama-addon, qwen2.5:1.5b
└── Addon: NetBird              ← netbirdio/addon-netbird, self-hosted management

HA Config (this repo → homeassistant/):
├── configuration.yaml          ← MQTT, input helpers, Ollama rest_command
├── automations.yaml            ← moisture irrigation, rain block, battery alerts, LLM summary
├── blueprints/automation/      ← irrigation_zone.yaml (one instance per zone)
├── zigbee2mqtt/                ← Zigbee2MQTT addon config
│   └── configuration.yaml
└── www/admin.html              ← Zone management UI (served at /local/admin.html)

Kindle: wget port 10000 → eips (every 90 s)
```

**Removed vs the docker-compose version:**
- `docker-compose.yml` → archived as `docker-compose.alternative.yml` with a note
- `mosquitto/` → handled by the Mosquitto addon
- `nginx/` → not needed; HA OS serves `/config/www/` at `/local/`
- `zigbee2mqtt/` (root) → config lives at `homeassistant/zigbee2mqtt/`

## Devices

| Item | AliExpress ID | Z2M Model |
|------|--------------|-----------
| Soil moisture sensor | 1005011801061136 | Tuya TS0601_soil |
| Water valve | 1005009336429185 | Tuya TS0601_water_valve |

## Hardware

**Soyo M4 Air** (Intel N95, 16 GB RAM, 512 GB SSD)

| Component | Value |
|---|---|
| CPU | Intel N95 (4× E-core, 3.4 GHz boost, 15 W TDP) |
| RAM | 16 GB DDR4/DDR5 |
| iGPU | Intel UHD (16 EU) |
| Ollama model | `qwen2.5:1.5b` — 8–20 tok/s, ~2.5 GB RAM, 200-token summary in ~10–25 s |

The LLM summary runs once per hour in the background (~20 s of ~80% CPU, then fully idle).

---

## Quick Start — HA OS Bare Metal

### 1. Flash HA OS to the SSD

1. Download **`haos_generic-x86-64.img.xz`** from the [HA releases page](https://github.com/home-assistant/operating-system/releases) (pick the latest stable)
2. Flash to the internal SSD using **Balena Etcher** (from another machine with USB-to-SSD adapter), or:
   ```bash
   xz -dc haos_generic-x86-64.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
   ```
3. Insert SSD, boot the Soyo M4 Air, wait ~3 minutes for first boot

### 2. Complete onboarding

Open `http://homeassistant.local:8123` → create your Home Assistant account.

### 3. Add community addon repositories

HA → Settings → Add-ons → Add-on Store → three-dot menu → **Repositories** → add each URL:

| Addon | Repository URL |
|---|---|
| Ollama | `https://github.com/alexbelgium/hassio-addons` *(or SirUli's repo)* |
| NetBird | `https://github.com/netbirdio/addon-netbird` |

> The **Mosquitto**, **Zigbee2MQTT**, and **File editor** addons are available in the default store.

### 4. Install addons

Install and start each addon in order:

| Addon | Key config (set via addon UI) |
|---|---|
| **Mosquitto Broker** | Create user `homeassistant` and user `zigbee2mqtt` in the *Logins* section with strong passwords |
| **Zigbee2MQTT** | Points to `/config/zigbee2mqtt/configuration.yaml` automatically |
| **puppet** | `access_token`: long-lived HA token (created in step 5); `home_assistant_url`: `http://localhost:8123`; `keep_browser_open`: true |
| **Ollama** | Default settings; pull model after install (see step 7) |
| **NetBird** | `admin_url`: your self-hosted management URL; `management_url`: your management API URL; `setup_key`: from your NetBird dashboard |

### 5. Copy this repo's config into HA

Using the **File editor** addon (or SSH addon):

```bash
# From a machine on the same LAN — scp into HA OS
scp -r homeassistant/* root@homeassistant.local:/config/
```

Or use the HA File Editor to upload/paste files one by one.

### 6. Edit secrets

Open `/config/secrets.yaml` and fill in real passwords:

```yaml
mqtt_user: "homeassistant"
mqtt_password: "YOUR_STRONG_MQTT_PASSWORD"   # must match Mosquitto addon Logins
z2m_mqtt_password: "YOUR_Z2M_MQTT_PASSWORD"  # must match zigbee2mqtt user in Mosquitto
```

### 7. Generate a long-lived HA token

HA → Profile (bottom-left avatar) → Security → Long-Lived Access Tokens → **Create Token** → copy it.

You will need this token for:
- The **puppet** addon config (`access_token`)
- The admin UI at `/local/admin.html` (paste it once in the browser — stored in localStorage)

### 8. Restart Home Assistant

HA → Settings → System → **Restart** → Restart Home Assistant.

After restart: all automations load, Zigbee2MQTT connects, Ollama starts.

### 9. Pull the Ollama model

In the Ollama addon UI (or via API):

```bash
curl http://homeassistant.local:11434/api/pull \
  -d '{"name":"qwen2.5:1.5b"}'
```

Wait for the ~1 GB download to complete. The first hourly summary will run at the next top of the hour.

### 10. Pair Zigbee devices

Open `http://homeassistant.local:8080` (Zigbee2MQTT UI):
1. Click **Permit join**
2. Hold the pairing button on each device until the LED blinks
3. Set a friendly name (e.g. `zone1_soil`, `zone1_valve`)
4. Turn **Permit join off** when done
5. Set `permit_join: false` in `/config/zigbee2mqtt/configuration.yaml` → restart the Z2M addon

### 11. Assign zones

Open `http://homeassistant.local:8123/local/admin.html`:
1. Paste your long-lived token and click **Save**
2. Select soil sensor + valve from the dropdowns (auto-populated from HA entity discovery)
3. Enter zone name and moisture threshold (default 30%)
4. Click **Add Zone**

Repeat for each irrigation zone.

### 12. Create the Kindle dashboard in HA

HA → Settings → Dashboards → **Add Dashboard**:
- Name: `Kindle`
- URL path: `kindle`

Add cards for each zone's entities (soil moisture gauge, valve switch, battery level, rain boolean).
Use a high-contrast theme for best e-ink readability.

### 13. Set up Kindle

Edit `kindle/update.sh` and set `SERVER_IP` to your HA host's LAN IP, then:

```bash
# Replace 192.168.1.XXX with your Kindle's IP (Settings → Device Info → WiFi)
scp kindle/update.sh root@192.168.1.XXX:/mnt/us/
ssh root@192.168.1.XXX 'sh /mnt/us/update.sh &'
```

The dashboard appears on screen and refreshes every 90 seconds.

---

## Adding a New Zone

1. Pair the new sensor and valve in Z2M UI (port 8080), set friendly names
2. Go to `http://homeassistant.local:8123/local/admin.html` → Add Zone → select devices → Save
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
| Irrigation LLM Summary | Every hour (top of hour) | — | Ollama `qwen2.5:1.5b` → `input_text.irrigation_summary` |

---

## Service Ports

| Service | Port | Notes |
|---|---|---|
| Home Assistant | 8123 | Main UI + REST API |
| Zigbee2MQTT | 8080 | Device pairing + MQTT debug |
| Mosquitto | 1883 | MQTT broker — local only (NetBird provides remote access) |
| puppet | 10000 | On-demand HA dashboard screenshots for Kindle |
| Ollama | 11434 | LLM inference (local only) |

---

## NetBird

With the NetBird addon running on HA OS, all your NetBird peers can reach the host on its NetBird IP — including Mosquitto (port 1883) and the HA UI (port 8123) — without any public port forwards. No TLS cert is needed for MQTT because the WireGuard tunnel encrypts traffic end-to-end.

To connect remote soil sensors or external clients, install the NetBird client on those devices and join the same NetBird network.

---

## Verification

```bash
# Check Zigbee2MQTT is receiving device data
# (use MQTT Explorer or the Z2M UI at port 8080)

# Test puppet screenshot
curl "http://homeassistant.local:10000/?url=/lovelace/kindle&viewport=600x800" -o test.png
file test.png   # PNG image data, 600 x 800

# Test HA API
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://homeassistant.local:8123/api/states/input_boolean.rain_detected

# Simulate low soil moisture to trigger irrigation automation
# (use MQTT Explorer or Z2M virtual device feature)

# Trigger LLM summary manually
# HA → Developer Tools → Actions → automation.trigger
# Action: irrigation_llm_summary
# Then check: Developer Tools → States → input_text.irrigation_summary
```

---

## Alternative: Docker Compose

If you want to run this stack without HA OS (e.g. on a generic Ubuntu server), see [`docker-compose.alternative.yml`](docker-compose.alternative.yml) for the full docker-compose configuration.
