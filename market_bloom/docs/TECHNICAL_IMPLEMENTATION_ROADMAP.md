# Technical Implementation Roadmap

## Objective

The technical plan should support a major product upgrade without introducing unnecessary complexity. The goal is to expand PoMarket’s content and retention systems while keeping the architecture maintainable, testable, and compatible with the current Flutter foundation.

## Current Technical Strengths

The project already has several strengths:

- a clear game loop centered around GameController,
- a separation between gameplay state and UI rendering,
- persistent save/load support,
- monetization abstraction for future store and ad integration,
- a modular UI structure with custom painter-based game rendering.

These are strong foundations for a controlled product expansion.

## Recommended Architecture Principles

### 1. Keep the domain model central

Gameplay rules and progression logic should live in the controller and model layer rather than in widgets. This keeps the experience easier to test and easier to evolve.

### 2. Prefer additive systems

New content should be introduced as new systems or extensions rather than large rewrites. Examples include:

- new store zones,
- new upgrade categories,
- event systems,
- new content hooks for quests and milestones.

### 3. Preserve the current UI composition

The current single-screen structure is a strength. The app should continue to use sheets, overlays, and a central game view instead of turning into a full-page app shell.

### 4. Keep data persistence resilient

Because saves can be edited or partially corrupt, the existing defensive parsing pattern should continue to be used.

## Suggested Technical Phases

### Phase 1: Foundation and clarity

Focus on the systems that improve perception and maintainability:

- introduce clearer progression metadata,
- strengthen upgrade definitions and descriptions,
- add more structured content definitions for zones and events,
- improve telemetry and analytics hooks,
- add test coverage around progression and reward loops.

### Phase 2: Content expansion

Introduce new content without overcomplicating the architecture:

- new store zones or departments,
- new themed customer behavior patterns,
- new quest and milestone categories,
- richer reward events and daily structures.

### Phase 3: Live operations readiness

Prepare the game for a more sustained product lifecycle:

- event-driven content systems,
- remote config or content toggles if later needed,
- stronger analytics and funnel tracking,
- optional server-side receipt validation for IAP.

## Data Model Recommendations

A few new model layers would make future growth easier:

- StoreZoneDefinition for zone unlocks and visuals.
- UpgradeDefinition for richer metadata and preview states.
- EventDefinition for limited-time content.
- ContentCatalog for organizing content by phase and unlock level.

These additions can stay lightweight while making the game much easier to expand.

## UI Architecture Recommendations

### Keep the current approach

The current use of a custom-painter market scene and overlay-driven UI is appropriate for this game stage.

### Add structure gradually

Possible UI improvements include:

- a dedicated progression panel,
- better state cards for store and customer activity,
- more modular sheet components,
- additional animation hooks for upgrades and rewards.

## Testing Strategy

The current test suite is a solid starting point. The next phase should add tests for:

- upgrade purchase effects,
- quest milestone progression,
- daily bonus edge cases,
- save/load compatibility,
- reward flow success and failure conditions.

## Dependency Policy

No new dependencies should be introduced during the planning phase. If content expansion proceeds, dependencies should only be added when they clearly solve a real product need and can be justified in the implementation plan.

## Risks and Mitigations

### Risk: Feature sprawl

Mitigation: define a tight scope per phase and prioritize from the player experience first.

### Risk: Overly complex progression systems

Mitigation: keep systems readable and tied to visible store improvement.

### Risk: UI fragmentation

Mitigation: keep the main screen as the center of the experience and use overlays for secondary views.

### Risk: Save incompatibility

Mitigation: preserve defensive parsing and version-aware migration patterns.

## Recommended Implementation Order

1. Refine progression and content definitions.
2. Add clearer upgrade and reward presentation.
3. Expand store personality and zone variety.
4. Add retention hooks and event structures.
5. Prepare analytics, monetization robustness, and store readiness.

## Recommendation

The best technical path is not a rewrite. The best path is to extend the existing model and UI architecture in a controlled, test-driven way so the product can grow in a stable and maintainable fashion.
