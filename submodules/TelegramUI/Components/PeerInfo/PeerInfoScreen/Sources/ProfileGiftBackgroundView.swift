import UIKit
import AccountContext
import TelegramCore
import SwiftSignalKit
import ComponentFlow
import PeerInfoCoverComponent
import UniversalMediaPlayer

/// A fixed backdrop: scrolling content never changes the music envelope's geometry.
final class ProfileGiftBackgroundView: UIView {
    private let context: AccountContext
    private let cover = ComponentView<Empty>()
    private let dimView = UIView()
    private var playbackDisposable: Disposable?
    private var musicFileId: Int64?
    private var status: PeerEmojiStatus?
    private var isDark = false

    init(context: AccountContext) {
        self.context = context
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.dimView.backgroundColor = .black
        self.dimView.alpha = 0.0
        self.addSubview(self.dimView)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPlayback), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPlayback), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.suspendPlayback), name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.playbackDisposable?.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    func update(status: PeerEmojiStatus, isDark: Bool, musicFileId: Int64?) {
        let appearanceChanged = self.status != status || self.isDark != isDark
        self.status = status
        self.isDark = isDark
        if self.musicFileId != musicFileId {
            self.musicFileId = musicFileId
            self.refreshPlayback()
        }
        if appearanceChanged {
            self.setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let status = self.status, self.bounds.width > 0.0 else { return }
        let size = self.bounds.size
        _ = self.cover.update(
            transition: .immediate,
            component: AnyComponent(PeerInfoCoverComponent(
                context: self.context, subject: .status(status), files: [:], isDark: self.isDark,
                avatarCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.28),
                avatarScale: 1.0, defaultHeight: size.height,
                avatarTransitionFraction: 0.0, patternTransitionFraction: 1.0
            )), environment: {}, containerSize: size
        )
        if let view = self.cover.view {
            if view.superview == nil { self.insertSubview(view, belowSubview: self.dimView) }
            view.frame = self.bounds
        }
        self.dimView.frame = self.bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.refreshPlayback()
    }

    @objc private func suspendPlayback() {
        self.playbackDisposable?.dispose()
        self.playbackDisposable = nil
        self.dimView.layer.removeAllAnimations()
        self.dimView.alpha = 0.0
    }

    @objc private func refreshPlayback() {
        self.suspendPlayback()
        guard self.window != nil, UIApplication.shared.applicationState == .active,
              let musicFileId = self.musicFileId else { return }
        let context = self.context
        self.playbackDisposable = (context.sharedContext.mediaManager.musicMediaPlayerState
        |> mapToSignal { value -> Signal<Float, NoError> in
            guard let (account, playback, type) = value, account.id == context.account.id,
                  case let .state(state) = playback, case .playing = state.status.status,
                  let data = state.item.playbackData,
                  case let .telegramFile(reference, _, _) = data.source,
                  reference.media.fileId.id == musicFileId else {
                return .single(-1.0)
            }
            if UIAccessibility.isReduceMotionEnabled {
                return .single(0.0)
            }
            return .single(0.0) |> then(context.sharedContext.mediaManager.filteredPlayerAudioLevelEvents(
                accountId: account.id, playlistId: state.playlistId, itemId: state.item.id, type: type
            ))
        }
        |> deliverOnMainQueue).start(next: { [weak self] level in
            guard let self else { return }
            // The player supplies amplitude, not a frequency spectrum. Limit contrast and
            // use a slower release to avoid harsh flashes on highly compressed tracks.
            let alpha: CGFloat = level < 0.0 ? 0.0 : 0.12 + 0.16 * CGFloat(min(1.0, max(0.0, level / 8.192)))
            let duration = alpha > self.dimView.alpha ? 0.12 : 0.38
            UIView.animate(withDuration: duration, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: {
                self.dimView.alpha = alpha
            })
        })
    }
}
