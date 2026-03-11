---
phase: 06-infrastructure-app-polish
plan: 05
subsystem: ui
tags: [swiftui, homeview, recording, onboarding, liquid-glass]
status: complete
commits: [604a846, ada363b, 2e4b391, c3d97f4, 3a61a4a, 1b6985d, 8ef1b46, 1e1732e, 01236c0, 50ddb1c, 171de30]
---

## What Was Done

Fixed HomeView stale state after onboarding, recording screen immersive UI, and applied Liquid Glass polish.

### Changes
- **DictusApp.swift**: Added onChange handler to refresh model state when onboarding completes
- **HomeView.swift**: Vertically centered content layout, fixed stale model display
- **DictationCoordinator.swift**: Removed auto-idle timer, explicit resetStatus from RecordingView
- **RecordingView.swift**: Stable layout with tap-to-copy, sinusoidal processing waveform, nav bar stays hidden until user action, Liquid Glass press animations
- **MainTabView.swift**: Liquid Glass styling on tab elements
- **AnimatedMicButton.swift**: Liquid Glass press animations

### UAT Results
- Test 4 (Fresh State After Onboarding): **pass**
- Test 5 (Recording Screen Immersive UI): **pass**
- Test 6 (Onboarding No Swiping): **pass**
- Test 7 (Keyboard Auto-Detection): **pass**
