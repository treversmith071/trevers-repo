# Contract: Location Service

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01

---

## Purpose

Defines the interface and behavior contract for `LocationMonitor` and `StoreResolver` — the services that translate GPS coordinates into store category detections and fire the geofence monitoring lifecycle.

---

## LocationMonitor Interface

```swift
protocol LocationMonitorProtocol {
    /// Start the two-layer location monitoring pipeline.
    /// Must be called after "Always" authorization is granted.
    func startMonitoring()

    /// Stop all location monitoring (called when user revokes permission).
    func stopMonitoring()

    /// Update the geofence pool for a new user position.
    /// Called internally by significant-location-change callback.
    func refreshGeofences(near coordinate: CLLocationCoordinate2D)

    /// Output event stream (Combine publisher).
    var storeEntryEvents: AnyPublisher<StoreEntryEvent, Never> { get }
}

struct StoreEntryEvent {
    let geofenceId: String          // CLCircularRegion.identifier
    let storeName: String
    let storeCategory: StoreCategory
    let coordinate: CLLocationCoordinate2D
    let detectedAt: Date
}
```

---

## Geofence Identifier Convention

Each `CLCircularRegion.identifier` is a stable string constructed as:

```
"{chainSlug}-{lat6}-{lon6}"
```

Example: `"whole-foods-market-376745--1223011"`

This allows mapping from a `didEnterRegion` callback back to the store name and category without a database lookup at notification time.

---

## StoreResolver Interface

```swift
protocol StoreResolverProtocol {
    /// Resolve the store name and category at a coordinate.
    /// Implements the three-tier lookup: chain DB → MapKit → Apple Maps Server API.
    func resolveStore(
        at coordinate: CLLocationCoordinate2D
    ) async -> StoreResolution
}

enum StoreResolution {
    case identified(storeName: String, category: StoreCategory, confidence: Float)
    case unidentified(nearestPlaceName: String?)
}
```

**Confidence levels**:
- `1.0` — Tier 1 exact chain name match
- `0.85` — Tier 2 MapKit category (unambiguous category, e.g., `.gasStation`, `.pharmacy`)
- `0.70` — Tier 2 MapKit `.store` resolved via name heuristics
- `0.60` — Tier 3 Apple Maps Server API result
- `0.0` — No match; `StoreResolution.unidentified`

---

## Location Permission States

```swift
enum LocationAuthState {
    case notDetermined          // Initial state; show permission prompt
    case whenInUse              // Partial; app opens manually; no proactive notifications
    case always                 // Full; background monitoring active
    case denied                 // Blocked; show settings deep-link
    case restricted             // MDM/parental control; show message
}
```

**Required behavior per FR-012b**:
- `.whenInUse` → App shows last recommendation on open; banner: "Enable background location for proactive notifications"
- `.denied` → Settings deep-link prompt; manual store category picker available as fallback (FR-011)
- `.always` → Full proactive mode

---

## Geofence Pool Management

```
Maximum monitored regions: 20 (iOS hard limit)
Refresh trigger: significant location change (~500m threshold)
Selection: 20 closest stores from chain database within 2km
Minimum geofence radius: 150m
Default geofence radius: max(store.footprint, 150m)
```

**Refresh algorithm**:
```
1. Fetch stores from Chains.sqlite within 2,000m radius of new coordinate
2. Sort by distance ascending
3. Take first 20
4. Remove all current monitored regions
5. Register new 20 as CLCircularRegion (notifyOnEntry=true, notifyOnExit=false)
6. Call requestState(for:) on each to handle already-inside-store
```

**Already-inside-store handling**: `locationManager(_:didDetermineState:for:)` with `.inside` → immediately fire `StoreEntryEvent` without waiting for a separate entry callback.

---

## Background Relaunch Contract

When the app is cold-launched via `UIApplication.LaunchOptionsKey.location`:

```swift
// In SelectrApp.swift / AppDelegate
if launchOptions?[.location] != nil {
    locationMonitor.startMonitoring()  // Re-register monitoring; do NOT show UI
    // System delivers any pending region events via delegate after startMonitoring()
}
```

The app must NOT display any UI during a background relaunch. All work is notification scheduling and Core Data writes only.

---

## Manual Store Category Override (FR-011)

When `StoreResolution.unidentified` or when the user taps "Wrong store?" in `RecommendationView`:

```swift
// Present manual category picker
// User selects from StoreCategory.allCases
// Selected category → RecommendationEngine.recommend(for: selectedCategory, ...)
// Result stored to LastRecommendation as usual
```

The manual selection does not write to any persistent store (it is session-only). It does not affect geofence configuration.
