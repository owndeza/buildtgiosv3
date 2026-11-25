import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import AnimationCache
import MultiAnimationRenderer
import TelegramCore
import AccountContext
import SwiftSignalKit
import EmojiTextAttachmentView
import LokiRng
import TextFormat
import PeerInfoPaneNode
import TelegramStringFormatting

public final class PeerInfoGiftsCoverComponent: Component {
    public let context: AccountContext
    public let peerId: EnginePeer.Id
    public let giftsContext: ProfileGiftsContext
    public let hasBackground: Bool
    public let avatarCenter: CGPoint
    public let avatarSize: CGSize
    public let defaultHeight: CGFloat
    public let avatarTransitionFraction: CGFloat
    public let statusBarHeight: CGFloat
    public let topLeftButtonsSize: CGSize
    public let topRightButtonsSize: CGSize
    public let titleWidth: CGFloat
    /// The title's center on a layout with a side strip (iPhone Duo); nil centers on the full width.
    public let titleCenterX: CGFloat?
    /// Keeps the icons off the navigation buttons and out of a side strip (iPhone Duo).
    public let sideInsets: PeerInfoSideInsets
    public let bottomHeight: CGFloat
    public let action: (ProfileGiftsContext.State.StarGift) -> Void
    
    public init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        giftsContext: ProfileGiftsContext,
        hasBackground: Bool,
        avatarCenter: CGPoint,
        avatarSize: CGSize,
        defaultHeight: CGFloat,
        avatarTransitionFraction: CGFloat,
        statusBarHeight: CGFloat,
        topLeftButtonsSize: CGSize,
        topRightButtonsSize: CGSize,
        titleWidth: CGFloat,
        titleCenterX: CGFloat?,
        sideInsets: PeerInfoSideInsets,
        bottomHeight: CGFloat,
        action: @escaping (ProfileGiftsContext.State.StarGift) -> Void
    ) {
        self.context = context
        self.peerId = peerId
        self.giftsContext = giftsContext
        self.hasBackground = hasBackground
        self.avatarCenter = avatarCenter
        self.avatarSize = avatarSize
        self.defaultHeight = defaultHeight
        self.avatarTransitionFraction = avatarTransitionFraction
        self.statusBarHeight = statusBarHeight
        self.topLeftButtonsSize = topLeftButtonsSize
        self.topRightButtonsSize = topRightButtonsSize
        self.titleWidth = titleWidth
        self.titleCenterX = titleCenterX
        self.sideInsets = sideInsets
        self.bottomHeight = bottomHeight
        self.action = action
    }
    
    public static func ==(lhs: PeerInfoGiftsCoverComponent, rhs: PeerInfoGiftsCoverComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.peerId != rhs.peerId {
            return false
        }
        if lhs.hasBackground != rhs.hasBackground {
            return false
        }
        if lhs.avatarCenter != rhs.avatarCenter {
            return false
        }
        if lhs.avatarSize != rhs.avatarSize {
            return false
        }
        if lhs.defaultHeight != rhs.defaultHeight {
            return false
        }
        if lhs.avatarTransitionFraction != rhs.avatarTransitionFraction {
            return false
        }
        if lhs.statusBarHeight != rhs.statusBarHeight {
            return false
        }
        if lhs.topLeftButtonsSize != rhs.topLeftButtonsSize {
            return false
        }
        if lhs.topRightButtonsSize != rhs.topRightButtonsSize {
            return false
        }
        if lhs.titleWidth != rhs.titleWidth {
            return false
        }
        if lhs.titleCenterX != rhs.titleCenterX {
            return false
        }
        if lhs.sideInsets != rhs.sideInsets {
            return false
        }
        if lhs.bottomHeight != rhs.bottomHeight {
            return false
        }
        return true
    }
    
    public final class View: UIView, UIGestureRecognizerDelegate {
        private var currentSize: CGSize?
        private var component: PeerInfoGiftsCoverComponent?
        private var state: EmptyComponentState?
                
        private var giftsDisposable: Disposable?
        private var gifts: [ProfileGiftsContext.State.StarGift] = []
        private var appliedGiftIds: [Int64] = []
        
        private var iconLayers: [AnyHashable: GiftIconLayer] = [:]
        private var iconPositions: [PositionGenerator.Position] = []
        private let seed = UInt(Date().timeIntervalSince1970)
        
        private var isCurrentlyInHierarchy = false
        private weak var touchedLayer: GiftIconLayer?
        
        private var isUpdating = false
        private weak var draggedLayer: GiftIconLayer?
        private var dragOrigin = CGPoint.zero
        private var dragRestPosition = CGPoint.zero

        private func gift(at point: CGPoint) -> GiftIconLayer? {
            return self.iconLayers.values.sorted(by: { $0.zPosition > $1.zPosition }).first { layer in
                let visible = layer.presentation() ?? layer
                guard visible.opacity > 0.1 else { return false }
                let localPoint = visible.convert(point, from: self.layer.presentation() ?? self.layer)
                let radius = max(22.0, visible.bounds.width / 2.0)
                return hypot(localPoint.x - visible.bounds.midX, localPoint.y - visible.bounds.midY) <= radius
            }
        }

        public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            return self.touchedLayer != nil
        }

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let layer = self.gift(at: touch.location(in: self))
            if gestureRecognizer is UIPanGestureRecognizer {
                self.touchedLayer = layer
            }
            return layer != nil
        }

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.view is UIScrollView
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard let layer = self.touchedLayer, layer.superlayer === self.layer else { return }
                self.draggedLayer = layer
                self.dragRestPosition = layer.position
                let visible = layer.presentation() ?? layer
                self.dragOrigin = visible.convert(CGPoint(x: visible.bounds.midX, y: visible.bounds.midY), to: self.layer.presentation() ?? self.layer)
                layer.stopAnimations()
                layer.removeAnimation(forKey: "position")
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.position = self.dragOrigin
                CATransaction.commit()
                layer.zPosition = 10.0
            case .changed:
                guard let layer = self.draggedLayer, let component = self.component else { return }
                let translation = gesture.translation(in: self)
                let radius = layer.bounds.width * 0.6
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.position = CGPoint(
                    x: max(component.sideInsets.stripLeft + radius, min(self.bounds.width - component.sideInsets.stripRight - radius, self.dragOrigin.x + translation.x)),
                    y: max(component.statusBarHeight + radius, min(self.bounds.height - radius, self.dragOrigin.y + translation.y))
                )
                CATransaction.commit()
            case .ended, .cancelled, .failed:
                self.finishDragging()
            default:
                break
            }
        }

        private func finishDragging() {
            guard let layer = self.draggedLayer else { return }
            self.draggedLayer = nil
            self.touchedLayer = nil
            let position = layer.position
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = self.dragRestPosition
            layer.zPosition = 0.0
            CATransaction.commit()
            // Keep the original phase; compensate for its current offset at hand-over.
            let offset = self.isCurrentlyInHierarchy ? layer.startAnimations() : .zero
            layer.animatePosition(from: CGPoint(x: position.x - offset.x, y: position.y - offset.y), to: self.dragRestPosition, duration: UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.65, timingFunction: UIAccessibility.isReduceMotionEnabled ? CAMediaTimingFunctionName.easeOut.rawValue : kCAMediaTimingFunctionSpring)
        }
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
            
            self.clipsToBounds = true
            
            // On iOS 27 a view with no rendered contents may not receive real touches.
            // A transparent backing leaves the appearance unchanged and supplies a surface.
            self.layer.contents = generateImage(CGSize(width: 1.0, height: 1.0), rotatedContext: { size, context in
                context.clear(CGRect(origin: .zero, size: size))
            })?.cgImage

            let pan = UIPanGestureRecognizer(target: self, action: #selector(self.panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            self.addGestureRecognizer(pan)
            let tap = UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:)))
            tap.require(toFail: pan)
            self.addGestureRecognizer(tap)
            NotificationCenter.default.addObserver(self, selector: #selector(self.motionPreferenceChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        
        required public init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            self.giftsDisposable?.dispose()
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func tapped(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let component = self.component else {
                return
            }
            let location = gestureRecognizer.location(in: self)
            if let layer = self.gift(at: location) {
                component.action(layer.gift)
            }
        }
        
        private var accessibilityGiftElements: [AnyHashable: GiftAccessibilityElement] = [:]
        
        /// VoiceOver: the collectible gifts on the cover are buttons (a tap opens the gift), named as the gift screen
        /// names them ("Title #number"); other gifts are decoration. Elements are kept per gift so focus survives.
        override public var accessibilityElements: [Any]? {
            get {
                guard let component = self.component else {
                    return []
                }
                let dateTimeFormat = component.context.sharedContext.currentPresentationData.with { $0 }.dateTimeFormat
                var elements: [(frame: CGRect, element: GiftAccessibilityElement)] = []
                var validIds = Set<AnyHashable>()
                for (id, iconLayer) in self.iconLayers {
                    guard case let .unique(gift) = iconLayer.gift.gift, iconLayer.opacity > 0.01, self.bounds.intersects(iconLayer.frame) else {
                        continue
                    }
                    validIds.insert(id)
                    let element: GiftAccessibilityElement
                    if let current = self.accessibilityGiftElements[id] {
                        element = current
                    } else {
                        element = GiftAccessibilityElement(accessibilityContainer: self)
                        self.accessibilityGiftElements[id] = element
                    }
                    element.accessibilityLabel = "\(gift.title) #\(formatCollectibleNumber(gift.number, dateTimeFormat: dateTimeFormat))"
                    element.accessibilityTraits = .button
                    element.accessibilityFrameInContainerSpace = (iconLayer.presentation() ?? iconLayer).frame
                    let starGift = iconLayer.gift
                    element.activate = { [weak self] in
                        guard let self, let component = self.component else {
                            return false
                        }
                        component.action(starGift)
                        return true
                    }
                    elements.append((iconLayer.frame, element))
                }
                for id in self.accessibilityGiftElements.keys where !validIds.contains(id) {
                    self.accessibilityGiftElements.removeValue(forKey: id)
                }
                elements.sort(by: { lhs, rhs in
                    if lhs.frame.minY != rhs.frame.minY {
                        return lhs.frame.minY < rhs.frame.minY
                    }
                    return lhs.frame.minX < rhs.frame.minX
                })
                return elements.map(\.element)
            } set(value) {
            }
        }
        
        public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            return self.gift(at: point) != nil
        }

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            self.isCurrentlyInHierarchy = self.window != nil && UIApplication.shared.applicationState == .active
            if !self.isCurrentlyInHierarchy { self.finishDragging() }
            self.updateAnimations()
        }

        @objc private func applicationWillResignActive() {
            self.isCurrentlyInHierarchy = false
            self.finishDragging()
            self.updateAnimations()
        }

        @objc private func applicationDidBecomeActive() {
            self.isCurrentlyInHierarchy = self.window != nil
            self.updateAnimations()
        }

        @objc private func motionPreferenceChanged() {
            self.updateAnimations()
        }

        func updateAnimations() {
            for iconLayer in self.iconLayers.values {
                guard iconLayer !== self.draggedLayer else { continue }
                if self.isCurrentlyInHierarchy && !UIAccessibility.isReduceMotionEnabled {
                    iconLayer.resumeMotion()
                } else {
                    iconLayer.suspendMotion(reduceMotion: UIAccessibility.isReduceMotionEnabled)
                }
            }
        }

        private var scheduledAnimateIn = false
        public func willAnimateIn() {
            self.scheduledAnimateIn = true
            for (_, layer) in self.iconLayers {
                layer.opacity = 0.0
            }
        }
        
        public func animateIn() {
            guard let _ = self.currentSize, let component = self.component else {
                return
            }
            self.scheduledAnimateIn = false
            
            for (_, layer) in self.iconLayers {
                layer.opacity = 1.0
                if UIAccessibility.isReduceMotionEnabled {
                    continue
                }
                layer.animatePosition(
                    from: component.avatarCenter,
                    to: layer.position,
                    duration: 0.4,
                    timingFunction: kCAMediaTimingFunctionSpring
                )
            }
        }
    
        func update(component: PeerInfoGiftsCoverComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.isUpdating = true
            defer {
                self.isUpdating = false
            }
            
            let previousComponent = self.component
            self.component = component
            self.state = state
            
            let previousCurrentSize = self.currentSize
            self.currentSize = availableSize
                    
            let iconSize = CGSize(width: 58.0, height: 58.0)
            
            let giftIds = self.gifts.map { gift in
                if case let .unique(gift) = gift.gift {
                    return gift.id
                } else {
                    return 0
                }
            }
            
            let resized = previousCurrentSize != nil && (previousCurrentSize?.width != availableSize.width || previousComponent?.sideInsets.stripLeft != component.sideInsets.stripLeft || previousComponent?.sideInsets.stripRight != component.sideInsets.stripRight)
            if resized, let previousComponent, let previousCurrentSize {
                // Keep the same slots/layers on rotation: rerunning the random packing
                // can drop gifts and recreate them when the original width returns.
                let oldWidth = max(1.0, previousCurrentSize.width - previousComponent.sideInsets.stripLeft - previousComponent.sideInsets.stripRight)
                let newWidth = max(1.0, availableSize.width - component.sideInsets.stripLeft - component.sideInsets.stripRight)
                self.iconPositions = self.iconPositions.map { position in
                    let point = position.relativeCartesian
                    let x = point.x * newWidth / oldWidth
                    return PositionGenerator.Position(distance: hypot(x, point.y), angle: atan2(point.y, x), scale: position.scale)
                }
            }
            if !giftIds.isEmpty && (self.iconPositions.isEmpty || self.appliedGiftIds != giftIds) {
                var avatarCenter = component.avatarCenter
                if avatarCenter.y < 0.0 {
                    avatarCenter.y = component.statusBarHeight + 75.0
                }
                
                var excludeRects: [CGRect] = [component.avatarSize.centered(around: avatarCenter).insetBy(dx: -8.0, dy: -8.0)]
                if component.statusBarHeight > 0.0 {
                    excludeRects.append(CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: component.statusBarHeight + 4.0)))
                }
                excludeRects.append(contentsOf: peerInfoGiftsCoverSideExclusionRects(width: availableSize.width, height: component.defaultHeight, statusBarHeight: component.statusBarHeight, topLeftButtonsSize: component.topLeftButtonsSize, topRightButtonsSize: component.topRightButtonsSize, sideInsets: component.sideInsets))
                excludeRects.append(CGRect(origin: CGPoint(x: component.titleCenterX.map { floor($0 - component.titleWidth / 2.0) } ?? floor((availableSize.width - component.titleWidth) / 2.0), y: avatarCenter.y + component.avatarSize.height / 2.0 + 6.0), size: CGSize(width: component.titleWidth, height: 100.0)))
                if component.bottomHeight > 0.0 {
                    excludeRects.append(CGRect(origin: CGPoint(x: 0.0, y: component.defaultHeight - component.bottomHeight), size: CGSize(width: availableSize.width, height: component.bottomHeight)))
                }
                                                
                let positionGenerator = PositionGenerator(
                    containerSize: CGSize(width: availableSize.width, height: component.defaultHeight),
                    centerFrame: component.avatarSize.centered(around: avatarCenter),
                    exclusionZones: excludeRects,
                    minimumDistance: 70.0,
                    edgePadding: 14.0,
                    seed: self.seed
                )
                
                self.iconPositions = positionGenerator.generatePositions(count: min(6, giftIds.count), itemSize: CGSize(width: 76.0, height: 76.0))
            }
            self.appliedGiftIds = giftIds
            
            if self.giftsDisposable == nil {
                self.giftsDisposable = combineLatest(
                    queue: Queue.mainQueue(),
                    component.giftsContext.state,
                    component.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: component.peerId))
                    |> map { peer -> Int64? in
                        if case let .user(user) = peer, case let .starGift(id, _, _, _, _, _, _, _, _) = user.emojiStatus?.content {
                            return id
                        }
                        return nil
                    }
                    |> distinctUntilChanged
                ).start(next: { [weak self] state, giftStatusId in
                    guard let self else {
                        return
                    }
                    
                    let pinnedGifts = state.gifts.filter { gift in
                        if gift.pinnedToTop {
                            if case let .unique(uniqueGift) = gift.gift {
                                return uniqueGift.id != giftStatusId
                            }
                        }
                        return false
                    }
                    self.gifts = pinnedGifts
                    
                    if !self.isUpdating {
                        self.state?.updated(transition: .spring(duration: 0.4))
                    }
                })
            }
                                                                          
            var validIds = Set<AnyHashable>()
            var index = 0
            for gift in self.gifts.prefix(6) {
                guard index < self.iconPositions.count else {
                    break
                }
                let id: AnyHashable
                if case let .unique(uniqueGift) = gift.gift {
                    id = uniqueGift.slug
                } else {
                    id = index
                }
                validIds.insert(id)
                
                var iconTransition = resized && transition.animation.isImmediate && !UIAccessibility.isReduceMotionEnabled ? ComponentTransition.easeInOut(duration: 0.25) : transition
                let iconPosition = self.iconPositions[index]
                let iconLayer: GiftIconLayer
                if let current = self.iconLayers[id] {
                    iconLayer = current
                } else {
                    iconTransition = .immediate
                    iconLayer = GiftIconLayer(context: component.context, gift: gift, size: iconSize, glowing: component.hasBackground)
                    self.iconLayers[id] = iconLayer
                    self.layer.addSublayer(iconLayer)
                    
                    if self.scheduledAnimateIn {
                        iconLayer.opacity = 0.0
                    } else {
                        iconLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        iconLayer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                    }
                    
                    iconLayer.motionIndex = index
                    if self.isCurrentlyInHierarchy {
                        iconLayer.resumeMotion()
                    }
                }
                iconLayer.glowing = component.hasBackground
                
                let itemDistanceFraction = max(0.0, min(0.5, (iconPosition.distance - component.avatarSize.width / 2.0) / 144.0))
                let itemScaleFraction = patternScaleValueAt(fraction: min(1.0, component.avatarTransitionFraction * 1.33), t: itemDistanceFraction, reverse: false)
               
                func interpolatePosition(from: PositionGenerator.Position, to: PositionGenerator.Position, t: CGFloat) -> PositionGenerator.Position {
                    let clampedT = max(0, min(1, t))
                    
                    let interpolatedDistance = from.distance + (to.distance - from.distance) * clampedT
                    let interpolatedAngle = from.angle + (to.angle - from.angle) * clampedT
                    
                    return PositionGenerator.Position(distance: interpolatedDistance, angle: interpolatedAngle, scale: from.scale)
                }
                
                let toAngle: CGFloat = .pi * 0.18
                let centerPosition = PositionGenerator.Position(distance: 0.0, angle: iconPosition.angle + toAngle, scale: iconPosition.scale)
                let effectivePosition = interpolatePosition(from: iconPosition, to: centerPosition, t: itemScaleFraction)
                let effectiveAngle = toAngle * itemScaleFraction
                
                let absolutePosition = getAbsolutePosition(position: effectivePosition, centerPoint: component.avatarCenter)
                                
                iconTransition.setBounds(layer: iconLayer, bounds: CGRect(origin: .zero, size: iconSize))
                if self.draggedLayer === iconLayer {
                    self.dragRestPosition = absolutePosition
                } else {
                    iconTransition.setPosition(layer: iconLayer, position: absolutePosition)
                }
                iconLayer.updateRotation(effectiveAngle, transition: iconTransition)
                iconTransition.setScale(layer: iconLayer, scale: iconPosition.scale * (1.0 - itemScaleFraction))
                
                if !self.scheduledAnimateIn {
                    iconTransition.setAlpha(layer: iconLayer, alpha: 1.0 - itemScaleFraction)
                }
                
                index += 1
            }
            
            var removeIds: [AnyHashable] = []
            for (id, layer) in self.iconLayers {
                if !validIds.contains(id) {
                    removeIds.append(id)
                    layer.animateScale(from: 1.0, to: 0.01, duration: 0.25, removeOnCompletion: false)
                    layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { _ in
                        layer.removeFromSuperlayer()
                    })
                }
            }
            for id in removeIds {
                self.iconLayers.removeValue(forKey: id)
            }
            self.updateAnimations()
            return availableSize
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private var shadowImage: UIImage? = {
    return generateImage(CGSize(width: 44.0, height: 44.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        
        var locations: [CGFloat] = [0.0, 0.3, 1.0]
        let colors: [CGColor] = [UIColor(rgb: 0xffffff, alpha: 0.65).cgColor, UIColor(rgb: 0xffffff, alpha: 0.65).cgColor, UIColor(rgb: 0xffffff, alpha: 0.0).cgColor]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), startRadius: 0.0, endCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), endRadius: size.width / 2.0, options: .drawsAfterEndLocation)
    })
}()

private final class StarsEffectLayer: SimpleLayer {
    private let emitterLayer = CAEmitterLayer()
    
    override init() {
        super.init()
        
        self.addSublayer(self.emitterLayer)
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup(color: UIColor, size: CGSize) {
        self.color = color
        
        let emitter = CAEmitterCell()
        emitter.name = "emitter"
        emitter.contents = UIImage(bundleImageName: "Premium/Stars/Particle")?.cgImage
        emitter.birthRate = 8.0
        emitter.lifetime = 2.0
        emitter.velocity = 0.1
        emitter.scale = (size.width / 40.0) * 0.12
        emitter.scaleRange = 0.02
        emitter.alphaRange = 0.1
        emitter.emissionRange = .pi * 2.0
        
        let staticColors: [Any] = [
            color.withAlphaComponent(0.0).cgColor,
            color.withAlphaComponent(0.58).cgColor,
            color.withAlphaComponent(0.58).cgColor,
            color.withAlphaComponent(0.0).cgColor
        ]
        let staticColorBehavior = CAEmitterCell.createEmitterBehavior(type: "colorOverLife")
        staticColorBehavior.setValue(staticColors, forKey: "colors")
        emitter.setValue([staticColorBehavior], forKey: "emitterBehaviors")
        self.emitterLayer.emitterCells = [emitter]
    }
    
    private var color: UIColor?
        
    func update(color: UIColor, size: CGSize) {
        if self.color != color {
            self.setup(color: color, size: size)
        }
        self.emitterLayer.seed = UInt32.random(in: .min ..< .max)
        self.emitterLayer.emitterShape = .circle
        self.emitterLayer.emitterSize = size
        self.emitterLayer.emitterMode = .surface
        self.emitterLayer.frame = CGRect(origin: .zero, size: size)
        self.emitterLayer.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
    }
}

private class GiftIconLayer: SimpleLayer {
    private let context: AccountContext
    let gift: ProfileGiftsContext.State.StarGift
    private let size: CGSize
    var glowing: Bool {
        didSet {
            self.shadowLayer.opacity = self.glowing ? 1.0 : 0.0
            
            let color: UIColor
            if self.glowing {
                color = .white
            } else if let layerTintColor = self.shadowLayer.layerTintColor {
                color = UIColor(cgColor: layerTintColor)
            } else {
                color = .white
            }
            
            let side = floor(self.size.width * 1.25)
            let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: self.size))
            self.starsLayer.frame = starsFrame
            self.starsLayer.update(color: color, size: starsFrame.size)
        }
    }
    
    private let bubbleLayer = CAGradientLayer()
    private let rimLayer = CAShapeLayer()
    let shadowLayer = SimpleLayer()
    let starsLayer = StarsEffectLayer()
    let animationLayer: InlineStickerItemLayer
    
    private var isPresentationCopy = false
    var motionIndex = 0
    private var motionEpoch: CFTimeInterval?
    private var suspendedMotionTime: CFTimeInterval?

    override init(layer: Any) {
        guard let source = layer as? GiftIconLayer else { preconditionFailure() }
        self.context = source.context
        self.gift = source.gift
        self.size = source.size
        self.glowing = source.glowing
        self.animationLayer = source.animationLayer
        self.isPresentationCopy = true
        super.init(layer: layer)
    }

    init(
        context: AccountContext,
        gift: ProfileGiftsContext.State.StarGift,
        size: CGSize,
        glowing: Bool
    ) {
        self.context = context
        self.gift = gift
        self.size = size
        self.glowing = glowing
        
        var file: TelegramMediaFile?
        var color: UIColor = .white
        switch gift.gift {
        case let .generic(gift):
            file = gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, fileValue, _, _) = attribute {
                    file = fileValue
                } else if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
                    color = UIColor(rgb: UInt32(bitPattern: innerColor))
                }
            }
        }
        
        let emoji = ChatTextInputTextCustomEmojiAttribute(
            interactivelySelectedFromPackId: nil,
            fileId: file?.fileId.id ?? 0,
            file: file
        )
        self.animationLayer = InlineStickerItemLayer(
            context: .account(context),
            userLocation: .other,
            attemptSynchronousLoad: false,
            emoji: emoji,
            file: file,
            cache: context.animationCache,
            renderer: context.animationRenderer,
            unique: true,
            placeholderColor: UIColor.white.withAlphaComponent(0.2),
            pointSize: CGSize(width: size.width * 2.0, height: size.height * 2.0),
            loopCount: 1
        )
        
        self.shadowLayer.contents = shadowImage?.cgImage
        self.shadowLayer.layerTintColor = color.cgColor
        self.shadowLayer.opacity = glowing ? 1.0 : 0.0
        
        super.init()
        
        let side = floor(size.width * 1.25)
        let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: size))
        self.starsLayer.frame = starsFrame
        self.starsLayer.update(color: glowing ? .white : color, size: starsFrame.size)
        
        self.bubbleLayer.colors = [UIColor.white.withAlphaComponent(0.38).cgColor, UIColor.white.withAlphaComponent(0.06).cgColor, UIColor(red: 0.65, green: 0.79, blue: 0.93, alpha: 0.24).cgColor]
        self.bubbleLayer.locations = [0.0, 0.45, 1.0]
        self.bubbleLayer.startPoint = CGPoint(x: 0.1, y: 0.0)
        self.bubbleLayer.endPoint = CGPoint(x: 0.9, y: 1.0)
        self.bubbleLayer.borderWidth = 0.75
        self.bubbleLayer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        self.rimLayer.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor
        self.rimLayer.fillColor = UIColor.clear.cgColor
        self.rimLayer.lineWidth = 1.2
        self.rimLayer.lineCap = .round
        self.addSublayer(self.bubbleLayer)
        self.addSublayer(self.rimLayer)
        self.addSublayer(self.shadowLayer)
        self.addSublayer(self.starsLayer)
        self.addSublayer(self.animationLayer)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    override func layoutSublayers() {
        guard !self.isPresentationCopy else { return }
        self.shadowLayer.frame = CGRect(origin: .zero, size: self.bounds.size).insetBy(dx: -8.0, dy: -8.0)
        self.bubbleLayer.frame = self.bounds
        self.bubbleLayer.cornerRadius = self.bounds.width / 2.0
        self.rimLayer.frame = self.bounds
        self.rimLayer.path = UIBezierPath(arcCenter: CGPoint(x: self.bounds.midX, y: self.bounds.midY), radius: max(0.0, self.bounds.width / 2.0 - 3.0), startAngle: .pi * 1.08, endAngle: .pi * 1.62, clockwise: true).cgPath
        self.animationLayer.bounds = CGRect(origin: .zero, size: CGSize(width: self.bounds.width * 0.68, height: self.bounds.height * 0.68))
        self.animationLayer.position = CGPoint(x: self.bounds.width / 2.0, y: self.bounds.height / 2.0)
    }
    
    func updateRotation(_ angle: CGFloat, transition: ComponentTransition) {
        self.animationLayer.transform = CATransform3DMakeRotation(angle, 0.0, 0.0, 1.0)
    }
    
    func stopAnimations() {
        self.removeAnimation(forKey: "hover")
        self.animationLayer.removeAnimation(forKey: "wiggle")
        self.shadowLayer.removeAnimation(forKey: "glow")
    }

    func suspendMotion(reduceMotion: Bool) {
        guard self.suspendedMotionTime == nil else { return }
        self.suspendedMotionTime = self.convertTime(CACurrentMediaTime(), from: nil)
        // Retain the current transform instead of snapping the bubble back to its anchor.
        if let visible = self.presentation(), self.animation(forKey: "hover") != nil {
            let held = CABasicAnimation(keyPath: "transform.translation")
            let offset = NSValue(cgSize: CGSize(width: visible.transform.m41, height: visible.transform.m42))
            held.fromValue = offset
            held.toValue = offset
            held.duration = 1.0
            held.repeatCount = .infinity
            self.add(held, forKey: "hover")
        }
        if reduceMotion {
            self.animationLayer.removeAnimation(forKey: "wiggle")
            self.shadowLayer.removeAnimation(forKey: "glow")
        }
    }

    func resumeMotion() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        if let suspendedTime = self.suspendedMotionTime {
            let now = self.convertTime(CACurrentMediaTime(), from: nil)
            if let epoch = self.motionEpoch { self.motionEpoch = epoch + now - suspendedTime }
            self.suspendedMotionTime = nil
            self.removeAnimation(forKey: "hover")
        }
        _ = self.startAnimations()
    }

    @discardableResult
    func startAnimations() -> CGPoint {
        guard !UIAccessibility.isReduceMotionEnabled else { return .zero }
        let now = self.convertTime(CACurrentMediaTime(), from: nil)
        let epoch = self.motionEpoch ?? now
        self.motionEpoch = epoch
        let duration = 8.0 + Double(self.motionIndex % 4)
        if self.animation(forKey: "hover") == nil {
            // Layout owns position and scale. Only translation is animated, so scrolling
            // and component updates cannot reset the loop. All child layers move together.
            let orbit = CAKeyframeAnimation(keyPath: "transform.translation")
            orbit.values = (0 ... 120).map { index -> NSValue in
                let offset = giftBubbleMotionOffset(phase: Double(index) / 120.0, index: self.motionIndex)
                return NSValue(cgSize: CGSize(width: offset.x, height: offset.y))
            }
            orbit.duration = duration
            orbit.repeatCount = .infinity
            orbit.calculationMode = .linear
            orbit.beginTime = epoch
            self.add(orbit, forKey: "hover")
        }
        return giftBubbleMotionOffset(phase: (now - epoch) / duration, index: self.motionIndex)
    }

}

func giftBubbleMotionOffset(phase: Double, index: Int) -> CGPoint {
    let angle = phase * .pi * 2.0
    let variation = Double(index % 7) * 0.73
    let depth = 0.75 + Double(index % 3) * 0.125
    return CGPoint(
        x: depth * 7.0 * sin(angle) * (0.8 + 0.2 * cos(2.0 * angle + variation)),
        y: depth * 5.0 * sin(2.0 * angle) * (0.8 + 0.2 * cos(angle + variation))
    )
}

private struct PositionGenerator {
    struct Position {
        let distance: CGFloat
        let angle: CGFloat
        let scale: CGFloat
        
        var relativeCartesian: CGPoint {
            return CGPoint(
                x: self.distance * cos(self.angle),
                y: self.distance * sin(self.angle)
            )
        }
    }
    
    let containerSize: CGSize
    let centerFrame: CGRect
    let exclusionZones: [CGRect]
    let minimumDistance: CGFloat
    let edgePadding: CGFloat
    let scaleRange: (min: CGFloat, max: CGFloat)
    
    let innerOrbitRange: (min: CGFloat, max: CGFloat)
    let outerOrbitRange: (min: CGFloat, max: CGFloat)
    let innerOrbitCount: Int
    
    private let lokiRng: LokiRng
    
    init(
        containerSize: CGSize,
        centerFrame: CGRect,
        exclusionZones: [CGRect],
        minimumDistance: CGFloat,
        edgePadding: CGFloat,
        seed: UInt,
        scaleRange: (min: CGFloat, max: CGFloat) = (0.7, 1.15),
        innerOrbitRange: (min: CGFloat, max: CGFloat) = (1.4, 2.2),
        outerOrbitRange: (min: CGFloat, max: CGFloat) = (2.5, 3.6),
        innerOrbitCount: Int = 4
    ) {
        self.containerSize = containerSize
        self.centerFrame = centerFrame
        self.exclusionZones = exclusionZones
        self.minimumDistance = minimumDistance
        self.edgePadding = edgePadding
        self.scaleRange = scaleRange
        self.innerOrbitRange = innerOrbitRange
        self.outerOrbitRange = outerOrbitRange
        self.innerOrbitCount = innerOrbitCount
        self.lokiRng = LokiRng(seed0: seed, seed1: 0, seed2: 0)
    }
    
    func generatePositions(count: Int, itemSize: CGSize) -> [Position] {
        var positions: [Position] = []
        
        let centerPoint = CGPoint(x: self.centerFrame.midX, y: self.centerFrame.midY)
        let centerRadius = min(self.centerFrame.width, self.centerFrame.height) / 2.0
        
        let maxAttempts = count * 200
        var attempts = 0
        
        var leftPositions = 0
        var rightPositions = 0
        
        let innerCount = min(self.innerOrbitCount, count)
        
        while positions.count < innerCount && attempts < maxAttempts {
            attempts += 1
            
            let placeOnLeftSide = rightPositions > leftPositions
            
            let orbitRangeSize = self.innerOrbitRange.max - self.innerOrbitRange.min
            let orbitDistanceFactor = self.innerOrbitRange.min + orbitRangeSize * CGFloat(self.lokiRng.next())
            let distance = orbitDistanceFactor * centerRadius
            
            let angleRange: CGFloat = placeOnLeftSide ? .pi : .pi
            let angleOffset: CGFloat = placeOnLeftSide ? .pi/2 : -(.pi/2)
            let angle = angleOffset + angleRange * CGFloat(self.lokiRng.next())
            
            let absolutePosition = getAbsolutePosition(distance: distance, angle: angle, centerPoint: centerPoint)
            
            if absolutePosition.x - itemSize.width/2 < self.edgePadding ||
                absolutePosition.x + itemSize.width/2 > self.containerSize.width - self.edgePadding ||
                absolutePosition.y - itemSize.height/2 < self.edgePadding ||
                absolutePosition.y + itemSize.height/2 > self.containerSize.height - self.edgePadding {
                continue
            }
            
            let itemRect = CGRect(
                x: absolutePosition.x - itemSize.width/2,
                y: absolutePosition.y - itemSize.height/2,
                width: itemSize.width,
                height: itemSize.height
            )
            
            if self.isValidPosition(itemRect, existingPositions: positions.map {
                getAbsolutePosition(distance: $0.distance, angle: $0.angle, centerPoint: centerPoint)
            }, itemSize: itemSize) {
                let scaleRangeSize = max(self.scaleRange.min + 0.1, 0.75) - self.scaleRange.max
                let scale = self.scaleRange.max + scaleRangeSize * CGFloat(self.lokiRng.next())
                positions.append(Position(distance: distance, angle: angle, scale: scale))
                
                if absolutePosition.x < centerPoint.x {
                    leftPositions += 1
                } else {
                    rightPositions += 1
                }
            }
        }
        
        let maxPossibleDistance = hypot(self.containerSize.width, self.containerSize.height) / 2
        
        while positions.count < count && attempts < maxAttempts {
            attempts += 1
            
            let placeOnLeftSide = rightPositions >= leftPositions
            
            let orbitRangeSize = self.outerOrbitRange.max - self.outerOrbitRange.min
            let orbitDistanceFactor = self.outerOrbitRange.min + orbitRangeSize * CGFloat(self.lokiRng.next())
            let distance = orbitDistanceFactor * centerRadius
            
            let angleRange: CGFloat = placeOnLeftSide ? .pi : .pi
            let angleOffset: CGFloat = placeOnLeftSide ? .pi/2 : -(.pi/2)
            let angle = angleOffset + angleRange * CGFloat(self.lokiRng.next())
            
            let absolutePosition = getAbsolutePosition(distance: distance, angle: angle, centerPoint: centerPoint)
            if absolutePosition.x - itemSize.width/2 < self.edgePadding ||
                absolutePosition.x + itemSize.width/2 > self.containerSize.width - self.edgePadding ||
                absolutePosition.y - itemSize.height/2 < self.edgePadding ||
                absolutePosition.y + itemSize.height/2 > self.containerSize.height - self.edgePadding {
                continue
            }
            
            let itemRect = CGRect(
                x: absolutePosition.x - itemSize.width/2,
                y: absolutePosition.y - itemSize.height/2,
                width: itemSize.width,
                height: itemSize.height
            )
            
            if self.isValidPosition(itemRect, existingPositions: positions.map {
                getAbsolutePosition(distance: $0.distance, angle: $0.angle, centerPoint: centerPoint)
            }, itemSize: itemSize) {
                let normalizedDistance = min(distance / maxPossibleDistance, 1.0)
                let scale = self.scaleRange.max - normalizedDistance * (self.scaleRange.max - self.scaleRange.min)
                positions.append(Position(distance: distance, angle: angle, scale: scale))
                
                if absolutePosition.x < centerPoint.x {
                    leftPositions += 1
                } else {
                    rightPositions += 1
                }
            }
        }
        
        return positions
    }
    
    func getAbsolutePosition(distance: CGFloat, angle: CGFloat, centerPoint: CGPoint) -> CGPoint {
        return CGPoint(
            x: centerPoint.x + distance * cos(angle),
            y: centerPoint.y + distance * sin(angle)
        )
    }
    
    private func isValidPosition(_ rect: CGRect, existingPositions: [CGPoint], itemSize: CGSize) -> Bool {
        if rect.minX < self.edgePadding || rect.maxX > self.containerSize.width - self.edgePadding ||
            rect.minY < self.edgePadding || rect.maxY > self.containerSize.height - self.edgePadding {
            return false
        }
        
        for zone in self.exclusionZones {
            if rect.intersects(zone) {
                return false
            }
        }
        
        let effectiveMinDistance = existingPositions.count > 5 ? max(self.minimumDistance * 0.7, 10.0) : self.minimumDistance
        
        for existingPosition in existingPositions {
            let distance = hypot(existingPosition.x - rect.midX, existingPosition.y - rect.midY)
            if distance < effectiveMinDistance {
                return false
            }
        }
        
        return true
    }
}

private func getAbsolutePosition(position: PositionGenerator.Position, centerPoint: CGPoint) -> CGPoint {
    return CGPoint(
        x: centerPoint.x + position.distance * cos(position.angle),
        y: centerPoint.y + position.distance * sin(position.angle)
    )
}

private func getAbsolutePosition(distance: CGFloat, angle: CGFloat, centerPoint: CGPoint) -> CGPoint {
    return CGPoint(
        x: centerPoint.x + distance * cos(angle),
        y: centerPoint.y + distance * sin(angle)
    )
}

private func windowFunction(t: CGFloat) -> CGFloat {
    return bezierPoint(0.6, 0.0, 0.4, 1.0, t)
}

private func patternScaleValueAt(fraction: CGFloat, t: CGFloat, reverse: Bool) -> CGFloat {
    let windowSize: CGFloat = 0.8

    let effectiveT: CGFloat
    let windowStartOffset: CGFloat
    let windowEndOffset: CGFloat
    if reverse {
        effectiveT = 1.0 - t
        windowStartOffset = 1.0
        windowEndOffset = -windowSize
    } else {
        effectiveT = t
        windowStartOffset = -windowSize
        windowEndOffset = 1.0
    }

    let windowPosition = (1.0 - fraction) * windowStartOffset + fraction * windowEndOffset
    let windowT = max(0.0, min(windowSize, effectiveT - windowPosition)) / windowSize
    let localT = 1.0 - windowFunction(t: windowT)

    return localT
}

private final class GiftAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    
    override func accessibilityActivate() -> Bool {
        return self.activate?() ?? false
    }
}
