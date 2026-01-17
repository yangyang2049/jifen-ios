# iScore - Multi-Platform Sports Scoring & Timing App

## Overview

**iScore** is a comprehensive multi-platform application designed for sports enthusiasts, coaches, and referees to manage scoring, timing, and various competition tools. The app provides an intuitive interface for tracking scores across multiple sports while offering additional utility tools for competitions.

## Platform Support

- **iOS App**: Main application built with SwiftUI
- **WatchOS App**: Companion app for Apple Watch
- **HarmonyOS App**: Huawei ecosystem version built with ArkTS/ETS

## Core Features

### 🏆 Sports Scoreboard
Supports comprehensive scoring for multiple sports with customizable rules:

**Racket Sports:**
- Badminton
- Table Tennis (Ping Pong)
- Tennis

**Team Sports:**
- Football (Soccer)
- Basketball
- Volleyball

**Other Sports:**
- Boxing
- Billiards
- Pickleball

**Traditional Games:**
- Go (Weiqi)
- Chinese Chess (Xiangqi)
- Chess
- Guandan
- Doudizhu

### ⏱️ Timer Functionality
Advanced timing features for strategic games:
- Configurable time controls
- Game phase management
- Pause/resume capabilities
- Multiple timer presets

### 🛠️ Competition Tools
Essential utilities for referees and players:

**Match Tools:**
- 🎲 Dice Roller
- 🪙 Coin Flip
- 🔔 Whistle (audio cues)
- 👥 Random Team Generator
- 🟨 Red/Yellow Card System
- 📊 Points Table

**Utility Tools:**
- 🕐 Time & Date Tool
- 💰 AA Calculator (Dutch treat calculator)
- ⏱️ 10-Second Challenge

## Technical Architecture

### iOS Implementation (SwiftUI)
```
jifen/
├── Core/                    # Core functionality
│   ├── Managers/           # Business logic managers
│   ├── Network/            # API communication
│   └── Theme/              # UI theming system
├── Features/               # Feature modules
│   ├── Home/               # Main dashboard
│   ├── Scoreboard/         # Sports scoring interface
│   ├── Timer/              # Timing functionality
│   └── Tools/              # Competition utilities
├── Resources/              # Assets and localization
└── Watch App/              # watchOS companion
```

### Key Components

**Managers:**
- `ScoreboardRecordsViewModel` - Score tracking
- `QuickStartConfigManager` - User preferences
- `SoundManager` - Audio feedback
- `VibrationManager` - Haptic feedback
- `FontRegistrar` - Custom typography

**Views:**
- `MainTabView` - Primary navigation (Home/Score/Tools)
- `HomeTab` - Dashboard with quick actions
- `ScoreboardTab` - Sports-specific scoring interfaces
- `ToolsTab` - Competition utilities grid

### HarmonyOS Implementation (ArkTS)
```
home/, *.ets files/
├── components/             # Reusable UI components
├── models/                 # Data models and types
├── viewmodel/              # State management
└── managers/               # Business logic
```

## Design System

### Color Scheme
- **Primary**: Dark theme optimized (#1a1a1a background)
- **Accent**: iOS green (#32D74B)
- **Text**: White primary, 60% opacity secondary
- **Cards**: Dark overlays (#000000) with subtle borders

### Typography
- Custom 7-segment font for score displays
- System fonts for UI elements
- Responsive text sizing

### Interaction Design
- Tab-based navigation
- Modal presentations for tools
- Swipe gestures for card systems
- Haptic feedback integration
- Sound effects for actions

## Data Management

### Record Types
- **Scoreboard Records**: Match results with team/player scores
- **Timer Records**: Game timing sessions
- **Activity History**: Combined chronological view

### Storage
- Local persistence with managers
- Background synchronization
- Record export capabilities

## Localization

### Supported Languages
- English (`en.lproj`)
- Chinese Simplified (`zh-Hans.lproj`)

### String Resources
- 100+ localized strings
- Sports-specific terminology
- Tool descriptions and instructions

## Audio & Haptic Feedback

### Sound Assets
- Buzzer sounds
- Dice rolling effects
- Coin flip audio
- Whistle tones
- UI interaction sounds

### Vibration Patterns
- Score changes
- Timer alerts
- Game state transitions

## Build System

### iOS
- Xcode project with SwiftUI
- CocoaPods/ SPM dependencies
- Asset catalog management
- Multi-target configuration (iOS + WatchOS)

### HarmonyOS
- ArkTS/ETS compilation
- Huawei DevEco Studio
- Cross-platform component library

## Development Status

### Current Features ✅
- Complete sports scoreboard system
- Timer functionality for strategic games
- Full suite of competition tools
- Multi-platform support (iOS/WatchOS/HarmonyOS)
- Dark theme optimization
- Localization support
- Audio/haptic feedback

### Architecture Highlights
- MVVM pattern implementation
- Modular feature organization
- Cross-platform code sharing
- Responsive design system
- Comprehensive error handling

## Target Audience

- **Sports Enthusiasts**: Casual players tracking scores
- **Coaches**: Training session management
- **Referees**: Professional officiating tools
- **Competitors**: Tournament preparation and tracking
- **Event Organizers**: Multi-sport event management

## Unique Value Proposition

iScore distinguishes itself through:
- **Multi-platform availability** across major ecosystems
- **Comprehensive sports coverage** from casual to professional
- **Integrated tool suite** reducing need for multiple apps
- **Professional-grade features** suitable for official use
- **Intuitive design** optimized for fast-paced environments

---

**Repository**: https://github.com/yangyang2049/jifen_ios
**Platform**: iOS 15+, WatchOS 8+, HarmonyOS 3.1+
**Language**: Swift (iOS), ArkTS (HarmonyOS)
**Architecture**: SwiftUI, MVVM, Modular Design
