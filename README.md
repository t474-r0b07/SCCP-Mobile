```
███████╗ ██████╗ ██████╗██████╗ 
██╔════╝██╔════╝██╔════╝██╔══██╗
███████╗██║     ██║     ██████╔╝
╚════██║██║     ██║     ██╔═══╝ 
███████║╚██████╗╚██████╗██║     
╚══════╝ ╚═════╝ ╚═════╝╚═╝     

      M · O · B · I · L · E
      
       [SPECIALIZED ARMOR]
```

> **Sistema de Control Policial — Custodia Domiciliaria**  
> `// built to watch. designed to detect evasion.`

---

```bash
$ whoami
> guardian of compliance · Flutter · Android

$ cat /etc/mission
> 24/7 monitoring · subject surveillance
> evasion detection · cognitive forensics
> real-time alerting · zero tolerance anomaly

$ cat /status
> ACTIVE MONITORING [■■■■■■■■■■] 100%
> BACKEND SYNC [■■■■■■■■░░] 85%
> BATTERY OPTIMIZATION [■■■■■■■░░░] 70%
```

---

## `> ./about.sh`

This is **NOT** a general field app.

This is the **heavy armor** of the SCCP ecosystem.  
It runs on ONE device. Watches ONE subject. 24/7.  
Detects every anomaly: voice, GPS fakery, geofence breach, metadata corruption.

Part of SCCP. Part of the broader platform.  
But specialized for one mission: **evasion prevention**.

Built from the dev side — hardened with the hunter's mindset.

---

## `> cat deployment_context.txt`

```
PART OF: SCCP Ecosystem
ROLE:    Specialized surveillance · home arrest monitoring
SCOPE:   Permanent 24/7 watch on ONE subject
TARGET:  Person under house arrest / electronic ankle alternative
PARENT:  github.com/t474-r0b07/SCCP-DTEX (command center)
STATUS:  Operational · ~4 weeks production
```

---

## `> cat what_this_does.txt`

```
NOT: General officer tracking (see DTEX Custodio for that)
YES: Subject evasion detection

LAYERS OF DETECTION

[VOICE LAYER]
  • Biometric voice recognition
  • Confirms: is this the right person?
  • Triggers: voice mismatch = ALERT_IMPERSONATION

[GPS LAYER]
  • Dual validation: device GPS + network triangulation
  • Detects: spoofing, mock location, position jumping
  • Triggers: GPS anomaly = ALERT_SPOOFING

[GEOFENCE LAYER]
  • Hardcoded home coordinates ± radius
  • Real-time boundary monitoring
  • Triggers: crossing perimeter = ALERT_ESCAPE

[TELEMETRY LAYER]
  • Metadata: battery, connectivity, last sync
  • Anomaly: sudden shutdown, VPN activation, root detection
  • Triggers: tampering = ALERT_DEVICE_COMPROMISE

[BEHAVIORAL LAYER]
  • Patterns: movement speed, frequency, timing
  • Anomaly: 60km/h in 2 blocks = impossible
  • Triggers: physics violation = ALERT_IMPLAUSIBLE_MOVEMENT
```

---

## `> cat security_features.txt`

```
WHAT WE DETECT

GPS Spoofing
  ✓ Mock location API detection
  ✓ Position velocity analysis (is 60km physically possible?)
  ✓ Dual source validation (device + network triangulation)
  → Evasion attempt caught in <100ms

Biometric Tampering
  ✓ Voice mismatch detection (not the enrolled subject)
  ✓ Repeated failures → escalation
  → Impersonation caught immediately

Device Compromise
  ✓ Root detection (SafetyNet / Play Integrity)
  ✓ VPN detection (interface fingerprinting)
  ✓ Emulator detection (device profiling)
  → Manipulation attempt caught at startup

Geofence Breach
  ✓ Continuous boundary monitoring
  ✓ Grace period: 0 seconds
  ✓ Alert → command center → police dispatch
  → Escape attempt alerted in real-time

Data Exfiltration
  ✓ Encrypted local storage (Hive + AES)
  ✓ TLS pinning to Supabase
  ✓ Token rotation every 15min
  → Forensic integrity maintained

WHAT WE DON'T ACCEPT

• Mock locations
• Root access
• VPN tunneling
• Biometric forgery
• Geofence crossing
• Device tampering
```

---

## `> cat stack.txt`

| Layer | Technology |
|---|---|
| Framework | Flutter · Dart |
| Architecture | Clean Architecture |
| State management | GetX (reactive) |
| Backend | **Supabase (shared with SCCP-DTEX)** |
| Auth | Biometric lock + Supabase Auth |
| Realtime | Supabase Realtime · WebSocket |
| Local storage | Encrypted Hive database |
| Security | Play Integrity · voice biometrics · geofencing |

---

## `> cat ecosystem_context.txt`

```
PART OF THE SCCP UNIVERSE

SCCP COMMAND CENTER (DTEX)
├─ WebApp dashboard (tactical HUD)
├─ Custodio Android (officer tracking · temp missions)
├─ Supervisor Android (command mobile · coordination)
└─ → github.com/t474-r0b07/SCCP-DTEX

SCCP MOBILE (THIS REPO)
├─ Subject evasion detection
├─ Home arrest monitoring · 24/7 surveillance
├─ Shared backend with DTEX
└─ → github.com/t474-r0b07/SCCP-Mobile

INFRASTRUCTURE: UNIFIED
  • Same Supabase instance
  • Same realtime subscriptions
  • Same audit trail
  • Different business logic (different use cases)

ALERT ROUTING: UNIFIED
  Officer pauses traffic (DTEX)     → OPERATIONAL ALERT
  Subject crosses boundary (Mobile) → CRITICAL ALERT
  All → Command center WebApp
```

---

## `> cat /etc/author_signature`

```
> built by t474-r0b07
> one operator on this stack
> not a product pitch
> this repo is the evidence
> the repo is the challenge
```

> pistas y easter eggs no son accidente. si llegaste hasta aquí, ya entiendes quién está detrás.

---

## `> cat /etc/test_coverage`

```
> tests unitarios disponibles en:
>   - test/core/utils
>   - test/data/services/voice_biometric_service_test.dart
> exactitud operativa validada en lógica de permisos y background.
```

---

## `> cat /var/log/design_decisions.log`

> **Why Flutter for a field app?**  
> One codebase shared with the command WebApp.  
> The officer and the commander run the same logic. No drift.

> **Why offline-first?**  
> A field app that dies without signal is a liability.  
> Queue locally. Sync when possible. Never lose an event.

> **Why threat modeling on a mobile app?**  
> Because the weakest point of a command platform  
> is the device in the field officer's pocket.

---

## `> cat threat_model.txt`

```
ATTACK VECTOR          MITIGATION
────────────────────────────────────────────────────────
GPS spoofing           Android mock location API detection
Root access            SafetyNet / Play Integrity API
VPN / proxy use        active network interface check
Replay attacks         token rotation + request timestamps
Tampered APK           build integrity check on launch
Session fixation       server-side invalidation · short TTL
```

> *Most apps are built to work.*  
> *This one was built assuming someone will try to break it.*

---

## `> ./demo.sh`

```
[⏳] field demo · coming soon
     unlisted · YouTube · t474-r0b07
```

---

## `> cat changelog.log`

> Full release history → [`SCCP CHANGELOG`](https://github.com/t474-r0b07/SCCP/blob/main/CHANGELOG_PUBLIC.md)

---

## `> ls -la ../`

> Full platform: [`SCCP Command Center`](https://github.com/t474-r0b07/sccp)  
> Includes WebApp · Backend · Architecture docs

---

> `[!]` · [`signal detected`](./CHALLENGE.md) · origin unknown

---

```
████████████████████████████████████████████████████
█                                                  █
█   T A C T I C A L   A W A R E N E S S           █
█             I S   N O T   O P T I O N A L       █
█                                                  █
████████████████████████████████████████████████████
```

---

## `> cat /etc/license`

```
© t474-r0b07 · All Rights Reserved
This code is not open source.
Viewing ≠ permission to use, copy, or distribute.
```

---

<!--
  ┌─────────────────────────────────────────────────────┐
  │  [DECLASSIFIED] · DOD · 1995                        │
  │  PROJECT 621B — NAVSTAR GPS                         │
  ├─────────────────────────────────────────────────────┤
  │                                                     │
  │  Originally designed to guide nuclear warheads.     │
  │  Declassified for civilian use: 1983.               │
  │  Selective Availability disabled: May 1, 2000.      │
  │                                                     │
  │  The same system that tracks ICBMs                  │
  │  now tracks your delivery driver.                   │
  │                                                     │
  │  >> https://www.gps.gov/systems/gps/history/        │
  │                                                     │
  └─────────────────────────────────────────────────────┘
-->
