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
> Monitoreo móvil especializado
> GPS · geofencing · partes · alertas · radio
> Servicios en segundo plano · telemetría operativa

$ cat /status
> PUBLIC STATE        [ DEVELOPMENT / TESTING ]
> BACKEND             [ SUPABASE ]
> PLATFORM            [ ANDROID ]
```

---

## `> ./about.sh`

This is **NOT** a general field app.

This is the mobile monitoring surface of the SCCP ecosystem.  
The current implementation combines GPS, geofencing, operational reports, alerts, radio and background services.

Built from the dev side.  
Hardened from the other side.

---

## `> cat what_this_does.txt`

```
NOT: General officer tracking — see DTEX Custodio for that.
YES: Subject evasion detection.

[VOICE LAYER]
  Voice profile + biometric verification via Supabase RPC
  Verification failure → operational rejection

[GPS LAYER]
  GPS validation
  Location permissions · movement data · operational telemetry

[GEOFENCE LAYER]
  Hardcoded home coordinates ± radius
  Perimeter crossed → ALERT_ESCAPE

[TELEMETRY LAYER]
  Battery · connectivity · last sync
  Background service health and operational state

[BEHAVIORAL LAYER]
  Movement and operational telemetry
  Anomalies can be recorded as inconsistencies
```

---

## `> cat stack.txt`

```
FRAMEWORK     Flutter · Dart
ARCHITECTURE  Presentation · Data · Core
STATE         Provider
BACKEND       Supabase — shared ecosystem with SCCP-DTEX
REALTIME      Supabase Realtime
STORAGE       SharedPreferences + Flutter Secure Storage
SECURITY      Permission checks · device binding · voice RPC · geofencing
```

---

## `> cat threat_model.txt`

```
ATTACK VECTOR      MITIGATION
──────────────     ───────────────────────────────────────
GPS spoofing    →  Mock location API detection
                   Velocity analysis (is 60km/h possible?)
                   Dual source validation
                   → Recorded as an operational anomaly

Biometric       →  Voice mismatch detection
tampering          Repeated failures → escalation
                   → Impersonation caught immediately

Device          →  Device binding and operational session checks
compromise         Background-service health checks
                   → Operational state can be rejected or closed

Geofence        →  Continuous boundary monitoring
breach             Grace period: 0 seconds
                   → Escape alerted in real-time

Data            →  Supabase access + RPC validation
integrity          Local sensitive data uses secure storage
                   → Audit and operational records are persisted server-side
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
     unlisted · YouTube · Tata Robot
```

---

## `> cat /etc/author_signature`

```
built by Tata Robot · GitHub: t474-r0b07
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
