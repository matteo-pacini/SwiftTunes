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
    case words(WordsCard)
    case queue(QueueCard)
    case setup(SetupCard)
    case chooser(ChooserCard)
    case editor(EditorCard)
    case share(ShareCard)
    case player(PlayerCard)
}

// MARK: - Your own words

/// The sheet asking for one tune sung with the user's words.
public struct WordsCard: Sendable, Equatable {
    public var back: Control
    /// `SING MY WORDS`.
    public var label: String
    /// `A tune in <g>`.
    public var title: String
    /// `+ Verse` and the rest.
    public var inserts: [Control]
    public var text: String
    public var caret: Int
    /// `N sung lines · N of 2,000 characters`.
    public var counter: String
    public var counterRight: String
    /// The words' rule, once they have been typed in.
    public var wordsError: String
    public var nameLabel: String
    public var name: String
    public var nameError: String
    public var note: String
    /// The engine's refusal of the last request.
    public var refused: String
    public var cancel: Control
    public var compose: Control
}

// MARK: - Queue

/// Everything that will play this round, in order.
public struct QueueCard: Sendable, Equatable {
    public var back: Control
    /// `QUEUE · N THIS ROUND`.
    public var label: String
    public var title: String
    public var head: String
    public var rows: [PlayerCard.Row]
    /// Under the list: what happens after it, nil with nothing queued.
    public var last: String?
    public var making: PlayerCard.Making?
    public var palette: Palette
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
    /// The Colours row: the four colours as `#RRGGBB`.
    public var colours: [String]
    public var coloursLabel: String
    /// The Singing row.
    public var singing: Singing

    public struct Singing: Sendable, Equatable {
        public var label: String
        public var sub: String
        public var on: Bool
    }
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
    /// Under the meta line: the picture can be dragged out.
    public var hint: String
    /// The tune's picture, once the tune is described.
    public var artwork: Artwork?
    /// The file the picture drags out and `Share…` offers, once described.
    public var file: URL?
    public var rows: [Row]

    public enum Action: Sendable, Equatable {
        case share, copyPath, showInFinder, export, keep
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
    /// The selected genre's colours, for the backdrop.
    public var palette: Palette
    public var strip: String?
    public var now: Now
    public var next: Next
    public var making: Making?
    public var composer: Composer

    public struct Now: Sendable, Equatable {
        /// "NOW PLAYING", with " · KEPT TUNES" or " · REPEATING".
        public var label: String
        /// "repeating", "kept tunes" or "".
        public var suffix: String
        /// The genre button.
        public var genre: Control
        public var title: String
        public var titleTone: Tone
        /// A click on the name starts renaming it: `Rename`; nil with no tune.
        public var titleControl: Control?
        /// The name as a text field, while it is being renamed.
        public var rename: RenameField?
        /// `Lyrics`, on a sung tune; lit while its words are open.
        public var lyricsButton: Control?
        /// The words, as written, while they are open.
        public var lyrics: String?
        public var lyricsHead: String
        /// "" or "★ kept for good".
        public var badge: String
        public var meta: String
        public var wave: Wave?
        /// With no tune and a tune being made: the forming wave's stage.
        public var forming: JobStage?
        /// Repeat is on one tune.
        public var repeatsOne: Bool
        public var time: (left: String, right: String)?
        public var playPause: Control
        /// Whether the main button shows pause.
        public var showsPause: Bool
        public var next: Control
        public var shuffle: Control
        public var `repeat`: Control
        public var share: Control
        public var scrap: Control
        /// What the share control opens: the playing tune as drawn.
        public var shareRequest: ShareRequest?
        /// What the scrap control sends: the playing tune's name as drawn.
        public var scrapCommand: Command?

        public static func == (a: Now, b: Now) -> Bool {
            a.suffix == b.suffix && a.genre == b.genre && a.title == b.title && a.titleTone == b.titleTone
                && a.badge == b.badge && a.meta == b.meta && a.wave == b.wave
                && a.time?.left == b.time?.left && a.time?.right == b.time?.right
                && a.playPause == b.playPause && a.showsPause == b.showsPause && a.next == b.next
                && a.shuffle == b.shuffle && a.repeat == b.repeat && a.share == b.share && a.scrap == b.scrap
        }
    }

    public struct RenameField: Sendable, Equatable {
        public var text: String
        /// The local rule's sentence, else the engine's refusal, else "".
        public var error: String
        public var save: Control
        public var cancel: Control
    }

    public struct Wave: Sendable, Equatable {
        /// 78 levels in 0…1.
        public var levels: [Double]
        /// Bars drawn as played, 0…78.
        public var played: Int
        public var help: String
    }

    /// UP NEXT: finished tunes in play order, numbered from 1.
    public struct Next: Sendable, Equatable {
        public var head: String
        public var rows: [Row]
        /// `then N more this round · Show all`, opening the queue card, when
        /// more wait than the rows show.
        public var more: Control?
    }

    /// BEING MADE: the job and what has not started, under UP NEXT.
    public struct Making: Sendable, Equatable {
        public var head: String
        public var rows: [Row]
    }

    public struct Row: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case tune, job, placeholder }
        /// Stable while the row shows the same tune.
        public var id: String
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
        /// A tune's picture.
        public var artwork: Artwork?
        /// The job's stage, for its small forming wave.
        public var stage: JobStage?
        /// What the pointer over the row offers.
        public var playNow: Control?
        public var share: Control?
        public var scrap: Control?
        /// The commands and the share target, built from this row as drawn,
        /// so a click carries the name the user saw at this row's index
        /// even if a newer snapshot has moved the queue meanwhile.
        public var playNowCommand: Command?
        public var scrapCommand: Command?
        public var shareRequest: ShareRequest?
    }

    public struct Composer: Sendable, Equatable {
        public var on: Bool
        public var label: String
        public var labelTone: Tone
        /// The state as a pill beside the switch: the label when it is
        /// not plain "on", else the first line's right-hand words.
        public var pill: String?
        public var pillTone: Tone
        public var toggle: Control
        public var lines: [Line]
        /// "Try now", when failed or no device.
        public var retry: Control?
        /// `Sing my words…`, for a sung genre.
        public var words: Control?
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

/// A share sheet to open: the tune as it was drawn, and its file stem to
/// find it again once its name changes to the title.
public struct ShareRequest: Sendable, Equatable {
    public var target: TuneTarget
    public var file: String
    /// The tune has words.
    public var sung: Bool = false
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
