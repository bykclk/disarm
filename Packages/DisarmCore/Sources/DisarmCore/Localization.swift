import Foundation

/// Paket içi yerelleştirme. Anahtar İngilizce kaynak metindir; çeviriler Resources/Localizable.xcstrings içinde.
@inline(__always)
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
