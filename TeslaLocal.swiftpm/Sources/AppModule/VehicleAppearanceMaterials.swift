import UIKit
import RealityKit
import simd

@MainActor
enum VehicleAppearanceMaterials {
    static func paint(_ value: VehicleAppearance) throws -> SimpleMaterial {
        let roughness: Float = value.finish == .gloss ? 0.24 : value.finish == .satin ? 0.48 : 0.85
        // Painted clearcoat is not bare metal: fully metallic white appeared chrome.
        var material = SimpleMaterial(color: UIColor(appearanceHex: value.paint), roughness: .float(roughness), isMetallic: false)
        if value.wrap != .none, let image = wrapImage(value), let cg = image.cgImage {
            let texture = try TextureResource.generate(from: cg, options: .init(semantic: .color))
            material.color = .init(tint: .white, texture: .init(texture))
        }
        return material
    }
    static func glass(_ value: VehicleAppearance) -> SimpleMaterial {
        let base = UIColor(appearanceHex: value.tint)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor = CGFloat(1 - value.tintStrength * 0.82)
        return SimpleMaterial(color: UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: 1), roughness: 0.18, isMetallic: true)
    }
    static func plate(_ value: VehicleAppearance) throws -> SimpleMaterial {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: 1024, height: 205)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let color = UIColor(appearanceHex: value.plateColor)
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let foreground: UIColor = 0.2126*r + 0.7152*g + 0.0722*b > 0.45 ? .black : .white
            foreground.withAlphaComponent(0.65).setStroke()
            let border = UIBezierPath(roundedRect: CGRect(x: 6, y: 6, width: 1012, height: 193), cornerRadius: 15); border.lineWidth = 4; border.stroke()
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let text = value.validated().plate as NSString
            var font = UIFont.systemFont(ofSize: 145, weight: .semibold)
            while text.size(withAttributes: [.font: font]).width > 950 && font.pointSize > 60 { font = UIFont.systemFont(ofSize: font.pointSize - 1, weight: .semibold) }
            let height = font.lineHeight
            text.draw(in: CGRect(x: 32, y: (size.height-height)/2, width: 960, height: height), withAttributes: [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph])
        }
        let texture = try TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
        var material = SimpleMaterial(color: .white, roughness: 0.65, isMetallic: false)
        material.color = .init(tint: .white, texture: .init(texture)); return material
    }
    private static func wrapImage(_ value: VehicleAppearance) -> UIImage? {
        if value.wrap == .image {
            guard let url = VehicleAppearanceStore.shared.imageURL(value.imageID) else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor(appearanceHex: value.paint).setFill(); context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            UIColor(appearanceHex: value.accent).setFill()
            if value.wrap == .stripes {
                context.fill(CGRect(x: 213, y: 0, width: 34, height: 512)); context.fill(CGRect(x: 265, y: 0, width: 34, height: 512))
            } else if value.wrap == .twoTone { context.fill(CGRect(x: 0, y: 0, width: 512, height: 210)) }
        }
    }
    // Calculated once from closed, rest-space geometry. UVs remain attached to panels
    // when hinges animate; no time-varying/world-position shader or texture swimming.
    static func wrapUV(_ point: SIMD3<Float>, normal: SIMD3<Float>, wrap: VehicleAppearance.Wrap) -> SIMD2<Float> {
        if wrap == .stripes { return SIMD2((point.x + 0.96)/1.92, (point.z + 2.48)/4.96) }
        if wrap == .twoTone { return SIMD2((point.z + 2.48)/4.96, point.y/1.67) }
        if abs(normal.y) > 0.65 { return SIMD2((point.x + 0.96)/1.92, (point.z + 2.48)/4.96) }
        if abs(normal.x) > 0.5 { return SIMD2((point.z + 2.48)/4.96, point.y/1.67) }
        return SIMD2((point.x + 0.96)/1.92, point.y/1.67)
    }
}
