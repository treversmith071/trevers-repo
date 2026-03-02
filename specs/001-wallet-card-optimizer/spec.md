# Feature Specification: Smart Wallet Card Optimizer

**Feature Branch**: `001-wallet-card-optimizer`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "I'm looking to create an iphone app that integrates with apple's wallet apis so that it can detect the type of store a user is in, the app will also review the cards currently stored within apple wallet and compare the store the user is in to determine which card in the users wallet would have the most beneficial credit card benefits"

## Clarifications

### Session 2026-03-01

- Q: Should the app deliver recommendations proactively via background location monitoring and notifications, or on-demand when the user opens the app? → A: B — Proactive only; the app monitors location in the background and pushes a lock-screen notification when the user enters a recognized store.
- Q: Should credit card reward rates come from a built-in database of known card programs, from user-entered data only, or from a database that the user can override? → A: C — Built-in database pre-populates reward rates for well-known cards; user can override any rate per card per store category.
- Q: When comparing points-earning cards against cash back cards, how should the reward types be normalized for ranking? → A: B — Normalize points to an estimated cash value using a default baseline of 1 point = 1 cent; users can override the per-point valuation per card to reflect how they actually redeem points.
- Q: Should user-configured card override data and settings sync across the user's Apple devices, or remain local to one device? → A: B — Sync via iCloud so customizations are preserved across device upgrades and available on all the user's Apple devices automatically.
- Q: How should proactive store-entry notifications be deduplicated — every entry, once per store per day, or once per session? → A: A — Notify on every detected store entry with no deduplication; users who find this too frequent can manage notification settings in the system settings.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full Recommendation Detail View (Priority: P1)

A shopper receives a proactive notification that they are at a store and taps it. The app opens to a full-screen recommendation view showing the store name, store category, the recommended card, and a clear breakdown of how that card compares to the other cards in their wallet for this store type. The user also has the option to open the app directly at any time to see the current or last-known recommendation.

**Why this priority**: The detail view is the primary content surface of the app and is required for the proactive notification flow to deliver complete value. Without it, the notification is a dead end.

**Independent Test**: Can be fully tested by tapping a proactive store-entry notification and verifying the full recommendation screen appears with card name, store category, reward rate, and a comparison against the user's other eligible cards.

**Acceptance Scenarios**:

1. **Given** the user has at least two credit cards in their wallet and is physically at a grocery store, **When** they open the app, **Then** the app displays the store name, store category, the recommended card, and the specific reward rate advantage (e.g., "Chase Sapphire — 3% at grocery stores vs. 1% on your other cards")
2. **Given** the user is at a gas station, **When** they open the app, **Then** the app identifies the location as "Gas & Fuel" and recommends the card with the highest reward rate for that category
3. **Given** the user opens the app while at a recognized store, **When** the recommendation is displayed, **Then** the result appears within 5 seconds of the app launching

---

### User Story 2 - Card Benefits Setup & Management (Priority: P2)

A new user opens the app for the first time after granting wallet and location permissions. The app displays all credit cards found in their wallet and shows the benefit/reward rates associated with each card across common store categories. The user can confirm or correct the benefit information shown.

**Why this priority**: The recommendation engine is only as accurate as the benefit data it has for each card. Users need a way to verify and correct this data before trusting the recommendations.

**Independent Test**: Can be fully tested by a new user viewing their detected wallet cards and manually entering the cash back/points rates for two cards across three store categories, then verifying those rates are reflected in subsequent recommendations.

**Acceptance Scenarios**:

1. **Given** a first-time user opens the app, **When** they grant wallet access, **Then** the app displays a list of all credit cards found in their wallet by name/last-four-digits
2. **Given** the user views the benefits for a specific card, **When** they tap a store category, **Then** they can update the reward rate (percentage or points multiplier) for that category
3. **Given** the user updates a card's benefit rate for "Restaurants" from 1% to 4%, **When** they are next at a restaurant, **Then** the recommendation reflects the updated rate

---

### User Story 3 - Proactive In-Store Notification (Priority: P1)

The app continuously monitors the user's location in the background. When the user enters a recognized store, the app immediately pushes a lock-screen notification showing the store name and the best card to use — without requiring the user to open the app. Tapping the notification opens the full recommendation detail view.

**Why this priority**: Proactive notification at the point of entry is the primary recommendation delivery mechanism. The app's core value is reaching the user at the right moment without requiring any manual action on their part.

**Independent Test**: Can be tested by walking into a store with the app closed and verifying a notification appears within 30 seconds of entry showing the recommended card.

**Acceptance Scenarios**:

1. **Given** the user has enabled notifications and background location, **When** they enter a store that matches a known store category, **Then** a notification appears within 30 seconds displaying the store name and recommended card
2. **Given** the user taps the notification, **When** the app opens, **Then** it displays the full recommendation with benefit comparison details
3. **Given** the user has disabled notifications, **When** they enter a store, **Then** no notification appears and the recommendation is only shown when the app is opened manually

---

### User Story 4 - No-Match & No-Card Graceful Handling (Priority: P4)

A user opens the app in a location that the system cannot identify as a known store, or all cards in their wallet are non-credit cards. The app clearly communicates what it could and could not determine, and guides the user to a useful next step.

**Why this priority**: Error states must be handled gracefully for the app to feel trustworthy and production-ready, but this does not deliver new user value on its own.

**Independent Test**: Can be tested by opening the app in an unrecognized location (home, park) and verifying the app displays an appropriate "could not identify store" message rather than crashing or showing a wrong recommendation.

**Acceptance Scenarios**:

1. **Given** the user opens the app in a location that does not match a known store, **When** the location check completes, **Then** the app displays a message indicating the store could not be identified and invites the user to search manually or wait until at a recognized location
2. **Given** the user's wallet contains only debit cards or non-payment passes, **When** the app scans their wallet, **Then** the app informs them no eligible credit cards were found and prompts them to add a credit card to their wallet
3. **Given** two cards tie on reward rate for the current store category, **When** the recommendation is shown, **Then** both cards are displayed as equally optimal with a note that either is a great choice

---

### Edge Cases

- What happens when the user's location permission is denied? App must explain the limitation and allow manual store category selection as a fallback.
- What happens when a card's benefits have a monthly or annual spending cap? App should indicate when a cap applies, if known.
- What happens when a store is near a category boundary (e.g., a Walmart that could be "Grocery" or "Retail")? App should display the matched category and allow the user to override it.
- What happens when the app is opened in airplane mode or with no internet connection? App should still function with locally cached location and benefit data.
- What happens when a new card is added to the wallet after the app is installed? App should detect newly added cards on next launch.
- What happens when two or more cards have identical reward rates for the current store? Show all equally optimal cards.
- What happens when the user briefly passes by a store (e.g., walks past the entrance without entering)? A geofence entry event may still fire; the notification will appear and the user can dismiss it — no special suppression is applied.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: App MUST read the list of payment cards currently stored in the user's digital wallet upon user permission grant
- **FR-002**: App MUST identify the user's current location and match it to a recognized store and store category
- **FR-003**: App MUST support at minimum the following store categories: Grocery, Gas & Fuel, Restaurants & Dining, Travel, Drugstore/Pharmacy, Department Store, Entertainment, Online/General Retail
- **FR-004**: App MUST compare the reward rates of all eligible credit cards for the identified store category
- **FR-005**: App MUST display a primary card recommendation with the reason for the selection (reward rate advantage over alternatives)
- **FR-006**: App MUST allow users to view all credit cards detected in their wallet
- **FR-007**: App MUST allow users to view and edit reward rates per card per store category
- **FR-008**: App MUST display the benefit comparison between the top recommended card and the user's other cards
- **FR-009**: App MUST handle gracefully when no store can be identified at the current location
- **FR-010**: App MUST handle gracefully when no eligible credit cards are found in the user's wallet
- **FR-011**: App MUST allow users to manually select a store category when automatic detection fails or is incorrect
- **FR-012**: App MUST request only the minimum required permissions (wallet read access, always-on background location, and notifications) and explain to the user why each is needed at the time of the request
- **FR-012a**: App MUST request background location access with a clear explanation that it is used solely to detect when the user enters a store and trigger a card recommendation notification
- **FR-012b**: App MUST function as a read-only detail viewer (showing the last recommendation) if the user denies background location, while clearly informing them that proactive notifications require background location to be enabled
- **FR-013**: App MUST display a card recommendation within 5 seconds of opening the app while at a recognized store location
- **FR-014**: System MUST pre-populate reward rates for detected wallet cards using a built-in database of well-known credit card reward programs, covering at minimum the 50 most common US consumer credit cards
- **FR-015**: System MUST allow users to override any pre-populated reward rate per card per store category, with user overrides taking permanent precedence over database values
- **FR-015a**: System MUST allow users to set a custom per-point valuation (cents per point) per card to control how points-based rewards are converted to a cash equivalent for comparison purposes; default is 1 point = 1 cent
- **FR-016**: System MUST clearly distinguish pre-populated (database) rates from user-confirmed or user-overridden rates in the card benefits view
- **FR-017**: System MUST sync all user-customized card data (overrides, per-point valuations, settings) via iCloud, with graceful fallback to local-only storage when iCloud is unavailable
- **FR-018**: System MUST fire a notification on every detected store entry event with no deduplication; users may manage notification frequency via the device's system notification settings

### Key Entities

- **Payment Card**: A credit card detected from the user's digital wallet, identified by card name, issuing bank, last four digits, and associated reward rates per store category
- **Store Category**: A classification of retail store type (e.g., Grocery, Gas & Fuel, Restaurant) that determines which card reward rates apply
- **Store Location**: A specific physical retail location matched to a store category based on the user's current GPS coordinates
- **Card Benefit**: A reward rate linked to a specific card and store category, expressed as either a cash back percentage or a points multiplier. Points-based benefits are normalized to an effective cash back equivalent using the card's per-point valuation (default: 1 point = 1 cent) to enable direct comparison across reward types. Optionally includes a spending cap.
- **Recommendation**: The app's output for a given store visit — identifying the highest-benefit card, the benefit rate, and a comparison showing the advantage over the user's other cards

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users receive a card recommendation within 5 seconds of opening the app while physically at a recognized store location
- **SC-002**: The app correctly identifies store category for at least 85% of major national retail chain locations
- **SC-003**: The app selects the card with the highest reward rate for the current store category in 100% of cases where benefit data is available for at least two cards
- **SC-004**: 90% of first-time users successfully receive and understand a card recommendation during their first store visit without needing external help
- **SC-005**: Users can add or correct a card's reward rate for a store category in under 90 seconds
- **SC-006**: App functions and displays the last known recommendation in offline mode without crashing

## Scope & Boundaries

### In Scope

- Reading credit card identities (name, issuer, last four digits) from the user's digital wallet
- Detecting user's current location and matching to a known store and store category
- Comparing reward rates across cards and displaying the best card for the current store
- Allowing users to view and edit card benefit rates by store category
- Support for the 8 core store categories listed in FR-003
- Graceful handling of unrecognized locations, no eligible cards, and tied reward rates

### Out of Scope

- Executing or initiating payments on the user's behalf
- Storing or transmitting actual card numbers, CVVs, or full financial account data
- Integrating with bank or card issuer accounts to automatically retrieve transaction history or real-time spending caps
- Providing financial or investment advice
- Supporting non-iPhone platforms in the initial release
- Managing loyalty/rewards point redemption or balance tracking

## Assumptions

- The app will only read card metadata (name, issuer, last four digits) from the wallet — never full card numbers or sensitive payment credentials
- Reward rates for cards are pre-populated from a built-in database of well-known credit card reward programs; users can override any rate per card per category, and overrides permanently take precedence over database values
- Location matching will use the device's GPS combined with a store location database to identify the current store and category
- The app will not require user account creation — all user-customized data (card overrides, per-point valuations, settings) is stored locally and synced across the user's Apple devices via iCloud under their existing Apple ID
- "Most beneficial" is defined as the highest effective reward value for the store's category, with points-based rewards normalized to a cash equivalent using a default valuation of 1 point = 1 cent; users can override this valuation per card
- When a spending cap applies to a card's category benefit, the app will display the cap information if available but will not track cumulative spending to determine cap status
- Users are assumed to have at least one credit card in their Apple Wallet; debit cards and loyalty/transit passes are excluded from benefit comparison

## Dependencies

- Device location services must be available and user-granted for automatic store detection
- User must grant read access to their digital wallet for card detection
- A store location database or mapping service must be available to match GPS coordinates to store categories
- Cards added after initial app setup must be detectable on subsequent app launches without requiring full re-setup
- iCloud availability is required for cross-device sync; if iCloud is unavailable or disabled, the app must fall back to local-only storage and notify the user that sync is paused
