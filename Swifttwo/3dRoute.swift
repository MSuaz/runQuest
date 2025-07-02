Clips
Blog
Blog
Any Distance Goes Open Source
Any Distance
A note from Dan: Today I'm open sourcing Any Distance, a fitness tracker app I worked on alongside several others for almost 5 years. You can read my announcement blog post here where I share some of motivations for open sourcing the app.

This collaboration with SIP includes code snippets, screen recordings, and commentary on some of my favorite parts of the app. You can view the full source code for Any Distance here.

The code snippets here are meant to be illustrative. They're not complete implementations. Please be sure to click through to GitHub to get the full picture.

3D Routes
View on GitHub
Copy
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
A fan favorite in Any Distance, these 3D routes are rendered with SceneKit. The geometry is constructed at runtime using a combination of "line nodes" (which are really just low poly cylinders) and planes.

The vertical elevation plane uses a constant lighting model (which basically just skips all lighting and fills everything with one color) and a replace blend mode, so it just replaces whatever is behind it with its own color. This results in a much cleaner look than normal transparency, since you can't see anything "behind" the plane.

I used an SCNAction sequence to animate the elevation labels, and a custom SCNAction to count up the text as the labels rise.

3-2-1 Go Animation
View on GitHub
Copy
import SwiftUI

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct CountdownView: View {
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let startGenerator = UINotificationFeedbackGenerator()

    @State private var animationStep: CGFloat = 4
    @State private var animationTimer: Timer?
    @State private var isFinished: Bool = false
    @Binding var skip: Bool
    var finishedAction: () -> Void

    func hStackXOffset() -> CGFloat {
        let clampedStep = animationStep.clamped(to: 0...3)
        if clampedStep > 0 {
            return 60 * (clampedStep - 1) - 10
        } else {
            return -90
        }
    }

    func startTimer() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true, block: { _ in
            if animationStep == 0 {
                withAnimation(.easeIn(duration: 0.15)) {
                    isFinished = true
                }
                finishedAction()
                animationTimer?.invalidate()
            }

            withAnimation(.easeInOut(duration: animationStep == 4 ? 0.3 : 0.4)) {
                animationStep -= 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if animationStep < 4 && animationStep > 0 {
                    impactGenerator.impactOccurred()
                } else if animationStep == 0 {
                    startGenerator.notificationOccurred(.success)
                }
            }
        })
    }

    var body: some View {
        VStack {
            ZStack {
                DarkBlurView()

                HStack(alignment: .center, spacing: 0) {
                    Text("3")
                        .font(.system(size: 89, weight: .semibold, design: .default))
                        .frame(width: 60)
                        .opacity(animationStep >= 3 ? 1 : 0.6)
                        .scaleEffect(animationStep >= 3 ? 1 : 0.6)
                    Text("2")
                        .font(.system(size: 89, weight: .semibold, design: .default))
                        .frame(width: 60)
                        .opacity(animationStep == 2 ? 1 : 0.6)
                        .scaleEffect(animationStep == 2 ? 1 : 0.6)
                    Text("1")
                        .font(.system(size: 89, weight: .semibold, design: .default))
                        .frame(width: 60)
                        .opacity(animationStep == 1 ? 1 : 0.6)
                        .scaleEffect(animationStep == 1 ? 1 : 0.6)
                    Text("GO")
                        .font(.system(size: 65, weight: .bold, design: .default))
                        .frame(width: 100)
                        .opacity(animationStep == 0 ? 1 : 0.6)
                        .scaleEffect(animationStep == 0 ? 1 : 0.6)
                }
                .foregroundStyle(Color.white)
                .offset(x: hStackXOffset())
            }
            .mask {
                RoundedRectangle(cornerRadius: 65)
                    .frame(width: 130, height: 200)
            }
            .opacity(isFinished ? 0 : 1)
            .scaleEffect(isFinished ? 1.2 : 1)
            .blur(radius: isFinished ? 6.0 : 0.0)
            .opacity(animationStep < 4 ? 1 : 0)
            .scaleEffect(animationStep < 4 ? 1 : 0.8)
        }
        .onChange(of: skip) { newValue in
            if newValue == true {
                animationTimer?.invalidate()
                withAnimation(.easeIn(duration: 0.15)) {
                    isFinished = true
                }
                finishedAction()
            }
        }
        .onAppear {
            guard animationStep == 4 else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startTimer()
            }
        }
    }
}

#Preview {
    ZStack {
        CountdownView(skip: .constant(false)) {}
    }
    .background(Color(white: 0.2))
}
This is our classic countdown timer written in SwiftUI. It's a good example of how stacking lots of different SwiftUI modifiers (scaleEffect, opacity, blur) can let you create more complex animations.

Goal Picker
View on GitHub
Copy
import SwiftUI

fileprivate struct CancelHeader: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var showingSettings: Bool
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Button {
                showingSettings = true
            } label: {
                Text("Settings")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                    .frame(width: 95, height: 50)
            }
            Spacer()
            Button {
                UIApplication.shared.topViewController?.dismiss(animated: true)
                isPresented = false
            } label: {
                Text("Cancel")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                    .frame(width: 90, height: 50)
            }
        }
    }
}

fileprivate struct TitleView: View {
    var activityType: ActivityType
    var goalType: RecordingGoalType

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(activityType.displayName)
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goalType.promptText)
                    .font(.system(size: 18, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.6))
                    .id(goalType.promptText)
                    .modifier(BlurOpacityTransition(speed: 1.75))
            }
            Spacer()
            Image(activityType.glyphName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 53, height: 53)
        }
    }
}

fileprivate struct GoalTypeSelector: View {
    var types: [RecordingGoalType] = []
    @Binding var selectedIdx: Int

    private var scrollViewAnchor: UnitPoint {
        switch selectedIdx {
        case RecordingGoalType.allCases.count - 1:
            return .trailing
        default:
            return .center
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(types.enumerated()),
                            id: \.element.rawValue) { (idx, goalType) in
                        GoalTypeButton(idx: idx,
                                       goalType: goalType,
                                       selectedIdx: $selectedIdx)
                    }
                }
                .padding([.leading, .trailing], 15)
            }
            .introspectScrollView { scrollView in
                scrollView.setValue(0.25, forKeyPath: "contentOffsetAnimationDuration")
            }
            .onChange(of: selectedIdx) { newValue in
                withAnimation {
                    proxy.scrollTo(RecordingGoalType.allCases[selectedIdx].rawValue,
                                   anchor: scrollViewAnchor)
                }
            }
            .onAppear {
                proxy.scrollTo(RecordingGoalType.allCases[selectedIdx].rawValue,
                               anchor: scrollViewAnchor)
            }
        }
    }

    struct GoalTypeButton: View {
        var idx: Int
        var goalType: RecordingGoalType
        @Binding var selectedIdx: Int

        var isSelected: Bool {
            return selectedIdx == idx
        }

        func animation(for idx: Int) -> Animation {
            return idx == 0 ? .timingCurve(0.33, 1, 0.68, 1, duration: 0.35) :
                              .timingCurve(0.25, 1, 0.5, 1, duration: 0.4)
        }

        var body: some View {
            Button {
                let request = FrameRateRequest(duration: 0.5)
                request.perform()

                withAnimation(animation(for: idx)) {
                    selectedIdx = idx
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 40, style: .circular)
                        .fill(isSelected ? Color(goalType.color) : Color(white: 0.2))
                        .frame(height: 50)

                    HStack(alignment: .center, spacing: 6) {
                        let unit = ADUser.current.distanceUnit
                        if let glyph = goalType.glyph(forDistanceUnit: unit) {
                            Image(uiImage: glyph)
                        }
                        Text(goalType.displayName)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundColor((isSelected && goalType == .open) ? .black : .white)
                    }
                    .padding([.leading, .trailing], 20)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 50)
                }
                .contentShape(Rectangle())
                .background(Color.black.opacity(0.01))
                .animation(.none, value: isSelected)
            }
        }
    }
}

fileprivate struct SetTargetView: View {
    @ObservedObject var goal: RecordingGoal
    @ObservedObject var howWeCalculateModel: HowWeCalculatePopupModel
    @State private var originalGoalTarget: Float = -1
    @State private var dragStartPoint: CGPoint?
    private let generator = UISelectionFeedbackGenerator()

    private var bgRectangle: some View {
        Rectangle()
            .padding(.top, 35)
            .opacity(0.001)
            .onTapGesture(count: 2) {
                goal.setTarget(goal.type.defaultTarget)
                generator.selectionChanged()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { data in
                        if originalGoalTarget == -1 {
                            originalGoalTarget = goal.target
                        }

                        let prevTarget = goal.target
                        var xOffset = -1 * (data.location.x - (dragStartPoint?.x ?? data.startLocation.x))
                        let minDistance: CGFloat = 10.0

                        if abs(xOffset) < minDistance && dragStartPoint == nil {
                            return
                        }

                        if dragStartPoint == nil {
                            dragStartPoint = data.location
                            xOffset = 0.0
                        }

                        let delta = goal.type.slideIncrement * Float((xOffset / 8).rounded())
                        let newTarget = ((originalGoalTarget + delta) / goal.type.slideIncrement).rounded() * goal.type.slideIncrement
                        goal.setTarget(newTarget)

                        if goal.target != prevTarget {
                            generator.selectionChanged()
                        }
                    }
                    .onEnded { _  in
                        originalGoalTarget = -1
                        dragStartPoint = nil
                    }
            )
    }

    var dotBg: some View {
        ZStack {
            Color.black

            Image("dot_bg")
                .resizable(resizingMode: .tile)
                .renderingMode(.template)
                .foregroundColor(Color(goal.type.lighterColor))
                .opacity(0.15)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black, lineWidth: 18)
                .blur(radius: 16)

            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.clear, Color(goal.type.color), .clear],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(height: 90)
                    .offset(y: -30)

                Spacer()
            }
            .scaleEffect(x: 1.8, y: 3)
            .blur(radius: 25)
            .opacity(0.45)

            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.clear, Color(goal.type.color), Color(goal.type.color), .clear],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(height: 1.8)

                Spacer()
            }
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(goal.formattedUnitString)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(goal.type.lighterColor))
                .shadow(color: Color(goal.type.color), radius: 6, x: 0, y: 0)
                .shadow(color: Color.black, radius: 5, x: 0, y: 0)
                .allowsHitTesting(false)
            HStack {
                Button {
                    goal.setTarget(goal.target - goal.type.buttonIncrement)
                    generator.selectionChanged()
                } label: {
                    Image("glyph_digital_minus")
                        .foregroundColor(Color(white: 0.9))
                        .frame(width: 70, height: 70)
                }
                .padding(.leading, 5)
                .offset(y: -3)

                Spacer()

                Text(goal.formattedTarget)
                    .font(.custom("Digital-7", size: 73))
                    .foregroundColor(Color(goal.type.lighterColor))
                    .shadow(color: Color(goal.type.color), radius: 6, x: 0, y: 0)
                    .allowsHitTesting(false)

                Spacer()

                Button {
                    goal.setTarget(goal.target + goal.type.buttonIncrement)
                    generator.selectionChanged()
                } label: {
                    Image("glyph_digital_plus")
                        .foregroundColor(Color(white: 0.9))
                        .frame(width: 70, height: 70)
                }
                .padding(.trailing, 5)
                .offset(y: -3)
            }

            SlideToAdjust(color: goal.type.lighterColor)
                .shadow(color: Color(goal.type.color), radius: 6, x: 0, y: 0)
                .allowsHitTesting(false)
        }
        .padding([.top, .bottom], 16)
        .overlay {
            HStack {
                VStack {
                    Button {
                        howWeCalculateModel.showStatCalculation(for: goal.type.statisticType)
                    } label: {
                        Image(systemName: .infoCircleFill)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13)
                            .foregroundColor(Color(goal.type.lighterColor))
                            .padding(16)
                    }
                    .shadow(color: Color(goal.type.color), radius: 7, x: 0, y: 0)
                    .shadow(color: Color.black, radius: 5, x: 0, y: 0)
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .maxWidth(.infinity)
        .background(bgRectangle)
        .background(dotBg)
        .mask(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.2))
                .offset(y: 1)
        }
    }

    struct SlideToAdjust: View {
        var color: UIColor

        var body: some View {
            HStack(spacing: 18) {
                Arrows(color: color)
                Text("SLIDE TO ADJUST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(color))
                Arrows(color: color)
                    .scaleEffect(x: -1, y: 1, anchor: .center)
            }
        }

        struct Arrows: View {
            let color: UIColor
            let animDuration: Double = 0.8
            @State private var animate: Bool = false

            var body: some View {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { idx in
                        Image(systemName: .chevronLeft)
                            .font(Font.system(size: 10, weight: .heavy))
                            .foregroundColor(Color(color))
                            .opacity(animate ? 0.2 : 1)
                            .animation(
                                .easeIn(duration: animDuration)
                                .repeatForever(autoreverses: true)
                                .delay(-1 * Double(idx) * animDuration / 5),
                                value: animate)
                    }
                }
                .onAppear {
                    animate = true
                }
            }
        }
    }
}

fileprivate struct TargetOpacityAnimation: AnimatableModifier {
    var progress: CGFloat = 0

    var animatableData: CGFloat {
        get {
            return progress
        }

        set {
            progress = newValue
        }
    }

    func body(content: Content) -> some View {
        let scaledProgress = ((progress - 0.3) * 1.5).clamped(to: 0...1)
        let easedProgress = easeInCubic(scaledProgress)
        content
            .opacity(easedProgress)
            .maxHeight(progress * 140)
    }

    func easeInCubic(_ x: CGFloat) -> CGFloat {
        return x * x * x;
    }
}

struct RecordingGoalSelectionView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var howWeCalculatePopupModel = HowWeCalculatePopupModel()
    var activityType: ActivityType
    @Binding var goal: RecordingGoal
    @State var hasSetup: Bool = false
    @State var isPresented: Bool = true
    @State var hasRecordingViewAppeared: Bool = false
    @State var showingWeightEntryView: Bool = false
    @State var showingRecordingSettings: Bool = false
    @State var selectedGoalTypeIdx: Int = 1
    @State var prevSelectedGoalTypeIdx: Int = 1
    @State var goals: [RecordingGoal] = []
    
    private let generator = UIImpactFeedbackGenerator(style: .heavy)
    private let screenName = "Tracking Goal Select"

    func goal(for idx: Int) -> RecordingGoal {
        return goals[idx]
    }
    
    func setTargetGoal(for idx: Int) -> RecordingGoal {
        if selectedGoalTypeIdx == 0 {
            return goal(for: prevSelectedGoalTypeIdx)
        } else {
            return goal(for: idx)
        }
    }

    var body: some View {
        ZStack {
            BlurView(style: .systemUltraThinMaterialDark,
                     intensity: 0.55,
                     animatesIn: true,
                     animateOut: !isPresented)
                .padding(.top, -1500)
                .opacity(hasRecordingViewAppeared ? 0 : 1)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                    presentationMode.dismiss()
                }
            
            VStack {
                HowWeCalculatePopup(model: howWeCalculatePopupModel, drawerClosedHeight: 0)
                
                VStack(spacing: 16) {
                    CancelHeader(showingSettings: $showingRecordingSettings,
                                 isPresented: $isPresented)
                        .zIndex(20)
                        .padding(.bottom, -12)
                        .padding(.top, 6)
                        .padding([.leading, .trailing], 8)
                    
                    if !goals.isEmpty {
                        VStack(spacing: 16) {
                            TitleView(activityType: activityType,
                                      goalType: goal.type)
                            GoalTypeSelector(types: goals.map { $0.type },
                                             selectedIdx: $selectedGoalTypeIdx)
                                .zIndex(20)
                                .padding([.leading, .trailing], -21)
                            SetTargetView(goal: goal,
                                          howWeCalculateModel: howWeCalculatePopupModel)
                                .animation(.none)
                                .modifier(TargetOpacityAnimation(progress: selectedGoalTypeIdx > 0 ? 1.0 : 0.0))
                            Button {
                                generator.impactOccurred()
                                isPresented = false
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(UIColor.adOrangeLighter))

                                    Text("Set Goal")
                                        .foregroundColor(.black)
                                        .semibold()
                                }
                                .frame(height: 56)
                                .maxWidth(.infinity)
                            }
                            .padding(.top, 2)
                            .zIndex(20)
                        }
                        .padding(.bottom, 15)
                        .padding([.leading, .trailing], 21)
                    }
                }
                .background(
                    Color(white: 0.05)
                        .cornerRadius(35, corners: [.topLeft, .topRight])
                        .ignoresSafeArea()
                )
            }
        }
        .background(Color.clear)
        .onAppear {
            goals = NSUbiquitousKeyValueStore.default.goals(for: activityType)
            goals.forEach { goal in
                goal.unit = ADUser.current.distanceUnit
            }
            selectedGoalTypeIdx = goals.firstIndex(where: { $0.type == goal.type }) ?? 0
            goals[selectedGoalTypeIdx] = goal
            if !NSUbiquitousKeyValueStore.default.hasSetBodyMass && ADUser.current.totalDistanceTracked > 0.0 {
                showingWeightEntryView = true
            }

            hasSetup = true
        }
        .onDisappear {
            NSUbiquitousKeyValueStore.default.setGoals(goals, for: activityType)
            NSUbiquitousKeyValueStore.default.setSelectedGoalIdx(selectedGoalTypeIdx, for: activityType)
            Analytics.logEvent("Dismiss", screenName, .buttonTap)
        }
        .onChange(of: selectedGoalTypeIdx) { [selectedGoalTypeIdx] newValue in
            guard hasSetup else {
                return
            }

            goal = goal(for: newValue)
            goal.objectWillChange.send()
            prevSelectedGoalTypeIdx = selectedGoalTypeIdx
            if howWeCalculatePopupModel.statCalculationInfoVisible {
                howWeCalculatePopupModel.showStatCalculation(for: goals[newValue].type.statisticType)
            }
        }
        .fullScreenCover(isPresented: $showingWeightEntryView) {
            WeightEntryView()
                .background(BackgroundClearView())
        }
        .fullScreenCover(isPresented: $showingRecordingSettings) {
            RecordingSettingsView()
                .background(BackgroundClearView())
        }
    }
}
This fun retro goal picker UI was made entirely in SwiftUI. The staggered chevron animation is my favorite part – it really makes you want to scroll with your finger.

3D Medals
View on GitHub
Copy
import UIKit
import SceneKit
import SceneKit.ModelIO
import CoreImage
import ARKit

class Collectible3DView: SCNView, CollectibleSCNView {
    var collectible: Collectible?
    var localUsdzUrl: URL?
    var collectibleEarned: Bool = true
    var engraveInitials: Bool = true
    var sceneStartTime: TimeInterval?
    var latestTime: TimeInterval = 0
    var itemNode: SCNNode?
    var isSetup: Bool = false
    var defaultCameraDistance: Float = 50.0
    internal var assetLoadTask: Task<(), Never>?
    var placeholderImageView: UIImageView?

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
            self.setup(withLocalUsdzUrl: localUsdzUrl)
        }

        if !isVisible && self.isSetup {
            self.cleanup()
            self.alpha = 0
            self.isSetup = false
        }
    }
}

class CollectibleARSCNView: GestureARView, CollectibleSCNView {
    var collectible: Collectible?
    var localUsdzUrl: URL?
    var collectibleEarned: Bool = true
    var engraveInitials: Bool = true
    var sceneStartTime: TimeInterval?
    var latestTime: TimeInterval = 0
    var itemNode: SCNNode?
    var isSetup: Bool = false
    var defaultCameraDistance: Float = 50.0
    internal var assetLoadTask: Task<(), Never>?
    var placeholderImageView: UIImageView?

    override var nodeToMove: SCNNode? {
        return itemNode
    }

    override var distanceToGround: Float {
        if let collectible = collectible {
            switch collectible.type {
            case .remote(let remote):
                if !remote.shouldFloatInAR {
                    return 0
                }
            default: break
            }
        }

        return super.distanceToGround
    }

    override func getShadowImage(_ completion: @escaping (UIImage?) -> Void) {
        switch collectible?.itemType {
        case .medal:
            completion(UIImage(named: "medal_shadow"))
        case .foundItem:
            completion(UIImage(named: "item_shadow"))
        default:
            completion(nil)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        sceneStartTime = sceneStartTime ?? time
        latestTime = time

        if isPlaying, let startTime = sceneStartTime {
            sceneTime = time - startTime
        }
    }

    func initialSceneLoaded() {}
}

protocol CollectibleSCNView: SCNView, SCNSceneRendererDelegate {
    var collectible: Collectible? { get set }
    var localUsdzUrl: URL? { get set }
    var collectibleEarned: Bool { get set }
    var engraveInitials: Bool { get set }
    var sceneStartTime: TimeInterval? { get set }
    var latestTime: TimeInterval { get set }
    var itemNode: SCNNode? { get set }
    var isSetup: Bool { get set }
    var defaultCameraDistance: Float { get set }
    var assetLoadTask: Task<(), Never>? { get set }
    var placeholderImageView: UIImageView? { get set }
}

extension CollectibleSCNView {
    func setup(withCollectible collectible: Collectible,
               earned: Bool,
               engraveInitials: Bool) {
        self.collectible = collectible
        self.collectibleEarned = earned
        self.engraveInitials = engraveInitials
        self.localUsdzUrl = nil

        switch collectible.itemType {
        case .medal:
            if let medalUsdzUrl = Bundle.main.url(forResource: "medal", withExtension: "scn") {
                self.localUsdzUrl = medalUsdzUrl
                self.setup(withLocalUsdzUrl: medalUsdzUrl)
            }
        case .foundItem:
            switch collectible.type {
            case .remote(let remote):
                if let usdzUrl = remote.usdzUrl {
                    self.loadRemoteUsdz(atUrl: usdzUrl)
                }
            default: break
            }
        }
    }

    func setupForReusableView(withCollectible collectible: Collectible, earned: Bool = true) {
        guard collectible != self.collectible || self.collectibleEarned != earned else {
            return
        }

        self.preferredFramesPerSecond = 30
        self.reset()
        self.cleanup()
        self.collectible = collectible
        self.collectibleEarned = earned
        self.localUsdzUrl = nil

        switch collectible.type {
        case .remote(let remote):
            if let usdzUrl = remote.usdzUrl {
                self.alpha = 0.0
                loadRemoteUsdz(atUrl: usdzUrl)
            }
        default: break
        }
    }

    fileprivate func addPlaceholder() {
        DispatchQueue.main.async {
            self.placeholderImageView?.removeFromSuperview()
            self.placeholderImageView = UIImageView(image: UIImage(systemName: "shippingbox",
                                                                   withConfiguration: UIImage.SymbolConfiguration(weight: .light)))
            self.placeholderImageView?.alpha = 0.3
            self.placeholderImageView?.contentMode = .scaleAspectFit
            self.placeholderImageView?.tintColor = .white
            self.superview?.addSubview(self.placeholderImageView!)
            self.placeholderImageView?.autoPinEdge(.leading, to: .leading, of: self)
            self.placeholderImageView?.autoPinEdge(.trailing, to: .trailing, of: self)
            self.placeholderImageView?.autoPinEdge(.top, to: .top, of: self)
            self.placeholderImageView?.autoPinEdge(.bottom, to: .bottom, of: self)
        }
    }

    private func loadRemoteUsdz(atUrl url: URL) {
        if !CollectibleDataCache.hasLoadedItem(atUrl: url) {
            addPlaceholder()
        }

        assetLoadTask?.cancel()
        assetLoadTask = Task(priority: .userInitiated) {
            let localUrl = await CollectibleDataCache.loadItem(atUrl: url)
            if let localUrl = localUrl, !Task.isCancelled {
                self.localUsdzUrl = localUrl
                self.setup(withLocalUsdzUrl: localUrl)
            }
        }
    }

    func setup(withLocalUsdzUrl url: URL) {
        Task {
            if let scene = await SceneLoader.loadScene(atUrl: url) {
                DispatchQueue.main.async {
                    self.isSetup = true
                    self.load(scene)
                }
            }
        }
    }

    func load(_ loadedScene: SCNScene) {
        #if targetEnvironment(simulator)
        return
        #endif

        CustomFiltersVendor.registerFilters()
        cleanup()
        if !(self is ARSCNView) {
            self.alpha = 0
            backgroundColor = .clear
        }

        self.scene = loadedScene

        if !(self is ARSCNView) {
            scene?.background.contents = UIColor.clear
        }

        allowsCameraControl = true
        defaultCameraController.interactionMode = .orbitTurntable
        defaultCameraController.minimumVerticalAngle = -0.01
        defaultCameraController.maximumVerticalAngle = 0.01
        autoenablesDefaultLighting = true

        if (collectible?.itemType ?? .foundItem) != .medal && !(self is ARSCNView) {
            pointOfView = SCNNode()
            pointOfView?.camera = SCNCamera()
            scene?.rootNode.addChildNode(pointOfView!)
        }

        if !(self is ARSCNView) {
            pointOfView?.camera?.wantsHDR = true
            pointOfView?.camera?.wantsExposureAdaptation = false
            pointOfView?.camera?.exposureAdaptationBrighteningSpeedFactor = 20
            pointOfView?.camera?.exposureAdaptationDarkeningSpeedFactor = 20
            pointOfView?.camera?.motionBlurIntensity = 0.5
            switch collectible?.type {
            case .remote(let remote):
                pointOfView?.camera?.bloomIntensity = CGFloat(remote.bloomIntensity)
                pointOfView?.position.z = remote.cameraDistance
            default:
                pointOfView?.camera?.bloomIntensity = 0.7
                pointOfView?.position.z = defaultCameraDistance
            }
            pointOfView?.camera?.bloomBlurRadius = 5
            pointOfView?.camera?.contrast = 0.5
            pointOfView?.camera?.saturation = self.collectibleEarned ? 1.05 : 0

            if collectible == nil {
                pointOfView?.camera?.focalLength = 40
            }
        }
        antialiasingMode = .multisampling4X

        if !(self is ARSCNView) {
            let pinchGR = UIPinchGestureRecognizer(target: nil, action: nil)
            addGestureRecognizer(pinchGR)

            let panGR = UIPanGestureRecognizer(target: nil, action: nil)
            panGR.minimumNumberOfTouches = 2
            panGR.maximumNumberOfTouches = 2
            addGestureRecognizer(panGR)
        }

        if collectible?.itemType == .medal {
            let medalNode = scene?.rootNode.childNodes.first?.childNodes.first?.childNodes.first?.childNodes.first
            itemNode = medalNode
            medalNode?.opacity = 0

            Task {
                let diffuseTexture = await generateTexture(fromCollectible: collectible!,
                                                           engraveInitials: self.engraveInitials)

                DispatchQueue.main.async {
                    var roughnessTexture = self.exposureAdjustedImage(diffuseTexture)
                    let metalnessTexture = diffuseTexture
                    if self.collectible!.medalImageHasBlackBackground {
                        let roughnessCIImage = CIImage(cgImage: diffuseTexture.cgImage!)
                        let invertedRoughness = roughnessCIImage
                            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 4])
                            .applyingFilter("CIColorInvert")
                        roughnessTexture = UIImage(ciImage: invertedRoughness).resized(withNewWidth: 1024, imageScale: 1)
                    }

                    medalNode?.geometry?.materials.first?.diffuse.contents = diffuseTexture
                    medalNode?.geometry?.materials.first?.roughness.contents = roughnessTexture
                    medalNode?.geometry?.materials.first?.metalness.contents = metalnessTexture
                    medalNode?.geometry?.materials.first?.metalness.intensity = 1
                    medalNode?.geometry?.materials.first?.emission.contents = diffuseTexture
                    medalNode?.geometry?.materials.first?.emission.intensity = 0.15
                    medalNode?.geometry?.materials.first?.selfIllumination.contents = diffuseTexture

                    let normalTexture = CIImage(cgImage: roughnessTexture.cgImage!).applyingFilter("NormalMap")
                    let normalImage = UIImage(ciImage: normalTexture).resized(withNewWidth: 1024, imageScale: 1)
                    medalNode?.geometry?.materials.first?.normal.contents = normalImage

                    if !(self is ARSCNView) {
                        let opacityAction = SCNAction.fadeOpacity(by: 1, duration: 0.2)
                        medalNode?.runAction(opacityAction)
                    }
                }
            }
        } else {
            itemNode = scene?.rootNode.childNode(withName: "found_item_node", recursively: true) ?? scene?.rootNode.childNodes[safe: 0]
            //.childNodes[0].childNodes[0].childNodes[0].childNodes[0]
        }

        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(x: 0, y: 1, z: 0, w: 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(x: 0, y: 1, z: 0, w: 2 * .pi))
        spin.duration = 6
        spin.repeatCount = .infinity
        spin.usesSceneTimeBase = true
        delegate = self

        if self is ARSCNView {
            allowsCameraControl = false
            if collectible?.itemType == .medal {
                itemNode?.scale = SCNVector3(0.02, 0.02, 0.02)
            } else if let itemNode = itemNode {
                let desiredHeight: Float = 0.4
                let currentHeight = max(abs(itemNode.boundingBox.max.y - itemNode.boundingBox.min.y),
                                        abs(itemNode.boundingBox.max.x - itemNode.boundingBox.min.x),
                                        abs(itemNode.boundingBox.max.z - itemNode.boundingBox.min.z))
                let scale = desiredHeight / currentHeight
                itemNode.scale = SCNVector3(scale, scale, scale)
            }
            itemNode?.position.z -= 1
            itemNode?.position.y -= 1

            switch collectible?.type {
            case .remote(let remote):
                if remote.shouldSpinInAR {
                    itemNode?.addAnimation(spin, forKey: "rotation")
                }
            default:
                itemNode?.addAnimation(spin, forKey: "rotation")
            }

            (self as? GestureARView)?.addShadow()
            itemNode?.opacity = 0
        } else if let itemNode = itemNode {
            if (collectible?.itemType ?? .foundItem) != .medal {
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
            }

            itemNode.addAnimation(spin, forKey: "rotation")
            scene?.rootNode.rotation = SCNVector4(x: 0, y: 1, z: 0, w: 1.75 * .pi)
            isPlaying = true

            UIView.animate(withDuration: 0.2) {
                self.alpha = self.collectibleEarned ? 1.0 : 0.45
            }
        }

        UIView.animate(withDuration: 0.2) {
            self.placeholderImageView?.alpha = 0.0
        } completion: { finished in
            self.placeholderImageView?.removeFromSuperview()
            self.placeholderImageView = nil
        }

        (self as? CollectibleARSCNView)?.initialSceneLoaded()
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
        collectible = nil
        localUsdzUrl = nil
    }

    private func generateTexture(fromCollectible collectible: Collectible,
                                 engraveInitials: Bool = true,
                                 backgroundColor: UIColor = .black) async -> UIImage {
        let medalImage = await collectible.medalImage
        let borderColor = await collectible.medalBorderColor
        let medalBackImage = await generateBackImage(forCollectible: collectible,
                                                     engraveInitials: engraveInitials)

        let options = UIGraphicsImageRendererFormat()
        options.opaque = true
        options.scale = 1
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size, format: options)

        return renderer.image { ctx in
            backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let medalImgSize = CGSize(width: 512, height: 884)
            medalImage?.draw(in: CGRect(origin: CGPoint(x: 512, y: 0), size: medalImgSize)
                .insetBy(dx: 8, dy: 5)
                .offsetBy(dx: 0, dy: 5))

            let backRect = CGRect(origin: .zero, size: medalImgSize)
                                .insetBy(dx: 8, dy: 5)
                                .offsetBy(dx: 0, dy: 5)
            medalBackImage?.sd_flippedImage(withHorizontal: true, vertical: true)?.draw(in: backRect)

            if let borderColor = borderColor {
                let borderFrame = CGRect(x: 0, y: 892, width: 716, height: 132)
                borderColor.setFill()
                ctx.fill(borderFrame)
            }
        }
    }

    private func generateBackImage(forCollectible collectible: Collectible, engraveInitials: Bool) async -> UIImage? {
        guard let medalImage = await collectible.medalImage,
              let borderColor = await collectible.medalBorderColor else {
            return nil
        }

        let isDarkBorder = borderColor.isBrightnessUnder(0.3)
        let medalBackImage = isDarkBorder ? UIImage(named: "medal_back_white")! : UIImage(named: "medal_back")!
        let textColor = isDarkBorder ? UIColor(white: 0.65, alpha: 1) : UIColor(white: 0.35, alpha: 1)

        let options = UIGraphicsImageRendererFormat()
        options.opaque = true
        options.scale = 1
        let size = medalImage.size
        let renderer = UIGraphicsImageRenderer(size: size, format: options)

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping

        return renderer.image { ctx in
            borderColor.setFill()
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(rect)
            medalBackImage.draw(in: rect)

            if engraveInitials {
                // Initial text
                let initialText = NSString(string: ADUser.current.initials)
                let initialFont = UIFont.presicav(size: 95, weight: .heavy)
                let initialAttributes: [NSAttributedString.Key : Any] = [.font: initialFont,
                                                                         .paragraphStyle: style,
                                                                         .foregroundColor: textColor]
                let initialTextSize = initialText.size(withAttributes: initialAttributes)
                let initialRect = CGRect(x: size.width / 2 - initialTextSize.width / 2,
                                         y: size.height / 2 - initialTextSize.height - 20,
                                         width: initialTextSize.width,
                                         height: initialTextSize.height)
                initialText.draw(in: initialRect, withAttributes: initialAttributes)

                // Earned Text
                let earnedDate = collectible.dateEarned.formatted(withStyle: .medium)
                let earnedText = NSString(string: "Earned on \(earnedDate)").uppercased
                let earnedFont = UIFont.presicav(size: 24)
                let earnedAttributes: [NSAttributedString.Key : Any] = [.font: earnedFont,
                                                                        .paragraphStyle: style,
                                                                        .foregroundColor: textColor,
                                                                        .kern: 3]
                let lrMargin: CGFloat = 100
                let earnedRect = CGRect(x: lrMargin,
                                        y: size.height / 2 + 20,
                                        width: size.width - lrMargin * 2,
                                        height: 300)
                earnedText.draw(in: earnedRect, withAttributes: earnedAttributes)
            } else {
                let unearnedText = NSString(string: "#anydistancecounts").uppercased
                let font = UIFont.presicav(size: 24)
                let attributes: [NSAttributedString.Key : Any] = [.font: font,
                                                                  .paragraphStyle: style,
                                                                  .foregroundColor: textColor,
                                                                  .kern: 3]
                let lrMargin: CGFloat = 100
                let rect = CGRect(x: lrMargin,
                                  y: size.height / 2 + 20,
                                  width: size.width - lrMargin * 2,
                                  height: 300)
                unearnedText.draw(in: rect, withAttributes: attributes)
            }
        }
    }

    func exposureAdjustedImage(_ image: UIImage) -> UIImage {
        let filter = CIFilter(name: "CIColorControls")
        let ciInputImage = CIImage(cgImage: image.cgImage!)
        filter?.setValue(ciInputImage, forKey: kCIInputImageKey)
        filter?.setValue(0.7, forKey: kCIInputContrastKey)
        filter?.setValue(-0.3, forKey: kCIInputBrightnessKey)

        if let output = filter?.outputImage {
            let context = CIContext()
            let cgOutputImage = context.createCGImage(output, from: ciInputImage.extent)
            return UIImage(cgImage: cgOutputImage!)
        }
        return image
    }
}

class NormalMapFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?

    override var attributes: [String : Any] {
        return [
            kCIAttributeFilterDisplayName: "Normal Map",
            "inputImage": [kCIAttributeIdentity: 0,
                              kCIAttributeClass: "CIImage",
                        kCIAttributeDisplayName: "Image",
                               kCIAttributeType: kCIAttributeTypeImage]
        ]
    }

    let normalMapKernel = CIKernel(source:
                                    "float lumaAtOffset(sampler source, vec2 origin, vec2 offset)" +
                                   "{" +
                                   " vec3 pixel = sample(source, samplerTransform(source, origin + offset)).rgb;" +
                                   " float luma = dot(pixel, vec3(0.2126, 0.7152, 0.0722));" +
                                   " return luma;" +
                                   "}" +


                                   "kernel vec4 normalMap(sampler image) \n" +
                                   "{ " +
                                   " vec2 d = destCoord();" +

                                   " float northLuma = lumaAtOffset(image, d, vec2(0.0, -1.0));" +
                                   " float southLuma = lumaAtOffset(image, d, vec2(0.0, 1.0));" +
                                   " float westLuma = lumaAtOffset(image, d, vec2(-1.0, 0.0));" +
                                   " float eastLuma = lumaAtOffset(image, d, vec2(1.0, 0.0));" +

                                   " float horizontalSlope = ((westLuma - eastLuma) + 1.0) * 0.5;" +
                                   " float verticalSlope = ((northLuma - southLuma) + 1.0) * 0.5;" +


                                   " return vec4(horizontalSlope, verticalSlope, 1.0, 1.0);" +
                                   "}"
    )

    override var outputImage: CIImage? {
        guard let inputImage = inputImage,
              let normalMapKernel = normalMapKernel else
        {
            return nil
        }

        return normalMapKernel.apply(extent: inputImage.extent,
                                     roiCallback:
                                        {
            (index, rect) in
            return rect
        },
                                     arguments: [inputImage])
    }
}

class CustomFiltersVendor: NSObject, CIFilterConstructor {
    func filter(withName name: String) -> CIFilter? {
        switch name {
        case "NormalMap":
            return NormalMapFilter()
        default:
            return nil
        }
    }

    static func registerFilters() {
        CIFilter.registerName("NormalMap",
                              constructor: CustomFiltersVendor(),
                              classAttributes: [
                                kCIAttributeFilterCategories: ["CustomFilters"]
                              ])
    }
}
3D medals are one of the core parts of Any Distance, and we spent a lot of time getting them right. These are rendered in SceneKit, an older but highly versatile native 3D rendering library. The base medal is a .usdz model that gets textured at runtime, so we only need to store a single usdz.

Texturing is highly dynamic and configurable. The app generates textures for diffuse, metalness, roughness, and a normal map. We also inscribe the back of the medal with the user's name and the date they earned it.

We divided the texturing pipeline into two types of medals – ones that have black backgrounds and ones that don't. Ones with black backgrounds tend to look good with highly metallic textures on light parts. Ones without black backgrounds look better with the opposite behavior.

3D Sneakers
View on GitHub
Copy
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
Like the medals, these 3D sneakers are also textured at runtime. Each sneaker texture is 5 layers, which all get tinted independently with CoreGraphics, then combined to create the final texture.

Gradient Animation (Metal)
View on GitHub
Copy
#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

struct NodeBuffer {
    float4x4 modelTransform;
    float4x4 modelViewTransform;
    float4x4 normalTransform;
    float4x4 modelViewProjectionTransform;
};

struct VertexIn {
    float2 position;
};

struct VertexOut {
    float4 position [[position]];
    float time;
    float2 viewSize;
    int page;
};

struct Uniforms {
    int page;
};

/// Passthrough vertex shader
vertex VertexOut gradient_animation_vertex(const device packed_float3* in [[ buffer(0) ]],
                                           constant float &time [[buffer(1)]],
                                           const device packed_float2* viewSize [[buffer(2)]],
                                           constant int &page [[buffer(3)]],
                                           unsigned int vid [[ vertex_id ]]) {
    VertexOut out;
    out.position = float4(in[vid], 1);
    out.time = time + (float)page * 10.;
    out.viewSize = float2(viewSize->x, viewSize->y);
    out.page = page;
    return out;
}

float noise1(float seed1, float seed2){
    return(
           fract(seed1+12.34567*
                 fract(100.*(abs(seed1*0.91)+seed2+94.68)*
                       fract((abs(seed2*0.41)+45.46)*
                             fract((abs(seed2)+757.21)*
                                   fract(seed1*0.0171))))))
    * 1.0038 - 0.00185;
}

float noise2(float seed1, float seed2, float seed3){
    float buff1 = abs(seed1+100.81) + 1000.3;
    float buff2 = abs(seed2+100.45) + 1000.2;
    float buff3 = abs(noise1(seed1, seed2)+seed3) + 1000.1;
    buff1 = (buff3*fract(buff2*fract(buff1*fract(buff2*0.146))));
    buff2 = (buff2*fract(buff2*fract(buff1+buff2*fract(buff3*0.52))));
    buff1 = noise1(buff1, buff2);
    return(buff1);
}

float noise3(float seed1, float seed2, float seed3) {
    float buff1 = abs(seed1+100.813) + 1000.314;
    float buff2 = abs(seed2+100.453) + 1000.213;
    float buff3 = abs(noise1(buff2, buff1)+seed3) + 1000.17;
    buff1 = (buff3*fract(buff2*fract(buff1*fract(buff2*0.14619))));
    buff2 = (buff2*fract(buff2*fract(buff1+buff2*fract(buff3*0.5215))));
    buff1 = noise2(noise1(seed2,buff1), noise1(seed1,buff2), noise1(seed3,buff3));
    return(buff1);
}

/// Fragment shader for gradient animation
fragment float4 gradient_animation_fragment(VertexOut in [[stage_in]]) {
    float2 st = in.position.xy/in.viewSize.xy;
    st = float2(tan(st.x), sin(st.y));

    st.x += (sin(in.time/2.1)+2.0)*0.12*sin(sin(st.y*st.x+in.time/6.0)*8.2);
    st.y -= (cos(in.time/1.73)+2.0)*0.12*cos(st.x*st.y*5.1-in.time/4.0);

    float3 bg = float3(0.0);

    float3 color1;
    float3 color2;
    float3 color3;
    float3 color4;
    float3 color5;

    if (in.page == 0) {
        color1 = float3(252.0/255.0, 60.0/255.0, 0.0/255.0);
        color2 = float3(253.0/255.0, 0.0/255.0, 12.0/255.0);
        color3 = float3(26.0/255.0, 0.5/255.0, 6.0/255.0);
        color4 = float3(128.0/255.0, 0.0/255.0, 17.0/255.0);
        color5 = float3(255.0/255.0, 15.0/255.0, 8.0/255.0);
    } else if (in.page == 1) {
        color1 = float3(183.0/255.0, 246.0/255.0, 254.0/255.0);
        color2 = float3(50.0/255.0, 160.0/255.0, 251.0/255.0);
        color3 = float3(3.0/255.0, 79.0/255.0, 231.0/255.0);
        color4 = float3(1.0/255.0, 49.0/255.0, 161.0/255.0);
        color5 = float3(3.0/255.0, 12.0/255.0, 47.0/255.0);
    } else if (in.page == 2) {
        color1 = float3(102.0/255.0, 231.0/255.0, 255.0/255.0);
        color2 = float3(4.0/255.0, 207.0/255.0, 213.0/255.0);
        color3 = float3(0.0/255.0, 160.0/255.0, 119.0/255.0);
        color4 = float3(0.0/255.0, 175.0/255.0, 139.0/255.0);
        color5 = float3(2.0/255.0, 37.0/255.0, 27.0/255.0);
    } else {
        color1 = float3(255.0/255.0, 50.0/255.0, 134.0/255.0);
        color2 = float3(236.0/255.0, 18.0/255.0, 60.0/255.0);
        color3 = float3(178.0/255.0, 254.0/255.0, 0.0/255.0);
        color4 = float3(0.0/255.0, 248.0/255.0, 209.0/255.0);
        color5 = float3(0.0/255.0, 186.0/255.0, 255.0/255.0);
    }

    float mixValue = smoothstep(0.0, 0.8, distance(st,float2(sin(in.time/5.0)+0.5,sin(in.time/6.1)+0.5)));
    float3 outColor = mix(color1,bg,mixValue);

    mixValue = smoothstep(0.1, 0.9, distance(st,float2(sin(in.time/3.94)+0.7,sin(in.time/4.2)-0.1)));
    outColor = mix(color2,outColor,mixValue);

    mixValue = smoothstep(0.1, 0.8, distance(st,float2(sin(in.time/3.43)+0.2,sin(in.time/3.2)+0.45)));
    outColor = mix(color3,outColor,mixValue);

    mixValue = smoothstep(0.14, 0.89, distance(st,float2(sin(in.time/5.4)-0.3,sin(in.time/5.7)+0.7)));
    outColor = mix(color4,outColor,mixValue);

    mixValue = smoothstep(0.01, 0.89, distance(st,float2(sin(in.time/9.5)+0.23,sin(in.time/3.95)+0.23)));
    outColor = mix(color5,outColor,mixValue);

    /// ----

    mixValue = smoothstep(0.01, 0.89, distance(st,float2(cos(in.time/8.5)/2.+0.13,sin(in.time/4.95)-0.23)));
    outColor = mix(color1,outColor,mixValue);

    mixValue = smoothstep(0.1, 0.9, distance(st,float2(cos(in.time/6.94)/2.+0.7,sin(in.time/4.112)+0.66)));
    outColor = mix(color2,outColor,mixValue);

    mixValue = smoothstep(0.1, 0.8, distance(st,float2(cos(in.time/4.43)/2.+0.2,sin(in.time/6.2)+0.85)));
    outColor = mix(color3,outColor,mixValue);

    mixValue = smoothstep(0.14, 0.89, distance(st,float2(cos(in.time/10.4)/2.-0.3,sin(in.time/5.7)+0.8)));
    outColor = mix(color4,outColor,mixValue);

    mixValue = smoothstep(0.01, 0.89, distance(st,float2(cos(in.time/4.5)/2.+0.63,sin(in.time/4.95)+0.93)));
    outColor = mix(color5,outColor,mixValue);

    float2 st_unwarped = in.position.xy/in.viewSize.xy;
    float3 noise = float3(noise3(st_unwarped.x*0.000001, st_unwarped.y*0.000001, in.time * 1e-15));
    outColor = (outColor * 0.85) - (noise * 0.1);

    return float4(outColor, 1.0);
}
This gradient animation shader was written in Metal. Although the implementation is completely different than the SwiftUI version, it follows the same basic principle – lots of blurred circles with random sizes, positions, animation, and blurs. It's really easy to draw a blurred oval in a shader – just ramp the color according to the distance to a center point. On top of that, there's some subtle domain warping and a generative noise function to really make it pop.

Tap & Hold To Stop Animation
View on GitHub
Copy
fileprivate struct TapAndHoldToStopView: View {
    @Binding var isPressed: Bool
    @State private var isVisible: Bool = false
    var drawerClosedHeight: CGFloat

    var body: some View {
        VStack {
            ZStack {
                Group {
                    DarkBlurView()
                        .mask(RoundedRectangle(cornerRadius: 30))
                    ToastText(text: "Tap and hold to stop",
                              icon: Image(systemName: .stopFill),
                              iconIncludesCircle: false)
                }

                ZStack {
                    BlurView(style: .systemUltraThinMaterialLight, intensity: 0.3)
                        .brightness(0.2)
                        .mask(RoundedRectangle(cornerRadius: 30))
                    ToastText(text: "Tap and hold to stop",
                              icon: Image(systemName: .stopFill),
                              iconIncludesCircle: false,
                              foregroundColor: .black)
                }
                .mask {
                    GeometryReader { geo in
                        HStack {
                            Rectangle()
                                .frame(width: isPressed ? geo.size.width : 0)
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 260)
            .opacity(isVisible ? 1.0 : 0.0)
            .scaleEffect(isVisible ? 1.0 : 1.1)
            .frame(height: 60)
            .onChange(of: isPressed) { _ in
                withAnimation(isPressed ? .easeOut(duration: 0.15) : .easeIn(duration: 0.15)) {
                    isVisible = isPressed
                }
            }

            Spacer()
                .height(drawerClosedHeight)
        }
        .ignoresSafeArea()
    }
}
This animation uses two instances of the "Tap and hold to stop" text - one in black and one in white. The black text gets masked by the progress bar as it slides over the screen, ensuring the text is legible no matter where the progress bar is.

Access Code Field
View on GitHub
Copy
import SwiftUI

fileprivate struct GradientAnimation: View {
    @Binding var animate: Bool

    private func rand18(_ idx: Int) -> [Float] {
        let idxf = Float(idx)
        return [sin(idxf * 6.3),
                cos(idxf * 1.3 + 48),
                sin(idxf + 31.2),
                cos(idxf * 44.1),
                sin(idxf * 3333.2),
                cos(idxf + 1.12 * pow(idxf, 3)),
                sin(idxf * 22),
                cos(idxf * 34)]
    }

    var body: some View {
        ZStack {
            ForEach(Array(0...50), id: \.self) { idx in
                let rands = rand18(idx)
                let fill = Color(hue: sin(Double(idx) * 5.12) + 1.1, saturation: 1, brightness: 1)

                Ellipse()
                    .fill(fill)
                    .frame(width: CGFloat(rands[1] + 2.0) * 50.0, height: CGFloat(rands[2] + 2.0) * 40.0)
                    .blur(radius: 25.0 + CGFloat(rands[1] + rands[2]) / 2)
                    .opacity(0.8)
                    .offset(x: CGFloat(animate ? rands[3] * 150.0 : rands[4] * 150.0),
                            y: CGFloat(animate ? rands[5] * 50.0 : rands[6] * 50.0))
                    .animation(.easeInOut(duration: TimeInterval(rands[7] + 3.0) * 1.3).repeatForever(autoreverses: true),
                               value: animate)
            }
        }
        .offset(y: 0)
        .onAppear {
            animate = true
        }
    }
}

struct AccessCodeField: View {
    @Binding var accessCode: String
    var isFocused: FocusState<Bool>.Binding
    @State private var chars: [String] = [String](repeating: " ", count: 6)
    @State private var animateGradient: Bool = false
    @State private var showingPasteButton: Bool = false

    fileprivate struct CharacterText: View {
        @Binding var text: String
        var cursorVisible: Bool

        @State private var animateCursor: Bool = false

        var body: some View {
            ZStack {
                Text(text)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 29, weight: .light, design: .monospaced))
                    .foregroundColor(.white)
                    .maxHeight(.infinity)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 1.5)
                    .frame(width: 3)
                    .frame(height: 40)
                    .opacity(animateCursor ? 1 : 0)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: animateCursor)
            }
            .onAppear {
                animateCursor = true
            }
        }
    }

    struct GridSeparator: View {
        var body: some View {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(colors: [.black, .clear, .clear, .black],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(height: 2)

                HStack(spacing: 0) {
                    Group {
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2)
                    }

                    Group {
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                    }
                }
            }
        }
    }

    var pasteButton: some View {
        Button {
            accessCode = String(UIPasteboard.general.string?.prefix(6) ?? "")
            showingPasteButton = false
        } label: {
            ZStack {
                VStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.2))
                        .frame(width: 75, height: 40)
                    Rectangle()
                        .rotation(.degrees(45))
                        .fill(Color(white: 0.2))
                        .frame(width: 20, height: 20)
                        .offset(y: -25)
                }
                Text("Paste")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(.white)
                    .offset(y: -14)
            }
        }
        .opacity(showingPasteButton ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showingPasteButton)
        .offset(y: -45)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                Image(uiImage: UIImage(named: "dot_bg")!.resized(withNewWidth: 4))
                    .resizable(resizingMode: .tile)
                    .opacity(0.15)
                    .mask {
                        GridSeparator()
                    }

                GradientAnimation(animate: $animateGradient)
                    .frame(height: 60.0)
                    .frame(maxWidth: .infinity)
                    .drawingGroup()
                    .saturation(1.2)
                    .brightness(0.1)
                    .mask {
                        LinearGradient(colors: [.black, .black.opacity(0.1)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    }
                    .onChange(of: isFocused.wrappedValue) { _ in
                        animateGradient = !animateGradient
                    }

                GridSeparator()
                    .opacity(0.45)

                TextField("", text: $accessCode)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.characters)
                    .focused(isFocused)
                    .opacity(0.01)

                HStack(spacing: 0) {
                    ForEach(Array(0...5), id: \.self) { idx in
                        CharacterText(text: .constant("0"), cursorVisible: false)
                            .frame(width: geo.size.width / 6, height: 60)
                    }
                }
                .opacity((isFocused.wrappedValue || !accessCode.isEmpty) ? 0.0 : 0.4)
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(Array(0...5), id: \.self) { idx in
                        CharacterText(text: $chars[idx],
                                      cursorVisible: accessCode.count == idx && isFocused.wrappedValue)
                        .frame(width: geo.size.width / 6.0, height: 60.0)
                    }
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) {
                    showingPasteButton = true
                }
                .simultaneousGesture(TapGesture().onEnded({ _ in
                    accessCode = ""
                    isFocused.wrappedValue = true
                    showingPasteButton = false
                }))
            }
        }
        .frame(height: 60.0)
        .mask {
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
        }
        .background {
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                .fill(Color.white.opacity(0.25))
                .offset(y: 1.0)
        }
        .overlay {
            pasteButton
        }
        .onChange(of: accessCode) { newValue in
            if newValue.count >= 6 {
                isFocused.wrappedValue = false
            }
            showingPasteButton = false

            chars = newValue.padding(toLength: 6,
                                     withPad: " ",
                                     startingAt: 0).map { String($0).capitalized }
        }
    }
}

#Preview {
    @FocusState var focused: Bool
    AccessCodeField(accessCode: .constant(""), isFocused: $focused)
}
This is a fun glowing text field written in SwiftUI. We used it when we announced early access for Active Clubs, our swing at a social network. The trick to the soupy rainbow effect is layering lots of ovals with varying size and opacity, animating them back and forth at various phases and durations, and blurring them random amounts. The video below shows what this looks like without the blur, which might give you a better idea of what's going on.

Custom MapKit Overlay Renderer
View on GitHub
Copy
fileprivate struct MapView: UIViewRepresentable  {
    @ObservedObject var model: ActivityProgressGraphModel
    @Binding var selectedClusterIdx: Int

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .mutedStandard
        mapView.preferredConfiguration.elevationStyle = .flat
        mapView.isPitchEnabled = false
        mapView.showsUserLocation = false
        mapView.showsBuildings = false
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = MKPointOfInterestFilter.excludingAll
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.delegate = context.coordinator
        mapView.alpha = 0.0
        context.coordinator.mkView = mapView

        model.$coordinateClusters
            .receive(on: DispatchQueue.main)
            .sink { _ in
                selectedClusterIdx = 0
            }.store(in: &context.coordinator.subscribers)

        model.$viewVisible
            .receive(on: DispatchQueue.main)
            .sink { visible in
                if visible {
                    addPolylines(mapView)
                } else {
                    mapView.removeOverlays(mapView.overlays)
                }
            }.store(in: &context.coordinator.subscribers)

        return mapView
    }

    private func addPolylines(_ mapView: MKMapView) {
        if model.coordinateClusters.isEmpty {
            return
        }

        Task(priority: .userInitiated) {
            mapView.removeOverlays(mapView.overlays)
            model.coordinateClusters[selectedClusterIdx].coordinates.forEach { coordinates in
                coordinates.withUnsafeBufferPointer { pointer in
                    if let base = pointer.baseAddress {
                        let newPolyline = MKPolyline(coordinates: base, count: coordinates.count)
                        mapView.addOverlay(newPolyline)
                    }
                }
            }
        }
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if model.coordinateClusters.count > selectedClusterIdx {
            addPolylines(uiView)
            let rect = model.coordinateClusters[selectedClusterIdx].rect
            if rect != context.coordinator.displayedRect {
                let edgePadding = UIEdgeInsets(top: 180.0,
                                               left: 25.0,
                                               bottom: UIScreen.main.bounds.height * 0.4,
                                               right: 25.0)
                uiView.setVisibleMapRect(rect,
                                         edgePadding: edgePadding,
                                         animated: context.coordinator.hasSetInitialRegion)
                context.coordinator.displayedRect = rect
                context.coordinator.resetAnimationTimer()
                context.coordinator.hasSetInitialRegion = true
            }

            context.coordinator.shouldAnimateIn = true
        } else if model.coordinateClusters.isEmpty {
            uiView.removeOverlays(uiView.overlays)
            if context.coordinator.hasSetInitialRegion && model.hasPerformedInitialLoad {
                context.coordinator.shouldAnimateIn = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var parent: MapView
        var mkView: MKMapView?
        var subscribers: Set<AnyCancellable> = []
        var hasSetInitialRegion: Bool = false
        var hasInitialFinishedRender: Bool = false
        var displayedRect: MKMapRect?
        var shouldAnimateIn: Bool = false
        var willRender: Bool = false
        private lazy var displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFire))
        private var polylineProgress: CGFloat = 0
        private let lineColor = UIColor.white.withAlphaComponent(0.6)

        init(parent: MapView) {
            self.parent = parent
            super.init()

            self.displayLink.add(to: .main, forMode: .common)
            self.displayLink.add(to: .main, forMode: .tracking)
            self.displayLink.isPaused = false
        }

        func resetAnimationTimer() {
            polylineProgress = -0.05
            displayLinkFire()
            displayLink.isPaused = true
        }

        @objc func displayLinkFire() {
            if polylineProgress <= 1 {
                for overlay in mkView!.overlays {
                    if !overlay.boundingMapRect.intersects(mkView?.visibleMapRect ?? MKMapRect()) {
                        continue
                    }

                    if let polylineRenderer = mkView!.renderer(for: overlay) as? MKPolylineRenderer {
                        polylineRenderer.strokeEnd = RouteScene.easeOutQuad(x: polylineProgress).clamped(to: 0...1)
                        polylineRenderer.strokeColor = polylineProgress <= 0.01 ? .clear : lineColor
                        polylineRenderer.blendMode = .destinationAtop
                        polylineRenderer.setNeedsDisplay()
                    }
                }
                
                polylineProgress += 0.01
            }
        }

        func lineWidth(for mapView: MKMapView) -> CGFloat {
            let visibleWidth = mapView.visibleMapRect.width
            return CGFloat(-0.00000975 * visibleWidth + 2.7678715).clamped(to: 1.5...2.5)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let stroke = lineWidth(for: mapView)
            if let routePolyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: routePolyline)
                renderer.strokeColor = displayLink.isPaused ? .clear : lineColor
                renderer.lineWidth = stroke
                renderer.strokeEnd = displayLink.isPaused ? 0 : 1
                renderer.blendMode = .destinationAtop
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }

            return MKOverlayRenderer()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let stroke = lineWidth(for: mapView)
            for overlay in mkView!.overlays {
                if !overlay.boundingMapRect.intersects(mkView?.visibleMapRect ?? MKMapRect()) {
                    continue
                }

                if let polylineRenderer = mkView!.renderer(for: overlay) as? MKPolylineRenderer {
                    polylineRenderer.lineWidth = stroke
                }
            }
        }

        func mapViewWillStartRenderingMap(_ mapView: MKMapView) {
            willRender = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if willRender {
                return
            }

            displayLink.isPaused = false
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered {
                displayLink.isPaused = false
                willRender = false

                if shouldAnimateIn {
                    UIView.animate(withDuration: 0.3) {
                        mapView.alpha = 1.0
                    }
                    shouldAnimateIn = false
                }
            }
        }
    }
}
This was my attempt at animating polylines using only the native MapKit API. It's a bit of a hack – I use a CADisplayLink to force a redraw on every frame where I update each polyline renderer's strokeEnd property. This creates a beautiful sprawling animation as your route lines all fill out simultaneously.

Fake UIAlertView
View on GitHub
Copy
import SwiftUI

struct AppleHealthPermissionsView: View {
    @State var dismissing: Bool = false
    @State var isPresented: Bool = false
    var nextAction: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .opacity(isPresented ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isPresented)

            VStack(spacing: 0) {
                Text("Permissions for Apple Health")
                    .padding([.leading, .trailing, .top], 16)
                    .padding([.bottom], 4)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .semibold))
                Text("To sync your Activities, Any Distance needs permission to view your Apple Health data. The data is only read, it's never stored or shared elsewhere.\n\nOn the next screen, tap “Turn On All” and “Allow” to continue with your setup.")
                    .padding([.leading, .trailing, .bottom], 16)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))

                LoopingVideoView(videoUrl: Bundle.main.url(forResource: "health-how-to", withExtension: "mp4"),
                                 videoGravity: .resizeAspect)
                    .frame(width: UIScreen.main.bounds.width * 0.7,
                           height: UIScreen.main.bounds.width * 0.55)
                    .background(Color.white)

                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 0.5)

                HStack(spacing: 0) {
                    Button {
                        dismissing = true
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            UIApplication.shared.topViewController?.dismiss(animated: false)
                        }
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.blue)
                            .brightness(0.1)
                            .frame(width: (UIScreen.main.bounds.width * 0.35) - 1, height: 46)
                    }
                    .buttonStyle(AlertButtonStyle())

                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 0.5, height: 46)

                    Button {
                        nextAction?()
                    } label: {
                        Text("Next")
                            .foregroundColor(.blue)
                            .brightness(0.1)
                            .frame(width: (UIScreen.main.bounds.width * 0.35) - 1, height: 46)
                    }
                    .buttonStyle(AlertButtonStyle())
                }
            }
            .background {
                BlurView()
            }
            .cornerRadius(14, style: .continuous)
            .frame(width: UIScreen.main.bounds.width * 0.7)
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(dismissing ? 1 : (isPresented ? 1 : 1.15))
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
        .onAppear {
            isPresented = true
        }
    }
}

struct AppleHealthPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        AppleHealthPermissionsView()
    }
}
Is this allowed? We first designed this in Figma, thinking we could insert a video into a UIAlertView. Turns out you can't do that. So as a challenge, I tried to recreate UIAlertView as closely as possible in SwiftUI, but with the addition of a looping video view. The look is now outdated for iOS 26, but it was a fun test to see how far we could push SwiftUI to recreate native system UI.

Health Connect Animation (2021)
View on GitHub
Copy
import UIKit

class SyncAnimationView: UIView {

    // MARK: - Images

    let supportedActivitiesIcons = UIImage(named: "sync_supported_activities")!

    let sourceIcons: [UIImage] = [UIImage(named: "icon_garmin")!,
                                  UIImage(named: "icon_runkeeper")!,
                                  UIImage(named: "icon_peloton")!,
                                  UIImage(named: "icon_nrc")!,
                                  UIImage(named: "icon_strava")!,
                                  UIImage(named: "icon_fitness")!]
    let healthIcon = UIImage(named: "glyph_applehealth_100px")!
    let syncIcon = UIImage(named: "glyph_sync")!

    // MARK: - Colors

    let sourceColors: [UIColor] = [UIColor(hex: "00B0F3")!,
                                   UIColor(hex: "00CCDA")!,
                                   UIColor(hex: "FF003D")!,
                                   UIColor(hex: "464646")!,
                                   UIColor(hex: "FF5700")!,
                                   UIColor(hex: "CCFF00")!]
    let trackColor = UIColor(hex: "2B2B2B")!
    let healthDotColor = UIColor(hex: "FFC100")!

    // MARK: - Layout

    let headerHeight: CGFloat = 50
    let sourceIconSize: CGFloat = 61
    let sourceIconSpacing: CGFloat = 14
    let sourceTrackSpacing: CGFloat = 10
    let sourceStartY: CGFloat = 142
    let trackWidth: CGFloat = 4.5
    let trackCornerRadius: CGFloat = 32
    let dotRadius: CGFloat = 7.5
    var sourceHealthSpacing: CGFloat = 110
    let healthIconSize: CGFloat = 100
    let verticalLineLength: CGFloat = 400
    let syncIconSize: CGFloat = 113

    let iconCarouselSpeed: CGFloat = 0.5
    let dotSpeed: CGFloat = 0.6
    let dotSpawnRate: Int = 40
    let verticalDotSpeed: CGFloat = 0.4
    let verticalDotSpawnRate: Int = 120
    let syncIconRotationRate: CGFloat = 0.05

    let translateAnimationDuration: CGFloat = 1.5
    var finalTranslateY: CGFloat = -650

    // MARK: - Variables

    private var displayLink: CADisplayLink!
    private var t: Int = 0
    private var dots: [Dot] = []
    private var verticalDots: [VerticalDot] = []
    private var dotSpawn: Int = 0
    private var verticalDotSpawn: Int = 0
    private var translateY: CGFloat = 0
    private var syncIconRotate: CGFloat = 0
    private var prevDotSpawnIdx: Int = 0

    private var animProgress: CGFloat = 0
    private var animatingTranslate: Bool = false

    // MARK: - Setup

    override func awakeFromNib() {
        super.awakeFromNib()

        // adjust spacing between source icons and health icon for smaller screens
        let sizeDiff = (844 - UIScreen.main.bounds.height).clamped(to: -30...60)
        sourceHealthSpacing -= sizeDiff
        finalTranslateY += sizeDiff

        // make dots spawn immediately
        dotSpawn = dotSpawnRate - 1
        verticalDotSpawn = verticalDotSpawnRate - 30

        layer.masksToBounds = false
        clipsToBounds = false
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .common)
    }

    func animateTranslate() {
        animatingTranslate = true
    }

    func translateWithoutAnimating() {
        translateY = finalTranslateY
    }

    @objc private func update() {
        t += 1
        incrementDots()
        spawnNewDots()
        spawnNewVerticalDots()
        setNeedsDisplay()

        if animatingTranslate {
            animProgress += 1 / translateAnimationDuration / 60
            let easedProgress = easeInOutQuart(x: animProgress)
            translateY = easedProgress * finalTranslateY
            if easedProgress >= 1 {
                animatingTranslate = false
            }
        }
    }

    private func easeInOutQuart(x: CGFloat) -> CGFloat {
        return x < 0.5 ? 8 * pow(x, 4) : 1 - pow(-2 * x + 2, 4) / 2
    }

    private func incrementDots() {
        var i = 0
        while i < dots.count {
            dots[i].percent += dotSpeed / 100
            dots[i].pathStartX -= iconCarouselSpeed
            if dots[i].percent >= 1 {
                dots.remove(at: i)
            } else {
                i += 1
            }
        }

        i = 0
        while i < verticalDots.count {
            verticalDots[i].percent += verticalDotSpeed / 100
            if verticalDots[i].percent >= 1 {
                verticalDots.remove(at: i)
            } else {
                i += 1
            }
        }
    }

    private func spawnNewDots() {
        guard dotSpawn == dotSpawnRate else {
            dotSpawn += 1
            return
        }
        dotSpawn = 0

        var i = 0
        var startX = (-1 * iconCarouselSpeed * CGFloat(t)) - 150
        while startX < 0 {
            startX += (sourceIconSize + sourceIconSpacing)
            i += 1
        }

        var rand = prevDotSpawnIdx
        while rand == prevDotSpawnIdx {
            rand = Int(arc4random_uniform(5))
        }
        prevDotSpawnIdx = rand

        startX += CGFloat(rand) * (sourceIconSize + sourceIconSpacing)
        startX += sourceIconSize / 2
        i += rand

        let newDot = Dot(percent: 0, pathStartX: startX, color: sourceColors[i % sourceColors.count])
        dots.append(newDot)
    }

    private func spawnNewVerticalDots() {
        guard verticalDotSpawn == verticalDotSpawnRate else {
            verticalDotSpawn += 1
            return
        }
        verticalDotSpawn = 0

        let newVerticalDot = VerticalDot(percent: 0)
        verticalDots.append(newVerticalDot)
    }

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.translateBy(x: 0, y: headerHeight)
        ctx?.translateBy(x: 0, y: translateY)

        // Draw Source Icons + Tracks + Dots
        var i = 0
        var startX = (-1 * iconCarouselSpeed * CGFloat(t)) - 150
        func inc() {
            i += 1
            startX += (sourceIconSize + sourceIconSpacing)
        }

        let pathStartY: CGFloat = sourceStartY + sourceIconSize + sourceTrackSpacing
        let pathEndY: CGFloat = sourceStartY + sourceIconSize + sourceHealthSpacing + (healthIconSize / 2)
        trackColor.setStroke()

        // Draw horizonal line
        let horizontalPath = UIBezierPath()
        horizontalPath.lineCapStyle = .round
        horizontalPath.lineWidth = trackWidth
        horizontalPath.move(to: CGPoint(x: -20, y: pathEndY))
        horizontalPath.addLine(to: CGPoint(x: bounds.width + 20, y: pathEndY))
        horizontalPath.stroke()

        var sourceIconsToDraw: [UIImage] = []
        var sourceIconRects: [CGRect] = []

        ctx?.setShadow(offset: .zero, blur: 10, color: nil)
        while startX < rect.width + (2 * sourceIconSize) {
            if startX < -2 * sourceIconSize {
                inc()
                continue
            }

            // Draw Path
            let path = UIBezierPath()
            path.lineCapStyle = .round
            path.lineWidth = trackWidth
            path.move(to: CGPoint(x: startX + sourceIconSize / 2,
                                  y: pathStartY))
            path.addLine(to: CGPoint(x: startX + sourceIconSize / 2,
                                     y: pathEndY - trackCornerRadius))

            let isRightSide = (startX + sourceIconSize / 2) > (bounds.width / 2)
            let centerX = isRightSide ? startX + (sourceIconSize / 2) - trackCornerRadius :
                                        startX + (sourceIconSize / 2) + trackCornerRadius
            path.addArc(withCenter: CGPoint(x: centerX,
                                            y: pathEndY - trackCornerRadius),
                        radius: trackCornerRadius,
                        startAngle: isRightSide ? 0 : .pi,
                        endAngle: .pi / 2,
                        clockwise: isRightSide)
            path.stroke()

            // Queue source icon drawing for after we draw the dots
            let icon = sourceIcons[i % sourceIcons.count]
            let rect = CGRect(x: startX, y: sourceStartY, width: sourceIconSize, height: sourceIconSize)
            sourceIconsToDraw.append(icon)
            sourceIconRects.append(rect)

            inc()
        }

        // Draw Dots
        for dot in dots {
            let centerPoint = pointOnPath(forDot: dot)
            dot.color.setFill()
            ctx?.setShadow(offset: .zero, blur: 10, color: dot.color.cgColor)
            UIBezierPath(ovalIn: CGRect(x: centerPoint.x - dotRadius,
                                        y: centerPoint.y - dotRadius,
                                        width: dotRadius * 2,
                                        height: dotRadius * 2)).fill()
        }

        // Draw Source Icons
        ctx?.setShadow(offset: .zero, blur: 10, color: nil)
        for (icon, rect) in zip(sourceIconsToDraw, sourceIconRects) {
            icon.draw(in: rect)
        }

        // Draw vertical line
        let verticalPath = UIBezierPath()
        verticalPath.lineWidth = trackWidth
        verticalPath.move(to: CGPoint(x: bounds.width / 2, y: pathEndY))
        verticalPath.addLine(to: CGPoint(x: bounds.width / 2, y: pathEndY + verticalLineLength))
        verticalPath.stroke()

        // Draw vertical dots
        ctx?.setShadow(offset: .zero, blur: 10, color: healthDotColor.cgColor)
        for dot in verticalDots {
            let y = pathEndY + (verticalLineLength * dot.percent)
            let centerPoint = CGPoint(x: bounds.width / 2, y: y)
            let dotFrame = CGRect(x: centerPoint.x - dotRadius,
                                  y: centerPoint.y - dotRadius,
                                  width: dotRadius * 2,
                                  height: dotRadius * 2)
            healthDotColor.setFill()
            UIBezierPath(ovalIn: dotFrame).fill()
        }

        // Draw Health Icon
        ctx?.setShadow(offset: .zero, blur: 10, color: nil)
        let healthIconFrame = CGRect(x: (bounds.width / 2) - (healthIconSize / 2),
                                     y: pathEndY - (healthIconSize / 2),
                                     width: healthIconSize,
                                     height: healthIconSize)
        healthIcon.draw(in: healthIconFrame)

        // Draw Sync Icon
        ctx?.translateBy(x: (bounds.width / 2),
                         y: (pathEndY + verticalLineLength))
        ctx?.rotate(by: syncIconRotate)
        ctx?.translateBy(x: -1 * (syncIconSize / 2), y: -1 * (syncIconSize / 2))
        syncIcon.draw(in: CGRect(origin: .zero,
                                 size: CGSize(width: syncIconSize, height: syncIconSize)))

        syncIconRotate += syncIconRotationRate
    }

    private func pointOnPath(forDot dot: Dot) -> CGPoint {
        let percent = dot.percent
        let isRightSide = dot.pathStartX > (bounds.width / 2)
        let centerX = isRightSide ? dot.pathStartX - trackCornerRadius :
                                    dot.pathStartX + trackCornerRadius

        let pathStartY: CGFloat = sourceStartY + (sourceIconSize / 2)
        let pathEndY: CGFloat = sourceStartY + sourceIconSize + sourceHealthSpacing + (healthIconSize / 2)

        let verticalLineLength = pathEndY - pathStartY - trackCornerRadius
        let curveLength = .pi * trackCornerRadius / 2
        let horizontalLineLength = abs((bounds.width / 2) - centerX)
        let totalLineLength = verticalLineLength + curveLength + horizontalLineLength

        let vertPercent = percent / (verticalLineLength / totalLineLength)
        let curvePercent = (percent - (verticalLineLength / totalLineLength)) / (curveLength / totalLineLength)
        let horizontalPercent = (percent - ((verticalLineLength + curveLength) / totalLineLength)) / (horizontalLineLength / totalLineLength)

        var dotPoint: CGPoint = .zero
        if percent <= verticalLineLength / totalLineLength {
            // Dot is on vertical line
            dotPoint = CGPoint(x: dot.pathStartX,
                               y: pathStartY + (verticalLineLength * vertPercent))
        } else if percent <= (verticalLineLength + curveLength) / totalLineLength {
            // Dot is on curve
            if abs((bounds.width / 2) - dot.pathStartX) < healthIconSize / 3 {
                // Make dot go straight down if its under the Health icon
                dotPoint = CGPoint(x: bounds.width / 2,
                                   y: pathEndY)
            } else if isRightSide {
                let angle = ((.pi / 2) * (1 - curvePercent))
                dotPoint = CGPoint(x: centerX + (trackCornerRadius * sin(angle)),
                                   y: (pathEndY - trackCornerRadius) + (trackCornerRadius * cos(angle)))
            } else {
                let angle = ((.pi / 2) * curvePercent) - (.pi / 2)
                dotPoint = CGPoint(x: centerX + (trackCornerRadius * sin(angle)),
                                   y: (pathEndY - trackCornerRadius) + (trackCornerRadius * cos(angle)))
            }
        } else {
            // Dot is on horizontal line
            if abs((bounds.width / 2) - dot.pathStartX) < healthIconSize / 3 {
                // Make dot go straight down if its under the Health icon
                dotPoint = CGPoint(x: bounds.width / 2,
                                   y: pathEndY)
            } else {
                let clampedPercent = horizontalPercent.clamped(to: 0...1)
                let x = isRightSide ? centerX - (clampedPercent * horizontalLineLength) :
                centerX + (clampedPercent * horizontalLineLength)
                dotPoint = CGPoint(x: x, y: pathEndY)
            }
        }

        return dotPoint
    }
}

fileprivate struct Dot {
    var percent: CGFloat
    var pathStartX: CGFloat
    var color: UIColor
}

fileprivate struct VerticalDot {
    var percent: CGFloat
}
This was one of our earliest Apple Health connection experiences. At the time, the whole app including this screen was 100% UIKit. The animation is made by manually drawing every image and shape at the correct position on every frame, with the refresh driven by a CADisplayLink. I love this style of procedural UI, where layout is calculated manually – it's very similar to generative art.

Nice Confetti
View on GitHub
Copy
import UIKit
import QuartzCore

public final class ConfettiView: UIView {
    public var colors = GoalProgressIndicator().trackGradientColors
    public var intensity: Float = 0.8
    public var style: ConfettiViewStyle = .large

    private(set) var emitter: CAEmitterLayer?
    private var active = false
    private var image = UIImage(named: "confetti")?.cgImage

    public func startConfetti(beginAtTimeZero: Bool = true) {
        emitter?.removeFromSuperlayer()
        emitter = CAEmitterLayer()

        if beginAtTimeZero {
            emitter?.beginTime = CACurrentMediaTime()
        }

        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: -10)
        emitter?.emitterShape = .line
        emitter?.emitterSize = CGSize(width: frame.size.width, height: 1)

        var cells = [CAEmitterCell]()
        for color in colors {
            cells.append(confettiWithColor(color: color))
        }

        emitter?.emitterCells = cells

        switch style {
        case .large:
            emitter?.birthRate = 4
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.emitter?.birthRate = 0.6
            }
        case .small:
            emitter?.birthRate = 0.35
        }

        layer.addSublayer(emitter!)
        active = true
    }

    public func stopConfetti() {
        emitter?.birthRate = 0
        active = false
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: -10)
        emitter?.emitterSize = CGSize(width: frame.size.width, height: 1)
    }

    func confettiWithColor(color: UIColor) -> CAEmitterCell {
        let confetti = CAEmitterCell()
        confetti.birthRate = 12.0 * intensity
        confetti.lifetime = 14.0 * intensity
        confetti.lifetimeRange = 0
        confetti.color = color.cgColor
        confetti.velocity = CGFloat(350.0 * intensity)
        confetti.velocityRange = CGFloat(80.0 * intensity)
        confetti.emissionLongitude = CGFloat(Double.pi)
        confetti.emissionRange = CGFloat(Double.pi)
        confetti.spin = CGFloat(3.5 * intensity)
        confetti.spinRange = CGFloat(4.0 * intensity)
        confetti.scaleRange = CGFloat(intensity)
        confetti.scaleSpeed = CGFloat(-0.1 * intensity)
        confetti.contents = image
        confetti.contentsScale = 1.5
        confetti.setValue("plane", forKey: "particleType")
        confetti.setValue(Double.pi, forKey: "orientationRange")
        confetti.setValue(Double.pi / 2, forKey: "orientationLongitude")
        confetti.setValue(Double.pi / 2, forKey: "orientationLatitude")

        if style == .small {
            confetti.contentsScale = 3.0
            confetti.velocity = CGFloat(70.0 * intensity)
            confetti.velocityRange = CGFloat(20.0 * intensity)
        }

        return confetti
    }

    public func isActive() -> Bool {
        return self.active
    }
}

public enum ConfettiViewStyle {
    case large
    case small
}
Confetti has been common on iOS for a while, but several people have told me that our confetti looks especially nice. We use SpriteKit, which I believe is the best looking and most performant way to do it. The key is to take advantage of all of CAEmitterCell's randomization properties. The subtle orientation transforms on each particle really sell it.

Recent Photo Picker
View on GitHub
Copy
import UIKit
import PureLayout

protocol RecentPhotoPickerDelegate: AnyObject {
    func recentPhotoPickerPickedPhoto(_ photo: UIImage)
}

final class RecentPhotoPicker: UIView {

    // MARK: - Constants

    let buttonSize: CGSize = CGSize(width: 46, height: 68)
    let collapsedOverlap: CGFloat = 12
    let expandedSpacing: CGFloat = 8
    let deselectedBorderColor: UIColor = UIColor(white: 0.15, alpha: 1)
    let inactiveBorderColor: UIColor = UIColor(white: 0.08, alpha: 1)

    // MARK: - Variables

    weak var delegate: RecentPhotoPickerDelegate?

    private var activityIndicator: UIActivityIndicatorView?
    private var loadingSquare: UIImageView?
    private var buttons: [ScalingPressButton] = []
    private var widthConstraint: NSLayoutConstraint?
    private var buttonLeadingConstraints: [NSLayoutConstraint] = []
    private var state: RecentPhotoPickerState = .collapsed

    // MARK: - Setup

    override func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }

    private func setup() {
        layer.masksToBounds = false
        backgroundColor = .black

        loadingSquare = UIImageView(image: UIImage(named: "button_editor_empty")?.withRenderingMode(.alwaysTemplate))
        loadingSquare?.tintColor = inactiveBorderColor
        addSubview(loadingSquare!)
        loadingSquare?.autoPinEdge(toSuperviewEdge: .top, withInset: 18)
        loadingSquare?.autoAlignAxis(.vertical, toSameAxisOf: self, withOffset: 0)
        loadingSquare?.autoSetDimensions(to: buttonSize)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator?.startAnimating()
        addSubview(activityIndicator!)
        activityIndicator?.autoAlignAxis(.horizontal, toSameAxisOf: loadingSquare!)
        activityIndicator?.autoAlignAxis(.vertical, toSameAxisOf: loadingSquare!)
        widthConstraint = self.autoSetDimension(.width, toSize: buttonSize.width + expandedSpacing * 2)
    }

    func addButtonsWithPhotos(_ photos: [UIImage]) {
        var prevButton: ScalingPressButton?
        for i in 0..<photos.count {
            let button = ScalingPressButton()
            button.imageView?.contentMode = .scaleAspectFill
            button.imageView?.layer.cornerRadius = 5.5
            button.imageView?.layer.cornerCurve = .continuous
            button.imageView?.layer.masksToBounds = true
            button.imageView?.layer.minificationFilter = .trilinear
            button.imageView?.layer.minificationFilterBias = 0.06
            button.imageEdgeInsets = UIEdgeInsets(top: 2.5, left: 2.5, bottom: 2.5, right: 2.5)
            let grayBorder = UIImage(named: "button_editor_empty")?.withRenderingMode(.alwaysTemplate)
            button.setBackgroundImage(grayBorder, for: .normal)
            button.tintColor = deselectedBorderColor
            button.setImage(photos[i], for: .normal)
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            button.alpha = 0
            button.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            addSubview(button)
            sendSubviewToBack(button)
            buttons.append(button)

            button.autoPinEdge(toSuperviewEdge: .top, withInset: 18)
            button.autoSetDimensions(to: buttonSize)

            if let prev = prevButton {
                let constraint = button.autoPinEdge(.leading,
                                                    to: .leading,
                                                    of: prev,
                                                    withOffset: collapsedOverlap)
                buttonLeadingConstraints.append(constraint)
            } else {
                button.autoPinEdge(.leading, to: .leading, of: self)
            }

            prevButton = button
        }
        layoutIfNeeded()

        if !buttons.isEmpty {
            self.widthConstraint?.constant = CGFloat(buttons.count - 1) * collapsedOverlap + buttonSize.width + (expandedSpacing * 2)
            hideLoadingView()

            for (i, button) in self.buttons.enumerated() {
                UIView.animate(withDuration: 0.5,
                               delay: TimeInterval(i) * 0.05,
                               usingSpringWithDamping: 0.8,
                               initialSpringVelocity: 0.1,
                               options: [.curveEaseIn],
                               animations: {
                    button.alpha = 1
                    button.transform = .identity
                }, completion: nil)
            }
        } else {
            self.widthConstraint?.constant = 0
            hideLoadingView()
        }
    }

    private func hideLoadingView() {
        UIView.animate(withDuration: 0.6,
                       delay: 0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.1,
                       options: [.curveEaseIn],
                       animations: {
            self.activityIndicator?.alpha = 0
            self.loadingSquare?.alpha = 0
            self.superview?.layoutIfNeeded()
        }, completion: nil)
    }

    private func expand() {
        buttonLeadingConstraints.forEach { constraint in
            constraint.constant = buttonSize.width + expandedSpacing
        }
        widthConstraint?.constant = CGFloat(buttons.count) * (buttonSize.width + expandedSpacing)

        UIView.animate(withDuration: 0.5,
                       delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0.1,
                       options: [.curveEaseIn, .allowUserInteraction],
                       animations: {
            self.superview?.layoutIfNeeded()
        }, completion: nil)

        state = .expanded
    }

    func deselectAllButtons() {
        buttons.forEach { button in
            button.tintColor = deselectedBorderColor
        }
    }

    @objc private func buttonTapped(_ button: ScalingPressButton) {
        if state == .collapsed && buttons.count > 1 {
            expand()
            return
        }

        if let image = button.image(for: .normal) {
            delegate?.recentPhotoPickerPickedPhoto(image)
        }

        for b in buttons {
            UIView.transition(with: button, duration: 0.2, options: [.transitionCrossDissolve], animations: {
                b.tintColor = (b === button) ? .white : self.deselectedBorderColor
            }, completion: nil)
        }
    }
}

enum RecentPhotoPickerState {
    case collapsed
    case expanded
}
This fun photo widget is one of my favorite UIKit components in the app. UIKit makes it easy to stack, stagger, and choreograph multi-step animation sequences without sacrificing performance. We can transition from the loading state into the loaded state and simultaneously transition in all the photos views with a staggered effect.

The photos in this picker are pulled from around the timestamp of the corresponding workout, making it easy to quickly find a photo you took during your workout.

Vertical Picker
View on GitHub
Copy
import UIKit
import PureLayout

class HitTestView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return outsideBoundsHitTest(point, with: event)
    }
}

class HitTestScrollView: UIScrollView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return outsideBoundsHitTest(point, with: event)
    }
}

extension UIView {
    func outsideBoundsHitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled else { return nil }
        guard !isHidden else { return nil }
        guard alpha >= 0.01 else { return nil }

        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let candidate = subview.hitTest(convertedPoint, with: event) {
                return candidate
            }
        }
        return nil
    }
}

final class VerticalPicker: HitTestView {
    private var label: UILabel!
    private var backgroundView: UIView!
    private var buttons: [UIButton] = []
    private var buttonBottomConstraints: [NSLayoutConstraint] = []
    private var selectedIdx: Int = 0
    private var state: VerticalPickerState = .contracted
    private let generator = UIImpactFeedbackGenerator(style: .medium)
    private var panGR: UIPanGestureRecognizer?

    private let expandedWidth: CGFloat = 77.0
    private let contractedWidth: CGFloat = 60.0

    var tapHandler: ((_ selectedIdx: Int) -> Void)?

    init(title: String,
         buttonImages: [UIImage]) {
        super.init(frame: .zero)

        backgroundColor = .clear
        layer.masksToBounds = false
        clipsToBounds = false

        label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        label.textColor = .white
        addSubview(label)

        backgroundView = UIView()
        backgroundView.layer.cornerRadius = 12.0
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.masksToBounds = true
        addSubview(backgroundView)

        let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        backgroundView.addSubview(visualEffectView)
        visualEffectView.autoPinEdgesToSuperviewEdges()

        for (i, image) in buttonImages.enumerated() {
            let button = ScalingPressButton()
            button.setImage(image, for: .normal)
            button.alpha = (i == selectedIdx) ? 1.0 : 0.0
            button.tag = i
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)

            buttons.append(button)
            backgroundView.addSubview(button)

            button.autoPinEdge(toSuperviewEdge: .leading)
            button.autoPinEdge(toSuperviewEdge: .trailing)
            button.autoSetDimensions(to: CGSize(width: expandedWidth, height: expandedWidth))

            let bottomConstraint = button.autoPinEdge(toSuperviewEdge: .bottom)
            buttonBottomConstraints.append(bottomConstraint)
        }

        backgroundView.autoSetDimension(.width, toSize: expandedWidth)
        backgroundView.autoAlignAxis(toSuperviewAxis: .vertical)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 20.0)
        backgroundView.autoPinEdge(.top, to: .top, of: buttons.last!)
        backgroundView.transform = CGAffineTransform(scaleX: contractedWidth / expandedWidth, y: contractedWidth / expandedWidth)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 94.0)
        label.autoPinEdge(toSuperviewEdge: .bottom)
        label.autoAlignAxis(toSuperviewAxis: .vertical)

        panGR = UIPanGestureRecognizer(target: self, action: #selector(panGestureHandler(_:)))
        addGestureRecognizer(panGR!)
    }

    @objc private func buttonTouchDown(_ button: UIButton) {
        expand()
    }

    @objc private func buttonTapped(_ button: UIButton) {
        if (state == .expanding || state == .contracting) &&
           button.tag == selectedIdx {
            return
        }

        selectedIdx = button.tag
        tapHandler?(button.tag)
        contract()
        generator.impactOccurred()
    }

    @objc func panGestureHandler(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .ended ||
           recognizer.state == .cancelled ||
           recognizer.state == .failed {
            contract()
            return
        }

        let location = recognizer.location(in: backgroundView)

        let closestButton = buttons.min { button1, button2 in
            let distance1 = location.distance(to: button1.center)
            let distance2 = location.distance(to: button2.center)
            return distance1 < distance2
        }

        guard let closestButton = closestButton,
                  closestButton.tag != selectedIdx else {
            return
        }

        selectedIdx = closestButton.tag
        tapHandler?(closestButton.tag)
        generator.impactOccurred()
        updateButtonSelection()
    }

    func selectIdx(_ idx: Int) {
        guard idx != selectedIdx else { return }
        
        selectedIdx = idx
        
        for button in buttons {
            button.alpha = (button.tag == selectedIdx) ? 1.0 : 0.0
        }
    }

    func expand() {
        guard state == .contracted || state == .contracting else {
            return
        }

        state = .expanding

        for (i, constraint) in buttonBottomConstraints.enumerated() {
            constraint.constant = -0.8 * expandedWidth * CGFloat(i)
        }

        UIView.animate(withDuration: 0.45,
                       delay: 0.0,
                       usingSpringWithDamping: 0.92,
                       initialSpringVelocity: 1.0,
                       options: [.curveEaseIn, .allowUserInteraction, .allowAnimatedContent],
                       animations: {
            self.layoutIfNeeded()
            self.backgroundView.transform = .identity
        }, completion: { _ in
            self.state = .expanded
        })

        updateButtonSelection()
    }

    func updateButtonSelection() {
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: [.allowUserInteraction, .curveEaseOut],
                       animations: {
            for button in self.buttons {
                button.alpha = (button.tag == self.selectedIdx) ? 1.0 : 0.5
            }
        }, completion: nil)
    }

    func contract() {
        guard state == .expanded || state == .expanding else {
            return
        }

        state = .contracting

        for constraint in buttonBottomConstraints {
            constraint.constant = 0
        }

        let scale = contractedWidth / expandedWidth

        UIView.animate(withDuration: 0.45,
                       delay: 0.0,
                       usingSpringWithDamping: 0.92,
                       initialSpringVelocity: 1,
                       options: [.curveEaseIn, .allowUserInteraction],
                       animations: {
            self.layoutIfNeeded()
            self.backgroundView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }, completion: { _ in
            self.state = .contracted
        })

        UIView.animate(withDuration: 0.17) {
            for button in self.buttons {
                button.alpha = (button.tag == self.selectedIdx) ? 1.0 : 0.0
            }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

private enum VerticalPickerState {
    case expanding
    case expanded
    case contracting
    case contracted
}
This vertical picker is used to change the text alignment when designing a share image. The interaction design is really detailed here – you can swipe your finger up immediately after touching down on the screen and the control will engage and let you quickly swipe between options.

This is a great example of where UIKit really shines for tricky interaction design. This would be much more of a headache to perfectly replicate in SwiftUI, which doesn't feature nearly as granular touch event handling.

Share Asset Generation
View on GitHub
Copy
import Foundation
import UIKit

class CanvasShareImageGenerator {

    static let backgroundRouteAlpha: CGFloat = 0.1
    static let rescale: CGFloat = 4

    static func generateShareImages(canvas: LayoutCanvas,
                                    design: ActivityDesign,
                                    cancel: @escaping (() -> Bool),
                                    progress: @escaping ((Float) -> Void),
                                    completion: @escaping ((_ images: ShareImages) -> Void)) {
        makeBaseImage(canvas: canvas) { (p) in
            progress(p * 0.5)
        } completion: { (baseImageInstaStory, baseImageInstaPost, baseImageTwitter) in
            if cancel() { return }

            let layoutIsFullscreen = design.cutoutShape == .fullScreen

            let scrollViewFrame = canvas.cutoutShapeView.photoFrame
            let zoomScale = CGFloat(design.photoZoom)
            let contentOffset = design.photoOffset
            var imageViewFrame = canvas.cutoutShapeView.photoFrame.insetBy(dx: -0.5 * scrollViewFrame.width * (zoomScale - 1.0),
                                                                           dy: -0.5 * scrollViewFrame.height * (zoomScale - 1.0))
            imageViewFrame.origin.x = -1 * contentOffset.x
            imageViewFrame.origin.y = -1 * contentOffset.y

            let userImage = canvas.mediaType != .none ? canvas.cutoutShapeView.image : nil
            let userImageFrame = CGSize.aspectFit(aspectRatio: userImage?.size ?? .zero,
                                                  inRect: imageViewFrame)
            let userImageFrameMultiplier = CGRect(x: userImageFrame.origin.x / canvas.cutoutShapeView.photoFrame.width,
                                                  y: userImageFrame.origin.y / canvas.cutoutShapeView.photoFrame.height,
                                                  width: userImageFrame.width / canvas.cutoutShapeView.photoFrame.width,
                                                  height: userImageFrame.height / canvas.cutoutShapeView.photoFrame.height)



            progress(0.6)
            let opaque = (canvas.mediaType != .video)
            let instagramStory = makeImage(withAspectRatio: 9/16,
                                           palette: design.palette,
                                           baseImage: baseImageInstaStory,
                                           padTop: true,
                                           opaque: opaque,
                                           userImage: userImage,
                                           userImageFrameMultiplier: userImageFrameMultiplier,
                                           layoutIsFullscreen: layoutIsFullscreen)
            if cancel() { return }

            progress(0.75)
            let instagramFeed = makeImage(withAspectRatio: 1,
                                          palette: design.palette,
                                          baseImage: baseImageInstaPost,
                                          padTop: false,
                                          opaque: opaque,
                                          userImage: userImage,
                                          userImageFrameMultiplier: userImageFrameMultiplier,
                                          layoutIsFullscreen: layoutIsFullscreen)
            if cancel() { return }

            progress(0.9)
            let twitter = makeImage(withAspectRatio: 3 / 4,
                                    palette: design.palette,
                                    baseImage: baseImageTwitter,
                                    padTop: false,
                                    opaque: opaque,
                                    userImage: userImage,
                                    userImageFrameMultiplier: userImageFrameMultiplier,
                                    layoutIsFullscreen: layoutIsFullscreen)
            if cancel() { return }

            progress(1)
            let images = ShareImages(base: baseImageInstaStory,
                                     instagramStory: instagramStory,
                                     instagramFeed: instagramFeed,
                                     twitter: twitter)

            DispatchQueue.main.async {
                completion(images)
            }
        }
    }

    static func renderInstaStoryBaseImage(_ canvas: LayoutCanvas, include3DRoute: Bool = false, completion: @escaping ((UIImage) -> Void)) {
        if NSUbiquitousKeyValueStore.default.shouldShowAnyDistanceBranding {
            canvas.watermark.isHidden = false
        }
        
        if canvas.mediaType == .none {
            canvas.cutoutShapeView.isHidden = true
        }
        
        canvas.cutoutShapeView.prepareForExport(true)

        // Rescale the canvas
        UIView.scaleView(canvas.view, scaleFactor: rescale)

        let frame = canvas.view.frame
        let layer = canvas.view.layer

        let opaque = (canvas.mediaType != .video)

        func finish(finalImage: UIImage) {
            DispatchQueue.main.async {
                completion(finalImage)
                canvas.watermark.isHidden = true
                canvas.cutoutShapeView.prepareForExport(false)
                canvas.cutoutShapeView.addMediaButtonImage.isHidden = canvas.mediaType == .none
                canvas.cutoutShapeView.isHidden = false
            }
        }

        renderLayer(layer, frame: frame, rescale: rescale, opaque: opaque) { (baseImageInstaStory) in
            if include3DRoute {
                // Include a static image of the 3D route
                UIGraphicsBeginImageContextWithOptions(baseImageInstaStory.size, opaque, 1)
                baseImageInstaStory.draw(at: .zero)

                let routeFrame = canvas.route3DView.convert(canvas.route3DView.frame, to: canvas)
                let scaledRouteFrame = CGRect(x: routeFrame.origin.x * rescale,
                                              y: routeFrame.origin.y * rescale,
                                              width: routeFrame.width * rescale,
                                              height: routeFrame.height * rescale)
                let snapshot = canvas.route3DView.snapshot()
                snapshot.draw(in: scaledRouteFrame)

                let image = UIGraphicsGetImageFromCurrentImageContext()!
                UIGraphicsEndImageContext()

                finish(finalImage: image)
            } else {
                finish(finalImage: baseImageInstaStory)
            }
        }
    }

    static func renderBackgroundAndOverlay(_ canvas: LayoutCanvas, completion: @escaping ((UIImage) -> Void)) {
        // Rescale the canvas 4x
        let rescale: CGFloat = 4
        UIView.scaleView(canvas.view, scaleFactor: rescale)

        let frame = canvas.view.frame
        let layer = canvas.view.layer

        let viewsToHide: [UIView] = [canvas.stackView,
                                     canvas.goalProgressIndicator,
                                     canvas.goalProgressYearLabel,
                                     canvas.goalProgressDistanceLabel,
                                     canvas.locationActivityTypeView]
        let previousViewHiddenStates: [Bool] = viewsToHide.map { $0.isHidden }

        viewsToHide.forEach { view in
            view.isHidden = true
        }

        renderLayer(layer, frame: frame, rescale: rescale, opaque: true) { image in
            DispatchQueue.main.async {
                zip(viewsToHide, previousViewHiddenStates).forEach { view, hidden in
                    view.isHidden = hidden
                }
                completion(image)
            }
        }
    }

    static func renderStats(_ canvas: LayoutCanvas, completion: @escaping ((UIImage) -> Void)) {
        // Rescale the canvas 4x
        let rescale: CGFloat = 4.0
        UIView.scaleView(canvas.view, scaleFactor: rescale)

        let frame = canvas.view.frame
        let layer = canvas.view.layer

        let viewsToHide: [UIView] = [canvas.cutoutShapeView,
                                     canvas.goalProgressIndicator,
                                     canvas.goalProgressYearLabel,
                                     canvas.goalProgressDistanceLabel]
        let previousViewHiddenStates: [Bool] = viewsToHide.map { $0.isHidden }

        viewsToHide.forEach { view in
            view.isHidden = true
        }

        renderLayer(layer, frame: frame, rescale: rescale, opaque: false) { image in
            DispatchQueue.main.async {
                completion(image)
                zip(viewsToHide, previousViewHiddenStates).forEach { view, hidden in
                    view.isHidden = hidden
                }
            }
        }
    }

    /// Renders base images (canvas aspect ratio) for Instagram story, post, and Twitter
    fileprivate static func makeBaseImage(canvas: LayoutCanvas,
                                          progress: @escaping ((Float) -> Void),
                                          completion: @escaping ((_ baseImageInstaStory: UIImage,
                                                                  _ baseImageInstaPost: UIImage,
                                                                  _ baseImageTwitter: UIImage) -> Void)) {
        if NSUbiquitousKeyValueStore.default.shouldShowAnyDistanceBranding {
            canvas.watermark.isHidden = false
        }

        canvas.cutoutShapeView.prepareForExport(true)

        let layoutIsFullscreen = canvas.cutoutShapeView.cutoutShape == .fullScreen
        
        if canvas.mediaType == .none || layoutIsFullscreen {
            // Hide the user image view so we can draw it later & extend
            // the image to the edges for Instagram posts.
            canvas.cutoutShapeView.isHidden = true
        }

        if layoutIsFullscreen {
            canvas.tintView.isHidden = true
        }

        // Rescale the canvas 4x
        let rescale: CGFloat = 4.0
        UIView.scaleView(canvas.view, scaleFactor: rescale)

        let frame = canvas.view.frame
        let layer = canvas.view.layer

        let prevWatermark = canvas.watermark.image
        
        // Render Instagram story base image
        renderLayer(layer, frame: frame, rescale: rescale, opaque: false) { (baseImageInstaStory) in
            progress(0.33)            
            // Render Instagram post base image
            renderLayer(layer, frame: frame, rescale: rescale, opaque: false) { (baseImageInstaPost) in
                progress(0.66)
                
                DispatchQueue.main.async {
                    // Render Twitter post base image
                    renderLayer(layer, frame: frame, rescale: rescale, opaque: false) { (baseImageTwitter) in
                        progress(0.99)
                        DispatchQueue.main.async {
                            canvas.watermark.image = prevWatermark
                            canvas.cutoutShapeView.prepareForExport(false)
                            canvas.cutoutShapeView.addMediaButtonImage.isHidden = canvas.mediaType == .none
                            canvas.cutoutShapeView.isHidden = false
                            canvas.tintView.isHidden = false
                            canvas.watermark.isHidden = true
                        }
                        
                        completion(baseImageInstaStory, baseImageInstaPost, baseImageTwitter)
                    }
                }
            }
        }
    }

    internal static func renderLayer(_ layer: CALayer,
                                    frame: CGRect,
                                    rescale: CGFloat,
                                    opaque: Bool = true,
                                    completion: @escaping ((_ image: UIImage) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bigSize = CGSize(width: frame.size.width * rescale,
                                 height: frame.size.height * rescale)
            UIGraphicsBeginImageContextWithOptions(bigSize, opaque, 1)
            let context = UIGraphicsGetCurrentContext()!
            context.scaleBy(x: rescale, y: rescale)

            layer.render(in: context)

            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            completion(image)
        }
    }

    fileprivate static func makeImage(withAspectRatio aspectRatio: CGFloat,
                                      palette: Palette = .dark,
                                      baseImage: UIImage,
                                      padTop: Bool = false,
                                      opaque: Bool = true,
                                      userImage: UIImage?,
                                      userImageFrameMultiplier: CGRect,
                                      layoutIsFullscreen: Bool) -> UIImage {
        let maxDimension = max(baseImage.size.width, baseImage.size.height)
        let topPadding = padTop ? ((baseImage.size.width * (1 / aspectRatio)) - baseImage.size.height) / 2 : 0
        let size = CGSize(width: (maxDimension + topPadding) * aspectRatio,
                          height: maxDimension + topPadding)
        UIGraphicsBeginImageContextWithOptions(size, opaque, 1)
        let context = UIGraphicsGetCurrentContext()!

        if opaque {
            context.setFillColor(palette.backgroundColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }

        if layoutIsFullscreen {
            if let backgroundUserImage = userImage {
                let xOffset: CGFloat = (size.width - baseImage.size.width) / 2

                let userImageFrame: CGRect = CGRect(x: userImageFrameMultiplier.origin.x * baseImage.size.width + xOffset,
                                                    y: userImageFrameMultiplier.origin.y * baseImage.size.height + topPadding,
                                                    width: userImageFrameMultiplier.size.width * baseImage.size.width,
                                                    height: userImageFrameMultiplier.size.height * baseImage.size.height)

                let aspectFilledUserImageFrame = CGSize.aspectFill(aspectRatio: CGSize(width: backgroundUserImage.size.width,
                                                                                       height: backgroundUserImage.size.height),
                                                                   minimumSize: size)

                if aspectFilledUserImageFrame.size.width > userImageFrame.size.width && aspectFilledUserImageFrame.size.height > userImageFrame.size.height {
                    backgroundUserImage.draw(in: aspectFilledUserImageFrame)
                } else {
                    backgroundUserImage.draw(in: userImageFrame)
                }

                let topGradient = UIImage(named: "layout_top_gradient")
                topGradient?.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.3), blendMode: .normal, alpha: 0.4)

                let bottomGradient = UIImage(named: "layout_gradient")
                bottomGradient?.draw(in: CGRect(x: 0, y: size.height * 0.5, width: size.width, height: size.height * 0.5), blendMode: .normal, alpha: 0.5)

                if !palette.backgroundColor.isReallyDark {
                    palette.backgroundColor.withAlphaComponent(0.3).setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                }
            }
        }

        let baseImageRect = CGRect(x: (size.width / 2) - baseImage.size.width / 2,
                                   y: topPadding + (size.height / 2) - baseImage.size.height / 2,
                                   width: baseImage.size.width,
                                   height: baseImage.size.height)
        baseImage.draw(in: baseImageRect)

        let finalImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return finalImage
    }
}

All of our share assets are generated with CoreGraphics, a powerful native graphics library that's been around for a very long time.

Header With Progressive Blur
View on GitHub
Copy
import SwiftUI
import UIKit

public enum VariableBlurDirection {
    case blurredTopClearBottom
    case blurredBottomClearTop
}


public struct VariableBlurView: UIViewRepresentable {
    public var maxBlurRadius: CGFloat = 2
    public var direction: VariableBlurDirection = .blurredTopClearBottom
    public var startOffset: CGFloat = 0

    public func makeUIView(context: Context) -> VariableBlurUIView {
        VariableBlurUIView(maxBlurRadius: maxBlurRadius, direction: direction, startOffset: startOffset)
    }

    public func updateUIView(_ uiView: VariableBlurUIView, context: Context) {}
}


open class VariableBlurUIView: UIVisualEffectView {
    public init(maxBlurRadius: CGFloat = 20,
                direction: VariableBlurDirection = .blurredTopClearBottom,
                startOffset: CGFloat = 0) {
        super.init(effect: UIBlurEffect(style: .regular))

        // Same but no need for `CAFilter.h`.
        let CAFilter = NSClassFromString("CAFilter")! as! NSObject.Type
        let variableBlur = CAFilter.self.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur").takeUnretainedValue() as! NSObject

        // The blur radius at each pixel depends on the alpha value of the corresponding pixel in the gradient mask.
        // An alpha of 1 results in the max blur radius, while an alpha of 0 is completely unblurred.
        let gradientImage = direction == .blurredTopClearBottom ? UIImage(named: "layout_top_gradient")?.cgImage : UIImage(named: "layout_gradient")?.cgImage

        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(gradientImage, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        // We use a `UIVisualEffectView` here purely to get access to its `CABackdropLayer`,
        // which is able to apply various, real-time CAFilters onto the views underneath.
        let backdropLayer = subviews.first?.layer

        // Replace the standard filters (i.e. `gaussianBlur`, `colorSaturate`, etc.) with only the variableBlur.
        backdropLayer?.filters = [variableBlur]

        // Get rid of the visual effect view's dimming/tint view, so we don't see a hard line.
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }

    override open func layoutSubviews() {
        subviews.first?.layer.frame = self.bounds
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        subviews.first?.layer.filters = nil
    }

    open override func didMoveToWindow() {
        // fixes visible pixelization at unblurred edge (https://github.com/nikstar/VariableBlur/issues/1)
        guard let window, let backdropLayer = subviews.first?.layer else { return }
        backdropLayer.setValue(window.screen.scale, forKey: "scale")
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}
}

fileprivate struct TopGradient: View {
    @Binding var scrollViewOffset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: 80.0)
            Image("gradient_bottom_ease_in_out")
                .resizable(resizingMode: .stretch)
                .scaleEffect(y: -1)
                .frame(width: UIScreen.main.bounds.width, height: 60.0)
                .overlay {
                    VariableBlurView()
                        .offset(y: -10.0)
                }
            Spacer()
        }
        .opacity((1.0 - (scrollViewOffset / 50.0)).clamped(to: 0...1))
        .ignoresSafeArea()
    }
}

fileprivate struct TitleView: View {
    @Binding var scrollViewOffset: CGFloat

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
                .frame(height: 45.0)

            let p = (scrollViewOffset / -80.0)
            HStack {
                Text("Any Distance")
                    .font(Font(UIFont.systemFont(ofSize: 23.0, weight: .bold, width: .expanded)))
                    .foregroundStyle(Color(white: 0.6))
                    .scaleEffect((0.6 + ((1.0 - p) * 0.4)).clamped(to: 0.6...1.0),
                                 anchor: .leading)
                    .offset(y: scrollViewOffset < 0 ? 0 : (0.3 * scrollViewOffset))
                    .offset(y: (-22.0 * p).clamped(to: -22.0...0.0))
                Spacer()
            }
            .overlay {
                HStack {
                    Spacer()
                    Button {
                        //
                    } label: {
                        Image(systemName: "gear")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24.0, height: 24.0)
                            .foregroundStyle(Color.white)
                            .padding()
                            .contentShape(Rectangle())
                            .opacity((1.0 - (scrollViewOffset / -70)).clamped(to: 0...1) * 0.6)
                            .blur(radius: (10 * scrollViewOffset / -70).clamped(to: 0...10))
                    }
                    .offset(x: 16.0)
                    .offset(y: scrollViewOffset < 0 ? 0 : (0.3 * scrollViewOffset))
                }
            }
        }
        .padding(.top, -22.5)
        .padding([.leading, .trailing], 20.0)
    }
}

struct HeaderView: View {
    @Binding var scrollViewOffset: CGFloat

    var body: some View {
        ZStack {
            TopGradient(scrollViewOffset: $scrollViewOffset)
            VStack {
                TitleView(scrollViewOffset: $scrollViewOffset)
                Spacer()
            }
        }
    }
}

struct ReadableScrollView<Content: View>: View {
    struct CGFloatPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat { 0.0 }
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {}
    }

    struct CGSizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize { .zero }
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
    }

    @Binding var offset: CGFloat
    @Binding var contentSize: CGSize
    var presentedInSheet: Bool = false
    var showsIndicators: Bool = true
    var content: Content

    init(offset: Binding<CGFloat>,
         contentSize: Binding<CGSize>? = nil,
         presentedInSheet: Bool = false,
         showsIndicators: Bool = true,
         @ViewBuilder contentBuilder: () -> Content) {
        self._offset = offset
        self._contentSize = contentSize ?? .constant(.zero)
        self.presentedInSheet = presentedInSheet
        self.showsIndicators = showsIndicators
        self.content = contentBuilder()
    }

    var scrollReader: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: CGFloatPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY)
                .preference(key: CGSizePreferenceKey.self,
                            value: geometry.size)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: showsIndicators) {
            VStack {
                content
            }
            .background(scrollReader.ignoresSafeArea())
            .onPreferenceChange(CGFloatPreferenceKey.self) { value in
                self.offset = value - (presentedInSheet ? 10.0 : 0.0)
            }
            .onPreferenceChange(CGSizePreferenceKey.self) { value in
                self.contentSize = value
            }
        }
    }
}

struct HeaderDemoView: View {
    @State var scrollViewOffset: CGFloat = 0.0

	var body: some View {
		ZStack {
            ReadableScrollView(offset: $scrollViewOffset) {
                VStack {
                    ForEach(1..<20) { _ in
                        RoundedRectangle(cornerRadius: 10.0)
                            .foregroundStyle(Color(white: 0.8))
                            .frame(height: 60.0)
                    }
                }
                .padding(.top, 100.0)
                .padding(.horizontal, 20.0)
            }

            HeaderView(scrollViewOffset: $scrollViewOffset)
        }
        .background(Color.black)
	}
}

#Preview {
    HeaderDemoView()
}
We use this style of navigation header throughout the app. It uses the current scroll position to apply transforms to the title view, making it shrink as you scroll down. Underneath, there's a subtle progressive blur layered with a cubic-eased gradient to make the content underneath fade out smoothly.

Custom Refresh Control
View on GitHub
Copy
import SwiftUI

struct RefreshableScrollView<Content: View>: View {
    @Binding var offset: CGFloat
    @Binding var isRefreshing: Bool
    var presentedInSheet: Bool = false
    var content: Content

    @State private var refreshControlVisible: Bool = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let refreshOffset: CGFloat = 150.0

    init(offset: Binding<CGFloat>,
         isRefreshing: Binding<Bool>,
         presentedInSheet: Bool = false,
         @ViewBuilder contentBuilder: () -> Content) {
        self._offset = offset
        self._isRefreshing = isRefreshing
        self.presentedInSheet = presentedInSheet
        self.content = contentBuilder()
    }

    var scrollReader: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: CGFloatPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                content
            }
            .if(!presentedInSheet) { view in
                view
                    .overlay {
                        VStack {
                            ZStack {
                                ProgressView()
                                    .opacity(isRefreshing ? 1.0 : 0.0)
                                    .offset(y: -12.0)
                                Text("PULL TO REFRESH")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                    .opacity((offset / refreshOffset).clamped(to: 0...1) * 0.6)
                                    .opacity(isRefreshing ? 0.0 : 1.0)
                                    .offset(y: -6.0)
                            }
                            .offset(y: -0.9 * offset)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRefreshing)

                            Spacer()
                        }
                    }
            }
            .offset(y: isRefreshing ? 30.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isRefreshing)
            .background(scrollReader.ignoresSafeArea())
            .onPreferenceChange(CGFloatPreferenceKey.self) { value in
                guard let window = UIApplication.shared.windows.first else {
                    self.offset = value
                    return
                }

                self.offset = value - window.safeAreaInsets.top - (presentedInSheet ? 10.0 : 0.0)
                if offset >= refreshOffset && !isRefreshing && !presentedInSheet {
                    isRefreshing = true
                    feedbackGenerator.impactOccurred()
                }
            }
        }
        .introspectScrollView { scrollView in
            scrollView.delaysContentTouches = false
        }
    }
}
I wrote this fun custom refresh control in SwiftUI. It's baked into a reusable scroll view wrapper called RefreshableScrollView.

Onboarding Carousel (2022)
View on GitHub
Copy
import SwiftUI

fileprivate struct GradientAnimation: View {
    @Binding var animate: Bool
    @Binding var pageIdx: Int

    private var firstPageColors: [Color] {
        return [Color(hexadecimal: "#F98425"),
                Color(hexadecimal: "#E82840"),
                Color(hexadecimal: "#4A0D21"),
                Color(hexadecimal: "#B12040"),
                Color(hexadecimal: "#F4523B")]
    }

    private var secondPageColors: [Color] {
        return [Color(hexadecimal: "#B7F6FE"),
                Color(hexadecimal: "#32A0FB"),
                Color(hexadecimal: "#034EE7"),
                Color(hexadecimal: "#0131A1"),
                Color(hexadecimal: "#030C2F")]
    }

    private var thirdPageColors: [Color] {
        return [Color(hexadecimal: "#66E7FF"),
                Color(hexadecimal: "#04CFD5"),
                Color(hexadecimal: "#00A077"),
                Color(hexadecimal: "#00Af8B"),
                Color(hexadecimal: "#02251B")]
    }

    private func rand18(_ idx: Int) -> [Float] {
        let idxf = Float(idx)
        return [sin(idxf * 6.3),
                cos(idxf * 1.3 + 48),
                sin(idxf + 31.2),
                cos(idxf * 44.1),
                sin(idxf * 3333.2),
                cos(idxf + 1.12 * pow(idxf, 3)),
                sin(idxf * 22),
                cos(idxf * 34)]
    }

    func gradient(withColors colors: [Color], seed: Int = 0) -> some View {
        return ZStack {
            let maxXOffset = Float(UIScreen.main.bounds.width) / 2
            let maxYOffset = Float(UIScreen.main.bounds.height) / 2
            ForEach(Array(0...9), id: \.self) { idx in
                let rands = rand18(idx + seed)
                let fill = colors[idx % colors.count]

                Ellipse()
                    .fill(fill)
                    .frame(width: CGFloat(rands[1] + 2) * 250, height: CGFloat(rands[2] + 2) * 250)
                    .blur(radius: 45 * 1 + CGFloat(rands[1] + rands[2]) / 2)
                    .opacity(1)
                    .offset(x: CGFloat(animate ? rands[3] * maxXOffset : rands[4] * maxXOffset),
                            y: CGFloat(animate ? rands[5] * maxYOffset : rands[6] * maxYOffset))
                    .animation(.easeInOut(duration: TimeInterval(rands[7] + 3) * 2.5).repeatForever(autoreverses: true),
                               value: animate)
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height+100)
        .drawingGroup()
    }

    var body: some View {
        ZStack {
            gradient(withColors: firstPageColors, seed: 5)
                .opacity(pageIdx == 0 ? 1 : 0)
                .animation(.easeInOut(duration: 1.5), value: pageIdx)

            gradient(withColors: secondPageColors, seed: 5)
                .opacity(pageIdx == 1 ? 1 : 0)
                .animation(.easeInOut(duration: 1.5), value: pageIdx)

            gradient(withColors: thirdPageColors, seed: 6)
                .opacity(pageIdx == 2 ? 1 : 0)
                .animation(.easeInOut(duration: 1.5), value: pageIdx)

            Image("noise")
                .resizable(resizingMode: .tile)
                .scaleEffect(0.25)
                .ignoresSafeArea()
                .luminanceToAlpha()
                .frame(width: UIScreen.main.bounds.width * 4,
                       height: UIScreen.main.bounds.height * 5)
                .opacity(0.15)
        }
        .onAppear {
            animate = true
        }
    }
}

fileprivate struct InfiniteScroller<Content: View>: View {
    var contentWidth: CGFloat
    var reversed: Bool = true
    var content: (() -> Content)

    @State var xOffset: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                content()
                content()
            }
            .offset(x: xOffset, y: 0)
        }
        .disabled(true)
        .onAppear {
            if reversed {
                xOffset = -1 * contentWidth
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                if reversed {
                    xOffset = 0
                } else {
                    xOffset = -contentWidth
                }
            }
        }
    }
}

fileprivate struct AppIcons: View {
    let iconWidth: CGFloat = 61
    let iconSpacing: CGFloat = 16

    var firstRow: some View {
        HStack(spacing: iconSpacing) {
            Image("icon_fitness")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_strava")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_garmin")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_nrc")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_peloton")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_runkeeper")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_wahoo")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitbod")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_ot")
                .frame(width: iconWidth, height: iconWidth)
            Rectangle()
                .frame(width: 0)
        }
    }

    var secondRow: some View {
        HStack(spacing: iconSpacing) {
            Image("icon_strava")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitbod")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_garmin")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_runkeeper")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_nrc")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_future")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitness")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_peloton")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_wahoo")
                .frame(width: iconWidth, height: iconWidth)
            Rectangle()
                .frame(width: 0)
        }
    }

    var thirdRow: some View {
        HStack(spacing: iconSpacing) {
            Image("icon_future")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_peloton")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitbod")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_garmin")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_nrc")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_runkeeper")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_ot")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitness")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_strava")
                .frame(width: iconWidth, height: iconWidth)
            Rectangle()
                .frame(width: 0)
        }
    }

    var body: some View {
        VStack {
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: true) {
                firstRow
            }
            .frame(height: iconWidth)
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: false) {
                secondRow
            }
            .frame(height: iconWidth)
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: true) {
                thirdRow
            }
            .frame(height: iconWidth)
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: false) {
                firstRow
            }
            .frame(height: iconWidth)
        }
        .mask {
            LinearGradient(colors: [.clear, .black, .black, .black, .black, .black, .clear],
                           startPoint: .leading,
                           endPoint: .trailing)
        }
    }
}

fileprivate var screenshotSize: CGSize {
    let aspect: CGFloat = 2.052
    let verticalSafeArea = (UIApplication.shared.topWindow?.safeAreaInsets.top ?? 0) +
                           (UIApplication.shared.topWindow?.safeAreaInsets.bottom ?? 0)
    let height = (UIScreen.main.bounds.height - verticalSafeArea) * 0.435
    return CGSize(width: height / aspect,
                  height: height)
}

fileprivate struct Carousel: View {
    @Binding var pageIdx: Int
    @Binding var dragging: Bool
    @State var offset: CGFloat = 0
    @State private var startOffset: CGFloat?

    fileprivate struct CarouselItem: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .frame(width: screenshotSize.width, height: screenshotSize.height)
                .foregroundColor(Color.black.opacity(0.5))
        }
    }

    var item: some View {
        GeometryReader { geo in
            CarouselItem()
                .scaleEffect((1 - ((geo.frame(in: .global).minX) / UIScreen.main.bounds.width * 0.3)).clamped(to: 0...1))
                .offset(x: pow(geo.frame(in: .global).minX / UIScreen.main.bounds.width, 2) * -60)
        }
        .frame(width: screenshotSize.width, height: screenshotSize.height)
    }

    func item(forScreen screen: Int) -> some View {
        GeometryReader { geo in
            ZStack {
                switch screen {
                case 1:
                    Image("onboarding-screen-1")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case 2:
                    LoopingVideoView(videoUrl: Bundle.main.url(forResource: "onboarding-screen-2", withExtension: "mp4")!,
                                     videoGravity: .resizeAspectFill)
                    EmptyView()
                case 3:
                    Image("onboarding-screen-3")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case 4:
                    LoopingVideoView(videoUrl: Bundle.main.url(forResource: "onboarding-screen-4", withExtension: "mp4")!,
                                     videoGravity: .resizeAspectFill)
                    EmptyView()
                case 5:
                    Image("onboarding-screen-5")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case 6:
                    Image("onboarding-screen-6")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    EmptyView()
                }
            }
            .frame(width: screenshotSize.width, height: screenshotSize.height)
            .cornerRadius(12, style: .continuous)
            .scaleEffect((1 - ((geo.frame(in: .global).minX) / UIScreen.main.bounds.width * 0.3)).clamped(to: 0...1))
            .offset(x: pow(geo.frame(in: .global).minX / UIScreen.main.bounds.width, 2) * -60)
        }
        .frame(width: screenshotSize.width, height: screenshotSize.height)
    }

    var contentWidth: CGFloat {
        return (screenshotSize.width * 6) + UIScreen.main.bounds.width + (16 * 7)
    }

    var secondPageOffset: CGFloat {
        return (screenshotSize.width * 3) + (16 * 3)
    }

    var thirdPageOffset: CGFloat {
        return (screenshotSize.width * 6) + (16 * 6)
    }

    var body: some View {
        HStack(spacing: 16) {
            item(forScreen: 1)
            item(forScreen: 2)
            item(forScreen: 3)
            item(forScreen: 4)
            item(forScreen: 5)
            item(forScreen: 6)
            AppIcons()
                .frame(width: UIScreen.main.bounds.width)
        }
        .id(0)
        .frame(height: screenshotSize.height)
        .offset(x: (contentWidth / 2) - (UIScreen.main.bounds.width / 2) - offset)
        .onChange(of: pageIdx) { newValue in
            print(newValue)
            withAnimation(smoothCurveAnimation) {
                switch newValue {
                case 0:
                    offset = 0
                case 1:
                    offset = secondPageOffset
                default:
                    offset = thirdPageOffset
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if startOffset == nil {
                        startOffset = offset
                    }
                    let gestureOffset = gesture.location.x - gesture.startLocation.x
                    offset = startOffset! - gestureOffset
                    dragging = true
                }
                .onEnded { gesture in
                    let finalOffset = startOffset! - (gesture.predictedEndLocation.x - gesture.startLocation.x)
                    let closestOffset = [0, secondPageOffset, thirdPageOffset].min(by: { abs($0 - finalOffset) < abs($1 - finalOffset) })!
                    let closestPage = [0, secondPageOffset, thirdPageOffset].firstIndex(of: closestOffset)!.clamped(to: (pageIdx-1)...(pageIdx+1))
                    let clampedClosestOffset = [0, secondPageOffset, thirdPageOffset][closestPage]
                    pageIdx = closestPage
                    withAnimation(.interactiveSpring(response: 0.6)) {
                        offset = clampedClosestOffset
                    }
                    startOffset = nil
                    dragging = false
                }
        )
    }
}

struct Onboarding2022View: View {
    @State private var animate: Bool = false
    @State private var pageIdx: Int = 0
    @State private var pageTimer: Timer?
    @State private var dragging: Bool = false

    private func setupPageTimer() {
        pageTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            pageIdx = (pageIdx + 1) % 3
        }
    }

    private func signInAction() {}

    private func getStartedAction() {
        let syncVC = UIStoryboard(name: "Onboarding", bundle: nil).instantiateViewController(withIdentifier: "sync")
        UIApplication.shared.topViewController?.present(syncVC, animated: true)
    }

    private func headlineText(forPageIdx pageIdx: Int) -> AttributedString {
        let string = ["**Privacy-driven**\nActivity Tracking and\n**safety-first** sharing.",
                      "Track your goals &\nearn **motivational\nCollectibles.**",
                      "**Easily Connect** the\nactive life apps\n**you already use.**"][pageIdx % 3]
        return try! AttributedString(markdown: string,
                                     options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    private func subtitleText(forPageIdx pageIdx: Int) -> String {
        return ["No leaderboards. No comparison.\nAny Distance Counts.",
                "Celebrate your active lifestyle.",
                "Connect with Garmin, Wahoo,\nand Apple Health."][pageIdx % 3]
    }

    struct BlurModifier: ViewModifier {
        var radius: CGFloat

        func body(content: Content) -> some View {
            content.blur(radius: radius)
        }
    }

    var body: some View {
        ZStack {
            GradientAnimation(animate: $animate, pageIdx: $pageIdx)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading) {
                HStack {
                    Image("wordmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 130)
                    Spacer()
                    Button(action: signInAction) {
                        Text("Sign In")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                HStack {
                    if #available(iOS 16.0, *) {
                        Text(headlineText(forPageIdx: pageIdx))
                            .font(.system(size: UIScreen.main.bounds.height * 0.041, weight: .regular))
                            .lineSpacing(0)
                            .tracking(-1)
                            .padding(.bottom, 1)
                    } else {
                        Text(headlineText(forPageIdx: pageIdx))
                            .font(.system(size: UIScreen.main.bounds.height * 0.041, weight: .semibold))
                            .lineSpacing(0)
                    }
                }
                .transition(.modifier(active: BlurModifier(radius: 8),
                                      identity: BlurModifier(radius: 0))
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.9))
                            .animation(smoothCurveAnimation))
                .id(pageIdx)

                Text(subtitleText(forPageIdx: pageIdx))
                    .font(.system(size: (UIScreen.main.bounds.height * 0.02).clamped(to: 0...14),
                                  weight: .semibold,
                                  design: .monospaced))
                    .foregroundColor(.white)
                    .opacity(0.7)
                    .transition(.modifier(active: BlurModifier(radius: 8),
                                          identity: BlurModifier(radius: 0))
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.9))
                        .animation(smoothCurveAnimation))
                    .id(pageIdx)

                Carousel(pageIdx: $pageIdx, dragging: $dragging)
                    .frame(width: UIScreen.main.bounds.width - 40)
                    .padding([.top, .bottom], 16)

                Button(action: getStartedAction) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                        Text("Get Started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .frame(height: 55)
                }

                Text("No sign-up required unless you want to\nstore your goals and Collectibles.")
                    .font(.system(size: 14, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .opacity(0.7)
            }
            .padding([.leading, .trailing], 20)
        }
        .onAppear {
            animate = true
            setupPageTimer()
        }
        .onChange(of: dragging) { newValue in
            if newValue == true {
                pageTimer?.invalidate()
            } else {
                setupPageTimer()
            }
        }
    }
}

struct Onboarding2022View_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding2022View()
    }
}
This splash page from 2022 was my favorite one.

The gradient effect in the background was done in SwiftUI using a similar technique to Access Code Field. It was eventually rewritten in Metal to be more performant.

Getting the scroll behavior right took a lot of trial and error. The current scroll position is used to apply various transforms to the container views. The 3 sections auto-scroll, but you can also scroll between them manually.

I'm really pleased with how the text transition came out. It's a custom SwiftUI ViewModifier that was meant to mimic the text transitions in Dynamic Island. We ended up using this text transition effect extensively throughout the rest of the app.

Scrubbable Line Graph
View on GitHub
Copy
import SwiftUI
import SwiftUIX

fileprivate struct ProgressLine: Shape {
    var data: [Float]
    var dataMaxValue: Float
    var totalCount: Int

    func path(in rect: CGRect) -> Path {
        guard !data.isEmpty else {
            return Path()
        }
        
        let max = dataMaxValue * 1.1
        var path = Path()

        let points = data.enumerated().map { (i, datum) in
            let x = (rect.width * CGFloat(i) / CGFloat(totalCount-1)).clamped(to: 4.0...(rect.width-4.0))
            let y = (rect.height - (rect.height * CGFloat(datum / max))).clamped(to: 4.0...(rect.height-4.0))
            return CGPoint(x: x, y: y)
        }

        path.move(to: points[0])
        var p1 = points[0]
        var p2 = CGPoint.zero

        for i in 0..<(points.count-1) {
            p2 = points[i+1]
            let midPoint = CGPoint(x: (p1.x + p2.x)/2.0, y: (p1.y + p2.y)/2.0)
            path.addQuadCurve(to: midPoint, control: p1)
            p1 = p2
        }

        path.addLine(to: points.last!)

        return path
    }
}

struct ProgressLineGraph: View {
    var data: [Float]
    var dataMaxValue: Float
    var fullDataCount: Int
    var strokeStyle: StrokeStyle
    var color: Color
    var showVerticalLine: Bool
    var showDot: Bool
    var animateProgress: Bool
    @Binding var dataSwipeIdx: Int

    @State private var lineAnimationProgress: Float = 1.0
    @State private var dotOpacity: Double = 0.0

    var body: some View {
        ZStack {
            color
                .maxWidth(.infinity)
                .mask {
                    ProgressLine(data: data, dataMaxValue: dataMaxValue, totalCount: fullDataCount)
                        .stroke(style: strokeStyle)
                }
                .mask {
                    GeometryReader { geo in
                        HStack(spacing: 0.0) {
                            let width = (geo.size.width * (CGFloat(data.count-1) / CGFloat(fullDataCount-1)) * CGFloat(lineAnimationProgress)).clamped(to: 4.0...(geo.size.width-4.0))
                            Rectangle()
                                .frame(width: width)
                            Spacer()
                                .frame(minWidth: 0.0)
                        }
                    }
                }
                .if(showVerticalLine && data.count > 1) { view in
                    view
                        .background {
                            GeometryReader { geo in
                                HStack(spacing: 0.0) {
                                    let width: CGFloat = {
                                        if dataSwipeIdx != -1 {
                                            return (geo.size.width * (CGFloat(dataSwipeIdx) / CGFloat(fullDataCount-1))).clamped(to: 4.0...(geo.size.width-4.0))
                                        } else {
                                            return (geo.size.width * (CGFloat(data.count-1) / CGFloat(fullDataCount-1)) * CGFloat(lineAnimationProgress)).clamped(to: 4.0...(geo.size.width-4.0))
                                        }
                                    }()

                                    Spacer()
                                        .frame(width: width)
                                    ZStack {
                                        Color.black
                                        Rectangle()
                                            .foregroundColor(color)
                                            .opacity(0.4)
                                    }
                                    .frame(width: 2.0)
                                    .cornerRadius(2.0)
                                    Spacer()
                                        .frame(minWidth: 0.0)
                                }
                                .offset(x: -1.5)
                                .animation(dataSwipeIdx == -1 ? .timingCurve(0.42, 0.27, 0.34, 0.96, duration: 0.2) : .none,
                                           value: dataSwipeIdx)
                            }
                        }
                }
                .if(showDot) { view in
                    view
                        .overlay {
                            GeometryReader { geo in
                                let x = (geo.size.width * CGFloat(data.count-1) / CGFloat(fullDataCount-1)).clamped(to: 4.0...(geo.size.width-4.0))
                                let y = (geo.size.height - (geo.size.height * CGFloat((data.last ?? 0.0) / (dataMaxValue * 1.1)))).clamped(to: 4.0...(geo.size.height-4.0))

                                ZStack {
                                    TimelineView(.animation) { timeline in
                                        Canvas { context, size in
                                            let duration: CGFloat = 1.4
                                            let time = timeline.date.timeIntervalSince1970.truncatingRemainder(dividingBy: duration) / duration
                                            let diameter = 12.0 + (20.0 * time)
                                            let rect = CGRect(x: 21.0 - (diameter / 2),
                                                              y: 21.0 - (diameter / 2),
                                                              width: diameter,
                                                              height: diameter)
                                            let shape = Circle().path(in: rect)
                                            let color = color.opacity(1.0 - time)
                                            context.fill(shape,
                                                         with: .color(color))
                                        }
                                    }
                                    .frame(width: 42.0, height: 42.0)

                                    Circle()
                                        .fill(color)
                                        .width(12.0)
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 0)
                                }
                                .scaleEffect(x: dotOpacity, y: dotOpacity)
                                .position(x: x, y: y)
                                .opacity(dotOpacity)
                            }
                        }
                }
                .opacity(Double(lineAnimationProgress))
                .onAppear {
                    if !animateProgress {
                        lineAnimationProgress = 1.0
                        dotOpacity = 1.0
                        return
                    }

                    lineAnimationProgress = 0.0
                    let duration = (0.3 + ((CGFloat(data.count-1) / CGFloat(fullDataCount-1)) * 0.9)).clamped(to: 0.0...0.9)
                    withAnimation(.timingCurve(0.42, 0.27, 0.34, 0.96, duration: duration)) {
                        lineAnimationProgress = 1.0
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + duration - 0.13) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.dotOpacity = 1.0
                        }
                    }
                }
        }
    }
}

struct ProgressLineGraphXLabels: View {
    var labelStrings: [(idx: Int, string: String)] = []
    var fullDataCount: Int
    var lrPadding: CGFloat

    var body: some View {
        Color.clear
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach(labelStrings, id: \.idx) { (idx, string) in
                            let xPos: CGFloat = (lrPadding + ((geo.size.width - (lrPadding * 2.0)) * CGFloat(idx) / CGFloat(fullDataCount - 1))).clamped(to: (lrPadding+4.0)...(geo.size.width-lrPadding-4.0))
                            HStack {
                                Text(string)
                                    .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .opacity(0.6)
                                    .frame(width: 50.0)
                                    .offset(x: xPos - 25.0)
                                Spacer()
                            }
                        }
                    }
                }
            }
    }
}

struct ProgressLineGraphSwipeOverlay: View {
    var field: PartialKeyPath<Activity>
    var data: [Float]
    var prevPeriodData: [Float]
    var dataFormat: (Float) -> String
    var startDate: Date
    var endDate: Date
    var prevPeriodStartDate: Date
    var prevPeriodEndDate: Date
    var alternatePrevPeriodLabel: String?
    @Binding var dataSwipeIdx: Int
    @Binding var showingOverlay: Bool

    @State private var dragLocation: CGPoint = .zero
    @State private var touchingDown: Bool = false
    @State private var longPressTimer: Timer?

    private let longPressDuration: TimeInterval = 0.1
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    var percentChangeLabel: some View {
        ZStack {
            let percent = ((data[dataSwipeIdx.clamped(to: 0...(data.count-1))] / (prevPeriodData[dataSwipeIdx.clamped(to: 0...(prevPeriodData.count-1))])
                .clamped(to: 0.01...Float.greatestFiniteMagnitude)) - 1.0)
                .clamped(to: -10.0...100.0)

            let glyphName: SFSymbolName = {
                switch abs(percent) {
                case 0.0:
                    return .minusCircleFill
                default:
                    return percent > 0.0 ? .arrowUpRightCircleFill : .arrowDownRightCircleFill
                }
            }()

            let percentString: String = {
                switch abs(percent) {
                case 100.0:
                    return "∞"
                case 0.0:
                    return "0"
                default:
                    return String(Int((abs(percent) * 100).rounded()))
                }
            }()

            let color = ActivityProgressGraphModel.color(for: percent, field: field)

            HStack(spacing: 3.0) {
                Image(systemName: glyphName)
                    .font(.system(size: 12.0, weight: .medium))
                HStack(spacing: 0.0) {
                    if percentString == "∞" {
                        Text(percentString)
                            .font(.system(size: 12.0, weight: .medium))
                    } else {
                        Text(percentString)
                            .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                    }
                    Text("%")
                        .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                }
            }
            .foregroundColor(color)
        }
    }

    var body: some View {
        Color.clear
            .overlay {
                GeometryReader { geo in
                    VStack {
                        Spacer()

                        if showingOverlay {
                            let overlayWidth: CGFloat = dataSwipeIdx >= data.count ? 110.0 : 155.0
                            let xOffset = (CGFloat(dataSwipeIdx) * (geo.size.width / CGFloat(max(data.count, prevPeriodData.count) - 1)) - (overlayWidth / 2.0))
                                .clamped(to: 0...(geo.size.width - overlayWidth))
                            HStack(spacing: 0.0) {
                                VStack(alignment: .leading, spacing: 8.0) {
                                    if dataSwipeIdx < data.count {
                                        VStack(alignment: .leading, spacing: 1.0) {
                                            HStack {
                                                Text(dataFormat(data[dataSwipeIdx.clamped(to: 0...(data.count-1))]))
                                                    .font(.system(size: 13.0, weight: .medium, design: .monospaced))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.5)
                                                Spacer()
                                                percentChangeLabel
                                            }
                                            Text(Calendar.current.date(byAdding: .day, value: dataSwipeIdx, to: startDate)!.formatted(withFormat: "MMM d YYYY"))
                                                .font(.system(size: 10.0, design: .monospaced))
                                                .opacity(0.5)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 1.0) {
                                        let idx = dataSwipeIdx.clamped(to: 0...(prevPeriodData.count-1))
                                        Text(dataFormat(prevPeriodData[idx]))
                                            .font(.system(size: 13.0, weight: .medium, design: .monospaced))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                        if let alternatePrevPeriodLabel = alternatePrevPeriodLabel {
                                            Text(alternatePrevPeriodLabel)
                                                .font(.system(size: 10.0, design: .monospaced))
                                                .opacity(0.5)
                                        } else {
                                            Text(Calendar.current.date(byAdding: .day, value: idx, to: prevPeriodStartDate)!.formatted(withFormat: "MMM d YYYY"))
                                                .font(.system(size: 10.0, design: .monospaced))
                                                .opacity(0.5)
                                        }
                                    }
                                }

                                if dataSwipeIdx >= data.count {
                                    Spacer()
                                }
                            }
                            .padding(8.0)
                            .frame(width: overlayWidth)
                            .background {
                                DarkBlurView()
                                    .cornerRadius(11.0)
                                    .brightness(0.1)
                            }
                            .modifier(BlurOpacityTransition(speed: 2.5,
                                                            anchor: UnitPoint(x: (xOffset + (overlayWidth / 2.0)) / overlayWidth, y: -2.5)))
                            .offset(x: xOffset,
                                    y: (-1.0 * geo.size.height) - 8.0)
                        }
                    }
                }
            }
            .overlay {
                TouchEventView { location, view in
                    guard let location = location else {
                        return
                    }

                    touchingDown = true
                    longPressTimer?.invalidate()

                    longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration,
                                                          repeats: false) { _ in
                        guard touchingDown else {
                            return
                        }

                        longPressTimer?.invalidate()
                        longPressTimer = nil
                        view.findContainingScrollView()?.isScrollEnabled = false

                        dataSwipeIdx = Int(location.x / (view.bounds.width / CGFloat(max(data.count, prevPeriodData.count))))
                            .clamped(to: 0...max(prevPeriodData.count-1, data.count-1))

                        showingOverlay = true
                        dragLocation = location
                    }
                } touchMoved: { location, view in
                    guard let location = location, showingOverlay else {
                        return
                    }

                    let prevIdx = dataSwipeIdx
                    dataSwipeIdx = Int(location.x / (view.bounds.width / CGFloat(prevPeriodData.count)))
                        .clamped(to: 0...max(prevPeriodData.count-1, data.count-1))

                    if dataSwipeIdx != prevIdx {
                        feedbackGenerator.impactOccurred()
                    }
                    dragLocation = location
                } touchCancelled: { location, view in
                    showingOverlay = false
                    view.findContainingScrollView()?.isScrollEnabled = true
                    touchingDown = false
                    dataSwipeIdx = -1
                } touchEnded: { location, view in
                    showingOverlay = false
                    view.findContainingScrollView()?.isScrollEnabled = true
                    touchingDown = false
                    dataSwipeIdx = -1
                }
            }
    }
}
We built this screen before the release of SwiftUI graphs, so it's all custom. The graph supports scrubbing so you can dig into every data point. There are also some fun animations when the data changes.

Made With Soul In Atlanta
View on GitHub
Copy
import UIKit

final class FlickeringImageView: UIImageView {

    // MARK: - Variables

    private var isLowered: Bool = false
    private var flickerCount: Int = 0

    // MARK: - Constants

    private let NUM_FLICKERS: Int = 8

    // MARK: - Setup

    override func awakeFromNib() {
        super.awakeFromNib()
        prepareForAnimation()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        startAnimation()
    }

    func prepareForAnimation() {
        alpha = 0.0
    }

    func startAnimation() {
        self.startGlowing()
        self.continueFlickering()
    }

    func startFloating() {
        let yTranslation: CGFloat = isLowered ? -7 : 7
        isLowered = !isLowered
        UIView.animate(withDuration: 2.0, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform(translationX: 0.0, y: yTranslation)
        }, completion: { [weak self] (finished) in
            if finished {
                self?.startFloating()
            }
        })
    }

    func flicker() {
        let newAlpha: CGFloat = (alpha < 1.0) ? 1.0 : 0.2
        alpha = newAlpha
        flickerCount += 1

        if alpha == 1.0 && flickerCount >= NUM_FLICKERS {
            continueFlickering()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startGlowing()
            }
        } else {
            let delay = TimeInterval.random(in: 0.05...0.07) - (0.03 * TimeInterval(flickerCount) / TimeInterval(NUM_FLICKERS))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flicker()
            }
        }
    }

    func continueFlickering() {
        let newAlpha: CGFloat = (alpha < 1.0) ? 1.0 : 0.2
        alpha = newAlpha

        var delay: TimeInterval {
            if alpha < 1.0 {
                return TimeInterval.random(in: 0.01...0.03)
            }

            return TimeInterval.random(in: 0.03...0.4)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.continueFlickering()
        }
    }

    func startGlowing(delay: TimeInterval = 0.0) {
        let duration = TimeInterval.random(in: 0.4...0.8)
        let newAlpha: CGFloat = (alpha < 1.0) ? 1.0 : 0.8
        UIView.animate(withDuration: duration, delay: delay, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
            self.alpha = newAlpha
        }) { [weak self] (finished) in
            if finished {
                self?.startGlowing()
            }
        }
    }
}
I made this flickering image component to mimic the look of neon. The graphic is a copy of a real neon sign that hung outside Switchyards in downtown Atlanta, where we had an office.

Thank you from Spotted in Prod
SIP: It's an honor that our site gets to become home to this piece of iOS history. We've always considered Any Distance a blend of software and art, and there is a reason we highlight it so often. A huge thank you to Dan for capturing and sharing these snippets in a way that only he could.

Back to Top · SIP Home

3D Routes
3-2-1 Go Animation
Goal Picker
3D Medals
3D Sneakers
Gradient Animation (Metal)
Tap & Hold To Stop Animation
Access Code Field
Custom MapKit Overlay Renderer
Fake UIAlertView
Health Connect Animation (2021)
Nice Confetti
Recent Photo Picker
Vertical Picker
Share Asset Generation
Header With Progressive Blur
Custom Refresh Control
Onboarding Carousel (2022)
Scrubbable Line Graph
Made With Soul In Atlanta
any-distance-goes-open-source/1
any-distance-goes-open-source/2
any-distance-goes-open-source/3
any-distance-goes-open-source/4
any-distance-goes-open-source/5
any-distance-goes-open-source/6
any-distance-goes-open-source/7
any-distance-goes-open-source/8
any-distance-goes-open-source/9
any-distance-goes-open-source/10
any-distance-goes-open-source/11
any-distance-goes-open-source/12
any-distance-goes-open-source/13
any-distance-goes-open-source/14
any-distance-goes-open-source/15
any-distance-goes-open-source/16
any-distance-goes-open-source/17
any-distance-goes-open-source/18
any-distance-goes-open-source/19
any-distance-goes-open-source/20
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
