// Licensed under the Any Distance Source-Available License
//
//  Gear3DView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 3/20/24.
//

import Foundation
import SceneKit
import SceneKit.ModelIO
import CoreImage
import ARKit

class Gear3DView: SCNView, SCNSceneRendererDelegate {
    var localUsdzUrl: URL?
    var sceneStartTime: TimeInterval?
    var latestTime: TimeInterval = 0
    var itemNode: SCNNode?
    var isSetup: Bool = false
    var defaultCameraDistance: Float = 50.0
    var color: GearColor = .white
    internal var assetLoadTask: Task<(), Never>?

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        scene?.background.contents = UIColor.clear
        backgroundColor = .clear

        if newSuperview != nil {
            SceneKitCleaner.shared.add(self)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        sceneStartTime = sceneStartTime ?? time
        latestTime = time

        if isPlaying, let startTime = sceneStartTime {
            sceneTime = time - startTime
        }
    }

    func cleanupOrSetupIfNecessary() {
        let frameInWindow = self.convert(self.frame, to: nil)
        guard let windowBounds = self.window?.bounds else {
            if self.isSetup {
                self.cleanup()
                self.alpha = 0
                self.isSetup = false
            }
            return
        }

        let isVisible = frameInWindow.intersects(windowBounds)

        if isVisible,
           !self.isSetup,
           let localUsdzUrl = self.localUsdzUrl {
            self.isSetup = true
            self.setup(withLocalUsdzUrl: localUsdzUrl, color: color)
        }

        if !isVisible && self.isSetup {
            self.cleanup()
            self.alpha = 0
            self.isSetup = false
        }
    }

    func setup(withLocalUsdzUrl url: URL, color: GearColor) {
        Task {
            self.localUsdzUrl = url
            if let scene = await SceneLoader.loadScene(atUrl: url) {
                DispatchQueue.main.async {
                    self.isSetup = true
                    self.color = color
                    self.load(scene)
                }
            }
        }
    }

    func setColor(color: GearColor) {
        self.color = color
        let textureNode = itemNode?.childNode(withName: "Plane_2", recursively: true)

        Task(priority: .userInitiated) {
            if let cachedTexture = HealthDataCache.shared.texture(for: color) {
                textureNode?.geometry?.materials.first?.diffuse.contents = cachedTexture
            } else if let texture = self.generateSneakerTexture(forColor: color) {
                HealthDataCache.shared.cache(texture: texture, for: color)
                textureNode?.geometry?.materials.first?.diffuse.contents = texture
            }
        }
    }

    func load(_ loadedScene: SCNScene) {
#if targetEnvironment(simulator)
        return
#endif

        CustomFiltersVendor.registerFilters()
        cleanup()
        self.alpha = 0
        backgroundColor = .clear
        self.scene = loadedScene
        scene?.background.contents = UIColor.clear

        allowsCameraControl = true
        defaultCameraController.interactionMode = .orbitTurntable
        defaultCameraController.minimumVerticalAngle = -0.01
        defaultCameraController.maximumVerticalAngle = 0.01
        autoenablesDefaultLighting = true

        pointOfView = SCNNode()
        pointOfView?.camera = SCNCamera()
        scene?.rootNode.addChildNode(pointOfView!)

        pointOfView?.camera?.wantsHDR = true
        pointOfView?.camera?.wantsExposureAdaptation = false
        pointOfView?.camera?.exposureAdaptationBrighteningSpeedFactor = 20
        pointOfView?.camera?.exposureAdaptationDarkeningSpeedFactor = 20
        pointOfView?.camera?.motionBlurIntensity = 0.5
        pointOfView?.camera?.bloomIntensity = 0.7
        pointOfView?.position.z = defaultCameraDistance
        pointOfView?.camera?.bloomBlurRadius = 5
        pointOfView?.camera?.contrast = 0.5
        pointOfView?.camera?.saturation = 1.05
        pointOfView?.camera?.focalLength = 40
        antialiasingMode = .multisampling4X

        //        debugOptions = [.showBoundingBoxes, .renderAsWireframe, .showWorldOrigin]

        itemNode = scene?.rootNode.childNode(withName: "found_item_node", recursively: true) ?? scene?.rootNode.childNodes[safe: 0]

        setColor(color: color)

        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(x: 0, y: 1, z: 0, w: 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(x: 0, y: 1, z: 0, w: 2 * .pi))
        spin.duration = 6
        spin.repeatCount = .infinity
        spin.usesSceneTimeBase = true
        delegate = self

        if let itemNode = itemNode {
            let desiredHeight: Float = 30
            let currentHeight = max(abs(itemNode.boundingBox.max.y - itemNode.boundingBox.min.y),
                                    abs(itemNode.boundingBox.max.x - itemNode.boundingBox.min.x),
                                    abs(itemNode.boundingBox.max.z - itemNode.boundingBox.min.z))
            let scale = desiredHeight / currentHeight
            itemNode.scale = SCNVector3(scale, scale, scale)

            let centerY = (itemNode.boundingBox.min.y + itemNode.boundingBox.max.y) / 2
            let centerX = (itemNode.boundingBox.min.x + itemNode.boundingBox.max.x) / 2
            let centerZ = (itemNode.boundingBox.min.z + itemNode.boundingBox.max.z) / 2
            itemNode.position = SCNVector3(-1 * centerX * scale, -1 * centerY * scale, -1 * centerZ * scale)

            pointOfView?.position.x = 0
            pointOfView?.position.y = 0

            itemNode.addAnimation(spin, forKey: "rotation")
        }

        scene?.rootNode.rotation = SCNVector4(x: 0, y: 1, z: 0, w: 1.75 * .pi)
        isPlaying = true

        UIView.animate(withDuration: 0.2) {
            self.alpha = 1.0
        }
    }

    func cleanup() {
        isPlaying = false
        scene?.isPaused = true
        scene?.rootNode.cleanup()
        itemNode = nil
        delegate = nil
        scene = nil
    }

    func reset() {
        localUsdzUrl = nil
    }

    private func generateSneakerTexture(forColor color: GearColor) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let size = CGSize(width: 1024.0, height: 1024.0)
        let renderer = UIGraphicsImageRenderer(size: size,
                                               format: format)
        return renderer.image { ctx in
            color.mainColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let texture1 = UIImage(named: "texture_sneaker_1")?.withTintColor(color.accent1)
            texture1?.draw(at: .zero)

            let texture2 = UIImage(named: "texture_sneaker_2")?.withTintColor(color.accent2)
            texture2?.draw(at: .zero)

            let texture3 = UIImage(named: "texture_sneaker_3")?.withTintColor(color.accent3)
            texture3?.draw(at: .zero)

            let texture4 = UIImage(named: "texture_sneaker_4")?.withTintColor(color.accent4)
            texture4?.draw(at: .zero)

            let texture5 = UIImage(named: "texture_sneaker_5")?.withTintColor(color.accent4)
            texture5?.draw(at: .zero)
        }
    }
}

extension UIColor {
    var rgbComponents: [UInt32] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let redComponent = UInt32(red * 255)
        let greenComponent = UInt32(green * 255)
        let blueComponent = UInt32(blue * 255)

        return [redComponent, greenComponent, blueComponent]
    }
}