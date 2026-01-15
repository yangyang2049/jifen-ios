//
//  RandomTeamView.swift
//  jifen
//
//  Random team division - pixel perfect copy from HarmonyOS
//

import SwiftUI

struct RandomTeamView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var numPlayers: Int = 0
    @State private var playerBoxes: [PlayerBox] = []
    @State private var touchedIndices: Set<Int> = Set()
    @State private var isAnimating: Bool = false
    @State private var statusText: String = ""
    @State private var showTestButton: Bool = false
    @State private var showResetButton: Bool = false
    @State private var showPlayerSelection: Bool = true
    
    @State private var animationTimer: Timer? = nil
    private let animationColors: [Color] = [
        Color(hex: "475569"), // slate-600
        Color(hex: "007AFF"), // primary blue
        Color(hex: "06b6d4"), // cyan-500
        Color(hex: "10b981"), // emerald-500
        Color(hex: "8b5cf6"), // violet-500
        Color(hex: "ec4899")  // pink-500
    ]
    private let teamColors: [String: Color] = [
        "A": Color(hex: "f43f5e"), // rose-500
        "B": Color(hex: "f59e0b")  // amber-500
    ]
    
    struct PlayerBox: Identifiable {
        let id: Int
        var team: String?
        var backgroundColor: Color
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Main content area
                if showPlayerSelection {
                    buildPlayerSelection(geometry: geometry)
                } else {
                    buildGridContainer(geometry: geometry)
                }
                
                // Floating status bar
                buildStatusBar(geometry: geometry)
                
                // Top right button: Simulate / Try Again
                if showTestButton || showResetButton {
                    buildTopRightButton(geometry: geometry)
                }
            }
        }
        .navigationTitle("随机分组")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            stopAnimation()
        }
    }
    
    @ViewBuilder
    private func buildPlayerSelection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            HStack(spacing: 16) {
                buildPlayerButton(label: "4人", players: 4, geometry: geometry)
                buildPlayerButton(label: "6人", players: 6, geometry: geometry)
                buildPlayerButton(label: "8人", players: 8, geometry: geometry)
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 16)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func buildPlayerButton(label: String, players: Int, geometry: GeometryProxy) -> some View {
        Button(action: { setupGame(players: players) }) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                
                // Player emojis (2 rows)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0..<players/2, id: \.self) { _ in
                            Text("👤")
                                .font(.system(size: 16))
                        }
                    }
                    
                    HStack(spacing: 4) {
                        ForEach(0..<(players - players/2), id: \.self) { _ in
                            Text("👤")
                                .font(.system(size: 16))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "007AFF"))
            )
        }
    }
    
    @ViewBuilder
    private func buildGridContainer(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: getGridColumns()), spacing: 16) {
                ForEach(playerBoxes) { box in
                    PlayerBoxView(box: box)
                        .onTapGesture {
                            handleTouchStart(index: box.id)
                        }
                        .onLongPressGesture(minimumDuration: 0.1, perform: {}) { pressing in
                            if !pressing {
                                handleTouchEnd()
                            }
                        }
                }
            }
            .frame(maxWidth: 500, maxHeight: 500)
            .padding(.horizontal, 16)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func buildStatusBar(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                }
                .padding(.leading, 24)
                
                Spacer()
                
                Text(showPlayerSelection ? "随机分组" : statusText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                if showTestButton || showResetButton {
                    Button(action: {
                        if showResetButton {
                            resetGame()
                        } else {
                            simulateTouches()
                        }
                    }) {
                        Text(showResetButton ? "再来一次" : "模拟")
                            .font(.system(size: 14, weight: showResetButton ? .medium : .regular))
                            .foregroundColor(showResetButton ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(showResetButton ? Color(hex: "007AFF") : Color.white.opacity(0.08))
                            )
                    }
                    .padding(.trailing, 16)
                } else {
                    Spacer().frame(width: 60)
                }
            }
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func buildTopRightButton(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                Spacer()
                
                Button(action: {
                    if showResetButton {
                        resetGame()
                    } else {
                        simulateTouches()
                    }
                }) {
                    Text(showResetButton ? "再来一次" : "模拟")
                        .font(.system(size: 14, weight: showResetButton ? .medium : .regular))
                        .foregroundColor(showResetButton ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(showResetButton ? Color(hex: "007AFF") : Color.white.opacity(0.08))
                        )
                }
                .padding(.trailing, 16)
            }
            
            Spacer()
        }
        .padding(.top, 16)
    }
    
    private func getGridColumns() -> Int {
        if numPlayers == 4 { return 2 }
        if numPlayers == 6 { return 3 }
        if numPlayers == 8 { return 4 } // Tablet uses 4, phone uses 2
        return 2
    }
    
    private func setupGame(players: Int) {
        numPlayers = players
        isAnimating = false
        touchedIndices = Set()
        showResetButton = false
        showTestButton = true
        showPlayerSelection = false
        
        playerBoxes = (0..<players).map { i in
            PlayerBox(id: i, team: nil, backgroundColor: Color(hex: "334155")) // slate-700
        }
        updateStatusText()
    }
    
    private func updateStatusText() {
        if numPlayers == 0 {
            statusText = ""
        } else if touchedIndices.count < numPlayers {
            statusText = "请将手指放在方块上 (\(touchedIndices.count)/\(numPlayers))"
        } else {
            statusText = "正在分组..."
        }
    }
    
    private func handleTouchStart(index: Int) {
        guard !isAnimating && !showResetButton else { return }
        
        touchedIndices.insert(index)
        if let i = playerBoxes.firstIndex(where: { $0.id == index }) {
            playerBoxes[i].backgroundColor = Color(hex: "007AFF") // primary blue
        }
        updateStatusText()
        checkStartCondition()
    }
    
    private func handleTouchEnd() {
        guard !isAnimating && !showResetButton else { return }
        
        touchedIndices = Set()
        for i in playerBoxes.indices {
            if playerBoxes[i].team == nil {
                playerBoxes[i].backgroundColor = Color(hex: "334155") // slate-700
            }
        }
        updateStatusText()
    }
    
    private func checkStartCondition() {
        if touchedIndices.count == numPlayers && !isAnimating {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = true
        showTestButton = false
        showResetButton = false
        VibrationManager.shared.vibrateMedium()
        
        var flashCount = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            if !isAnimating {
                timer.invalidate()
                animationTimer = nil
                return
            }
            for i in playerBoxes.indices {
                playerBoxes[i].backgroundColor = animationColors.randomElement()!
            }
            flashCount += 1
            if flashCount > 15 {
                timer.invalidate()
                animationTimer = nil
                endAnimation()
            }
        }
        animationTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }
    
    private func endAnimation() {
        // Generate random teams
        var teams: [String] = []
        for _ in 0..<(numPlayers / 2) {
            teams.append("A")
            teams.append("B")
        }
        teams.shuffle()
        
        // Apply results
        for i in playerBoxes.indices {
            let team = teams[i]
            playerBoxes[i].team = team
            playerBoxes[i].backgroundColor = teamColors[team]!
        }
        
        statusText = "分组完成！"
        isAnimating = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showResetButton = true
        }
        VibrationManager.shared.vibrateHeavy()
    }
    
    private func simulateTouches() {
        guard !isAnimating else { return }
        
        touchedIndices = Set(0..<numPlayers)
        for i in playerBoxes.indices {
            playerBoxes[i].backgroundColor = Color(hex: "007AFF")
        }
        updateStatusText()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            checkStartCondition()
        }
    }
    
    private func resetGame() {
        showResetButton = false
        touchedIndices = Set()
        playerBoxes = (0..<numPlayers).map { i in
            PlayerBox(id: i, team: nil, backgroundColor: Color(hex: "334155"))
        }
        startAnimation()
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = false
    }
}

struct PlayerBoxView: View {
    let box: RandomTeamView.PlayerBox
    
    var body: some View {
        ZStack {
            Text(box.team != nil ? box.team! : "\(box.id + 1)")
                .font(.system(size: box.team != nil ? 48 : 36, weight: .bold))
                .foregroundColor(box.team != nil ? .white : .white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(box.backgroundColor)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 4)
    }
}

#Preview {
    NavigationStack {
        RandomTeamView()
    }
}
