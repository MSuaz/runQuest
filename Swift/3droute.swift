// Licensed under the Any Distance Source-Available License
//
//  RouteScene.swift
//  ADAC
//
//  Created by Daniel Kuntz on 6/7/22.
//

import Foundation
import SceneKit
import SCNLine
import CoreLocation

struct RouteScene {
    let scene: SCNScene
    let camera: SCNCamera
    let lineNode: SCNLineNode
    let centerNode: SCNNode
    let dotNode: SCNNode
    let dotAnimationNode: SCNNode
    let planeNodes: [SCNNode]
    let animationDuration: TimeInterval
    let elevationMinNode: SCNNode?
    let elevationMinLineNode: SCNNode?
    let elevationMaxNode: SCNNode?
    let elevationMaxLineNode: SCNNode?
    private let forExport: Bool
    private let elevationMinTextAction: SCNAction?
    private let elevationMaxTextAction: SCNAction?
    
    fileprivate static let dotRadius: CGFloat = 3.0
    fileprivate static let initialFocalLength: CGFloat = 42.0
    fileprivate static let initialZoom: CGFloat = 1.0
    fileprivate var minElevation: CLLocationDistance = 0.0
    fileprivate var maxElevation: CLLocationDistance = 0.0
    fileprivate var minElevationPoint = SCNVector3(0, 1000, 0)
    fileprivate var maxElevationPoint = SCNVector3(0, -1000, 0)

    var zoom: CGFloat = 1.0 {
        didSet {
            camera.focalLength = Self.initialFocalLength * zoom
        }
    }
    
    var palette: Palette {
        didSet {
            lineNode.geometry?.firstMaterial?.diffuse.contents = palette.foregroundColor

            let darkeningPercentage: CGFloat = forExport ? 0.0 : 35.0
            let alpha = (palette.foregroundColor.isReallyDark ? 0.8 : 0.5) + (forExport ? 0.2 : 0.0)
            let color = palette.foregroundColor.darker(by: darkeningPercentage)?.withAlphaComponent(alpha)
            for plane in planeNodes {
                plane.geometry?.firstMaterial?.diffuse.contents = color
            }

            dotNode.geometry?.firstMaterial?.diffuse.contents = palette.accentColor
            dotAnimationNode.geometry?.firstMaterial?.diffuse.contents = palette.accentColor

            elevationMinNode?.geometry?.firstMaterial?.diffuse.contents = palette.foregroundColor.lighter(by: 15.0)
            elevationMinLineNode?.geometry?.firstMaterial?.diffuse.contents = palette.foregroundColor.lighter(by: 15.0)
            elevationMaxNode?.geometry?.firstMaterial?.diffuse.contents = palette.foregroundColor.lighter(by: 15.0)
            elevationMaxLineNode?.geometry?.firstMaterial?.diffuse.contents = palette.foregroundColor.lighter(by: 15.0)
        }
    }
}

// MARK: Init

extension RouteScene {
    
    func restartTextAnimation() {
        if let minAction = elevationMinTextAction {
            elevationMinNode?.runAction(minAction)
        }
        
        if let maxAction = elevationMaxTextAction {
            elevationMaxNode?.runAction(maxAction)
        }
    }
    
    private static func textAction(for node: SCNNode,
                                   lineNode: SCNNode,
                                   startPosition: SCNVector3,
                                   initialDelay: CGFloat,
                                   additionalDelay: CGFloat,
                                   icon: String,
                                   elevationLimit: CLLocationDistance) -> SCNAction {
        let textAnimationDuration: CGFloat = 2.2
        let delay: CGFloat = textAnimationDuration * 0.15
        var actions: [SCNAction] = []

        let textAction = SCNAction.customAction(duration: textAnimationDuration) { node, time in
            let p = time / textAnimationDuration
            let elevation = Self.easeOutQuint(x: p) * elevationLimit
            
            if let geo = node.geometry as? SCNText {
                geo.string = "\(icon)\(Int(elevation))" + (ADUser.current.distanceUnit == .miles ? "ft" : "m")
            }
        }
        
        let opacityDelay: CGFloat = textAnimationDuration * 0.2
        let opacityDuration: CGFloat = textAnimationDuration * 0.55
        let transformDuration: CGFloat = textAnimationDuration * 0.45
        let movementAmount: CGFloat = 18.0
        let lineDuration: CGFloat = textAnimationDuration * 0.2
        let moveBy = SCNAction.moveBy(x: 0.0, y: movementAmount, z: 0.0, duration: transformDuration)
        moveBy.timingFunction = { t in
            return Float(Self.easeOutQuad(x: CGFloat(t) / transformDuration))
        }

        actions.append(SCNAction.sequence([
            SCNAction.run({ _ in
                lineNode.runAction(SCNAction.fadeOut(duration: 0.0))
            }),
            SCNAction.fadeOut(duration: 0.0),
            SCNAction.move(to: startPosition, duration: 0.0),
            SCNAction.moveBy(x: 0.0, y: -movementAmount, z: 0.0, duration: 0.0),
            SCNAction.wait(duration: delay + additionalDelay * opacityDelay),
            SCNAction.group([
                SCNAction.fadeIn(duration: opacityDuration),
                textAction,
                SCNAction.sequence([
                    moveBy,
                    SCNAction.run({ _ in
                        lineNode.runAction(SCNAction.fadeIn(duration: lineDuration))
                    })
                ])
            ])
        ]))

        return SCNAction.group(actions)
    }
    
    static func routeScene(from coordinates: [CLLocation], forExport: Bool, palette: Palette = .dark) -> RouteScene? {
        guard !coordinates.isEmpty else { return nil }
        
        let latitudeMin: CLLocationDegrees = coordinates.min(by: { $0.coordinate.latitude < $1.coordinate.latitude })?.coordinate.latitude ?? 1
        let latitudeMax: CLLocationDegrees = coordinates.max(by: { $0.coordinate.latitude < $1.coordinate.latitude })?.coordinate.latitude ?? 1
        let longitudeMin: CLLocationDegrees = coordinates.min(by: { $0.coordinate.longitude < $1.coordinate.longitude })?.coordinate.longitude ?? 1
        let longitudeMax: CLLocationDegrees = coordinates.max(by: { $0.coordinate.longitude < $1.coordinate.longitude })?.coordinate.longitude ?? 1
        let altitudeMin = coordinates.min(by: { $0.altitude < $1.altitude })?.altitude ?? 0.0
        let altitudeMax = coordinates.max(by: { $0.altitude < $1.altitude })?.altitude ?? 0.0
        let altitudeRange = altitudeMax - altitudeMin

        let latitudeRange = latitudeMax - latitudeMin
        let longitudeRange = longitudeMax - longitudeMin
        let aspectRatio = CGSize(width: CGFloat(longitudeRange),
                                 height: CGFloat(latitudeRange))
        let bounds = CGSize.aspectFit(aspectRatio: aspectRatio, boundingSize: CGSize(width: 200.0, height: 200.0))
        
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        
        let routeCenterNode = SCNNode(geometry: SCNSphere(radius: 0.0))
        routeCenterNode.position = SCNVector3(0.0, 0.0, 0.0)
        scene.rootNode.addChildNode(routeCenterNode)

        var prevPoint: SCNVector3?
        let smoothing: Float = 0.2
        let elevationSmoothing: Float = 0.3
        let s = max(1, coordinates.count / 350)

        let dotNode = SCNNode(geometry: SCNSphere(radius: dotRadius))
        let dotAnimationNode = SCNNode(geometry: SCNSphere(radius: dotRadius))
        dotAnimationNode.castsShadow = false

        var points: [SCNVector3] = []
        var keyTimes: [NSNumber] = []

        var curTime = 0.0

        let degreesPerMeter = 0.0001
        let latitudeMultiple = Double(bounds.height) / latitudeRange
        let renderedAltitudeRange = (degreesPerMeter * latitudeMultiple * altitudeRange).clamped(to: 0...80)
        let altitudeMultiplier = altitudeRange == 0 ? 0.1 : (renderedAltitudeRange / altitudeRange)
        
        var planeNodes = [SCNNode]()

        var minElevation: CLLocationDistance = 0.0
        var maxElevation: CLLocationDistance = 0.0
        var minElevationPoint = SCNVector3(0, 1000, 0)
        var maxElevationPoint = SCNVector3(0, -1000, 0)

        for i in stride(from: 0, to: coordinates.count - 1, by: s) {
            let c = coordinates[i]
            let normalizedLatitude = (1 - ((c.coordinate.latitude - latitudeMin) / latitudeRange))
            let latitude = Double(bounds.height) * normalizedLatitude - Double(bounds.height / 2)
            let longitude = Double(bounds.width) * ((c.coordinate.longitude - longitudeMin) / longitudeRange) - Double(bounds.width / 2)
            let adjustedAltitude = (c.altitude - altitudeMin) * altitudeMultiplier

            var point = SCNVector3(longitude, adjustedAltitude, latitude)

            if i == 0 {
                dotNode.position = point
            }

            if let prevPoint = prevPoint {
                // smoothing
                point.x = (point.x * (1 - smoothing)) + (prevPoint.x * smoothing) + Float.random(in: -0.001...0.001)
                point.y = (point.y * (1 - elevationSmoothing)) + (prevPoint.y * elevationSmoothing) + Float.random(in: -0.001...0.001)
                point.z = (point.z * (1 - smoothing)) + (prevPoint.z * smoothing) + Float.random(in: -0.001...0.001)

                // draw elevation plane
                let point3 = SCNVector3(point.x, -18.0, point.z)
                let point4 = SCNVector3(prevPoint.x, -18.0, prevPoint.z)
                let plane = SCNNode.planeNode(corners: [point, prevPoint, point3, point4])

                let boxMaterial = SCNMaterial()
                boxMaterial.transparent.contents = UIImage(named: "route_plane_fade")!
                boxMaterial.lightingModel = .constant
                boxMaterial.diffuse.contents = UIColor.white
                boxMaterial.blendMode = .replace
                boxMaterial.isLitPerPixel = false
                boxMaterial.isDoubleSided = true
                plane.geometry?.materials = [boxMaterial]

                routeCenterNode.addChildNode(plane)
                planeNodes.append(plane)

                let duration = TimeInterval(point.distance(to: prevPoint) * 0.02)
                curTime += duration
                points.append(point)
                keyTimes.append(NSNumber(value: curTime))
            } else {
                points.append(point)
                keyTimes.append(NSNumber(value: 0))
            }

            if point.y < minElevationPoint.y {
                minElevationPoint = point
                minElevation = c.altitude
            }

            if point.y > maxElevationPoint.y {
                maxElevationPoint = point
                maxElevation = c.altitude
            }

            prevPoint = point
        }

        if ADUser.current.distanceUnit == .miles {
            minElevation = UnitConverter.metersToFeet(minElevation)
            maxElevation = UnitConverter.metersToFeet(maxElevation)
        }

        let lineNode = SCNLineNode(with: points, radius: 1, edges: 5, maxTurning: 4)
        let lineMaterial = SCNMaterial()
        lineMaterial.lightingModel = .constant
        lineMaterial.isLitPerPixel = false
        lineNode.geometry?.materials = [lineMaterial]
        routeCenterNode.addChildNode(lineNode)

        let animationDuration = curTime

        let centerNode = SCNNode(geometry: SCNSphere(radius: 0))
        centerNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(centerNode)

        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        camera.automaticallyAdjustsZRange = true
        camera.focalLength = initialFocalLength * initialZoom
        cameraNode.position = SCNVector3(0, 250, 450)
        scene.rootNode.addChildNode(cameraNode)

        let lookAtConstraint = SCNLookAtConstraint(target: centerNode)
        cameraNode.constraints = [lookAtConstraint]

        let material = SCNMaterial()
        material.lightingModel = .constant
        let dotColor = UIColor(realRed: 255, green: 198, blue: 99)
        material.diffuse.contents = dotColor
        material.ambient.contents = dotColor
        dotNode.geometry?.materials = [material]
        routeCenterNode.addChildNode(dotNode)

        let moveAlongPathAnimation = CAKeyframeAnimation(keyPath: "position")
        moveAlongPathAnimation.values = points
        moveAlongPathAnimation.keyTimes = keyTimes
        moveAlongPathAnimation.duration = curTime
        moveAlongPathAnimation.usesSceneTimeBase = !forExport
        moveAlongPathAnimation.repeatCount = .greatestFiniteMagnitude
        dotNode.addAnimation(moveAlongPathAnimation, forKey: "position")

        let dotAnimationMaterial = SCNMaterial()
        dotAnimationMaterial.lightingModel = .constant
        let dotAnimationColor = UIColor(realRed: 255, green: 247, blue: 189)
        dotAnimationMaterial.diffuse.contents = dotAnimationColor
        dotAnimationMaterial.ambient.contents = dotAnimationColor
        dotAnimationNode.geometry?.materials = [dotAnimationMaterial]
        routeCenterNode.addChildNode(dotAnimationNode)
        dotAnimationNode.addAnimation(moveAlongPathAnimation, forKey: "position")

        let scaleAnimation = CABasicAnimation(keyPath: "scale")
        scaleAnimation.fromValue = SCNVector3(1, 1, 1)
        scaleAnimation.toValue = SCNVector3(3, 3, 3)
        scaleAnimation.duration = 0.8
        scaleAnimation.repeatCount = .greatestFiniteMagnitude
        scaleAnimation.usesSceneTimeBase = !forExport
        dotAnimationNode.addAnimation(scaleAnimation, forKey: "scale")

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.5
        opacityAnimation.toValue = 0.001
        opacityAnimation.duration = 0.8
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        opacityAnimation.repeatCount = .greatestFiniteMagnitude
        opacityAnimation.usesSceneTimeBase = !forExport
        dotAnimationNode.addAnimation(opacityAnimation, forKey: "opacity")

        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(x: 0.0, y: 1.0, z: 0.0, w: 0.0))
        spin.toValue = NSValue(scnVector4: SCNVector4(x: 0.0, y: 1.0, z: 0.0, w: 2.0 * .pi))
        spin.duration = 14.0
        spin.repeatCount = .infinity
        spin.usesSceneTimeBase = !forExport
        routeCenterNode.addAnimation(spin, forKey: "rotation")

        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.white
        textMaterial.lightingModel = .constant
        textMaterial.isDoubleSided = true
       
        var elevationMinNode: SCNNode?
        var elevationMinTextAction: SCNAction?
        var elevationMinLineNode: SCNNode?
        var elevationMaxNode: SCNNode?
        var elevationMaxTextAction: SCNAction?
        var elevationMaxLineNode: SCNNode?
        
        if altitudeMin != altitudeMax {
            var i: CGFloat = 0.0
            for (elevationPoint, elevation) in zip([minElevationPoint, maxElevationPoint],
                                                   [minElevation, maxElevation]) {
                let arrow = elevation == maxElevation ? "▲" : "▼"
                let text = arrow + String(format: "%i", Int(elevation)) + (ADUser.current.distanceUnit == .miles ? "ft" : "m")
                let elevationText = SCNText(string: text, extrusionDepth: 0)
                elevationText.materials = [textMaterial]
                elevationText.font = UIFont.presicav(size: 36, weight: .heavy)
                elevationText.flatness = 0.2
                let textNode = SCNNode(geometry: elevationText)
                textNode.name = "elevation-\(elevation == maxElevation ? "max" : "min")"
                textNode.pivot = SCNMatrix4MakeTranslation(17, 0, 0)
                textNode.position = SCNVector3(elevationPoint.x, elevationPoint.y + 18, elevationPoint.z)
                textNode.scale = SCNVector3(0.22, 0.22, 0.22)
                textNode.constraints = [SCNBillboardConstraint()]
                textNode.opacity = 0.0
                routeCenterNode.addChildNode(textNode)

                let textLineNode = SCNNode.lineNode(from: SCNVector3(elevationPoint.x, elevationPoint.y, elevationPoint.z),
                                                    to: SCNVector3(elevationPoint.x, textNode.position.y - 1, elevationPoint.z))
                textLineNode.name = textNode.name! + "-line"
                textLineNode.geometry?.materials = [textMaterial]
                textLineNode.opacity = 0.0
                routeCenterNode.addChildNode(textLineNode)
                
                if elevation == minElevation {
                    elevationMinNode = textNode
                    elevationMinLineNode = textLineNode
                    elevationMinTextAction = textAction(for: textNode,
                                                        lineNode: textLineNode,
                                                        startPosition: textNode.position,
                                                        initialDelay: 0.3,
                                                        additionalDelay: i,
                                                        icon: arrow,
                                                        elevationLimit: minElevation)
                } else {
                    elevationMaxNode = textNode
                    elevationMaxLineNode = textLineNode
                    elevationMaxTextAction = textAction(for: textNode,
                                                        lineNode: textLineNode,
                                                        startPosition: textNode.position,
                                                        initialDelay: 0.7,
                                                        additionalDelay: i,
                                                        icon: arrow,
                                                        elevationLimit: maxElevation)
                }

                i += 1
            }
        }
        
        var routeScene = RouteScene(scene: scene,
                                    camera: camera,
                                    lineNode: lineNode,
                                    centerNode: routeCenterNode,
                                    dotNode: dotNode,
                                    dotAnimationNode: dotAnimationNode,
                                    planeNodes: planeNodes,
                                    animationDuration: animationDuration,
                                    elevationMinNode: elevationMinNode,
                                    elevationMinLineNode: elevationMinLineNode,
                                    elevationMaxNode: elevationMaxNode,
                                    elevationMaxLineNode: elevationMaxLineNode,
                                    forExport: forExport,
                                    elevationMinTextAction: elevationMinTextAction,
                                    elevationMaxTextAction: elevationMaxTextAction,
                                    zoom: initialZoom,
                                    palette: palette)
        routeScene.palette = palette
        return routeScene
    }

    static fileprivate func easeOutQuint(x: CGFloat) -> CGFloat {
        return 1.0 - pow(1.0 - x, 5.0)
    }

    static func easeOutQuad(x: CGFloat) -> CGFloat {
        return 1.0 - (1.0 - x) * (1.0 - x)
    }

    static func easeInOutQuart(x: CGFloat) -> CGFloat {
        return x < 0.5 ? 8.0 * pow(x, 4.0) : 1.0 - pow(-2.0 * x + 2.0, 4.0) / 2.0
    }
}