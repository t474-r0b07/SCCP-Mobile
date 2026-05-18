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

> `// built to watch. designed to detect evasion.`

---

```bash
$ cat /etc/mission
> Home arrest monitoring · subject surveillance
> Evasion detection · cognitive forensics
> Real-time alerting · zero tolerance anomaly

$ cat /status
> ACTIVE MONITORING  [■■■■■■■■■■] 100%
> BACKEND SYNC       [■■■■■■■■░░]  85%
> BATTERY OPT        [■■■■■■■░░░]  70%
```

---

## `> ./about.sh`

This is **NOT** a general field app.

This is the **heavy armor** of the SCCP ecosystem.  
One device. One subject. 24/7.  
Every anomaly — voice, GPS, geofence, metadata — gets caught.

Built from the dev side.  
Hardened from the other side.

---

## `> cat what_this_does.txt`

```
NOT: General officer tracking — see DTEX Custodio for that.
YES: Subject evasion detection.

[VOICE LAYER]
  Biometric voice recognition
  Wrong person detected → ALERT_IMPERSONATION

[GPS LAYER]
  Dual validation: device GPS + network triangulation
  Spoofing · mock location · position jump → ALERT_SPOOFING

[GEOFENCE LAYER]
  Hardcoded home coordinates ± radius
  Perimeter crossed → ALERT_ESCAPE

[TELEMETRY LAYER]
  Battery · connectivity · last sync
  Sudden shutdown · VPN · root → ALERT_DEVICE_COMPROMISE

[BEHAVIORAL LAYER]
  Movement speed · frequency · timing
  60km/h across 2 blocks → ALERT_IMPLAUSIBLE_MOVEMENT
```

---

## `> cat stack.txt`

```
FRAMEWORK     Flutter · Dart
ARCHITECTURE  Clean Architecture
STATE         GetX (reactive)
BACKEND       Supabase — shared instance with SCCP-DTEX
AUTH          Biometric lock + Supabase Auth
REALTIME      Supabase Realtime · WebSocket
STORAGE       Encrypted Hive (AES)
SECURITY      Play Integrity · voice biometrics · geofencing
```

---

## `> cat threat_model.txt`

```
ATTACK VECTOR      MITIGATION
──────────────     ───────────────────────────────────────
GPS spoofing    →  Mock location API detection
                   Velocity analysis (is 60km/h possible?)
                   Dual source validation
                   → Caught in <100ms

Biometric       →  Voice mismatch detection
tampering          Repeated failures → escalation
                   → Impersonation caught immediately

Device          →  Root detection (SafetyNet / Play Integrity)
compromise         VPN detection (interface fingerprinting)
                   Emulator detection (device profiling)
                   → Caught at startup

Geofence        →  Continuous boundary monitoring
breach             Grace period: 0 seconds
                   → Escape alerted in real-time

Data            →  TLS pinning to Supabase
integrity          Token rotation every 15min
                   → Forensic chain maintained
```

> *Most apps are built to work.*  
> *This one was built assuming someone will try to break it.*

---

## `> cat ecosystem_context.txt`

```
SCCP COMMAND CENTER (DTEX)
├─ WebApp dashboard (tactical HUD)
├─ Custodio Android (officer tracking · field missions)
├─ Supervisor Android (mobile command · coordination)
└─ → github.com/t474-r0b07/SCCP-DTEX

SCCP MOBILE (THIS REPO)
├─ Subject evasion detection
├─ Home arrest monitoring · 24/7
├─ Shared backend with DTEX
└─ → github.com/t474-r0b07/SCCP-Mobile

INFRASTRUCTURE: UNIFIED
  Same Supabase instance · same realtime subscriptions
  Same audit trail · different business logic

ALERT ROUTING
  Officer anomaly (DTEX)   → OPERATIONAL ALERT
  Subject breach (Mobile)  → CRITICAL ALERT
  All → Command Center WebApp
```

---

## `> cat /var/log/design_decisions.log`

> **Why Flutter?**  
> One codebase shared with the command WebApp.  
> Officer and commander run the same logic. No drift.

> **Why offline-first?**  
> A field app that dies without signal is a liability.  
> Queue locally. Sync when possible. Never lose an event.

> **Why threat modeling on a mobile app?**  
> Because the weakest point of a command platform  
> is the device in the field officer's pocket.

---

## `> ./demo.sh`

```
[⏳] field demo · coming soon
     unlisted · YouTube · t474-r0b07
```

---

## `> cat /etc/author_signature`

```
built by t474-r0b07
one operator on this stack
not a product pitch — this repo is the evidence
the repo is the challenge
```

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
