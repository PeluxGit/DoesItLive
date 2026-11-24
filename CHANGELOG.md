# Changelog

All notable changes to this addon are documented here, following [Keep a Changelog](https://keepachangelog.com/) conventions.

## [Unreleased]

### Fixed

- EllesmereUI frames could show a second block on the power bar.
- With high latency, the block of a HoT cast in combat could stay out of step with its ticks.
- On a druid's EllesmereUI player frame, out of Cat Form, the block now covers the full height of the health bar.

## [2026-11-22]

First release.

### Added

- A block on health bars showing the healing your Rejuvenation and Regrowth still have to do, after current health and incoming heals. Wild Growth, Renew and Riptide are supported but untested.
- Works on EllesmereUI frames. Blizzard, BetterBlizzFrames and ElvUI/oUF frames, and friendly nameplates (EllesmereUI, Platynator, Threat Plates, Blizzard and others), are supported but untested.
- Crits counted at their average, with an option to show only the healing you're sure of.
- Options window (`/dil`) with a live preview and four presets: Minimal, Classic, Juicy and Debug.
