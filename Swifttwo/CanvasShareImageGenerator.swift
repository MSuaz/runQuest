// Licensed under the Any Distance Source-Available License
//
//  ShareImageGenerator.swift
//  ADAC
//
//  Created by Daniel Kuntz on 1/2/21.
//

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

