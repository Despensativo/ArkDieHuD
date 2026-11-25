<p align="center">
  <strong>English</strong> | <a href="TUTORIAL.pt-BR.md">Português (BR)</a> | <a href="TUTORIAL.es.md">Español</a>
</p>

# ArkDieHuD — Complete Step-by-Step Tutorial

Welcome to **ArkDieHuD**. This guide walks you through installing the app (even with a **free Apple ID**), configuring the floating **Picture-in-Picture (`PiP`)** overlay, diagnosing network drops with **Dual-Probe (`ICMP + UDP + TCP`)**, viewing the **24-hour SQLite history**, and running the **PC/Mac Live Web Monitor (`:8787`)** cleanly over games.

---

## 1. Requirements & Free Apple ID Installation

- **Device:** iPad or iPhone running **iPadOS 17+ / iOS 17+** (Apple Silicon recommended for full CPU/GPU die thermals).
- **Developer Mode:** Required on iPadOS to run sideloaded or Xcode-signed builds.

### Enable Developer Mode on iPad
1. Open **Settings → Privacy & Security → Developer Mode**.
2. Toggle **Developer Mode** ON, restart your iPad when prompted, and confirm after reboot.
   *(If Developer Mode does not appear yet, plug your iPad into a Mac/PC running Xcode or Sideloadly once — iPadOS reveals it automatically.)*

### Option A: Install Pre-Built `.ipa` with Sideloadly / AltStore / SideStore (No Xcode Needed)
1. Download `ArkDieHuD-unsigned.ipa` from the **[GitHub Releases](https://github.com/Despensativo/ArkDieHuD/releases)** page.
2. Open **Sideloadly** (Windows/Mac) or **AltStore / SideStore**.
3. Connect your iPad, enter your **free Apple ID**, and drop `ArkDieHuD-unsigned.ipa` to install.
4. On the iPad, go to **Settings → General → VPN & Device Management**, tap your Apple ID profile, and tap **Trust**.

### Option B: Build from Source with Xcode (Free Personal Team)
1. Clone the repo and optionally create `Examples/Config/LocalSigning.xcconfig` (ignored by Git):
   ```xcconfig
   DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.yourname.ArkDieHuD
   ```
   Or build an unsigned `.ipa` from Terminal:
   ```bash
   ./Scripts/export-ipa.sh
   # Output: dist/ArkDieHuD-unsigned.ipa
   ```
2. Open `Examples/SwiftSensorsApp.xcodeproj`, pick your iPad target, and press **Cmd + R**.

---

## 2. Floating PiP HUD & Custom Metrics

1. Open **ArkDieHuD** on your iPad.
2. In the **Floating HUD (PiP)** card, choose your **HUD Layout**:
   - **Gamer Bar (1 Transparent Line):** Ultra-slim horizontal bar ideal for top/bottom screen edges during PUBG, CODM, Genshin, etc.
   - **Gamer Overlay (2 Lines):** Splits Hardware on line 1 and Network on line 2.
   - **Compact Grid:** Mini cards with color thresholds and fill bars.
   - **Detailed:** Full telemetry cards + live ranking of hottest thermal sensors.
3. Tap **Customize Metrics** to pick any subset of the **12 metrics** (`CPU °C`, `GPU °C`, `CPU Load`, `RAM`, `Watts`, `Battery`, `Thermal State`, `Ping`, `UDP 53`, `Router`, `Jitter`, `Packet Loss`) or pick a 1-tap preset (*Gamer*, *Competitive Net*, *Ultra Minimal*, *Show All*).
4. Tap **Overlay on Screen (PiP)**, then switch to your game. Drag the HUD pill to any corner or pinch to resize it.
   *(Tip: **Slide Over Mode** lets you keep a full telemetry drawer accessible by swiping from the right edge of the screen.)*

---

## 3. Competitive Network Diagnostics (Dual-Probe + Multi-Protocol)

Tap **Network & Packet Log** (or the **Ping / Packet Loss** tile) to open the full network analyzer.

### How to Read Dual-Probe Results
- **Simultaneous Mode (`ICMP + UDP + TCP`)** probes your external server over three protocols at **1 Hz**, **in parallel with your Local Router (Gateway)**:
  - **Both Local Router & External Target drop:** Problem is your **Wi-Fi signal or local router**.
  - **Local Router stays ~1–3 ms (`0%` loss) while External Target drops:** Problem is your **ISP route, CGNAT, or VPN**.
  - **Only UDP (`:53`) drops while ICMP/TCP remain stable:** Sign of **UDP NAT/CGNAT congestion or QoS throttling** (directly causes rubberbanding in UDP games like PUBG).
  - **Only ICMP drops while UDP/TCP stay stable:** Server simply rate-limits ICMP ping; actual gameplay traffic is fine.
- **Cycle Detector:** Tracks the interval (`Δ +93s`, etc.) between drops to spot periodic ISP micro-disconnections.
- **Export:** Tap the Share icon in the top bar to save a raw chronological `.csv` report.

---

## 4. 24-Hour SQLite History & Unified CSV

1. Make sure **Record telemetry logs (24h)** is enabled in the main card.
2. Open **24h Telemetry & Logs** to switch between **15m | 1h | 6h | 24h** windows across **Thermal**, **Power & RAM**, and **Network**.
3. Data is flushed to **SQLite WAL** every 15 seconds (and immediately when backgrounding) and entries older than 24h are pruned automatically.
4. Tap **Export CSV** to share a unified second-by-second spreadsheet containing both hardware sensors and network telemetry.

---

## 5. PC / Mac Live Monitor (`:8787`) & Stealth PiP

Want to see CPU/GPU thermals, Watts, latency charts, and packet drops on a second monitor (**PC / Mac / Laptop**) while keeping your iPad screen **completely clear**?

1. On your iPad inside **ArkDieHuD**, toggle ON **Monitor on PC/Mac (no screen PiP)**.
2. **Option 1 — Over Wi-Fi (Same Network):**
   Open `http://<IPAD_IP>:8787` (shown right inside the card with a **Copy URL** button) in any desktop/mobile browser.
3. **Option 2 — Over USB Cable (Zero Wi-Fi Dependency):**
   ```bash
   brew install libimobiledevice   # Mac (one-time)
   iproxy 8787 8787
   ```
   Then open **`http://127.0.0.1:8787`** on your Mac/PC browser.

### Stealth PiP Mode (Recommended When Using In-Game Mic / Voice Chat)
iPadOS aggressively suspends background apps if another app captures the microphone (like PUBG Voice Chat) and no active PiP window is present. To prevent suspension without blocking your view:
1. Keep **Stealth PiP (hide at screen edge)** enabled.
2. Tap **Overlay on Screen (PiP)** — a tiny `268×44` pill (`● ARKDIEHUD • PC | ... | Drag to edge to hide & stay active`) appears.
3. **Drag the pill past the left or right edge of the iPad screen** until it tucks away cleanly off-screen.
4. Your game screen stays 100% unobstructed, your in-game mic works normally, and your PC/Mac `:8787` dashboard + 24h SQLite logger stay alive with auto-recovery on audio interruptions!

---

## 6. Bonus: Live FPS on ANY Game or App with Apple Metal Performance HUD

Combine **ArkDieHuD** with Apple's native GPU FPS counter (`MTL_HUD_ENABLED=1`) using `./launch_metal_hud.sh` on your Mac — it works with **any** installed game or app, not only built-in examples:

1. **Interactive Menu (Zero Setup):**
   ```bash
   ./launch_metal_hud.sh
   ```
   Lists every user app on your iPad; just type its number and press Enter.

2. **Quick Search by Name:**
   ```bash
   ./launch_metal_hud.sh genshin     # Finds and launches Genshin Impact
   ./launch_metal_hud.sh cod         # Finds and launches Call of Duty Mobile
   ./launch_metal_hud.sh capcut      # Works on creative/video apps too
   ```

3. **Find Exact Bundle ID & Launch Directly:**
   ```bash
   ./launch_metal_hud.sh --list
   ./launch_metal_hud.sh --bundle com.example.yourgame
   ```

4. **Save Your Own 1-Word Shortcuts (Manually or Using an AI Assistant):**
   Open `launch_metal_hud.sh` and add your favorite games to `CUSTOM_SHORTCUTS`:
   ```python
   CUSTOM_SHORTCUTS = {
       "genshin": ("Genshin Impact", "com.miHoYo.GenshinImpact"),
       # ...
   }
   ```
   > **Using an AI coding assistant?** Paste this prompt:
   > *"Run `./launch_metal_hud.sh --list`, find my installed games/apps, and add 1-word shortcuts for them into `CUSTOM_SHORTCUTS` inside `launch_metal_hud.sh`."*

See [METAL_HUD_GUIDE.md](METAL_HUD_GUIDE.md) for device pairing troubleshooting.

---

## 7. Automatic 3-Language Support (`EN` / `PT-BR` / `ES`)

- **iPad App & PiP:** Automatically follows your iPadOS system language (**English**, **Portuguese BR**, or **Spanish**). To force a specific language just for ArkDieHuD on iPadOS, open **Settings → ArkDieHuD → Language**.
- **PC/Mac Web Dashboard (`:8787`):** Automatically detects your browser's language (`navigator.language`) and includes a quick **`EN | PT | ES`** switcher in the top toolbar.
