# kindle-irrigation-zigbee

Autonomous irrigation system using Zigbee soil sensors and water valves, with a live dashboard on a jailbroken Kindle e-ink display.

## Architecture

```
Soyo M4 Air — Proxmox VE (bare metal, Intel N95)
│
├── VM 100: HA OS (4 GB RAM, 64 GB SSD, USB Zigbee dongle passed through)
│   ├── Addon: Mosquitto Broker     ← local only (no public port needed with NetBird)
│   ├── Addon: Zigbee2MQTT          ← Zigbee USB dongle via Proxmox USB passthrough
│   ├── Addon: puppet               ← balloob, port 10000, Kindle screenshots
│   ├── Addon: Ollama               ← qwen2.5:1.5b, hourly irrigation summary
│   └── Addon: NetBird              ← netbirdio/addon-netbird, self-hosted management
│
└── (optional future VMs / LXCs)
    ├── Frigate NVR                 ← Intel iGPU VA-API object detection
    └── misc services

HA Config (this repo → homeassistant/):
├── configuration.yaml          ← MQTT, input helpers, Ollama rest_command
├── automations.yaml            ← moisture irrigation, rain block, battery alerts, LLM summary
├── blueprints/automation/      ← irrigation_zone.yaml (one instance per zone)
├── zigbee2mqtt/
│   └── configuration.yaml      ← Zigbee2MQTT addon config
└── www/admin.html              ← Zone management UI (served at /local/admin.html)

Kindle: wget port 10000 → eips (every 90 s)
```

**Why Proxmox instead of bare metal HA OS:**
- Proxmox snapshots = instant HA backups before risky config changes
- Leaves room for future VMs/LXCs (Frigate, NAS, etc.) on the same box
- HA OS VM is fully supported and behaves identically to bare metal
- USB dongle passthrough to a VM is rock-solid via Proxmox host configuration

**What was removed vs the docker-compose version:**
- `docker-compose.yml` → archived as `docker-compose.alternative.yml`
- `mosquitto/` → handled by the Mosquitto addon
- `nginx/` → not needed; HA OS serves `/config/www/` at `/local/`
- `zigbee2mqtt/` (root) → config lives at `homeassistant/zigbee2mqtt/`

## Devices

| Item | AliExpress ID | Z2M Model |
|------|--------------|-----------|
| Soil moisture sensor | 1005011801061136 | Tuya TS0601_soil |
| Water valve | 1005009336429185 | Tuya TS0601_water_valve |

## Hardware

**Soyo M4 Air** (Intel N95, 16 GB RAM, 512 GB SSD)

| Component | Value |
|---|---|
| CPU | Intel N95 (4× E-core, 3.4 GHz boost, 15 W TDP) |
| RAM | 16 GB DDR4/DDR5 |
| iGPU | Intel UHD (16 EU, VA-API, OpenCL 3.0) |
| Ollama model | `qwen2.5:1.5b` — 8–20 tok/s, ~2.5 GB RAM, 200-token summary in ~10–25 s |

The LLM summary runs once per hour in the background (~20 s at ~80% CPU, then fully idle).

---

## Quick Start — Proxmox + HA OS VM

### 1. Install Proxmox VE

1. Download the **Proxmox VE ISO** from [proxmox.com/downloads](https://www.proxmox.com/en/downloads)
2. Flash to a USB stick: `dd if=proxmox-ve_*.iso of=/dev/sdX bs=4M status=progress`
3. Boot the Soyo M4 Air from the USB, complete the installer
   - Target disk: your 512 GB SSD
   - Set a static IP or note the DHCP address shown at the end
4. Open the Proxmox web UI at `https://PROXMOX_IP:8006` (accept the self-signed cert)

> **Tip:** After first login, dismiss the "no valid subscription" nag with
> `sed -i 's/data.status !== .Active./false/' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js`
> then refresh the browser.

### 2. Create the HA OS VM (one command)

SSH into the Proxmox host and run the community helper script:

```bash
bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/vm/haos-vm.sh)"
```

Accept the defaults (or customise RAM/disk when prompted). The script:
- Downloads the latest `haos_generic-x86-64.qcow2`
- Creates VM 100 with UEFI boot, VirtIO disk, and the image pre-loaded
- Starts the VM automatically

> Manual alternative: download `haos_generic-x86-64.qcow2.xz` from the
> [HA releases page](https://github.com/home-assistant/operating-system/releases),
> import it, and configure the VM yourself (UEFI, q35 machine type, VirtIO SCSI).

### 3. Pass the Zigbee USB dongle through to the VM

Plug in the Zigbee USB coordinator (e.g. SONOFF Zigbee 3.0 USB Dongle), then on the Proxmox host:

```bash
# Find the dongle's vendor:product ID
lsusb
# e.g. "Bus 001 Device 003: ID 10c4:ea60 Silicon Labs CP210x UART Bridge"

# Pass it to VM 100 (replace vendorid/productid)
qm set 100 --usb0 host=10c4:ea60
```

Or via the web UI: **VM 100 → Hardware → Add → USB Device** → select the dongle by vendor/device ID.

The dongle will appear inside the HA OS VM as `/dev/ttyUSB0` — no driver installation needed.

### 4. Complete HA onboarding

Wait ~3 minutes for first boot, then open `http://homeassistant.local:8123` and create your Home Assistant account.

> If `homeassistant.local` doesn't resolve, use the IP shown in the Proxmox VM console
> (VM 100 → Console).

### 5. Add community addon repositories

HA → Settings → Add-ons → Add-on Store → ⋮ menu → **Repositories** → add:

| Addon | Repository URL |
|---|---|
| Ollama | `https://github.com/alexbelgium/hassio-addons` |
| NetBird | `https://github.com/netbirdio/addon-netbird` |

> **Mosquitto**, **Zigbee2MQTT**, and **File editor** are in the default store.

### 6. Install and configure addons

Install and start each in order:

| Addon | Key config |
|---|---|
| **Mosquitto Broker** | Create users `homeassistant` and `zigbee2mqtt` in the *Logins* section with strong passwords |
| **Zigbee2MQTT** | Auto-reads `/config/zigbee2mqtt/configuration.yaml` — no extra config needed |
| **puppet** | `access_token`: long-lived token (step 8); `home_assistant_url`: `http://localhost:8123`; `keep_browser_open`: true |
| **Ollama** | Default settings; pull model after install (step 10) |
| **NetBird** | `admin_url`: your self-hosted management URL; `management_url`: your API URL; `setup_key`: from NetBird dashboard |

### 7. Copy this repo's config into HA

```bash
# From a machine on the same LAN
scp -r homeassistant/* root@homeassistant.local:/config/
```

Or use the **File editor** addon to upload/paste files individually.

### 8. Edit secrets

Open `/config/secrets.yaml` and fill in real passwords:

```yaml
mqtt_user: "homeassistant"
mqtt_password: "YOUR_STRONG_MQTT_PASSWORD"   # must match Mosquitto addon Logins
z2m_mqtt_password: "YOUR_Z2M_MQTT_PASSWORD"  # must match zigbee2mqtt user in Mosquitto
```

### 9. Generate a long-lived HA token

HA → Profile (bottom-left avatar) → Security → Long-Lived Access Tokens → **Create Token** → copy it.

You'll need this token for:
- The **puppet** addon config (`access_token`)
- The admin UI at `/local/admin.html` (paste once in the browser — stored in localStorage)

### 10. Restart Home Assistant

HA → Settings → System → **Restart** → Restart Home Assistant.

After restart: all automations load, Zigbee2MQTT connects, Ollama starts.

### 11. Pull the Ollama model

```bash
curl http://homeassistant.local:11434/api/pull \
  -d '{"name":"qwen2.5:1.5b"}'
```

Wait for the ~1 GB download. The first hourly summary runs at the next top of the hour.

### 12. Pair Zigbee devices

Open `http://homeassistant.local:8080` (Zigbee2MQTT UI):
1. Click **Permit join**
2. Hold the pairing button on each device until the LED blinks
3. Set a friendly name (e.g. `zone1_soil`, `zone1_valve`)
4. Turn **Permit join off** when done
5. Set `permit_join: false` in `/config/zigbee2mqtt/configuration.yaml` → restart the Z2M addon

### 13. Assign zones

Open `http://homeassistant.local:8123/local/admin.html`:
1. Paste your long-lived token and click **Save**
2. Select soil sensor + valve from the dropdowns (auto-populated from HA entity discovery)
3. Enter zone name and moisture threshold (default 30%)
4. Click **Add Zone**

Repeat for each irrigation zone.

### 14. Create the Kindle dashboard in HA

HA → Settings → Dashboards → **Add Dashboard**:
- Name: `Kindle`
- URL path: `kindle`

Add cards for each zone's entities (soil moisture gauge, valve switch, battery level, rain boolean). Use a high-contrast theme for best e-ink readability.

### 15. Set up Kindle

Edit `kindle/update.sh` and set `SERVER_IP` to your HA VM's LAN IP, then:

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
| Proxmox web UI | 8006 | Hypervisor management (HTTPS) |
| Home Assistant | 8123 | Main UI + REST API |
| Zigbee2MQTT | 8080 | Device pairing + MQTT debug |
| Mosquitto | 1883 | MQTT broker — VM-local only (NetBird for remote access) |
| puppet | 10000 | On-demand HA dashboard screenshots for Kindle |
| Ollama | 11434 | LLM inference (VM-local only) |

---

## Proxmox Tips

### Snapshots (before risky changes)

```bash
# On the Proxmox host — snapshot VM 100 before a major HA update
qm snapshot 100 pre-ha-update --description "Before HA $(date +%Y-%m-%d) update"

# Roll back if something breaks
qm rollback 100 pre-ha-update
```

Or use the web UI: **VM 100 → Snapshots → Take Snapshot**.

### Recommended VM resource allocation

| Resource | Value | Notes |
|---|---|---|
| RAM | 4 GB | Enough for HA + Ollama `qwen2.5:1.5b` (~2.5 GB) + addons |
| vCPUs | 3 | Leave 1 core for Proxmox host |
| Disk | 64 GB | HA OS default is 32 GB; 64 GB gives room for history + backups |
| Machine type | q35 | Required for UEFI; default from tteck script |

### Future expansion on the same host

```
Proxmox VE (bare metal)
├── VM 100: HA OS          (4 GB RAM)
├── LXC 101: Frigate NVR   (2 GB RAM + Intel iGPU VA-API passthrough)
└── LXC 102: misc services (512 MB RAM)
```

The N95's Intel UHD iGPU can be shared between the host and LXCs via GVT-d or VA-API device passthrough — useful for Frigate object detection without impacting HA.

---

## NetBird

With the NetBird addon running inside the HA VM, all your NetBird peers can reach the VM on its NetBird IP — including Mosquitto (1883) and the HA UI (8123) — without any public port forwards or router NAT rules. WireGuard encrypts the traffic end-to-end so no TLS cert is needed for MQTT.

Remote soil sensors or clients connect by installing the NetBird client and joining the same network.

---

## Verification

```bash
# Test puppet screenshot
curl "http://homeassistant.local:10000/?url=/lovelace/kindle&viewport=600x800" -o test.png
file test.png   # PNG image data, 600 x 800

# Test HA API
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://homeassistant.local:8123/api/states/input_boolean.rain_detected

# Trigger LLM summary manually
# HA → Developer Tools → Actions → automation.trigger → irrigation_llm_summary
# Then: Developer Tools → States → input_text.irrigation_summary

# Proxmox: verify VM is running
qm status 100
```

---

## Alternative: Docker Compose

If you want to run this stack without Proxmox/HA OS (e.g. on a generic Ubuntu server), see [`docker-compose.alternative.yml`](docker-compose.alternative.yml).
