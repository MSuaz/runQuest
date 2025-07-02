// Licensed under the Any Distance Source-Available License
//
//  RecentPhotoPicker.swift
//  ADAC
//
//  Created by Daniel Kuntz on 6/24/21.
//

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

//    private var label: UILabel?
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
//            self.label?.alpha = 0
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