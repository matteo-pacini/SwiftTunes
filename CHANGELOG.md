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
  the menu. Pick a genre to start: nothing plays or composes by itself at
  launch.
- On first use, SwiftTunes downloads its music model once from Hugging Face:
  ACE-Step 1.5 Turbo with its 4B language model at Q8, four files, 7.57 GiB
  in all. The download shows its progress and speed,
  can be cancelled, picks up where it stopped, and every file is checked
  before it is used.
- Remove Music Model… in the menu deletes the model when you want the space
  back. Your tunes stay and keep playing.

### The composer

- Turn the composer on and it writes new tunes for the genre, about three
  minutes each, and keeps two ready ahead. A new tune plays next.
- Its bar says what it is doing. Being made shows the tune being written,
  with a bar and the time left; while nothing plays yet, the first tune's
  shape forms in the player and it starts by itself when it is ready.
- The model runs only while there is something to make and lets go of its
  memory when it rests. It waits by itself in Low Power Mode, while the Mac
  is running hot or while memory is under pressure, and carries on when that
  passes.
- A tune planned with a long silence in it is written again, and a silent
  ending is cut with a short fade.
- When making a tune fails, the bar says why and tries again by itself;
  Try now tries at once. Scrap the tune being made to stop it.

### The player

- The player shows the tune's name, tempo and key, its own picture in its
  genre's colours, and its shape as columns of dots that fill as it plays.
  Click or drag across the shape to jump.
- Controls: shuffle, repeat, Previous, play and pause, next, share and scrap,
  and a volume slider for SwiftTunes' own volume, not the Mac's.
- Click the playing tune's name to rename it.

### This round

- Every kept tune of the genre plays once a round, shuffled or in the order
  made. A new round never starts with the tune that ended the last one.
- This round lists the whole round: tunes already played, dimmed; the
  playing one, highlighted; then what waits. Point at a tune to play it now,
  share it or scrap it.
- Repeat all draws a new round at the end, Repeat off stops after the last
  tune, and Repeat one plays the same tune again. Previous goes back a tune
  within the first three seconds, and otherwise starts the tune again.
- Shuffle, repeat and the volume are remembered between launches.

### Keeping tunes

- The newest 50 tunes of each genre are kept; older ones make way, but never
  the tune playing or the ones about to play. Keep it for good, in a tune's
  share sheet, puts it beyond that rule.
- Scrap any tune and you can bring it back with Undo for ten seconds.
- Files SwiftTunes did not make are never touched.

### Genres

- Nine genres to start with, each in its own colours: Lo-fi, Ambient,
  Synthwave, Deep house, Jazz, Classical, Downtempo, Post-rock and Acoustic.
- Add, edit or delete genres: a name, a prompt, variations, a slowest and a
  fastest tempo, a Singing switch and four colours. Deleting a genre keeps
  its tunes.
- Tunes get two-word names drawn from words that suit their genre.

### Singing

- Turn Singing on for a genre and its new tunes are sung, with words the
  model writes in English. Lyrics shows a sung tune's words.
- Sing my words… makes one tune sung with words you write, up to 2,000
  characters, before the genre's next tune, even with the composer off.

### Files and sharing

- Tunes are saved as AAC at 256 kbit/s in .m4a files, in
  `~/Music/Tunes/<genre>`, tagged with their name, genre, tempo and key.
  Sung tunes keep their words in the file.
- From a tune's share sheet: share it through Mail, Messages, AirDrop and the
  rest, drag its picture to drop the tune anywhere, copy its path, show it in
  Finder, or export a copy to `~/Music/Tunes/Exports`.

### On the Mac

- The tune shows in Now Playing with its picture, and the media keys play,
  pause, skip, go back and seek.
- The menu bar icon moves and shows the genre's name while a tune plays, and
  carries a coloured dot while the model downloads or the composer works,
  waits or has failed.
- Start at Login, in the menu, is off until you turn it on.
- Liquid Glass throughout, over a slowly drifting field of the genre's
  colours, in light and dark. With Reduce Motion nothing moves.
- Quitting stops the composer and leaves nothing running.
