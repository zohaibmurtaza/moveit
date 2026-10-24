# Observable signals (educational notes)

MoveIt is intentionally more varied than naive “mouse moved every N seconds” jigglers. These notes describe signals you may observe when studying synthetic activity — for education, research, or authorized testing.

## 1. Process & binary fingerprint

| Signal | What MoveIt does | What you might look for |
| --- | --- | --- |
| Display name | **MoveIt** | Denylist known jiggler names and lookalikes |
| Bundle ID | `com.moveit.MoveIt` | Flag / score in test builds; expand as clones appear |
| Code signature | Ad-hoc or Developer ID | Prefer signed known-good apps; score unknown helpers that inject input |
| Menu-bar / accessory mode | Often Dock-hidden while running | Background-only apps with continuous input are higher risk |
| Launch at login | `SMAppService` (default on) | Persistence across sessions |

**Action:** Enumerate apps/agents; match bundle IDs, Team IDs, and path patterns (`*jiggle*`, `*moveit*`, fake “Helper” utilities).

## 2. Virtual HID / IOKit

MoveIt tries `IOHIDUserDeviceCreateWithProperties` (product strings like **SMH Pointing Device** / **SMH Keyboard**, vendor `0x05AC` camouflage). Creating a virtual HID device needs Apple’s `com.apple.developer.hid.virtual.device` entitlement. Local ad-hoc builds usually fall back to CGEvent — detect **both**.

**Action:**

- Flag user-mode virtual HID devices that appear/disappear with a helper process  
- Correlate new HID clients with Accessibility-trusted processes  
- Treat odd “Apple”-looking product strings as suspicious  

## 3. Event-source heuristics (CGEvent fallback)

Fallback posts via `CGEvent` / `cghidEventTap` with `.hidSystemState`.

**Action:** Where APIs allow, inspect event source fields; session-synthesized streams without matching hardware are a strong tell.

## 4. Behavioral / entropy features

| Feature | Suspicious pattern |
| --- | --- |
| Inter-event timing | Low variance vs human multimodal pauses |
| Path geometry | Repeated Bezier families; no accidental clicks |
| Activity mix | Moves + scrolls + letters/digits/arrows/modifiers; **zero mouse buttons** |
| Focus / UI | Cursor moves while frontmost app / document stay frozen |
| Screenshot correlation | High “activity” with near-identical screenshots |
| Idle wake | Activity after long idle with no context switch |
| Duty cycle | Steady bursts for hours without natural gaps |

**Action:** Score entropy, click/key ratio, screenshot delta, focus-change rate. Prompt when over threshold.

## 5. Correlation rules (highest ROI)

1. High input rate **and** low screenshot change  
2. Accessibility-trusted helper **and** virtual HID product match  
3. Continuous activity **and** no focus changes for N minutes  
4. Keystreams dominated by navigation/modifiers with no real document edits  

## 6. Out of scope for MoveIt v1

- Mouse clicks  
- Chorded shortcuts (⌘C, ⌘Q, etc.)  
- F-keys / Escape / Page Up-Down (intentionally avoided)  

Once you catch MoveIt reliably, raise the bar with a “full work simulation” profile on an isolated VM.
