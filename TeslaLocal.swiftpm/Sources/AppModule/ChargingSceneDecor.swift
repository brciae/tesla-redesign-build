import RealityKit
import UIKit
import simd

/// Smooth round cable with a continuous luminance wave shared by all vehicle scenes.
@MainActor final class ChargingSceneDecor {
    private let rig = Entity()
    private var cores: [ModelEntity] = []
    private var halos: [ModelEntity] = []
    private var distances: [Float] = []
    private var led: ModelEntity?
    private var length: Float = 1
    private var elapsed: Float = 0
    private var built = false
    private(set) var isCharging = false
    private(set) var isPlugged = false
    var needsAnimation: Bool { isCharging && isPlugged }
    private let points: [SIMD3<Float>] = [
        [0.92, 1.02, -2.22], [1.06, 0.82, -2.06], [1.22, 0.52, -1.78],
        [1.36, 0.22, -1.42], [1.46, 0.03, -1.08], [1.70, 0.02, -0.52], [2.00, 0.02, 0.15]
    ]
    init(vehicle: Entity) { vehicle.addChild(rig); rig.isEnabled = false }
    func setIsCharging(_ charging: Bool, plugged: Bool = true) {
        let changed = isCharging != charging || isPlugged != plugged
        isCharging = charging; isPlugged = plugged
        if plugged && !built { build() }
        rig.isEnabled = plugged
        for entity in cores + halos { entity.isEnabled = charging && plugged }
        led?.isEnabled = charging && plugged
        if changed { elapsed = 0; renderWave() }
    }
    private func material(_ brightness: Float, halo: Bool = false) -> UnlitMaterial {
        var value = UnlitMaterial(color: UIColor(red: CGFloat(0.01 + brightness * 0.20), green: CGFloat(0.24 + brightness * 0.76), blue: CGFloat(0.13 + brightness * 0.46), alpha: 1))
        if halo { value.blending = .transparent(opacity: .init(floatLiteral: 0.025 + brightness * 0.16)) }
        return value
    }
    private func curve(_ index: Int, _ t: Float) -> SIMD3<Float> {
        let a = points[max(0, index - 1)], b = points[index]
        let c = points[index + 1], d = points[min(points.count - 1, index + 2)]
        let t2 = t * t, t3 = t2 * t
        let linear = (c - a) * t
        let quadratic = (2 * a - 5 * b + 4 * c - d) * t2
        let cubic = (-a + 3 * b - 3 * c + d) * t3
        let p = (2 * b + linear + quadratic + cubic) * 0.5
        return SIMD3<Float>(p.x, max(0.02, p.y), p.z)
    }
    private func tube(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: Float, material: UnlitMaterial) -> ModelEntity {
        let delta = b - a
        let entity = ModelEntity(mesh: cylinder(height: simd_length(delta) + radius, radius: radius), materials: [material])
        entity.position = (a + b) * 0.5
        entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        rig.addChild(entity)
        return entity
    }
    private func cylinder(height: Float, radius: Float) -> MeshResource {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for ring in 0...1 {
            for side in 0..<12 {
                let angle = Float(side) * .pi / 6
                let normal = SIMD3<Float>(cos(angle), 0, sin(angle))
                positions.append(SIMD3<Float>(normal.x * radius, (Float(ring) - 0.5) * height, normal.z * radius))
                normals.append(normal)
            }
        }
        for side in 0..<12 {
            let a = UInt32(side), b = UInt32((side + 1) % 12)
            indices += [a, a + 12, b, b, a + 12, b + 12]
        }
        var descriptor = MeshDescriptor(name: "charging-cable-tube")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: radius)
    }
    private func build() {
        built = true
        var samples: [SIMD3<Float>] = []
        for index in 0..<(points.count - 1) {
            for step in 0..<16 { samples.append(curve(index, Float(step) / 16)) }
        }
        samples.append(points.last!)
        var distance: Float = 0
        for index in 0..<(samples.count - 1) {
            let a = samples[index], b = samples[index + 1]
            let segmentLength = simd_distance(a, b)
            _ = tube(a, b, radius: 0.014, material: UnlitMaterial(color: UIColor(white: 0.095, alpha: 1)))
            let lift = SIMD3<Float>(0, 0.012, 0)
            cores.append(tube(a + lift, b + lift, radius: 0.007, material: material(0.2)))
            halos.append(tube(a + lift, b + lift, radius: 0.023, material: material(0.2, halo: true)))
            distances.append(distance + segmentLength * 0.5)
            distance += segmentLength
        }
        length = distance
        let port = ModelEntity(mesh: .generateSphere(radius: 0.022), materials: [material(0.7)])
        port.position = points[0]; rig.addChild(port); led = port
        renderWave()
    }
    func step(dt: Float) {
        guard needsAnimation, built else { return }
        elapsed += min(0.1, max(0, dt))
        renderWave()
    }
    private func renderWave() {
        guard built else { return }
        // Distance-based travel stays smooth around bends; wrap happens outside the cable.
        let tail: Float = 0.85
        let travel = length + 2 * tail
        let head = length + tail - (elapsed * 0.85).truncatingRemainder(dividingBy: travel)
        for index in cores.indices {
            let delta = distances[index] - head
            let width: Float = delta >= 0 ? 0.48 : 0.13
            let wave = exp(-(delta * delta) / (2 * width * width))
            let intensity: Float = UIAccessibility.isReduceMotionEnabled ? 0.45 : 0.10 + 0.90 * wave
            cores[index].model?.materials = [material(intensity)]
            halos[index].model?.materials = [material(intensity, halo: true)]
        }
        let breath: Float = UIAccessibility.isReduceMotionEnabled ? 0.6 : 0.6 + 0.25 * sin(elapsed * 1.8)
        led?.model?.materials = [material(breath)]
    }
    func teardown() {
        rig.removeFromParent()
        for child in Array(rig.children) { child.removeFromParent() }
        cores.removeAll(); halos.removeAll(); distances.removeAll(); led = nil; built = false
    }
}
