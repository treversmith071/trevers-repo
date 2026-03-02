# Implementation Plan: Smart Wallet Card Optimizer

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01 | **Spec**: `specs/001-wallet-card-optimizer/spec.md`
**Input**: Feature specification from `/specs/001-wallet-card-optimizer/spec.md`

---

## Summary

Build **Selectr**, an iOS 17+ SwiftUI app that proactively recommends the user's best credit card when they enter a retail store. The app uses a hybrid significant-location-change + geofence pipeline to detect store entries, a three-tier POI lookup (bundled chain database → MapKit → Apple Maps Server API) to classify the store category, and a pure ranking function to select the highest-reward card from the user's manually-entered card set. User card data and rate overrides sync across devices via iCloud (Core Data + `NSPersistentCloudKitContainer`).

**Critical design pivot from spec**: PassKit does not allow third-party apps to enumerate cards from Apple Wallet. FR-001 is implemented as user-initiated card selection from a bundled database of 50+ US consumer credit cards, not automatic wallet reading. This is the standard implementation pattern for consumer wallet-optimizer apps (MaxRewards, CardPointers).

---

## Technical Context

**Language/Version**: Swift 5.9, SwiftUI
**Primary Dependencies**: CoreLocation, MapKit, UserNotifications, Core Data + NSPersistentCloudKitContainer, CloudKit (system frameworks only — no third-party dependencies in v1)
**Storage**: Core Data dual-store (CloudKit-synced store for user card data; local-only store for recommendations and settings) + Bundled JSON assets (CreditCards.json, Chains.json)
**Testing**: XCTest (Swift Testing for new unit tests)
**Target Platform**: iOS 17.0+
**Project Type**: Mobile app (iOS, SwiftUI)
**Performance Goals**: <5s recommendation display after app launch (SC-001); notification fired within ~30s of geofence entry (best-effort; iOS may delay 1–5 min)
**Constraints**: Offline-capable (cached last recommendation; bundled chain DB for known stores); background location (geofencing for terminated app); <100MB bundled assets
**Scale/Scope**: Single-user iOS app; 50+ built-in US credit cards; 8 store categories; 20 concurrent geofences (iOS limit)

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`/.specify/memory/constitution.md`) has not been established — the file contains only the placeholder template. No project-level principles are defined.

**Result**: No constitution gates to evaluate. No violations.

**Recommendation**: Establish a constitution before implementation begins. Suggested principles for this project:
- Privacy-first: No card numbers stored; no data transmitted to third parties
- Offline-capable: Core features must work without internet
- Permission-transparent: Every permission explained at time of request
- Test-driven: Recommendation engine logic requires unit tests before implementation

---

## Project Structure

### Documentation (this feature)

```text
specs/001-wallet-card-optimizer/
├── plan.md              # This file
├── research.md          # Phase 0: Research findings and decisions
├── data-model.md        # Phase 1: Entity definitions and state transitions
├── quickstart.md        # Phase 1: Setup and development guide
├── contracts/
│   ├── notification-payload.md     # Store-entry notification userInfo schema
│   ├── recommendation-engine.md    # Ranking algorithm input/output contract
│   └── location-service.md         # LocationMonitor + StoreResolver interface
└── tasks.md             # Phase 2 output (/speckit.tasks command — NOT created here)
```

### Source Code (repository root)

```text
Selectr/Selectr/
├── SelectrApp.swift                         # App entry; location relaunch detection
├── Info.plist                               # NSLocation* permission strings
├── Selectr.entitlements                     # iCloud, CloudKit, Background Modes
│
├── Resources/
│   ├── CreditCards.json                     # Built-in rewards database (50+ US cards)
│   └── Chains.json                          # Chain name → store category (~500 chains)
│
├── Models/
│   ├── CardTemplate.swift                   # Codable structs from CreditCards.json
│   ├── StoreCategory.swift                  # 8-case enum with display names
│   ├── RateTypes.swift                      # RateType, CapPeriod, CategoryRate
│   └── RecommendationModels.swift           # RankedCard, RecommendationResult
│
├── Persistence/
│   ├── PersistenceController.swift          # Core Data dual-store + CloudKit setup
│   ├── Selectr.xcdatamodeld/                # UserCard, CardBenefitOverride,
│   │                                        # CardPointValuation, LastRecommendation,
│   │                                        # AppSetting entities
│   └── CardDatabaseSeeder.swift             # Load CreditCards.json into CardTemplate array
│
├── Services/
│   ├── LocationMonitor.swift                # CLLocationManager; sig-change → geofences
│   ├── StoreResolver.swift                  # Three-tier POI lookup
│   ├── RecommendationEngine.swift           # Pure card ranking function
│   ├── NotificationScheduler.swift          # UNUserNotificationCenter + payload builder
│   └── CloudSyncMonitor.swift              # CKAccountStatus + sync event observation
│
└── Views/
    ├── Onboarding/
    │   ├── PermissionRequestView.swift      # Notification → WhenInUse → Always flow
    │   └── CardSetupView.swift              # Searchable card picker from bundled DB
    ├── Recommendation/
    │   ├── RecommendationView.swift         # Store name, category, best card, comparison
    │   └── CardComparisonView.swift         # All-card comparison breakdown (FR-008)
    ├── CardManagement/
    │   ├── CardListView.swift               # All user cards with sync status
    │   ├── CardDetailView.swift             # Per-card rates by category
    │   └── BenefitEditorView.swift          # Edit rate/type/cap per category (FR-007)
    └── Shared/
        ├── SyncStatusBanner.swift           # Non-blocking iCloud sync status
        └── ContentView.swift                # Root navigation (tab or nav stack)

SelectrTests/
└── SelectrTests/
    ├── RecommendationEngineTests.swift      # Core ranking algorithm tests
    ├── StoreCategoryMappingTests.swift      # MapKit category → app category mapping
    └── CardDatabaseTests.swift             # JSON parsing + rate computation tests
```

**Structure Decision**: Single iOS app project (no separate API backend). All data is local/iCloud-synced. No server-side component in v1.

---

## Complexity Tracking

> No constitution violations to justify.

| Decision | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Dual Core Data stores | Prevent data erasure when iCloud account signs out (documented NSPersistentCloudKitContainer footgun) | Single store risks losing all user-entered card data on iCloud sign-out |
| Three-tier POI lookup | MapKit's `.store` catch-all cannot distinguish Department Store from General Retail; bundled chain DB needed for offline | Single MapKit lookup misclassifies ~30% of retail locations; Google Places too expensive post-March 2025 pricing |
| User-initiated card entry | PassKit does not allow third-party enumeration of Wallet cards | No alternative — architectural iOS restriction |

---

## Key Architecture Decisions

### PassKit Limitation (Critical)

**Spec assumption**: FR-001 states the app "MUST read the list of payment cards from the user's digital wallet."

**Reality**: `PKPassLibrary.passes()` only returns passes where the app's bundle ID is registered by the card issuer's Token Service Provider. Third-party apps receive an empty array. This is an architectural iOS restriction with no workaround.

**Resolution**: FR-001 is implemented as user-initiated card selection from a searchable list of 50+ bundled card templates. The user selects their cards; the app pre-populates reward rates from the bundled database. This is the standard implementation pattern used by comparable consumer apps.

### Background Location Pipeline

```
App terminated
     │ significant location change (~500m movement)
     ▼
App cold-launched (UIApplication.LaunchOptionsKey.location)
     │
     ▼ didFinishLaunchingWithOptions → startMonitoringSignificantLocationChanges()
     │
     ▼ didUpdateLocations
     │ → query Chains.json within 2km
     │ → clear all monitored regions
     │ → register 20 closest stores as CLCircularRegion (radius ≥ 150m)
     │ → requestState(for:) on each
     │
     ▼ didEnterRegion (or .inside from requestState)
     │ → StoreResolver.resolveStore(at: coordinate)
     │ → RecommendationEngine.recommend(for: category, ...)
     │ → UNUserNotificationCenter.add(request)
     │ → PersistenceController.save(LastRecommendation)
```

### iCloud Sync Failure Handling

```
CKAccountStatus.available    → CloudKit store active; sync normally
CKAccountStatus.noAccount    → Detach CloudKit store; show SyncStatusBanner
CKAccountStatus.restricted   → Detach CloudKit store; show SyncStatusBanner
CKAccountStatus.temporarilyUnavailable → Keep CloudKit store; retry silently
```

All user card data is preserved in the local Core Data SQLite file regardless of iCloud status.

---

## Post-Phase 1 Constitution Check

Constitution not yet established. No gates to re-evaluate.

Design is consistent with the spec's stated values:
- No card numbers stored anywhere (only user-selected display names + last 4)
- No data transmitted to third parties (all API calls are to Apple-operated services)
- Every permission explained at request time (FR-012, FR-012a)
- Offline mode supported for last-known recommendation (FR-012b, SC-006)
