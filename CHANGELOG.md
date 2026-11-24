# Changelog

## Unreleased

## 0.1.0

SwiftTunes lives in the menu bar and plays endless music by genre,
composed on your Mac by the ACE-Step 1.5 Turbo music model. Once the
model is downloaded, nothing is sent anywhere. This is the first release.

### Getting started

- Needs a Mac with Apple silicon and macOS 26 or later, and about 8 GiB of
  memory free while a tune is being composed.
- Click the waveform in the menu bar to open SwiftTunes; right-click it for
  the menu.
- On first use, SwiftTunes needs a music model: ACE-Step 1.5 Turbo with its
  4B language model at Q8, four files and 7.57 GiB in all, downloaded once
  from Hugging Face. The card says how much it downloads, how much is free
  on disk, and the memory composing takes.
- The download shows which file it is on, how much has arrived, its speed
  and a progress bar. Cancel it at any time; Download again picks up where it
  stopped. If it fails, finished files are kept and Resume carries on. Every
  file is checked before it is used.
- The model's folder is left out of Time Machine backups.
- Remove Music Model… in the menu deletes the model when you want the space
  back, after saying how much it frees. Your tunes stay and keep playing;
  the composer bar offers the download again.

### The composer

- Turn the composer on and it writes new tunes for the genre, about three
  minutes each, and keeps two ready ahead. A new tune plays next.
- Its bar says what it is doing: starting the model, how much memory it is
  using while it works, or resting once two tunes are ready. While the
  composer is off, it says what turning it on would do.
- The model runs only while there is something to make, at a lower priority
  than your other work. Resting, held or off, it lets go of its memory.
- It waits by itself while Low Power Mode is on, while the Mac is running
  hot or while memory is under pressure, says so, and carries on when that
  passes. Tunes already made keep playing.
- A tune planned with a long silence in it is written again, and a silent
  ending is cut with a short fade.
- When making a tune fails, the bar says why and how many times in a row,
  and tries again by itself after 3 seconds, then every 30 seconds. Try now
  tries at once.
- SwiftTunes plays and composes nothing by itself at launch: pick a genre to
  start. The composer starts off.

### Being made

- Being made lists the tune being written or rendered, with a bar and the
  time left, estimated from the last five tunes (the estimates are
  remembered), and a place marked Not started for each tune still to come.
- While nothing plays yet, the first tune's shape forms in the player as it
  is made, and it starts by itself when it is ready.
- Scrap the tune being made to stop it.

### The player

- The player shows the tune's name, tempo and key, and the tune's shape as
  columns of dots that fill as it plays. Click the shape to jump, or drag
  across it; the position and length sit underneath.
- Controls: shuffle, repeat, Previous, play and pause, next, share and scrap.
- Previous goes back to the tune before within the first three seconds of a
  tune, and otherwise starts the tune again.
- Every tune gets its own picture, drawn from its name, tempo and key in its
  genre's colours.
- A volume slider under the controls sets SwiftTunes' own volume, not the
  Mac's.
- Click the playing tune's name to rename it.

### This round

- Every kept tune of the genre plays once a round, shuffled or in the order
  made. A new round never starts with the tune that ended the last one.
- This round lists the whole round in one scrolling list: tunes already
  played, dimmed; the playing one, highlighted, with a small level meter in
  place of its number; then what waits. The heading says which tune of how
  many is playing.
- Each tune keeps its number as the round goes on. The list follows the
  music, keeping the playing tune in view, and leaves you alone while the
  pointer is over it or for three seconds after you scroll it.
- Point at a tune to play it now, play it again if it already played, share
  it or scrap it.
- New tunes are marked new; tunes kept for good have a star.
- Repeat all draws a new round at the end. Repeat off stops after the last
  tune and Play starts over. Repeat one plays the same tune again, and new
  tunes wait until the repeat ends.
- Shuffle, repeat and the volume are remembered between launches.

### Keeping tunes

- The newest 50 tunes of each genre are kept; older ones make way. The tune
  playing and the ones about to play are never removed, and files SwiftTunes
  did not make are never touched.
- Keep it for good, in a tune's share sheet, puts it beyond the newest-50
  rule.
- Scrap any tune and you can bring it back with Undo for ten seconds.

### Genres

- Nine genres to start with, each in its own colours: Lo-fi, Ambient,
  Synthwave, Deep house, Jazz, Classical, Downtempo, Post-rock and Acoustic.
- The genre chooser shows a tile per genre with how many tunes it keeps or
  what is playing. A click plays what is kept.
- Add, edit or delete genres. Each has a name, a prompt, variations (two are
  picked for each tune), a slowest and a fastest tempo, a Singing switch and
  four colours.
- Mistakes show under their field as you type, such as a name already taken
  or a tempo outside 30 to 300 BPM.
- Renaming a genre moves its folder with it. Deleting a genre keeps its
  tunes in their folder.
- Tunes get two-word names drawn from words that suit their genre.

### Singing

- Turn Singing on for a genre and its new tunes are sung, with words the
  model writes in English. Tunes already kept stay as they are.
- A sung tune shows "sung" next to its tempo and key. Lyrics opens its words
  under it, as written.
- Sing my words… asks for one tune sung with words you write, up to 2,000
  characters, with buttons to mark a verse, chorus, bridge or instrumental
  break and a name already suggested. It is made once, before the genre's
  next tune, even with the composer off.

### Files and sharing

- Tunes are saved as AAC at 256 kbit/s in .m4a files, in
  ~/Music/Tunes/<genre>, tagged with their name, genre, tempo and key.
  Sung tunes keep their words in the file.
- Each tune's share sheet shows its picture: drag the picture to drop the
  tune anywhere.
- From the share sheet: share it through Mail, Messages, AirDrop and the
  rest, copy its path, show it in Finder, or export a copy to
  ~/Music/Tunes/Exports.

### On the Mac

- The tune shows in Now Playing with its picture, and the media keys play,
  pause, skip, go back and seek.
- The menu bar icon moves and shows the genre's name while a tune plays, and
  carries a coloured dot while the model downloads or the composer works,
  waits or has failed.
- Start at Login, in the menu, is off until you turn it on. The menu also
  shows the version.
- Liquid Glass throughout, over a slowly drifting field of the genre's
  colours, in light and dark. The field holds still in Low Power Mode;
  with Reduce Motion nothing moves, and nothing moves while the popover is
  closed.
- Quitting stops the composer and leaves nothing running.
