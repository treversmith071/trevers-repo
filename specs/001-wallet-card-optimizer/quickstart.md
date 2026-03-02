# Quickstart: Smart Wallet Card Optimizer (Selectr)

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01

---

## Prerequisites

| Requirement | Version |
|---|---|
| Xcode | 16.0+ |
| iOS Deployment Target | 17.0+ |
| Swift | 5.9+ |
| Apple Developer Program | Active membership (required for iCloud + CloudKit) |
| Physical iPhone (for location testing) | Recommended |

No third-party package dependencies in v1. All APIs used are Apple system frameworks.

---

## Project Structure

```
coding folder/
├── Selectr/
│   ├── Selectr/                          # iOS app source
│   │   ├── SelectrApp.swift              # App entry point
│   │   ├── ContentView.swift             # Root view (to be replaced)
│   │   ├── Info.plist                    # Permissions keys added here
│   │   ├── Selectr.entitlements          # iCloud + CloudKit + Background Location
│   │   │
│   │   ├── Resources/
│   │   │   ├── CreditCards.json          # Bundled rewards database (50+ cards)
│   │   │   └── Chains.json              # Bundled chain → category lookup (~500 chains)
│   │   │
│   │   ├── Models/
│   │   │   ├── CardTemplate.swift        # Codable structs decoded from CreditCards.json
│   │   │   ├── StoreCategory.swift       # Enum with 8 store categories
│   │   │   ├── RateTypes.swift           # RateType, CapPeriod, CategoryRate enums/structs
│   │   │   └── RecommendationModels.swift # RankedCard, RecommendationResult
│   │   │
│   │   ├── Persistence/
│   │   │   ├── PersistenceController.swift  # Core Data + CloudKit dual-store stack
│   │   │   ├── Selectr.xcdatamodeld/        # Core Data schema
│   │   │   └── CardDatabaseSeeder.swift     # JSON → memory seeder on first launch
│   │   │
│   │   ├── Services/
│   │   │   ├── LocationMonitor.swift         # Sig-change + geofence pipeline
│   │   │   ├── StoreResolver.swift           # Three-tier POI lookup
│   │   │   ├── RecommendationEngine.swift    # Pure ranking function
│   │   │   ├── NotificationScheduler.swift   # UNUserNotificationCenter wrapper
│   │   │   └── CloudSyncMonitor.swift        # CKAccountStatus + sync events
│   │   │
│   │   └── Views/
│   │       ├── Onboarding/
│   │       │   ├── PermissionRequestView.swift
│   │       │   └── CardSetupView.swift        # User-initiated card selection
│   │       ├── Recommendation/
│   │       │   ├── RecommendationView.swift   # Primary recommendation screen
│   │       │   └── CardComparisonView.swift   # All-card comparison table
│   │       ├── CardManagement/
│   │       │   ├── CardListView.swift
│   │       │   ├── CardDetailView.swift
│   │       │   └── BenefitEditorView.swift    # Per-card per-category rate editor
│   │       └── Shared/
│   │           └── SyncStatusBanner.swift
│   │
│   ├── Selectr.xcodeproj/
│   └── project.yml                       # XcodeGen config
│
└── specs/001-wallet-card-optimizer/      # This spec directory
```

---

## Initial Setup (one-time)

### 1. Enable Capabilities in Xcode

Open `Selectr.xcodeproj`, select the **Selectr** target → **Signing & Capabilities**:

1. **iCloud** → Enable → check **CloudKit** → create container `iCloud.com.selectr.app`
2. **Background Modes** → Enable → check **Location updates** and **Remote notifications**
3. Sign with your Apple Developer team

Xcode auto-generates `Selectr.entitlements` with the correct keys.

### 2. Info.plist Required Keys

Add these keys to `Selectr/Info.plist`:

```xml
<!-- Location permissions -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Selectr uses your location to find nearby stores and recommend your best credit card.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Selectr monitors your location in the background to notify you the moment you enter a store — no action needed on your part.</string>

<!-- Notification usage (iOS requires this in some configurations) -->
<key>NSUserNotificationsUsageDescription</key>
<string>Selectr sends a notification when you enter a store, showing which card gives you the best rewards.</string>
```

### 3. Build & Run

```bash
# From the Selectr/ directory (with XcodeGen if schema changes are needed)
cd "Selectr"
xcodegen generate   # Only needed if project.yml changes
open Selectr.xcodeproj
```

Press **⌘R** to build and run on a connected device or simulator.

> **Note**: Location monitoring in background requires a physical device. The simulator can simulate location updates but cannot reliably trigger geofence events.

---

## First Launch Flow

1. **Onboarding**: `PermissionRequestView` requests notification permission, then When In Use location, then Always location (two-step).
2. **Card Setup**: `CardSetupView` presents a searchable list of 50+ cards from `CreditCards.json`. User selects their cards.
3. **Ready**: `LocationMonitor.startMonitoring()` begins. Next time the user enters a store, a notification fires.

---

## Testing Locally

### Test Recommendation Engine (Unit Test)

```swift
// SelectrTests/RecommendationEngineTests.swift
func testGroceryRecommendation() {
    let engine = RecommendationEngine()
    let cards = [mockAmexBlueCashPreferred, mockChaseDoubleCard]
    let result = engine.recommend(
        for: .grocery,
        storeName: "Whole Foods",
        userCards: cards,
        templates: mockTemplates,
        overrides: [:],
        valuations: [:]
    )
    XCTAssertEqual(result.bestCards.first?.userCard.id, mockAmexBlueCashPreferred.id)
    XCTAssertEqual(result.bestCards.first?.effectiveRate, 0.06, accuracy: 0.001)
}
```

### Simulate Store Entry (on Device)

1. Open Maps app → long-press a location → "Simulate Location" (Xcode Debug → Simulate Location).
2. Or use a `CLLocationSimulationManager` in scheme settings.
3. Set simulated location to coordinates of a known chain (e.g., Safeway, Walgreens).
4. The app will fire a notification within 30–300 seconds (iOS geofence timing).

### Simulate Offline Mode

Enable Airplane Mode on device → open app → `LastRecommendation` from Core Data is displayed.

---

## Architecture Decisions Summary

| Concern | Decision | Rationale |
|---|---|---|
| Card discovery | User-initiated search (not PassKit) | PassKit blocks third-party apps from enumerating wallet cards |
| Location strategy | Significant-change + 20 geofences | Battery-efficient; covers terminated app; handles iOS 20-region limit |
| POI lookup | Chain SQLite → MapKit → Apple Maps Server API | Free, offline-capable for top chains, no third-party keys |
| Sync | Core Data + NSPersistentCloudKitContainer (dual store) | Record-level sync, proven stability, offline fallback |
| Card database | Bundled CreditCards.json | 50 cards × 8 categories = ~400 records; infrequent updates |
| UI framework | SwiftUI | Project deployment target iOS 17; modern Apple standard |

---

## Known Constraints

- **Geofence delay**: iOS does not guarantee sub-30-second geofence triggers. SC-001 (30 seconds) is best-effort. In practice, expect 1–5 minutes in light-traffic scenarios.
- **Location permission**: If user grants only "When In Use," the app shows the last recommendation when opened; no background notifications.
- **PassKit**: This app does not read cards from Apple Wallet. Cards are user-entered. The spec's FR-001 is implemented as user-initiated card selection, not automatic wallet enumeration.
- **Offline POI**: Tier 1 (bundled chain database) handles offline store detection for known chains. Unknown or independent stores require internet for Tier 2/3 lookup.

---

## Key Files Reference

| File | Purpose |
|---|---|
| `PersistenceController.swift` | Core Data stack; dual-store setup; CloudKit sync |
| `LocationMonitor.swift` | `CLLocationManager` delegate; significant-change → geofence refresh → entry events |
| `StoreResolver.swift` | Three-tier POI resolution; chain DB + MapKit + Apple Maps Server API |
| `RecommendationEngine.swift` | Pure function: cards + category → ranked results |
| `CreditCards.json` | Built-in rewards database; 50+ US consumer credit cards; 8 categories each |
| `Chains.json` | Chain name → store category lookup; ~500 top US retail chains |
| `NotificationScheduler.swift` | `UNUserNotificationCenter` wrapper; notification payload construction |
