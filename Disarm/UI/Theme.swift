import SwiftUI
import UIKit
import DisarmCore

enum Theme {
    static let background = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
    static let gridLine = UIColor(white: 1, alpha: 0.06)
    static let cellEmpty = UIColor(white: 1, alpha: 0.025)
    static let belt = UIColor(red: 0.18, green: 0.20, blue: 0.26, alpha: 1)
    static let beltArrow = UIColor(white: 1, alpha: 0.35)
    static let accent = UIColor(red: 0.25, green: 0.78, blue: 0.98, alpha: 1)
    static let danger = UIColor(red: 1.0, green: 0.30, blue: 0.32, alpha: 1)
    static let success = UIColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1)
    static let warning = UIColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 1)

    static func color(_ k: ModuleKind) -> UIColor {
        switch k {
        case .source: UIColor(red: 0.45, green: 0.50, blue: 0.60, alpha: 1)
        case .sink: UIColor(red: 0.30, green: 0.70, blue: 0.50, alpha: 1)
        case .scanner: UIColor(red: 0.95, green: 0.70, blue: 0.25, alpha: 1)
        case .parser: UIColor(red: 0.30, green: 0.60, blue: 0.95, alpha: 1)
        case .filter: UIColor(red: 0.90, green: 0.40, blue: 0.45, alpha: 1)
        case .transformer: UIColor(red: 0.65, green: 0.45, blue: 0.95, alpha: 1)
        case .packager: UIColor(red: 0.25, green: 0.75, blue: 0.75, alpha: 1)
        case .router: UIColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1)
        case .quarantine: UIColor(red: 0.50, green: 0.30, blue: 0.30, alpha: 1)
        }
    }

    static func symbol(_ k: ModuleKind) -> String {
        switch k {
        case .source: "tray.and.arrow.down.fill"
        case .sink: "paperplane.fill"
        case .scanner: "barcode.viewfinder"
        case .parser: "square.split.2x2.fill"
        case .filter: "line.3.horizontal.decrease.circle.fill"
        case .transformer: "wand.and.stars"
        case .packager: "shippingbox.fill"
        case .router: "arrow.triangle.branch"
        case .quarantine: "trash.fill"
        }
    }

    static func color(_ c: ContainerKind) -> UIColor {
        switch c {
        case .pdf: UIColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1)
        case .docx: UIColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1)
        case .xlsx: UIColor(red: 0.20, green: 0.65, blue: 0.40, alpha: 1)
        case .png: UIColor(red: 0.80, green: 0.55, blue: 0.85, alpha: 1)
        case .zip: UIColor(red: 0.75, green: 0.65, blue: 0.35, alpha: 1)
        }
    }

    static func color(_ p: PartKind) -> UIColor {
        switch p {
        case .text: UIColor(white: 0.9, alpha: 1)
        case .image: UIColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1)
        case .formula: UIColor(red: 0.45, green: 0.95, blue: 0.65, alpha: 1)
        case .macro: UIColor(red: 1.0, green: 0.60, blue: 0.25, alpha: 1)
        case .script: UIColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        case .embeddedFile: UIColor(red: 0.80, green: 0.70, blue: 0.45, alpha: 1)
        case .hiddenData: UIColor(red: 0.75, green: 0.45, blue: 0.95, alpha: 1)
        case .unknown: UIColor(red: 1.0, green: 0.25, blue: 0.55, alpha: 1)
        }
    }

    static func symbol(_ p: PartKind) -> String {
        switch p {
        case .text: "text.alignleft"
        case .image: "photo"
        case .formula: "function"
        case .macro: "gearshape.2"
        case .script: "chevron.left.forwardslash.chevron.right"
        case .embeddedFile: "doc.on.doc"
        case .hiddenData: "eye.slash"
        case .unknown: "questionmark.diamond"
        }
    }

    static func symbol(_ c: CustomerKind) -> String {
        switch c {
        case .accounting: "chart.bar.doc.horizontal"
        case .lawFirm: "scale.3d"
        case .designAgency: "paintpalette"
        case .bank: "building.columns"
        case .government: "building.2"
        }
    }

    static func symbol(_ l: LocationKind) -> String {
        switch l {
        case .smallOffice: "house"
        case .company: "building"
        case .bank: "building.columns"
        case .government: "building.2.crop.circle"
        }
    }
}

extension Color {
    init(_ ui: UIColor) { self.init(uiColor: ui) }
}

func money(_ v: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    return "₺" + (f.string(from: NSNumber(value: v)) ?? "\(v)")
}
