# Contract: Store-Entry Notification Payload

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01

---

## Purpose

Defines the `UNNotificationContent.userInfo` dictionary payload that is embedded in every store-entry notification. This contract governs:
- The data available for deep-link routing when the user taps a notification
- The data written to `LastRecommendation` Core Data entity
- The display content of the notification itself

---

## Notification Content

| Field | Value |
|---|---|
| `title` | Store name (e.g., `"Whole Foods Market"`) |
| `body` | `"Best card: {cardName} — {rateDisplay}"` (e.g., `"Best card: Amex Blue Cash Preferred — 6% cash back"`) |
| `sound` | `.default` |
| `interruptionLevel` | `.active` |
| `categoryIdentifier` | `"STORE_ENTRY"` |

---

## UserInfo Payload Schema

```swift
// Keys (String constants)
enum NotificationKey {
    static let storeName          = "storeName"       // String
    static let storeCategory      = "storeCategory"   // StoreCategory.rawValue
    static let recommendedCardId  = "recommendedCardId" // UUID string
    static let recommendedCardName = "recommendedCardName" // String
    static let effectiveRate      = "effectiveRate"   // Double (e.g. 0.06)
    static let timestamp          = "timestamp"       // ISO 8601 string
    static let geofenceId         = "geofenceId"      // CLCircularRegion.identifier
}
```

**Example payload**:
```json
{
  "storeName": "Whole Foods Market",
  "storeCategory": "grocery",
  "recommendedCardId": "550E8400-E29B-41D4-A716-446655440000",
  "recommendedCardName": "Amex Blue Cash Preferred",
  "effectiveRate": 0.06,
  "timestamp": "2026-03-01T14:32:00Z",
  "geofenceId": "whole-foods-market-sf-marina"
}
```

---

## Deep-Link Routing

When the user taps the notification:

1. `AppDelegate.application(_:didReceive:)` or the `UNUserNotificationCenter.delegate.didReceive(_:)` callback fires.
2. Extract `recommendedCardId` from `userInfo`.
3. Fetch the matching `UserCard` from Core Data.
4. Navigate to `RecommendationView` with the `LastRecommendation` data.

If the app is cold-launched via notification tap, the `WindowGroup` reads `LastRecommendation` from Core Data on launch and shows `RecommendationView` directly.

---

## Notification Category Actions

```swift
// Registered at app launch
let storeEntryCategory = UNNotificationCategory(
    identifier: "STORE_ENTRY",
    actions: [],   // No quick-reply actions in v1
    intentIdentifiers: [],
    options: [.hiddenPreviewsShowTitle]
)
UNUserNotificationCenter.current().setNotificationCategories([storeEntryCategory])
```

No quick-reply actions in v1. Users tap to open the full recommendation.

---

## Validation Rules

- `storeName`: non-empty string, max 100 characters
- `storeCategory`: must be a valid `StoreCategory.rawValue`
- `recommendedCardId`: valid UUID string
- `effectiveRate`: double in range [0.0, 1.0] (e.g., 0.06 = 6%)
- `timestamp`: ISO 8601 format

---

## Error States

If recommendation computation fails at notification fire time (e.g., no cards set up), the notification is still sent with:
- `body`: `"You're at {storeName} — open the app to see your best card"`
- `recommendedCardId`: omitted from userInfo
- App opens to the "Add Cards" onboarding flow if no cards are configured
