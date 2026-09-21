import RealityKit
import UIKit
import simd

/// 3D Tesla Charging Scene Decor: renders the connected charging cable,
/// flowing green neon energy pulse wave along the cable, and pulsing charge port LED.
@MainActor
final class ChargingSceneDecor {
    private let vehicle: Entity
    private let rig = Entity()
    private var cableSegments: [ModelEntity] = []
    private var pulseSegments: [ModelEntity] = []
    private var portLed: ModelEntity?
    private(set) var isCharging = false
    private(set) var isPlugged = false
    private var pulseTime: Float = 0
    private var ledTime: Float = 0
    private var isBuilt = false

    var needsAnimation: Bool {
        isCharging
    }

    // Waypoints connecting the vehicle's rear-left charge port to the ground and outward.
    // Car coordinates: +x is Left, +y is Up, +z is Forward, -z is Rear.
    // Tesla Model Y charge port is at approximately x: +0.92m, y: +1.02m, z: -2.22m.
    private let waypoints: [SIMD3<Float>] = [
        [0.92, 1.02, -2.22],  // Charge port inlet
        [1.06, 0.82, -2.06],  // Cable drape curve 1
        [1.22, 0.52, -1.78],  // Cable drape curve 2
        [1.36, 0.22, -1.42],  // Cable drape curve 3
        [1.46, 0.03, -1.08],  // Ground contact point
        [1.70, 0.02, -0.52],  // Ground extension curve
        [2.00, 0.02, 0.15]    // Floor lead towards charger
    ]

    init(vehicle: Entity) {
        self.vehicle = vehicle
        vehicle.addChild(rig)
        rig.isEnabled = false
    }

    func setIsCharging(_ charging: Bool, plugged: Bool = true) {
        isCharging = charging
        isPlugged = plugged
        if plugged && !isBuilt {
            buildCable()
        }
        rig.isEnabled = plugged
        for pulse in pulseSegments {
            pulse.isEnabled = charging
        }
        if !charging {
            portLed?.isEnabled = false
        }
    }

    private func buildCable() {
        guard !isBuilt else { return }
        isBuilt = true

        let cableColor = UIColor(white: 0.14, alpha: 1.0)
        let cableMaterial = UnlitMaterial(color: cableColor)
        let pulseColor = UIColor(red: 0.0, green: 1.0, blue: 0.55, alpha: 0.95)
        let pulseMaterial = UnlitMaterial(color: pulseColor)

        // 1. Build charging cable segments between waypoints
        for i in 0..<(waypoints.count - 1) {
            let p0 = waypoints[i]
            let p1 = waypoints[i + 1]
            let delta = p1 - p0
            let length = simd_length(delta)
            guard length > 0.01 else { continue }

            let dir = simd_normalize(delta)
            let mid = (p0 + p1) * 0.5

            // Main black rubber cable
            let thickness: Float = (i >= 4) ? 0.028 : 0.032
            let cableMesh = MeshResource.generateBox(width: thickness, height: thickness, depth: length)
            let segEntity = ModelEntity(mesh: cableMesh, materials: [cableMaterial])
            segEntity.position = mid
            segEntity.orientation = simd_quatf(from: [0, 0, 1], to: dir)
            rig.addChild(segEntity)
            cableSegments.append(segEntity)

            // Neon green energy glowing core (active only during charging)
            let pulseMesh = MeshResource.generateBox(width: thickness * 0.45, height: thickness * 0.45, depth: length * 0.92)
            let pulseEntity = ModelEntity(mesh: pulseMesh, materials: [pulseMaterial])
            pulseEntity.position = mid + SIMD3<Float>(0, 0.008, 0)
            pulseEntity.orientation = simd_quatf(from: [0, 0, 1], to: dir)
            pulseEntity.isEnabled = isCharging
            rig.addChild(pulseEntity)
            pulseSegments.append(pulseEntity)
        }

        // 2. Charge Port Pulsing Green LED
        let ledMesh = MeshResource.generatePlane(width: 0.065, height: 0.065)
        let ledEntity = ModelEntity(mesh: ledMesh, materials: [UnlitMaterial(color: pulseColor)])
        ledEntity.position = [0.93, 1.02, -2.22]
        ledEntity.orientation = simd_quatf(angle: .pi * 0.5, axis: [0, 1, 0])
        ledEntity.isEnabled = isCharging
        rig.addChild(ledEntity)
        portLed = ledEntity

        // Notice: NO groundWash plane created here to keep the ground clean and pitch black
    }

    /// Step animations at display rate: flowing energy wave + breathing port LED
    func step(dt: Float) {
        guard isCharging, isBuilt else { return }

        pulseTime += dt * 2.8 // Flow speed
        ledTime += dt * 3.6   // LED pulse speed

        // 1. Flowing energy wave: animate visibility/opacity of pulse segments sequentially
        let count = pulseSegments.count
        guard count > 0 else { return }

        // Moving wave phase along the cable
        let cycle = pulseTime.truncatingRemainder(dividingBy: Float(count))
        for i in 0..<count {
            // Wave flows from ground (highest index) towards the port (index 0)
            let reversedIndex = Float(count - 1 - i)
            let dist = abs(reversedIndex - cycle)
            let waveIntensity = max(0.2, 1.0 - min(1.0, dist * 0.6))
            pulseSegments[i].isEnabled = waveIntensity > 0.35
        }

        // 2. Breathing LED glow at the charge port inlet
        let breath = 0.45 + 0.55 * sin(ledTime)
        portLed?.isEnabled = breath > 0.4
    }

    func teardown() {
        for seg in cableSegments { seg.removeFromParent() }
        for pulse in pulseSegments { pulse.removeFromParent() }
        cableSegments.removeAll()
        pulseSegments.removeAll()
        portLed?.removeFromParent()
        portLed = nil
        rig.removeFromParent()
        isBuilt = false
    }
}
