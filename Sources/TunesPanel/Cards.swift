import Foundation
import TunesContract

/// A colour by meaning; the app maps each to a system colour.
public enum Tone: Sendable, Equatable {
    case normal, soft, dim, cyan, green, orange, red, accent
}

/// A clickable control as drawn: whether it acts, whether it shows its mode
/// as on, its visible text (often none), and the words of its tooltip and
/// accessibility label.
public struct Control: Sendable, Equatable {
    public var enabled: Bool
    public var lit: Bool
    public var text: String
    public var help: String

    public init(enabled: Bool = true, lit: Bool = false, text: String = "", help: String) {
        self.enabled = enabled
        self.lit = lit
        self.text = text
        self.help = help
    }
}

/// The one card the popover shows.
public enum Card: Sendable, Equatable {
    case setup(SetupCard)
    case chooser(ChooserCard)
    case editor(EditorCard)
    case share(ShareCard)
    case player(PlayerCard)
}

// MARK: - Setup

public struct SetupCard: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case missing, downloading, failed }
    public var kind: Kind
    public var title: String
    public var detail: String
    /// Label, value.
    public var rows: [Row]
    /// 0…1 while downloading.
    public var progress: Double?
    /// Download, Cancel or Resume.
    public var button: Control
    public var command: Command

    public struct Row: Sendable, Equatable {
        public var label: String
        public var value: String
    }
}

// MARK: - Chooser

public struct ChooserCard: Sendable, Equatable {
    /// The back link's text (the selected genre's name), nil with no genre.
    public var back: Control?
    public var title: String
    public var chip: String
    public var cells: [Cell]
    public var add: Control
    /// The line over the cells when there are none.
    public var empty: String
    /// The engine's error line.
    public var strip: String?

    public struct Cell: Sendable, Equatable {
        public var id: String
        public var name: String
        public var sub: String
        /// The selected genre.
        public var current: Bool
        public var pick: Control
        public var edit: Control
    }
}

// MARK: - Editor

public struct EditorCard: Sendable, Equatable {
    public var back: Control
    public var title: String
    /// "" for none.
    public var chip: String
    public var values: GenreFieldsText
    public var loading: Bool
    public var name: Field
    public var caption: Field
    public var turns: Field
    public var slowest: Field
    public var fastest: Field
    /// Under the two tempo boxes.
    public var tempoError: String
    public var hint: String
    /// Absent for a new genre and for the last genre.
    public var delete: Control?
    public var cancel: Control
    public var save: Control
    /// The delete question, in place of the fields.
    public var ask: Ask?

    public struct Field: Sendable, Equatable {
        public var label: String
        /// The label's note.
        public var side: String
        public var placeholder: String
        /// "" or the sentence under the box (never for a tempo box).
        public var error: String
        /// The box drawn in red.
        public var bad: Bool
    }

    public struct Ask: Sendable, Equatable {
        public var title: String
        public var detail: String
        public var error: String
        public var keep: Control
        public var delete: Control
    }
}

// MARK: - Share sheet

public struct ShareCard: Sendable, Equatable {
    public var back: Control
    /// Right of SHARE: the genre.
    public var head: String
    public var name: String
    public var meta: String
    public var rows: [Row]

    public enum Action: Sendable, Equatable {
        case copyFile, copyPath, showInFinder, export, keep
    }

    public struct Row: Sendable, Equatable {
        public var action: Action
        public var title: String
        public var sub: String
        /// For keep for good: the switch's position; nil for the others.
        public var on: Bool?
        public var control: Control
    }
}

// MARK: - Player

public struct PlayerCard: Sendable, Equatable {
    public var strip: String?
    public var now: Now
    public var next: Next
    public var composer: Composer

    public struct Now: Sendable, Equatable {
        /// "repeating", "kept tunes" or "".
        public var suffix: String
        /// The genre button.
        public var genre: Control
        public var title: String
        public var titleTone: Tone
        /// "" or "★ kept for good".
        public var badge: String
        public var meta: String
        public var wave: Wave?
        public var time: (left: String, right: String)?
        public var playPause: Control
        /// Whether the main button shows pause.
        public var showsPause: Bool
        public var next: Control
        public var shuffle: Control
        public var `repeat`: Control
        public var share: Control
        public var scrap: Control

        public static func == (a: Now, b: Now) -> Bool {
            a.suffix == b.suffix && a.genre == b.genre && a.title == b.title && a.titleTone == b.titleTone
                && a.badge == b.badge && a.meta == b.meta && a.wave == b.wave
                && a.time?.left == b.time?.left && a.time?.right == b.time?.right
                && a.playPause == b.playPause && a.showsPause == b.showsPause && a.next == b.next
                && a.shuffle == b.shuffle && a.repeat == b.repeat && a.share == b.share && a.scrap == b.scrap
        }
    }

    public struct Wave: Sendable, Equatable {
        /// 78 levels in 0…1.
        public var levels: [Double]
        /// Bars drawn as played, 0…78.
        public var played: Int
        public var help: String
    }

    public struct Next: Sendable, Equatable {
        public var head: String
        public var rows: [Row]
    }

    public struct Row: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case tune, job, placeholder }
        public var kind: Kind
        /// A queue index for a tune row.
        public var index: Int?
        public var number: String
        public var name: String
        public var nameTone: Tone
        /// "" or "new".
        public var tag: String
        public var star: Bool
        /// The whole row faded.
        public var dim: Bool
        public var sub: String
        public var right: String
        public var rightTone: Tone
        public var bar: Double?
        /// What the pointer over the row offers.
        public var playNow: Control?
        public var share: Control?
        public var scrap: Control?
    }

    public struct Composer: Sendable, Equatable {
        public var on: Bool
        public var label: String
        public var labelTone: Tone
        public var toggle: Control
        public var lines: [Line]
        /// "Try now", when failed or no device.
        public var retry: Control?
    }

    public struct Line: Sendable, Equatable {
        public var pre: String
        /// Drawn bold.
        public var em: String
        public var post: String
        public var tone: Tone
        public var right: String
        public var rightTone: Tone

        init(_ pre: String, em: String = "", post: String = "", tone: Tone = .dim, right: String = "", rightTone: Tone = .dim) {
            self.pre = pre
            self.em = em
            self.post = post
            self.tone = tone
            self.right = right
            self.rightTone = rightTone
        }

        /// The line's text as read.
        public var text: String { pre + em + post }
    }
}

// MARK: - Footer and status item

/// The line under the cards, when there is something to say.
public enum Footer: Sendable, Equatable {
    case notice(String)
    /// "Scrapped <t>." and the button "Undo · N s".
    case undo(text: String, button: Control)
}

/// The menu bar item: the note glyph, the genre's name while playing, the
/// composer's dot.
public struct StatusItem: Sendable, Equatable {
    public var dim: Bool
    public var text: String
    /// nil for no dot.
    public var dot: Tone?
    public var help: String
}
