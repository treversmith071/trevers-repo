# Contract: Recommendation Engine

**Branch**: `001-wallet-card-optimizer` | **Date**: 2026-03-01

---

## Purpose

Defines the input/output contract for `RecommendationEngine` — the pure function that ranks a user's credit cards for a given store category. This is the core algorithmic component of the app.

---

## Interface

```swift
protocol RecommendationEngineProtocol {
    /// Rank all user cards for the given store category.
    /// - Returns: RecommendationResult with cards sorted by effectiveRate descending.
    /// - Guarantees: Always returns a result (may be empty `bestCards` if no cards configured).
    func recommend(
        for storeCategory: StoreCategory,
        storeName: String,
        userCards: [UserCard],
        templates: [String: CardTemplate],     // keyed by CardTemplate.id
        overrides: [UUID: [String: CardBenefitOverride]],  // cardId → categoryRaw → override
        valuations: [UUID: CardPointValuation]
    ) -> RecommendationResult
}
```

---

## Input Specification

| Parameter | Type | Description |
|---|---|---|
| `storeCategory` | `StoreCategory` | Detected or user-selected store category |
| `storeName` | `String` | Human-readable store name for display |
| `userCards` | `[UserCard]` | All cards the user has added |
| `templates` | `[String: CardTemplate]` | Lookup by `CardTemplate.id`; may be empty for custom cards |
| `overrides` | `[UUID: [String: CardBenefitOverride]]` | User rate overrides indexed by cardId and categoryRaw |
| `valuations` | `[UUID: CardPointValuation]` | Per-card point valuations |

**Constraints**:
- Empty `userCards` → returns `RecommendationResult` with `bestCards: []`
- Cards where `templateId` is nil and no override exists for the category are ranked with the 1% base fallback rate

---

## Output Specification

```swift
struct RecommendationResult {
    let storeCategory: StoreCategory
    let storeName: String
    let bestCards: [RankedCard]        // Sorted descending by effectiveRate
    let generatedAt: Date

    /// The top-ranked card, if any.
    var primaryRecommendation: RankedCard? { bestCards.first }

    /// Cards tied with primaryRecommendation at the same effectiveRate.
    var tiedCards: [RankedCard] {
        guard let top = primaryRecommendation else { return [] }
        return bestCards.filter { abs($0.effectiveRate - top.effectiveRate) < 0.0001 }
    }
}

struct RankedCard: Identifiable {
    let id: UUID                        // UserCard.id
    let userCard: UserCard
    let template: CardTemplate?
    let effectiveRate: Double           // Normalized cash-back percentage (e.g. 0.06 = 6%)
    let rateSummary: String             // e.g. "6% cash back at Grocery stores"
    let rateSource: RateSource          // .database | .userOverride
    let caveats: [String]              // e.g. ["Cap: $6,000/year", "Rotating — activate quarterly"]
}

enum RateSource {
    case database       // From bundled CreditCards.json template
    case userOverride   // User-entered override via FR-007
}
```

---

## Ranking Algorithm

```
effectiveRate(card, category) =
  1. IF userOverride(card.id, category) exists:
       normalize(override.rate, override.rateType, pointValue(card))
  2. ELSE IF template(card.templateId) exists AND template.categoryRates[category] exists:
       normalize(template.rate, template.rateType, pointValue(card))
  3. ELSE:
       0.01  (1% base fallback)

pointValue(card) =
  valuations[card.id]?.centsPerPoint
  ?? templates[card.templateId]?.defaultPointValueCents
  ?? 1.0

normalize(rate, .cashBackPercent, _)  = rate / 100.0  (rate is stored as %, e.g. 6.0 → 0.06)
normalize(rate, .pointsMultiplier, v) = rate * v / 100.0
```

**Sort**: `bestCards.sorted { $0.effectiveRate > $1.effectiveRate }`

---

## Invariants (Must Hold in 100% of Cases — SC-003)

1. If two or more cards have benefits data available, the card with the highest `effectiveRate` is always `bestCards[0]`.
2. If two cards have identical `effectiveRate` (within 0.01%), both appear in `bestCards` — neither is suppressed.
3. `bestCards` never contains duplicate `UserCard.id` values.
4. The engine is deterministic: same inputs → same output (no randomization).
5. The engine has no side effects — it does not write to Core Data, fire notifications, or call any APIs.

---

## Rate Summary Formatting

```swift
func rateSummary(for card: RankedCard, storeCategory: StoreCategory) -> String {
    let rateDisplay = formatRate(card.effectiveRate)
    return "\(rateDisplay) at \(storeCategory.displayName)"
}

// e.g. 0.06 → "6% cash back"
// e.g. 0.03 → "3% cash back"
// e.g. 0.04 → "4x points (4¢ per dollar)"  if template.rewardCurrency == "points"
```

---

## Comparison Display Contract

When rendering `CardComparisonView` (FR-008), the advantage over non-recommended cards is computed as:

```
advantage(primaryCard, otherCard) =
  (primaryCard.effectiveRate - otherCard.effectiveRate) * 100
  formatted as: "+X.X% vs. {otherCard.displayName}"
```

Example: Primary = 6%, Other = 1.5% → `"+4.5% vs. Wells Fargo Active Cash"`

---

## Error Handling

| Scenario | Behavior |
|---|---|
| No cards configured | `bestCards: []`; UI shows onboarding prompt |
| Only base-fallback cards (all 1%) | All cards returned tied at 1%; note: "Add benefit rates to improve recommendations" |
| Single card | Returns that card as `bestCards[0]` with no comparison row |
| Template not found for user card | Falls back to 1% base rate; `rateSource: .database` with note |
