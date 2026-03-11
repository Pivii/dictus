---
phase: 06-infrastructure-app-polish
plan: 04
subsystem: infra
tags: [app-icon, brand-kit, coregraphics, xcassets]
status: complete
commits: [42ba74f]
---

## What Was Done

Fixed app icon generation script to match brand kit SVG proportions exactly.

### Changes
- **scripts/generate-app-icon.swift**: Corrected bar geometry — removed 1.2x scale factor, fixed positioning from forced bottom-alignment to brand kit staggered positions
- **AppIcon-1024.png**: Regenerated standard icon with correct bar proportions
- **AppIcon-1024-dark.png**: Added distinct dark variant with surface gradient (#1C2333 → #111827) and brighter bar colors
- **Tinted icon**: Uses correct brand kit geometry

### UAT Result
Test 1 (App Icon on Home Screen): **pass**
