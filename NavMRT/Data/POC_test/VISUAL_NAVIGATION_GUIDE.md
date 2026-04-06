# POC Visual Navigation - Quick Guide

## ⭐ The Best POC Navigation Experience

**POC Visual Navigation** is the recommended way to test beacon-based turn-by-turn navigation with a full-screen immersive interface.

---

## 🎯 How to Access

1. Launch NavMRT app
2. Tap **🔧 Developer Tools** (wrench icon, bottom-right)
3. Under "POC Testing", tap **POC Visual Navigation ⭐** (first option)

---

## 🎨 What You'll See

### Full-Screen Map
- **Background**: Gradient with grid lines (1m spacing)
- **Beacons**: Blue dots with ripple effects when active
- **Path**: Gradient line from green (start) to red (goal)
- **Your Position**: Purple dot with pulsing ring and direction arrow
- **Markers**: 
  - Green circle with "A" = Start (Point A)
  - Red circle with flag = Goal (Point B)

### Top Bar (Floating)
- **Progress**: "Step X/Y" with progress bar
- **Signal Strength**: Beacon count + signal icon
  - 🟢 Green (4+ beacons) = Excellent
  - 🟠 Orange (2-3 beacons) = Good
  - 🔴 Red (0-1 beacons) = Weak

### Bottom Card (Floating)
- **Instruction**: Current turn-by-turn direction (large text)
- **Distance**: Meters to next waypoint
- **Controls**:
  - **Start/Stop** button (green/red)
  - **🔊 Speaker** button (repeat instruction)

### Debug Sheet (Optional)
- Tap **ℹ️ info icon** (top-right) to open
- Shows:
  - Current position (X, Y coordinates)
  - Confidence score
  - List of all detected beacons with RSSI
  - Navigation status

---

## 🚀 Quick Start

### Step 1: Choose Mode

**Mock Mode** (Testing without hardware):
- Settings → Mock beacon mode → **ON** (orange)
- Perfect for UI testing and demonstrations
- Simulates beacon movement along path

**Real Mode** (With physical beacons):
- Settings → Mock beacon mode → **OFF** (green = Real)
- Requires BLE beacons with UUID: `FDA50693-A4E2-4FB1-AFCF-C6EB07647825`
- Needs Location permission

### Step 2: Set Data Pack

Settings → Data Pack → **POC Navigation Test**

Or run this once:
```swift
UserDefaults.standard.set("poc_test", forKey: "navmrt.dataPack")
// Then restart app
```

### Step 3: Start Navigation

1. Open **POC Visual Navigation ⭐**
2. Tap **Start** button (bottom)
3. Listen for voice: *"Starting navigation from Point A to Point B. Begin walking straight ahead."*
4. Watch purple dot appear on map
5. Follow voice instructions and visual guidance

---

## 🎮 Features

### Real-Time Position Tracking
- Purple dot shows your location on map
- Smooth animated movement
- Updates every 200ms based on beacon signals

### Direction Indicator
- Arrow inside purple dot points toward next waypoint
- Rotates automatically as you walk
- Helps you stay oriented

### Beacon Visualization
- Active beacons show ripple effects
- Inactive beacons appear gray
- Tap ℹ️ to see RSSI values in debug sheet

### Voice Guidance
- Automatic announcements at each waypoint
- Tap 🔊 button to repeat current instruction
- Announcements include:
  - Distance to walk
  - Turn directions (left/right)
  - Arrival confirmation

### Progress Tracking
- Top bar shows which step you're on (e.g., "Step 3/5")
- Progress bar fills as you advance
- Changes color based on signal quality:
  - 🟣 Purple = Good signal
  - 🟠 Orange = Weak signal
  - 🔴 Red = Lost signal

---

## 📍 The POC Route

```
      Point B (5,5) 🚩
           │
           │ 2.1m
           │
       Mid2 (4.5, 3)
           │
           │ 2.5m
           │
    Junction (4, 0.5) ← Turn left 90°
           │
           │ 2m
           │
       Mid1 (2, 0.5)
           │
           │ 2m
           │
      Point A (0, 0.5) 🟢 START
```

**Total Distance**: ~9 meters  
**Turn**: Left 90° at Junction  
**Time**: ~2-3 minutes walking

---

## 🔧 Controls

| Button | Function |
|--------|----------|
| **Start** (green) | Begin navigation with voice guidance |
| **Stop** (red) | End navigation and return to start |
| **🔊 Speaker** | Repeat current instruction |
| **ℹ️ Info** (top-right) | Open debug sheet |
| **Done** (in debug sheet) | Close debug sheet |

---

## ✅ Success Indicators

You know it's working when you see:

- ✅ Purple dot appears on map
- ✅ Purple dot moves when you walk
- ✅ Direction arrow rotates toward waypoint
- ✅ Blue beacons show ripple effects
- ✅ Voice says turn-by-turn instructions
- ✅ Distance countdown updates in real-time
- ✅ Progress bar advances when reaching waypoints
- ✅ Top bar shows "4+ beacons" in green

---

## ⚠️ Troubleshooting

### Purple dot doesn't appear

**Check:**
1. Is navigation started? (Tap Start button)
2. Mode correct? (Mock or Real based on your setup)
3. Fingerprints loaded? (Tap ℹ️ → should show fingerprints count > 0)

**Fix:**
- For **Mock mode**: Just tap Start - works immediately
- For **Real mode**: Need fingerprints + physical beacons nearby

### Position doesn't move

**Check:**
1. Are you in **Mock mode**? (Auto-simulates movement)
2. Are you in **Real mode** with beacons? (Need to physically walk)
3. Signal strength? (Top bar - should be green or orange, not red)

**Fix:**
- Walk closer to beacons
- Stand still for 3 seconds (let signal buffer fill)
- Check ℹ️ debug sheet for beacon count

### No beacons detected (Real mode)

**Check:**
1. Bluetooth enabled?
2. Location permission granted?
3. Beacons powered on?
4. Within 5 meters of beacons?

**Fix:**
- Settings → Bluetooth → ON
- Settings → Privacy → Location → NavMRT → While Using
- Check beacon batteries/power
- Try Mock mode first to test UI

### Voice not working

**Check:**
1. Device volume up?
2. Silent mode off?
3. Speech permission granted?

**Fix:**
- Turn up volume
- Disable silent mode
- Tap 🔊 button to test

---

## 🎓 Testing Tips

### First Time Testing
1. Use **Mock mode** first
2. Tap Start and watch purple dot move automatically
3. Listen to voice instructions
4. Familiarize yourself with UI

### With Real Beacons
1. Switch to **Real mode**
2. Make sure you have fingerprints (Fingerprint Collector)
3. Stand near 3+ beacons before starting
4. Walk slowly to see smooth position updates

### Debugging
1. Open debug sheet (ℹ️ icon)
2. Check beacon count (should be 2+)
3. Check confidence score (should be > 0.15)
4. Watch position update in real-time

---

## 📊 Debug Sheet Info

When you tap ℹ️, you see:

### Position Section
- X coordinate (0-6 meters)
- Y coordinate (0-6 meters)  
- Confidence score (0-1, higher = better)

### Beacons Section
- List of all detected beacons
- RSSI values in dBm
- Color coding:
  - 🟢 Green (-60 to -50) = Very strong
  - 🟠 Orange (-75 to -60) = Good
  - 🔴 Red (-90 to -75) = Weak

### Navigation Section
- Current segment (which waypoint heading to)
- Off-route streak (how many readings off path)
- Status (Good or Lost)

---

## 🆚 Comparison with Other Views

| Feature | Visual Navigation ⭐ | Navigation + Beacons | Manual Navigation |
|---------|---------------------|---------------------|-------------------|
| **Map Size** | Full screen | 250px compact | None |
| **Beacon Signals** | Animated ripples | Static dots | None |
| **Direction Arrow** | ✅ Yes | ❌ No | ❌ No |
| **Debug Sheet** | ✅ On demand | ✅ Always visible | ❌ No |
| **Immersion** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐ |
| **Best For** | Demos & testing | Quick testing | Instruction testing |
| **Requires Beacons** | Optional (mock) | Optional (mock) | No |

---

## 🎯 Summary

**POC Visual Navigation** is your go-to tool for:
- ✅ Testing beacon-based navigation
- ✅ Demonstrating the system
- ✅ Debugging positioning issues
- ✅ Experiencing full navigation flow
- ✅ Collecting performance data

**Access it**: Developer Tools → POC Visual Navigation ⭐

**Works best with**: Mock mode (no hardware needed) or Real mode (with beacons + fingerprints)

**Result**: Immersive, game-like navigation experience with real-time positioning! 🎮🗺️
