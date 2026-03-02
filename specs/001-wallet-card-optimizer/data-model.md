# Data Model: Smart Wallet Card Optimizer

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01

---

## Entities Overview

```
┌─────────────────────────────────┐     ┌──────────────────────────────────┐
│ CardTemplate (Codable, bundled) │     │ UserCard (Core Data, CloudKit)   │
│─────────────────────────────────│     │──────────────────────────────────│
│ id: String                      │◄────│ templateId: String?              │
│ displayName: String             │     │ id: UUID                         │
│ issuer: String                  │     │ displayName: String              │
│ network: String                 │     │ last4: String?                   │
│ rewardCurrency: RewardCurrency  │     │ pointValueCentsOverride: Double? │
│ rewardProgramName: String?      │     │ isConfirmedByUser: Bool          │
│ defaultPointValueCents: Double  │     │ addedAt: Date                   │
│ annualFee: Int                  │     └──────────────────────────────────┘
│ matchKeywords: [String]         │                    │ 1:N
│ categoryRates: [String:CatRate] │     ┌──────────────▼───────────────────┐
└─────────────────────────────────┘     │ CardBenefitOverride (Core Data)  │
                                        │──────────────────────────────────│
┌─────────────────────────────────┐     │ id: UUID                         │
│ LastRecommendation (Local only) │     │ categoryRawValue: String         │
│─────────────────────────────────│     │ rate: Double                     │
│ id: UUID                        │     │ rateType: String                 │
│ storeName: String               │     │ cap: Double?                     │
│ storeCategory: String           │     │ capPeriod: String?               │
│ recommendedCardId: UUID         │     │ lastModified: Date               │
│ effectiveRate: Double           │     └──────────────────────────────────┘
│ latitude: Double                │
│ longitude: Double               │     ┌──────────────────────────────────┐
│ detectedAt: Date                │     │ CardPointValuation (Core Data)   │
└─────────────────────────────────┘     │──────────────────────────────────│
                                        │ id: UUID                         │
┌─────────────────────────────────┐     │ cardId: UUID                     │
│ AppSetting (Core Data, Local)   │     │ centsPerPoint: Double            │
│─────────────────────────────────│     │ lastModified: Date               │
│ key: String                     │     └──────────────────────────────────┘
│ value: String                   │
│ lastModified: Date              │
└─────────────────────────────────┘
```

---

## Value Types (Swift Structs — Not Persisted)

### StoreCategory (Enum)

```swift
enum StoreCategory: String, CaseIterable, Codable {
    case grocery          = "grocery"
    case gasAndFuel       = "gas"
    case dining           = "dining"
    case travel           = "travel"
    case drugstore        = "drugstore"
    case departmentStore  = "departmentStore"
    case entertainment    = "entertainment"
    case onlineRetail     = "onlineRetail"

    var displayName: String { /* localized */ }
}
```

Maps to FR-003 required store categories. Raw value is the canonical key used in `categoryRates` JSON and `CardBenefitOverride.categoryRawValue`.

### RateType (Enum)

```swift
enum RateType: String, Codable {
    case cashBackPercent    // e.g. 6.0 → 6%
    case pointsMultiplier   // e.g. 4.0 → 4x; converted via pointValueCents
}
```

### CapPeriod (Enum)

```swift
enum CapPeriod: String, Codable {
    case monthly
    case quarterly
    case annual
}
```

### CategoryRate (Struct — embedded in CardTemplate)

```swift
struct CategoryRate: Codable {
    let rate: Double
    let rateType: RateType
    let cap: Double?
    let capPeriod: CapPeriod?
    let note: String?
    let hasRotatingBonus: Bool

    /// Effective cash-back percent at a given point valuation.
    func effectiveCashBackPercent(pointValueCents: Double) -> Double {
        switch rateType {
        case .cashBackPercent:   return rate
        case .pointsMultiplier:  return rate * pointValueCents
        }
    }
}
```

### CardTemplate (Struct — decoded from CreditCards.json)

```swift
struct CardTemplate: Codable, Identifiable {
    let id: String                              // e.g. "chase-sapphire-preferred"
    let displayName: String
    let issuer: String
    let network: String                         // "Visa" | "Mastercard" | "Amex" | "Discover"
    let rewardCurrency: String                  // "cashBack" | "points" | "miles"
    let rewardProgramName: String?              // e.g. "Chase Ultimate Rewards"
    let defaultPointValueCents: Double          // default 1.0
    let annualFee: Int
    let matchKeywords: [String]                 // for card-selection search
    let categoryRates: [String: CategoryRate]   // keyed by StoreCategory.rawValue
}
```

### RankedCard (Struct — recommendation output)

```swift
struct RankedCard {
    let userCard: UserCard
    let template: CardTemplate?
    let effectiveRate: Double          // normalized to cash-back%
    let rateSummary: String            // e.g. "6% cash back at grocery stores"
    let caveats: [String]              // notes: caps, rotating bonus, etc.
}
```

### RecommendationResult (Struct — recommendation engine output)

```swift
struct RecommendationResult {
    let storeCategory: StoreCategory
    let storeName: String
    let bestCards: [RankedCard]        // sorted descending by effectiveRate
    let generatedAt: Date
}
```

Displayed in `RecommendationView`. `bestCards[0]` is the primary recommendation. All cards surfaced for comparison per FR-008.

---

## Core Data Entities (CloudKit-Synced)

Stored in `Selectr-cloud.sqlite`. Synced via `NSPersistentCloudKitContainer`.

### UserCard

| Attribute | Type | Required | Notes |
|---|---|---|---|
| id | UUID | Yes | Stable identity across devices |
| displayName | String | Yes | User-facing name; defaults to template `displayName` |
| last4 | String | No | Last 4 digits; user-entered for disambiguation |
| templateId | String | No | Matches `CardTemplate.id`; nil for custom cards |
| pointValueCentsOverride | Double | No | nil → use `template.defaultPointValueCents` |
| isConfirmedByUser | Bool | Yes | false = auto-matched pending user review |
| addedAt | Date | Yes | For display ordering |

**Relationships**: `benefitOverrides` → one-to-many `CardBenefitOverride` (cascade delete)

**Validation**:
- `displayName` must be non-empty
- `pointValueCentsOverride`, if set, must be > 0

### CardBenefitOverride

| Attribute | Type | Required | Notes |
|---|---|---|---|
| id | UUID | Yes | |
| categoryRawValue | String | Yes | `StoreCategory.rawValue` |
| rate | Double | Yes | Must be ≥ 0 |
| rateType | String | Yes | `RateType.rawValue` |
| cap | Double | No | Spending cap in dollars |
| capPeriod | String | No | `CapPeriod.rawValue` |
| lastModified | Date | Yes | For last-writer-wins conflict resolution |

**Relationships**: `card` → many-to-one `UserCard` (nullify on delete)

**Validation**:
- `categoryRawValue` must be a valid `StoreCategory.rawValue`
- `rate` must be ≥ 0

### CardPointValuation

| Attribute | Type | Required | Notes |
|---|---|---|---|
| id | UUID | Yes | |
| cardId | UUID | Yes | References `UserCard.id` |
| centsPerPoint | Double | Yes | Default 1.0; must be > 0 |
| lastModified | Date | Yes | |

---

## Core Data Entities (Local Only — Not Synced)

Stored in `Selectr-local.sqlite`. `cloudKitContainerOptions = nil`.

### LastRecommendation

| Attribute | Type | Required | Notes |
|---|---|---|---|
| id | UUID | Yes | |
| storeName | String | Yes | |
| storeCategory | String | Yes | `StoreCategory.rawValue` |
| recommendedCardId | UUID | Yes | References `UserCard.id` |
| effectiveRate | Double | Yes | Normalized cash-back% |
| latitude | Double | Yes | Store GPS coordinate |
| longitude | Double | Yes | |
| detectedAt | Date | Yes | Notification fire time |

Stores the most recent recommendation for offline display (SC-006). Overwritten on each store entry event.

### AppSetting

| Attribute | Type | Required | Notes |
|---|---|---|---|
| key | String | Yes | Unique string key |
| value | String | Yes | String-encoded value |
| lastModified | Date | Yes | |

Used for notification permission state, onboarding completion flag, etc.

---

## Bundled Read-Only Data

### CreditCards.json

Bundled in app target. Parsed once on first launch into in-memory `[CardTemplate]` array. Not persisted to Core Data (loaded from bundle each launch for simplicity; Core Data `CardTemplate` entity can be added in v2 if search/filter performance requires it).

**Schema version field**: `schemaVersion: Int` — allows future migration handling.

**Size estimate**: ~50 cards × ~500 bytes each = ~25 KB. Well within app bundle budget.

### Chains.sqlite (or Chains.json)

Bundled chain name → store category lookup table. Used by Tier 1 of the POI resolution pipeline.

| Column | Type | Notes |
|---|---|---|
| name | TEXT | Normalized lowercase |
| category | TEXT | `StoreCategory.rawValue` |
| aliases | TEXT | Pipe-delimited |

**Size estimate**: 500 chains × ~200 bytes = ~100 KB.

---

## State Transitions

### UserCard.isConfirmedByUser

```
Added (isConfirmedByUser=false)
         │
         │ User reviews card in Card Benefits screen
         ▼
Confirmed (isConfirmedByUser=true)
```

Cards where `isConfirmedByUser=false` are displayed with a "Verify rates" prompt in `CardDetailView`.

### Recommendation Flow

```
GPS coordinate
    │
    ▼ Tier 1: chain DB
Store category resolved? ──YES──► RecommendationEngine.rank(cards, category)
    │                                         │
   NO                                         ▼
    │                             Sort by effectiveRate DESC
    ▼ Tier 2: MapKit POI                      │
Store category resolved? ──YES──► RecommendationResult
    │                                         │
   NO                                         ▼
    │                             UNNotification (background)
    ▼ Tier 3: Apple Maps Server API           +
Store category resolved? ──YES──► RecommendationView (foreground)
    │
   NO
    ▼
"Could not identify store" UI
```

---

## Effective Rate Computation

```
effectiveRate(card, category) =
  IF userOverride(card, category) exists:
    normalize(override.rate, override.rateType, effectivePointValue(card))
  ELSE IF template(card) exists AND template.categoryRates[category] exists:
    normalize(template.rate, template.rateType, effectivePointValue(card))
  ELSE:
    1.0%  (base fallback)

effectivePointValue(card) =
  card.pointValueCentsOverride ?? template.defaultPointValueCents ?? 1.0

normalize(rate, .cashBackPercent, _)  = rate
normalize(rate, .pointsMultiplier, v) = rate * v
```

All rates are compared as percentages. Highest percentage wins.
