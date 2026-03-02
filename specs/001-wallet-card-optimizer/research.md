# Research: Smart Wallet Card Optimizer

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01

---

## R-001: PassKit — Reading Wallet Card Metadata

**Decision**: Third-party apps CANNOT enumerate payment cards from Apple Wallet. The spec assumption that FR-001 is achievable via `PKPassLibrary` must be replaced with user-initiated card selection.

**Rationale**:
`PKPassLibrary.passes(of: .secureElement)` only returns passes where the app's bundle ID is listed in `associatedApplicationIdentifiers` by the card issuer's Token Service Provider (TSP) backend. Without that linkage—which requires Apple approval and a card-issuer relationship—the call returns an empty array. This restriction is architectural, not a permission gap.

The payment-network property (Visa, Mastercard, etc.) is also not readable from an existing provisioned pass via public API.

**What IS readable** (by issuer apps only):
- `PKSecureElementPass.primaryAccountNumberSuffix` — last 4 digits
- `PKSecureElementPass.primaryAccountIdentifier` — opaque stable token
- `PKPass.localizedName`, `organizationName`, `localizedDescription`

**Alternatives Considered**:
- Wait for Apple to open the API → No indication this will change; rejected.
- Request special entitlement → Requires card-issuer business relationship with Apple; not applicable.
- Screen-read Wallet UI → Private API, App Store ineligible; rejected.

**Impact on Spec**:
FR-001 must be re-scoped: the app presents a searchable list of 50+ known cards from the built-in database; the user selects their cards manually. This is the approach used by MaxRewards, CardPointers, and all comparable consumer apps. The spec language "read from wallet" is aspirational; the implementation is user-initiated card entry backed by a keyword-match disambiguation flow.

---

## R-002: iOS Background Location Strategy

**Decision**: Hybrid significant-location-change + dynamic 20-geofence pool.

**Rationale**:
iOS enforces a hard 20-region limit per app on `CLCircularRegion` monitoring. A two-layer strategy keeps battery cost low and notification reliability high:

1. `startMonitoringSignificantLocationChanges()` — fires every ~500m of real movement using only cell towers; cold-relaunches the terminated app via `UIApplication.LaunchOptionsKey.location`.
2. On each significant-change event: query the local chain database for stores within a 2km radius; evict all current regions; register the closest 20 as `CLCircularRegion` geofences (minimum radius 150m for reliable triggering).
3. `locationManager(_:didEnterRegion:)` → `UNUserNotificationCenter.add(request)` immediately.
4. Call `locationManager.requestState(for:)` after adding each region to handle the already-inside-store edge case.

**Alternatives Considered**:
- `CLVisit` monitoring alone → Too coarse and retrospective; 5–15 min delays; unsuitable for real-time at-store detection. Rejected.
- Continuous GPS in background → Requires `allowsBackgroundLocationUpdates = true` + blue status bar; prohibitive battery cost; App Store scrutiny. Rejected.

**Key Implementation Notes**:
- Requires both `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` in Info.plist.
- Two-step permission UX: request `whenInUse` first, then `always`.
- Background Modes entitlement: `location` (required for significant-change relaunch).
- iOS 17 minimum (project deployment target) — use `CLMonitor` (iOS 17) as alternative to `startMonitoringForRegion`, though it shares the 20-region limit and 3–5 min delays.
- Re-register all geofences in `didFinishLaunchingWithOptions` when relaunched via location event; they do not persist across termination automatically.
- Expect 1–5 minute delay on geofence triggers; SC-001 (notification within 30 seconds) is best-effort, not contractually guaranteed by iOS.

---

## R-003: Store/POI Category Detection

**Decision**: Three-tier hybrid architecture — bundled chain SQLite → MapKit `MKLocalPointsOfInterestRequest` → Apple Maps Server API.

**Rationale**:

**Tier 1 (offline, zero cost)**: Embed a curated SQLite database of the top ~500 US chain names mapped to app store categories. The top 500 chains cover approximately 70–80% of consumer retail transactions. Covers the offline requirement and is sub-millisecond.

**Tier 2 (online, free, native)**: `MKLocalPointsOfInterestRequest` (iOS 14+, MapKit) with 150m radius and `MKPointOfInterestFilter`. Maps `MKPointOfInterestCategory` values to app categories. Critical limitation: `.store` is a catch-all for all non-food retail (no Department Store vs. Generic Retail split). Handle with name heuristics on the `MKMapItem.name`.

**Tier 3 (online, free, richer)**: Apple Maps Server API `/v1/search` for cases where Tier 2 returns `.store` with an unrecognized chain name. The Server API uses 237+ Apple Business Connect categories, including explicit `GroceryStore`, `DepartmentStore`, `GasStation`, `Pharmacy`, etc.

**`MKPointOfInterestCategory` → App Category Mapping**:
```
.foodMarket          → Grocery
.gasStation          → Gas & Fuel
.restaurant, .cafe,
.bakery, .brewery    → Restaurants & Dining
.pharmacy            → Drugstore/Pharmacy
.hotel, .airport,
.carRental,
.publicTransport     → Travel
.movieTheater,
.nightlife, .stadium,
.museum,
.amusementPark       → Entertainment
.store               → Department Store (with name heuristics) or Online/General Retail
```

**Alternatives Considered**:
- Google Places API → Repriced March 2025; $32/1,000 calls beyond 5K/month free. Cost-prohibitive at scale. Rejected.
- Foursquare FSQ → Best category taxonomy; ~23K free calls/month; REST-only (no native iOS SDK); adds external API key dependency. Rejected as primary (considered future fallback).
- OSM bundled SQLite → Best offline option; 100MB+ data pipeline engineering cost; appropriate as future enhancement. Deferred.

**Apple Maps Server API Rate Limit**: 25,000 service requests/day per Developer Program membership (shared with MapKit JS). Sufficient for a single-user consumer app; Tier 3 calls are infrequent (only when Tier 1 and Tier 2 cannot resolve).

---

## R-004: iCloud Sync Architecture

**Decision**: Core Data + `NSPersistentCloudKitContainer` with dual-store pattern.

**Rationale**:
~800 records total (100 cards × 8 categories + valuations + settings). Core Data + `NSPersistentCloudKitContainer` provides record-level sync, transparent offline behavior, documented conflict resolution, and proven production stability on iOS 13+.

**Dual-store pattern** (required to prevent data erasure on iCloud sign-out):
- **Local store** (`Selectr-local.sqlite`): `cloudKitContainerOptions = nil`. Never wiped by CloudKit framework. Contains `UserSetting` entities.
- **Cloud store** (`Selectr-cloud.sqlite`): mirrored to CloudKit private database. Contains `UserCard`, `CardBenefitOverride`, `CardPointValuation`.

On `CKAccountStatus.noAccount` or `.restricted`, the cloud store is detached (options set to nil); user data remains in local SQLite. When account is restored, CloudKit re-mirrors from server.

**Merge Policy**: `NSMergeByPropertyObjectTrumpMergePolicy` — last-writer-wins per record with `lastModified: Date` field on each synced entity. Appropriate for personal preference data (card benefit overrides) where concurrent multi-device edits are rare and any valid value is acceptable.

**Sync status observation**: `NSPersistentCloudKitContainer.eventChangedNotification` (iOS 15+) drives a non-blocking `SyncStatusBanner` in the UI.

**Alternatives Considered**:
- `NSUbiquitousKeyValueStore` → 1,024-key ceiling; coarse last-writer-wins blob semantics. Rejected.
- SwiftData + CloudKit → Known stability issues in iOS 17/18; memory leaks, relationship bugs, data loss reports. Rejected for production data. Revisit for iOS 19.
- Direct CloudKit (`CKRecord`) → Weeks of sync loop engineering with no meaningful benefit over `NSPersistentCloudKitContainer` for private, non-shared data. Rejected.

**Required Capabilities**: iCloud + CloudKit, Background Modes → Remote Notifications.

---

## R-005: Credit Card Rewards Database

**Decision**: Bundled `CreditCards.json` in app target; parse on first launch into Core Data `CardTemplate` entity; user overrides shadow templates via `CardBenefitOverride`.

**Rationale**:
400 rate data points (50 cards × 8 categories) change infrequently (a few times per year per issuer). Manual curation from issuer websites is the most accurate and legally clean approach for v1. No live API calls needed; the database ships with the app and is updated via App Store updates.

**Rate resolution priority** (descending):
1. `CardBenefitOverride` for this card + category (user-confirmed, synced via iCloud)
2. `CardTemplate.categoryRates[category]` (bundled database)
3. 1% fallback (if no template match)

**Point normalization**: Effective cash-back% = `rate × pointValueCentsOverride ?? template.defaultPointValueCents`. Default: 1 point = 1 cent.

**Card matching flow** (since PassKit cannot enumerate wallet):
1. User taps "Add Card" → shown searchable list of all 50 templates.
2. Search matches `displayName` and `matchKeywords` (case-insensitive substring).
3. User selects match → `UserCard` created with `templateId`.
4. If no template match → user creates a custom card and manually enters rates.

**Key database entries confirmed** (top 15 by usage):
- Chase: Sapphire Preferred/Reserve, Freedom Unlimited, Freedom Flex
- Amex: Gold, Platinum, Blue Cash Preferred, Blue Cash Everyday
- Citi: Double Cash, Custom Cash
- Capital One: Venture X, Savor
- Discover: it Cash Back
- Wells Fargo: Active Cash
- US Bank: Altitude Reserve

**Rotating categories** (Chase Freedom Flex, Discover it): Store base (1%) rate in `categoryRates`; set `hasRotatingBonus: true`; surface a note in the card benefit view.

**Source**: Manual curation from issuer websites. Optional future refresh via RewardsCC API (rewardscc.com) for automated rate updates.

---

## R-006: Notification Deep-Link Contract

**Decision**: Store recommendation payload in `UNNotificationContent.userInfo` keyed by `"recommendation"` for deep-link routing from notification tap to `RecommendationView`.

```json
{
  "storeName": "Whole Foods Market",
  "storeCategory": "grocery",
  "recommendedCardId": "<UUID>",
  "recommendedCardName": "Amex Blue Cash Preferred",
  "effectiveRate": 0.06,
  "timestamp": "2026-03-01T14:32:00Z"
}
```

Tapping the notification sets the active `LastRecommendation` record and navigates directly to `RecommendationView`. If the app is terminated, the `SceneDelegate`/`WindowGroup` reads from `LastRecommendation` Core Data on launch.
