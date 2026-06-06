# JVP (Jamy-chan Video Player) Conceptual Architecture

Yo! This is the spec sheet explaining how JVP does its magic behind the scenes. No boring tech jargon here, just pure vibes and straight-up logic. 🚀✨


## 🎭 The Trio (3-Tier Architecture)

JVP is built on a sick tag-team of three totally different technologies. 

```
           ┌──────────────┐
           │ Flutter (UI) │ ── The Director (Big Boss)
           └──────────────┘
             ▲          ▲
             │          │ (The Bridges / Direct Hotlines)
             ▼          ▼
      ┌───────────┐   ┌──────────┐
      │   Swift   │ ─ │   Rust   │
      │  (Video)  │   │ (Shader) │
      └───────────┘   └──────────┘
           ▲            ▲
           └─────┬──────┘
            (Behind-the-scenes buddies)
```

1. **Flutter (Dart) ── "The Director (Big Boss)"**
   - Good at painting the UI (buttons, sliders, cute stuff) that you interact with.
   - Sucks at decoding heavy videos or doing hardcore graphics, so it delegates that stuff to the crew.
2. **Swift ── "The Video Specialist"**
   - Uses native macOS power to load video files, play audio, and handle hardware acceleration.
3. **Rust ── "The Shader Wizard"**
   - Flexes the GPU directly to apply crazy fast render effects (like vignette, sharpening, or vintage vibes) in real-time.


## 🎥 Video Pipeline (Zero-Copy Magic)

We don't copy heavy image data back and forth because that would slow things down like crazy. Instead, we use **"Zero-Copy"** to pass data directly on the GPU!

```
[Swift (AVPlayer)]  ── "Yo, I chopped out the current frame!"
       │
       ▼ (Passes only the memory pointer/address)
[Rust (Renderer)]   ── "Got it, overlaying effects on this frame right now!"
       │
       ▼ (Draws directly onto Flutter's texture frame)
[Flutter (Screen)]  ── "Boom! The vintage-filtered video is on your screen!"
```


## ⏱️ How Time & Loops Flow (Our Latest Update)

Instead of Flutter constantly asking "Are we there yet?", Swift now holds the master timer (`CVDisplayLink`) and tells Flutter exactly what's up.

### ① The Time Slider Flow
```
[Swift (AVPlayer)]  ── "Yo, just rendered frame at X.XX seconds!"
       │
       ▼ (NotificationCenter)
[MainFlutterWindow]  ── "Notifying Flutter via MethodChannel hotline!"
       │
       ▼ (Merged Stream)
[Dart Repository]   ── "Received PTS, pushing to the event stream!"
       │
       ▼
[ViewModel]         ── "Updating currentPosSecs and triggering notifyListeners!"
       │
       ▼
[_TimeSlider (UI)]  ── "Moving the slider thumb smoothly to the right spot!"
```

### ② The Looping Flow (ON/OFF Control)
To prevent event spamming, we use a lock flag (`hasPostedCompleted`) so completion only fires once per loop cycle.

- **When the video hits the end**:
  - Swift: "Done!" (sends a single `JvpPlayerCompleted` notification).
- **If Looping is ON**:
  - Flutter: "Sweet, rewind to 0.0 and play it again!"
  - Swift: "You got it!" (Seeks to zero and plays).
- **If Looping is OFF**:
  - Flutter: "Stop playing and rewind to 0.0 for standby."
  - Swift: "Stopping and sitting at 0.0." (Stops the render loop and waits).


And that's how JVP keeps things clean, fast, and buttery smooth! Flutter calls the shots, Swift handles the files, and Rust does the math. Pretty cool, right? 💖
