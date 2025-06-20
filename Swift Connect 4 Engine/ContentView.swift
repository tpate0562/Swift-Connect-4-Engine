import SwiftUI
import Combine

class Settings: ObservableObject {
    @Published var showProbabilities: Bool = false
    @Published var simulations: Int = 400
    @Published var userGoesFirst: Bool = true
}

struct ContentView: View {
    @StateObject private var settings = Settings()
    @StateObject private var game = ConnectFourGame()
    @State private var showingSettings = false
    @State private var showWhoStarts = false

    var body: some View {
        VStack {
            HStack {
                Text(game.status)
                    .font(.headline)
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                }
            }
            .padding(.horizontal)

            BoardView(board: game.board,
                      showProbabilities: settings.showProbabilities,
                      redProbabilities: game.redProbabilities,
                      yellowProbabilities: game.yellowProbabilities,
                      onColumnTap: { col in
                          game.userMove(in: col)
                      })
            .padding()

            if game.isGameOver {
                Button("Restart Game") {
                    showWhoStarts = true
                }
                .padding()
            }
        }
        .onAppear {
            game.applySettings(settings)
            showWhoStarts = true
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
                .presentationDetents([.medium])
                .onDisappear {
                    game.applySettings(settings)
                }
        }
        .sheet(isPresented: $showWhoStarts) {
            WhoStartsSheet(userGoesFirst: $settings.userGoesFirst) {
                game.applySettings(settings)
                game.reset()
                showWhoStarts = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct BoardView: View {
    let board: [[Token?]]
    let showProbabilities: Bool
    let redProbabilities: [Double]?
    let yellowProbabilities: [Double]?
    let onColumnTap: (Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if showProbabilities, let red = redProbabilities, let yellow = yellowProbabilities {
                HStack(spacing: 4) {
                    ForEach(0..<ConnectFourGame.cols, id: \.self) { c in
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f%%", red[c] * 100))
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text(String(format: "%.1f%%", yellow[c] * 100))
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                        .frame(width: 40)
                    }
                }
            }
            ForEach(0..<ConnectFourGame.rows, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<ConnectFourGame.cols, id: \.self) { c in
                        Circle()
                            .foregroundColor(color(for: board[r][c]))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                            .onTapGesture {
                                if board[0][c] == nil {
                                    onColumnTap(c)
                                }
                            }
                    }
                }
            }
        }
        .background(Color.blue.opacity(0.4))
        .cornerRadius(8)
    }
    
    func color(for token: Token?) -> Color {
        switch token {
        case .red: return .red
        case .yellow: return .yellow
        case .none: return .white
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var body: some View {
        NavigationView {
            Form {
                Toggle("Show Probabilities", isOn: $settings.showProbabilities)
                Stepper("Simulations: \(settings.simulations)", value: $settings.simulations, in: 50...2000, step: 50)
                Picker("Who goes first?", selection: $settings.userGoesFirst) {
                    Text("You").tag(true)
                    Text("AI").tag(false)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .navigationTitle("Settings")
        }
    }
}

struct WhoStartsSheet: View {
    @Binding var userGoesFirst: Bool
    var onStart: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Who should go first?")
                .font(.headline)
            Picker("", selection: $userGoesFirst) {
                Text("You").tag(true)
                Text("AI").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            Button("Start Game") { onStart() }
                .padding(.top)
        }
        .padding()
    }
}

enum Token: String, Codable {
    case red, yellow
}

final class ConnectFourGame: ObservableObject {
    static let rows = 6
    static let cols = 7

    @Published var board: [[Token?]] = Array(repeating: Array(repeating: nil, count: cols), count: rows)
    @Published var status: String = ""
    @Published var isGameOver: Bool = false
    @Published var redProbabilities: [Double]? = nil
    @Published var yellowProbabilities: [Double]? = nil

    private var simulations = 400
    private var userGoesFirst = true
    private var redIsAI = true
    private var yellowIsAI = false
    private(set) var currentPlayer: Token = .red

    func applySettings(_ settings: Settings) {
        simulations = settings.simulations
        userGoesFirst = settings.userGoesFirst
        // On settings change, update probabilities immediately if board is not full/game not over
        if !isGameOver {
            updateProbabilities()
        }
    }

    init() { reset() }

    func reset() {
        board = Array(repeating: Array(repeating: nil, count: ConnectFourGame.cols), count: ConnectFourGame.rows)
        currentPlayer = userGoesFirst ? .yellow : .red
        isGameOver = false
        status = userGoesFirst ? "Yellow (You) to move" : "Red (AI) to move"
        updateProbabilities()
        if currentPlayer == .red {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.AIMove() }
        }
    }

    func userMove(in column: Int) {
        guard !isGameOver, currentPlayer == .yellow else { return }
        if makeMove(column: column, token: .yellow) {
            checkEndOrContinue()
        }
    }

    func AIMove() {
        guard !isGameOver, currentPlayer == .red else { return }
        let move = monteCarloBestMove(for: .red)
        if let move {
            _ = makeMove(column: move, token: .red)
            checkEndOrContinue()
        }
    }

    // Returns true if move succeeds
    private func makeMove(column: Int, token: Token) -> Bool {
        for row in (0..<ConnectFourGame.rows).reversed() {
            if board[row][column] == nil {
                board[row][column] = token
                currentPlayer = (token == .red) ? .yellow : .red
                updateProbabilities()
                return true
            }
        }
        return false
    }

    private func checkEndOrContinue() {
        if let winner = checkWinner() {
            status = "\(winner.rawValue.capitalized) wins!"
            isGameOver = true
            redProbabilities = nil
            yellowProbabilities = nil
        } else if isBoardFull() {
            status = "It's a draw!"
            isGameOver = true
            redProbabilities = nil
            yellowProbabilities = nil
        } else {
            status = currentPlayer == .red ? "Red (AI) to move" : "Yellow (You) to move"
            if currentPlayer == .red { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.AIMove() } }
        }
    }

    // Monte Carlo simulation to pick best move for a player and calculate per-column probabilities
    private func monteCarloBestMove(for player: Token) -> Int? {
        var moveScores = Array(repeating: 0, count: ConnectFourGame.cols)
        var plays = Array(repeating: 0, count: ConnectFourGame.cols)
        for col in 0..<ConnectFourGame.cols {
            if board[0][col] != nil { continue }
            for _ in 0..<simulations {
                var simBoard = board
                _ = drop(in: col, token: player, on: &simBoard)
                if checkWinner(on: simBoard, for: player) != nil {
                    moveScores[col] += 1
                } else if simulateRandomPlayout(from: simBoard, starting: player == .red ? .yellow : .red) == player {
                    moveScores[col] += 1
                }
                plays[col] += 1
            }
        }
        let bestScore = moveScores.max()
        guard let best = bestScore, best > 0, let bestCol = moveScores.enumerated().filter({ board[0][$0.offset] == nil }).max(by: { $0.element < $1.element })?.offset else {
            return (0..<ConnectFourGame.cols).first(where: { board[0][$0] == nil })
        }
        return bestCol
    }

    private func updateProbabilities() {
        // Only update if game not over
        if isGameOver {
            redProbabilities = nil
            yellowProbabilities = nil
            return
        }
        redProbabilities = monteCarloProbabilities(for: .red)
        yellowProbabilities = monteCarloProbabilities(for: .yellow)
    }

    private func monteCarloProbabilities(for player: Token) -> [Double] {
        var moveScores = Array(repeating: 0, count: ConnectFourGame.cols)
        var plays = Array(repeating: 0, count: ConnectFourGame.cols)
        for col in 0..<ConnectFourGame.cols {
            if board[0][col] != nil { continue }
            for _ in 0..<simulations / 5 { // Fewer for display speed
                var simBoard = board
                _ = drop(in: col, token: player, on: &simBoard)
                if checkWinner(on: simBoard, for: player) != nil {
                    moveScores[col] += 1
                } else if simulateRandomPlayout(from: simBoard, starting: player == .red ? .yellow : .red) == player {
                    moveScores[col] += 1
                }
                plays[col] += 1
            }
        }
        return (0..<ConnectFourGame.cols).map { plays[$0] > 0 ? Double(moveScores[$0]) / Double(plays[$0]) : 0.0 }
    }

    private func simulateRandomPlayout(from board: [[Token?]], starting: Token) -> Token? {
        var simBoard = board
        var player = starting
        while true {
            if isBoardFull(board: simBoard) { return nil }
            let validMoves = (0..<ConnectFourGame.cols).filter { simBoard[0][$0] == nil }
            guard let move = validMoves.randomElement() else { return nil }
            _ = drop(in: move, token: player, on: &simBoard)
            if let winner = checkWinner(on: simBoard, for: player) {
                return winner
            }
            player = (player == .red) ? .yellow : .red
        }
    }

    // Returns winner if there is one
    private func checkWinner() -> Token? {
        checkWinner(on: board, for: .red) ?? checkWinner(on: board, for: .yellow)
    }
    private func checkWinner(on board: [[Token?]], for token: Token) -> Token? {
        for r in 0..<ConnectFourGame.rows {
            for c in 0..<ConnectFourGame.cols {
                guard board[r][c] == token else { continue }
                // Horizontal
                if c <= ConnectFourGame.cols - 4 && (1...3).allSatisfy({ board[r][c+$0] == token }) { return token }
                // Vertical
                if r <= ConnectFourGame.rows - 4 && (1...3).allSatisfy({ board[r+$0][c] == token }) { return token }
                // Diagonal /\
                if r >= 3 && c <= ConnectFourGame.cols - 4 && (1...3).allSatisfy({ board[r-$0][c+$0] == token }) { return token }
                // Diagonal \
                if r <= ConnectFourGame.rows - 4 && c <= ConnectFourGame.cols - 4 && (1...3).allSatisfy({ board[r+$0][c+$0] == token }) { return token }
            }
        }
        return nil
    }

    private func isBoardFull(board: [[Token?]]? = nil) -> Bool {
        let b = board ?? self.board
        return (0..<ConnectFourGame.cols).allSatisfy { b[0][$0] != nil }
    }

    // Drop a token in a copy of a board, used for simulation
    private func drop(in column: Int, token: Token, on board: inout [[Token?]]) -> Bool {
        for row in (0..<ConnectFourGame.rows).reversed() {
            if board[row][column] == nil {
                board[row][column] = token
                return true
            }
        }
        return false
    }
}

#Preview {
    ContentView()
}
