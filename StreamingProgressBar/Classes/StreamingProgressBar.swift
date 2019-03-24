//
//  StreamingProgressBar.swift
//
//  Created by Kyle Zaragoza on 9/16/15.
//  Copyright © 2015 Kyle Zaragoza. All rights reserved.
//

import UIKit

@objc public protocol StreamingProgressBarDelegate {
    @objc optional func streamingBar(bar: StreamingProgressBar, didScrubToProgress: CGFloat)
}

@IBDesignable open class StreamingProgressBar: UIControl {
    
    @IBOutlet public weak var delegate: StreamingProgressBar?
    
    @IBInspectable open var progressBarColor: UIColor = UIColor.white {
        didSet {
            progressBarLayer.backgroundColor = progressBarColor.cgColor
            draggerLayer.fillColor = progressBarColor.cgColor
        }
    }
    
    @IBInspectable open var secondaryProgressBarColor: UIColor = UIColor.clear {
        didSet {
            secondaryProgressBarLayer.backgroundColor = secondaryProgressBarColor.cgColor
        }
    }
    
    @IBInspectable open var secondaryProgress: CGFloat = 0 {
        didSet {
            if secondaryProgress > 1 {
                secondaryProgress = 1
            } else if secondaryProgress < 0 {
                secondaryProgress = 0
            }
            layout(secondaryProgressBarLayer, forProgress: secondaryProgress)
        }
    }

    @IBInspectable open var progress: CGFloat = 0.5 {
        willSet {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        }
        didSet {
            progress = progress.clamped(to: 0...1)
            layout(progressBarLayer, forProgress: progress)
            CATransaction.commit()
        }
    }
    
    @IBInspectable open var draggerRadius: CGFloat = 10 {
        didSet {
            let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: draggerRadius, height: draggerRadius))
            draggerLayer.path = path.cgPath
            layoutDragger()
        }
    }
    
    @IBInspectable open var scrubbingEnabled: Bool = true
    fileprivate var isDragging: Bool = false
    
    fileprivate let progressBarLayer: CALayer = {
        let layer = CALayer()
        return layer
    }()
    
    fileprivate let draggerLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.backgroundColor = UIColor.clear.cgColor
        return layer
    }()
    
    fileprivate let secondaryProgressBarLayer: CALayer = {
        let layer = CALayer()
        return layer
    }()
    
    
    // MARK: - Layout
    
    private func animateLayer(_ layer: CALayer, toFrame frame: CGRect) {
        let animation = CABasicAnimation(keyPath: "frame")
        animation.fromValue = layer.frame
        animation.toValue = frame
        layer.frame = frame
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "frame")
    }
    
    fileprivate func layout(_ layer: CALayer, forProgress progress: CGFloat) {
        let layerFrame = CGRect(
            origin: CGPoint.zero,
            size: CGSize(width: self.bounds.width * progress, height: self.bounds.height))
        
        animateLayer(layer, toFrame: layerFrame)
        
        if (layer == progressBarLayer) {
            layoutDragger()
        }
    }
    
    fileprivate func layoutDragger() {
        let layerFrame = CGRect(
            origin: CGPoint(x: (self.bounds.width * progress - draggerRadius/2),
                            y: (self.bounds.height - draggerRadius)/2),
            size: CGSize(width: draggerRadius, height: draggerRadius))
        
        animateLayer(draggerLayer, toFrame: layerFrame)
    }
    
    // MARK: - Init
    
    private func commonInit() {
        self.layer.addSublayer(secondaryProgressBarLayer)
        self.layer.addSublayer(progressBarLayer)
        self.layer.addSublayer(draggerLayer)
        self.clipsToBounds = false
        self.layer.masksToBounds = false
        layoutProgressBars()
        addTouchHandlers()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    
    // MARK: - Layout
    
    fileprivate func layoutProgressBars() {
        layout(secondaryProgressBarLayer, forProgress: secondaryProgress)
        layout(progressBarLayer,          forProgress: progress)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutProgressBars()
    }
    
    // MARK: - Interaction
    
    fileprivate func addTouchHandlers() {
        addTarget(self, action: .touchStarted, for: .touchDown)
        addTarget(self, action: .touchEnded, for: .touchUpInside)
        addTarget(self, action: .touchMoved, for: .touchDragInside)
    }
    
    func positionFromProgress(progress: CGFloat) -> CGFloat {
        return (CGFloat(bounds.width) * progress) - self.bounds.width
    }
    
    func progressFromPosition(position: CGFloat) -> CGFloat {
        return (position / CGFloat(bounds.width)).clamped(to: 0...1)
    }
    
    func eventIsInDragger(object: AnyObject, event: UIEvent) -> Bool {
        if let touch = event.touches(for: self)?.first, scrubbingEnabled == true {
            let pointInView = touch.location(in: self)
            
            let draggerRect = draggerLayer.frame
            let allowedRectSize = CGSize(width: draggerRect.width + 25,
                                         height: max(self.frame.height, draggerRect.height) + 20)
            let allowedRectOrigin = CGPoint(x: draggerRect.minX - (allowedRectSize.width - draggerRect.width)/2,
                                            y: draggerRect.minY - (allowedRectSize.height - draggerRect.height)/2)
            let allowedRect = CGRect(origin: allowedRectOrigin,
                                     size: allowedRectSize)
            
            /*let path = UIBezierPath(ovalIn: allowedRect)
             let isInDragger = path.contains(pointInView)*/
            
            let isInDragger = allowedRect.contains(pointInView)
            
            if isInDragger {
                return true
            }
        }
        return false
    }
    
    @objc func touchStarted(object: AnyObject, event: UIEvent) {
        if eventIsInDragger(object: object, event: event) {
            isDragging = true
        }
    }
    
    @objc func touchEnded(object: AnyObject, event: UIEvent) {
        if eventIsInDragger(object: object, event: event) {
            isDragging = false
        }
    }
    
    @objc func touchMoved(object: AnyObject, event: UIEvent) {
        if let touch = event.touches(for: self)?.first, scrubbingEnabled == true, isDragging == true {
            let pointInView = touch.location(in: self)
            
            let progress = progressFromPosition(position: pointInView.x)
            self.progress = progress
            delegate?.scrubberBar?(bar: self, didScrubToProgress: self.progress)
        }
    }
}

private extension Selector {
    static let touchStarted = #selector(StreamingProgressBar.touchStarted(object:event:))
    static let touchEnded = #selector(StreamingProgressBar.touchEnded(object:event:))
    static let touchMoved = #selector(StreamingProgressBar.touchMoved(object:event:))
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
