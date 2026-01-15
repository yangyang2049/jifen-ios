//
//  PointsTableView.swift
//  jifen
//
//  Points table tool
//

import SwiftUI

struct PointsTableView: View {
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
                            Text("暂无玩家")
                                .font(.headline)
                                .foregroundColor(Theme.textSecondary)
                            
                            Button(action: { showAddPlayer = true }) {
                                Text("添加玩家")
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
        .navigationTitle("积分表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddPlayer = true }) {
                    Image(systemName: "plus")
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
                TextField("玩家名称", text: $newPlayerName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button(action: addPlayer) {
                    Text("添加")
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
            .navigationTitle("添加玩家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
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

