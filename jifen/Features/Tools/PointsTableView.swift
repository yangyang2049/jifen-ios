//
//  PointsTableView.swift
//  jifen
//
//  Points table tool
//

import SwiftUI

struct PointsTableView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var players: [Player] = []
    @State private var showAddPlayer = false
    @State private var newPlayerName = ""
    
    struct Player: Identifiable {
        let id = UUID()
        var name: String
        var points: Int = 0
    }
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            VStack {
                    if players.isEmpty {
                        VStack(spacing: 20) {
                            Text(NSLocalizedString("no_players", comment: "No players"))
                                .font(.headline)
                                .foregroundColor(Theme.textSecondary)
                            
                            Button(action: { showAddPlayer = true }) {
                                Text(NSLocalizedString("add_player", comment: "Add Player"))
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                            .fill(Theme.accentColor)
                                    )
                            }
                            .padding(.horizontal, Theme.padding)
                        }
                    } else {
                        List {
                            ForEach(players) { player in
                                HStack {
                                    Text(player.name)
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    HStack(spacing: 20) {
                                        Button(action: { decreasePoints(for: player) }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        
                                        Text("\(player.points)")
                                            .font(.headline)
                                            .foregroundColor(Theme.textPrimary)
                                            .frame(minWidth: 50)
                                        
                                        Button(action: { increasePoints(for: player) }) {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .listRowBackground(Theme.cardBackground)
                            }
                            .onDelete(perform: deletePlayers)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
            }
        }
        .navigationTitle(NSLocalizedString("points_table_title", comment: "Points Table title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddPlayer = true }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showAddPlayer) {
            addPlayerSheet
        }
        .preferredColorScheme(.dark)
    }
    
    private var addPlayerSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField(NSLocalizedString("player_name", comment: "Player Name"), text: $newPlayerName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button(action: addPlayer) {
                    Text(NSLocalizedString("add", comment: "Add"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(Theme.accentColor)
                        )
                }
                .padding(.horizontal, Theme.padding)
                .disabled(newPlayerName.isEmpty)
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("add_player_title", comment: "Add Player title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "Cancel")) {
                        showAddPlayer = false
                        newPlayerName = ""
                    }
                }
            }
        }
    }
    
    private func addPlayer() {
        guard !newPlayerName.isEmpty else { return }
        players.append(Player(name: newPlayerName))
        newPlayerName = ""
        showAddPlayer = false
    }
    
    private func increasePoints(for player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].points += 1
            VibrationManager.shared.vibrateLight()
        }
    }
    
    private func decreasePoints(for player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].points = max(0, players[index].points - 1)
            VibrationManager.shared.vibrateLight()
        }
    }
    
    private func deletePlayers(at offsets: IndexSet) {
        players.remove(atOffsets: offsets)
    }
}

#Preview {
    PointsTableView()
}

