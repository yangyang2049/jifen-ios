//
//  ScoreboardTab.swift
//  jifen
//
//  Scoreboard tab - entry point for all sports scoreboards
//

import SwiftUI

struct ScoreboardTab: View {
    @State private var selectedSport: SportItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        // Sports grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: Theme.spacing),
                            GridItem(.flexible(), spacing: Theme.spacing)
                        ], spacing: Theme.spacing) {
                            ForEach(sports) { sport in
                                SportCardView(sport: sport) {
                                    selectedSport = sport
                                }
                            }
                        }
                        .padding(.horizontal, Theme.padding)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("scoreboard_title", comment: "Scoreboard title"))
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .navigationDestination(item: $selectedSport) { sport in
                sport.view
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .accentColor(Theme.accentColor)
    }
    
    private var sports: [SportItem] {
        [
            SportItem(emoji: "🏓", title: GameType.pingpong.displayName, gameType: .pingpong, view: AnyView(PingPongScoreboardView())),
            SportItem(emoji: "🏸", title: GameType.badminton.displayName, gameType: .badminton, view: AnyView(BadmintonScoreboardView())),
            SportItem(emoji: "🎾", title: GameType.tennis.displayName, gameType: .tennis, view: AnyView(TennisScoreboardView())),
            SportItem(emoji: "🏀", title: GameType.basketball.displayName, gameType: .basketball, view: AnyView(Text("\(GameType.basketball.displayName) \(NSLocalizedString("not_implemented", comment: "Not implemented"))").foregroundColor(.white))),
            SportItem(emoji: "⚽", title: GameType.football.displayName, gameType: .football, view: AnyView(Text("\(GameType.football.displayName) \(NSLocalizedString("not_implemented", comment: "Not implemented"))").foregroundColor(.white))),
            SportItem(emoji: "🏐", title: GameType.volleyball.displayName, gameType: .volleyball, view: AnyView(Text("\(GameType.volleyball.displayName) \(NSLocalizedString("not_implemented", comment: "Not implemented"))").foregroundColor(.white)))
        ]
    }
}

struct SportItem: Identifiable, Hashable {
    let id = UUID()
    let emoji: String
    let title: String
    let gameType: GameType
    
    // Hashable conformance (excluding view)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(emoji)
        hasher.combine(title)
        hasher.combine(gameType)
    }
    
    static func == (lhs: SportItem, rhs: SportItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // Store view separately (not in hashable)
    let view: AnyView
}

struct SportCardView: View {
    let sport: SportItem
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            VStack(spacing: 12) {
                Text(sport.emoji)
                    .font(.system(size: 48))
                
                Text(sport.title)
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.cardBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ScoreboardTab()
}