# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an iOS SwiftUI application for music listening tracking and analytics. The app uses Core Data with CloudKit sync to track user listening sessions and generate weekly statistics. Currently in early development with sophisticated backend architecture but basic UI implementation.

## Development Commands

**Note**: This project requires Xcode for building. Command line tools alone are insufficient.

```bash
# Build the project
xcodebuild -project MusicTracking.xcodeproj -scheme MusicTracking build

# Build for iOS Simulator
xcodebuild -project MusicTracking.xcodeproj -scheme MusicTracking -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests (when test targets exist)  
xcodebuild -project MusicTracking.xcodeproj -scheme MusicTracking test

# Open in Xcode
open MusicTracking.xcodeproj
```

## Architecture

### Core Data Model
The app uses two main entities with CloudKit sync:

- **ListeningSession**: Tracks individual listening sessions with song metadata, duration, and play counts
- **WeeklyStats**: Aggregates weekly listening statistics including total play time and top songs

### Key Components
- `MusicTrackingApp.swift`: App entry point with Core Data stack
- `ContentView.swift`: Main UI (currently placeholder implementation)
- `MusicTracking.xcdatamodeld/`: Core Data model with CloudKit configuration

### Background Processing
Two background task identifiers configured:
- `jaba.MusicTracking.cleanup`: Data maintenance tasks
- `jaba.MusicTracking.stats`: Statistics calculation

## Permissions & Capabilities

The app requires several sensitive permissions:
- Apple Music library access (configured in Info.plist)
- Background App Refresh for data processing
- CloudKit for cross-device sync
- Push notifications (development environment)

## Development Notes

- Data model is designed for real-time music tracking with weekly analytics
- CloudKit sync requires proper Apple Developer account setup
- UI follows SwiftUI/MVVM patterns
- Background tasks handle data processing without affecting user experience
- All music listening data requires careful privacy consideration