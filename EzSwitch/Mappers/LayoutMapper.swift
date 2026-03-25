import Foundation

/// Protocol for keyboard layout mappers
protocol LayoutMapper {
    /// Source layout name (e.g., "Russian – PC")
    var fromLayout: String { get }
    
    /// Target layout name (e.g., "ABC")
    var toLayout: String { get }
    
    /// Character mapping dictionary
    var mapping: [Character: Character] { get }
    
    /// Whether this mapper supports the given layout pair
    func supports(from: String, to: String) -> Bool
}

extension LayoutMapper {
    func supports(from: String, to: String) -> Bool {
        return self.fromLayout == from && self.toLayout == to
    }
}