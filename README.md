# NavMRT

NavMRT is a **blind-first indoor navigation iOS application** designed to assist visually impaired passengers in MRT stations.  
It uses **Bluetooth iBeacons**, **RSSI fingerprinting**, and **voice-first UX** to provide turn-by-turn indoor guidance.

This project focuses on **accessibility, robustness, and real-world deployability**, rather than visual maps.

## 🎯 Project Goals

- Enable **independent indoor navigation** for visually impaired users
- Provide **voice-first, VoiceOver-optimized UX**
- Support **multi-floor navigation** (elevators / stairs)
- Detect **off-route behavior** and recover automatically
- Be deployable with **real beacon hardware**

## ✨ Key Features

### Navigation & Positioning
- RSSI fingerprinting with **KNN positioning**
- Exponential Moving Average (EMA) RSSI smoothing
- Graph-based routing (shortest path)
- Turn-by-turn instructions (left / right / straight / U-turn)
- Arrival detection with haptics + voice feedback

### Accessibility (Blind-first UX)
- VoiceOver-first screen focus
- Auto-start navigation option
- Spoken route summaries
- Clear, non-spammy audio prompts
- Large, simple control layout

### Robustness
- Off-route detection using geometric distance to path
- Automatic re-routing from nearest node
- Floor change handling with elevator / stairs announcements
- Navigation pause during floor transitions

### Beacon Support
- Mock beacon manager for simulator & development
- Real iBeacon integration via CoreLocation
- RSSI Console for live signal debugging
- Strict ID consistency (`UUID:major:minor`) across pipeline

## 🚦 Current Status

- ✅ End-to-end navigation pipeline implemented
- ✅ Mock beacon testing complete
- ✅ Real beacon integration ready
- 🔬 Actively extending and refining (research prototype)

## 🔮 Future Work

- Floor-specific beacon filtering
- In-app fingerprint collection mode
- Background navigation support
- User studies & on-site MRT deployment
- Energy optimization & signal stabilization

```mermaid
flowchart TD
  A["App Launch"] --> B["SwiftUI App Entry<br/>NavMRTApp.swift"]
  B --> C["Start & Goal Selection UI<br/>startId / goalId"]
  C --> D["NavigatorView"]

  %% Static data
  D --> E["Load Static Data<br/>DataStore.shared<br/>graph / fingerprints / beacons / places"]

  %% Routing
  D --> F["Route Planning<br/>GraphRouter.shortestPath"]

  %% Beacon acquisition
  D --> G{Beacon Source}
  G -->|Mock| H["MockBeaconManager<br/>Timer → BeaconReading"]
  G -->|Real| I["BeaconManager<br/>CoreLocation ranging<br/>merged + rate-limited publish"]

  H --> J["Beacon Readings"]
  I --> J

  %% Signal processing
  J --> K["Rolling RSSI Window<br/>BeaconSignalBuffer<br/>median / stddev / EMA"]

  %% Localization
  K --> L["Localization<br/>KNNPositioner.estimate"]
  L --> L2["PositionFix<br/>x y floor confidence overlap ts"]

  %% Gating
  L2 --> M{Confidence & Overlap OK?}
  M -->|No| M1["Signal Weak Handling<br/>rate-limited speech + haptics"]
  M -->|Yes| N["Navigation State Machine"]

  %% Navigation logic
  N --> O["Floor Transition Handling<br/>expectedFloor gating"]
  N --> P["Off-route Detection<br/>distance-to-segment<br/>confidence-gated reroute"]
  N --> Q["Arrival & Turn Instructions<br/>geometry + segment advance"]

  %% Outputs
  O --> R["Outputs"]
  P --> R
  Q --> R
  M1 --> R

  R --> S["UI Text<br/>instructionText / accessibility"]
  R --> T["Speech & Haptics<br/>Speech.say + Haptics"]


```
