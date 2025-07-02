// Licensed under the Any Distance Source-Available License
//
//  VerticalPicker.swift
//  VerticalPicker
//
//  Created by Daniel Kuntz on 7/28/21.
//

import UIKit
import PureLayout

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