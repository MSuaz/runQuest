// Licensed under the Any Distance Source-Available License
//
//  SyncAnimationView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 8/29/21.
//

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

    let sourceColors: [UIColor] = [UIColor(hex: "00B0F3"),
                                   UIColor(hex: "00CCDA"),
                                   UIColor(hex: "FF003D"),
                                   UIColor(hex: "464646"),
                                   UIColor(hex: "FF5700"),
                                   UIColor(hex: "CCFF00")]
    let trackColor = UIColor(hex: "2B2B2B")
    let healthDotColor = UIColor(hex: "FFC100")

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