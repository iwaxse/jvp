# JVP Event Catalog & Data Specs

Yo! Since JVP is a fully event-driven video player, events are flying around like crazy between Dart, Swift, and Rust. Here is the breakdown of the dope events we use to keep everything in sync! 🎧🔥


## 1. Native to Dart Hotline (Swift ➔ Flutter MethodChannel)

These events are dispatched directly from native macOS land to Flutter's MethodChannel.

### `ptsChanged`
* **Triggered by**: `JvpTexture.swift` inside the `CVDisplayLink` frame rendering loop.
* **Payload**: `Double` (The current Presentation Timestamp, a.k.a. PTS, in seconds).
* **Vibe**: Tells the UI exactly where the playback head is, so the slider moves smoothly.

### `completed`
* **Triggered by**: `JvpTexture.swift` when `isCompleted()` turns `true` at the end of the video.
* **Payload**: `nil` (Just a heads-up that we hit the finish line).
* **Vibe**: Triggers either a rewind & loop restart, or halts the playback loop. Managed by a lock flag (`hasPostedCompleted`) to avoid event spam.


## 2. Shared Event Stream (Dart 合流 Stream)

All player state updates get unified in `VideoRepositoryImpl` and piped into `playerEventStream` as JSON strings.

### `{"type": "metadata", "data": { ... }}`
* **Fields**: `width` (Int), `height` (Int), `duration_secs` (Double), `frame_rate` (Double)
* **Vibe**: Broadcasts video dimensions and duration when a file is freshly loaded.

### `{"type": "frame", "data": { "pts_sec": X.XX }}`
* **Fields**: `pts_sec` (Double)
* **Vibe**: Pushes the current playback position. Born from the `ptsChanged` MethodChannel event.

### `{"type": "completed", "data": {}}`
* **Fields**: None
* **Vibe**: Triggers the ViewModel to handle loop resetting.

### `{"type": "playingState", "data": true/false}`
* **Fields**: `Boolean`
* **Vibe**: Signals whether the video is actively playing or paused.

### `{"type": "renderFps", "data": { "fps": XX.XX }}`
* **Fields**: `fps` (Double)
* **Vibe**: Dispatched by Rust to show the real-time render performance on screen.


## 3. App Event Bus (Dart Internal Messaging)

Used inside the Flutter application to notify the ViewModels and trigger UI changes without direct coupling.

### `VideoLoadedEvent`
* **Carries**: `textureId`, `width`, `height`, `durationSecs`
* **Vibe**: Tells the UI that the video is ready to be painted.

### `PlaybackPositionEvent`
* **Carries**: `position` (Double)
* **Vibe**: Keeps the slider thumb and time labels moving.

### `PlaybackStateEvent`
* **Carries**: `isPlaying` (Boolean)
* **Vibe**: Switches the play/pause button icon.

### `LoopingStateEvent`
* **Carries**: `isLooping` (Boolean)
* **Vibe**: Controls whether the video loops back on completion.

### `ScrubbingStateEvent`
* **Carries**: `isScrubbing` (Boolean), `wasPlayingBeforeScrub` (Boolean)
* **Vibe**: Locks/unlocks the time updates while the user is actively dragging the slider.


Keep this list handy when debugging state sync or adding new playback controls! Peace! ✌️😎
