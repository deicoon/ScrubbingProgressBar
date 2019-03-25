//
//  StreamingProgressBar.swift
//
//  Created by Kyle Zaragoza on 9/16/15.
//  Portions Copyright © 2015 Kyle Zaragoza. All rights reserved.
//  Portions from the `ScrubberBar` library, Copyright © 2015 Squareheads. MIT licensed.
//  Portions from the `JGDetailScrubber` library, Copyright © 2013 Jonas Gessner. All rights reserved.
//  Portions from the `OBSlider(-swift)` library, Copyright © 2011 Ole Begemann, Copyright © 2014 Nicolas Gomollon All rights reserved.
//  Portions Copyright © 2019 Perceval Faramaz.
//

import UIKit

@objc public protocol StreamingProgressBarDelegate {
    @objc optional func streamingBar(_ bar: StreamingProgressBar, didScrubToProgress: CGFloat)
    @objc optional func streamingBar(_ bar: StreamingProgressBar, didChangeScrubbingSpeed: CGFloat)
    
    @objc optional func streamingBarDidBeginScrubbing(_ bar: StreamingProgressBar)
    @objc optional func streamingBarDidEndScrubbing(_ bar: StreamingProgressBar)
}

@IBDesignable open class StreamingProgressBar: UIControl {
    
    @IBOutlet public weak var delegate: StreamingProgressBarDelegate?
    
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
            secondaryProgress = secondaryProgress.clamped(to: minimumValue...maximumValue)
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
            progress = progress.clamped(to: minimumValue...maximumValue)
            layout(progressBarLayer, forProgress: progress)
            CATransaction.commit()
        }
    }
    
    @IBInspectable open var minimumValue: CGFloat = 0
    @IBInspectable open var maximumValue: CGFloat = 1
    @IBInspectable open var isContinuous: Bool = true
    
    @IBInspectable open var draggerRadius: CGFloat = 10 {
        didSet {
            let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: draggerRadius, height: draggerRadius))
            draggerLayer.path = path.cgPath
            layoutDragger(forProgress: progress)
        }
    }
    
    @IBInspectable open var scrubbingEnabled: Bool = true
    @IBInspectable open var detailScrubbingEnabled: Bool = false
    open var scrubbingSpeed: CGFloat = 1
    
    open var scrubbingSpeeds: [CGFloat: CGFloat] = [0  :   1,
                                                    50 : 0.5,
                                                    100:0.25,
                                                    150: 0.1] {
        didSet {
            scrubbingPositions = scrubbingSpeeds.keys.sorted(by: { $0 > $1 })
        }
    }
    fileprivate var scrubbingPositions = [CGFloat]()
    fileprivate var thumbRect = CGRect.zero
    
    fileprivate var isDragging: Bool = false
    fileprivate var firstTouchPoint: CGPoint = .zero
    fileprivate var previousY: CGFloat = 0
    fileprivate var realPositionValue: CGFloat = 0
    
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
        let progress = progress.unitScaled(from: minimumValue...maximumValue)
        
        let layerFrame = CGRect(
            origin: CGPoint.zero,
            size: CGSize(width: self.bounds.width * progress, height: self.bounds.height))
        
        animateLayer(layer, toFrame: layerFrame)
        
        if (layer == progressBarLayer) {
            layoutDragger(forProgress: progress)
        }
    }
    
    fileprivate func layoutDragger(forProgress progress: CGFloat) {
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
        
        let speeds = self.scrubbingSpeeds
        self.scrubbingSpeeds = speeds //to trigger didSet and rebuild positions array
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
    
    func positionFromProgress(progress: CGFloat) -> CGFloat {
        return (CGFloat(bounds.width) * progress) - self.bounds.width
    }
    
    func progressFromPosition(position: CGFloat) -> CGFloat {
        return (position / CGFloat(bounds.width))
    }
    
    func pointIsInDragger(_ pointInView: CGPoint) -> Bool {
        let draggerRect = draggerLayer.frame
        let draggerThumbDiameter = max(draggerRect.width, 20)
        let allowedRectSize = CGSize(width: draggerThumbDiameter,
                                     height: draggerThumbDiameter)
        let allowedRectOrigin = CGPoint(x: draggerRect.minX - (allowedRectSize.width - draggerRect.width)/2,
                                        y: draggerRect.minY - (allowedRectSize.height - draggerRect.height)/2)
        let allowedRect = CGRect(origin: allowedRectOrigin,
                                 size: allowedRectSize)
        thumbRect = allowedRect
        
        /*let path = UIBezierPath(ovalIn: allowedRect)
         let isInDragger = path.contains(pointInView)*/
        
        let isInDragger = allowedRect.contains(pointInView)
        return isInDragger
    }
    
    func touchIsInDragger(object: AnyObject, touch: UITouch, touchPoint: inout CGPoint) -> Bool {
        if scrubbingEnabled == true {
            let pointInView = touch.location(in: self)
            
            let isInDragger = pointIsInDragger(pointInView)
            
            if isInDragger {
                touchPoint = pointInView
                return true
            }
        }
        return false
    }
    
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return pointIsInDragger(point)
    }
    
    open override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        var posPt : CGPoint = .zero
        if touchIsInDragger(object: self, touch: touch, touchPoint: &posPt) {
            isDragging = true
            firstTouchPoint = posPt
            realPositionValue = progress
            
            delegate?.streamingBarDidBeginScrubbing?(self)
            delegate?.streamingBar?(self, didChangeScrubbingSpeed: scrubbingSpeed)
            return true
        }
        return super.beginTracking(touch, with: event)
    }
    
    fileprivate func scrubbingSpeedAtDelta(_ verticalDelta: CGFloat) -> CGFloat {
        if (verticalDelta >= 0) {
            for position in scrubbingPositions {
                if verticalDelta >= position {
                    return scrubbingSpeeds[position]!
                }
            }
        }
        return 1
    }
    
    open override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if scrubbingEnabled == true, isDragging == true {
            let trackRect = self.bounds
            
            let previousLocation = touch.previousLocation(in: self)
            let currentLocation = touch.location(in: self)
            let trackingOffset = currentLocation.x - previousLocation.x
            
            guard detailScrubbingEnabled else {
                progress += (maximumValue - minimumValue) * (trackingOffset / trackRect.size.width)
                return super.continueTracking(touch, with: event)
            }
            
            // Find the scrubbing speed that corresponds to the touch's vertical offset.
            let verticalOffset = abs(abs(currentLocation.y) - firstTouchPoint.y)
            
            let newScrubbingSpeed = scrubbingSpeedAtDelta(verticalOffset)
            if (newScrubbingSpeed != scrubbingSpeed) {
                delegate?.streamingBar?(self, didChangeScrubbingSpeed: newScrubbingSpeed)
            }
            scrubbingSpeed = newScrubbingSpeed
            
            realPositionValue += (maximumValue - minimumValue) * (trackingOffset / trackRect.size.width)
            
            let valueAdjustment = scrubbingSpeed * (maximumValue - minimumValue) * (trackingOffset / trackRect.size.width)
            var thumbAdjustment: CGFloat = 0
            if (((firstTouchPoint.y < currentLocation.y) && (currentLocation.y < previousLocation.y)) ||
                ((firstTouchPoint.y > currentLocation.y) && (currentLocation.y > previousLocation.y))) {
                // We are getting closer to the slider, go closer to the real location.
                thumbAdjustment = (realPositionValue - progress) / (1.0 + abs(currentLocation.y - firstTouchPoint.y))
            }
            progress += valueAdjustment + thumbAdjustment
            
            if isContinuous {
                sendActions(for: .valueChanged)
            }
            
            delegate?.streamingBar?(self, didScrubToProgress: self.progress)
            
            return true
        }
        return super.continueTracking(touch, with: event)
    }
    
    open override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isDragging = false
        sendActions(for: .valueChanged)
        delegate?.streamingBarDidEndScrubbing?(self)
        super.endTracking(touch, with: event)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension CGFloat {
    func scaled(from start: ClosedRange<CGFloat>, to target: ClosedRange<CGFloat>) -> CGFloat {
        let clamped = self.clamped(to: start)
        return (clamped - start.lowerBound) * (target.upperBound - target.lowerBound) / (start.upperBound - start.lowerBound) // Thales
    }
    func unitScaled(from limits: ClosedRange<CGFloat>) -> CGFloat {
        return self.scaled(from: limits, to: 0...1)
    }
    func unitScaled(to limits: ClosedRange<CGFloat>) -> CGFloat {
        return self.scaled(from: 0...1, to: limits)
    }
}
