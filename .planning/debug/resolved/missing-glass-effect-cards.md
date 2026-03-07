---
status: resolved
trigger: "Models and Settings cards missing glass effect — flat cards instead of Liquid Glass"
created: 2026-03-07T00:00:00Z
updated: 2026-03-07T00:00:00Z
---

## Current Focus

hypothesis: ModelManagerView and SettingsView use native List without .dictusGlass(), while HomeView manually applies it to each card
test: compare styling patterns across all three views
expecting: HomeView uses .dictusGlass() on card containers; other views use plain List rows
next_action: return diagnosis

## Symptoms

expected: All three tabs (Home, Models, Settings) should have consistent Liquid Glass card styling
actual: Home tab cards have glass effect; Models and Settings tabs show regular flat List rows
errors: none (cosmetic only)
reproduction: open each tab and compare card appearance visually
started: since views were created — glass was only applied to HomeView

## Eliminated

(none needed — root cause identified on first pass)

## Evidence

- timestamp: 2026-03-07
  checked: HomeView.swift lines 85, 101, 120
  found: .dictusGlass() applied to modelStatusCard (line 85, 101) and transcriptionCard (line 120)
  implication: HomeView explicitly wraps each card's padding container with glass modifier

- timestamp: 2026-03-07
  checked: ModelManagerView.swift — full file
  found: Uses SwiftUI List with ModelRow. No .dictusGlass() anywhere. Rows are plain HStack with .padding(.vertical, 4). No background material applied to rows or sections.
  implication: Model rows render with default List row styling — no glass effect

- timestamp: 2026-03-07
  checked: SettingsView.swift — full file
  found: Uses SwiftUI List with Section groups. No .dictusGlass() anywhere. Standard List { Section { ... } } pattern with no custom card styling.
  implication: Settings renders with default grouped List styling — no glass effect

- timestamp: 2026-03-07
  checked: GlassModifier.swift
  found: Provides .dictusGlass() (RoundedRectangle) and .dictusGlassBar() (Capsule). Works correctly — HomeView proves it.
  implication: The modifier exists and works; it simply was never applied in the other two views

## Resolution

root_cause: ModelManagerView and SettingsView use native SwiftUI List without applying .dictusGlass() to any surfaces. HomeView uses a ScrollView + VStack pattern with .dictusGlass() on each card container — this is the pattern that produces the glass effect. The List-based views have no equivalent glass treatment.
fix: (not applied — diagnosis only)
verification: (not applied)
files_changed: []
