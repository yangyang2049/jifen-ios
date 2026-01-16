import Foundation

class CommonNamesManager {
    static let shared = CommonNamesManager()
    
    private let userDefaults = UserDefaults.standard
    private let teamsKey = "commonTeamNames"
    private let playersKey = "commonPlayerNames"
    
    // Limits the number of common names stored
    private let maxNames = 50
    
    private init() {}
    
    // Record usage of a name, moving it to the top of the list
    func recordUsage(_ name: String, _ type: NameType) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var names = getNames(type: type)
        
        // Remove existing entry to move it to the top
        names.removeAll { $0 == name }
        
        // Add to the front
        names.insert(name, at: 0)
        
        // Limit the number of stored names
        if names.count > maxNames {
            names = Array(names.prefix(maxNames))
        }
        
        saveNames(names, type: type)
    }
    
    // Get a list of common names for a given type
    func getNames(type: NameType) -> [String] {
        let key = (type == .team) ? teamsKey : playersKey
        return userDefaults.stringArray(forKey: key) ?? []
    }
    
    private func saveNames(_ names: [String], type: NameType) {
        let key = (type == .team) ? teamsKey : playersKey
        userDefaults.set(names, forKey: key)
    }
}
