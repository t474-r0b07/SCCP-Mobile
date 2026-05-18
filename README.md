```
███████╗ ██████╗ ██████╗██████╗ 
██╔════╝██╔════╝██╔════╝██╔══██╗
███████╗██║     ██║     ██████╔╝
╚════██║██║     ██║     ██╔═══╝ 
███████║╚██████╗╚██████╗██║     
╚══════╝ ╚═════╝ ╚═════╝╚═╝     
```
> **Sistema de Control y Comando Policial — Mobile**  
> `// built to protect. designed to detect.`

---

```bash
$ whoami
> tactical field application · Flutter · Android

$ cat /etc/mission
> real-time unit coordination
> threat detection at the edge
> offline resilience · sync on reconnect

$ uptime
> [■■■■■■■■■░] hardened. always on.
```

---

## `> ./about.sh`

This is the field unit of the SCCP platform.  
It runs on the officer's device. It tracks. It reports. It resists.  
Built from the dev side — hardened with the attacker's mindset.

---

## `> cat features.txt`

```
FIELD OPERATIONS
  [✓] Real-time GPS reporting          continuous ping · < 1s
  [✓] Incident reporting               structured · timestamped
  [✓] Push notifications               server-driven alerts
  [✓] Offline mode                     local queue · auto-sync
  [✓] Background services              persistent · battery-aware

SECURITY LAYER
  [✗] GPS spoofing                     mock location detection
  [✗] Root access                      Play Integrity check
  [✗] VPN / proxy tunneling            interface fingerprinting
  [✗] Session hijacking                token rotation
  [✗] Tampered builds                  integrity verification
```

---

## `> ls -la /stack`

| Layer | Technology |
|---|---|
| Framework | Flutter · Dart |
| Architecture | Clean Architecture |
| State management | BLoC |
| Backend | Supabase (shared platform) |
| Auth | Supabase Auth + biometric lock |
| Realtime | Supabase Realtime · WebSocket |
| Local storage | Hive · offline queue |
| Security | Play Integrity · mock location detection · VPN fingerprinting |

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
