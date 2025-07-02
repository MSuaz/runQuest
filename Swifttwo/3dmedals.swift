// Licensed under the Any Distance Source-Available License
//
//  collectible3DView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 2/8/22.
//

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

        //        debugOptions = [.showBoundingBoxes, .renderAsWireframe, .showWorldOrigin]

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