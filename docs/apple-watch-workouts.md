# Apple Watch workout companion

Future exploration, recorded November 19, 2026. No watchOS target, HealthKit access, microphone recording, or new simulator is included in the current app.

The idea is a MyPIU workout that tracks a Pump It Up visit, identifies play and rest intervals, and eventually associates songs with those intervals. A typical three-song round should be convenient, while shorter rounds, extra stages, retries, and breaks remain possible. Low battery use matters more than automatic recognition.

## First useful version

Start with an explicit **Start workout**, **Mark song**, **Rest**, and **Finish** flow on Apple Watch. Record elapsed time, heart rate and available energy estimates, save a HealthKit workout, and show a summary in MyPIU. Keep uncertain song matches editable and allow the workout to work offline without song recognition.

A watchOS app using `HKWorkoutSession` and a live workout builder is a feasible starting point. Apple permits active workout sessions to continue in the background; excessive background CPU work can still cause suspension. The user should start and stop the workout deliberately. Only one workout session can be active on Apple Watch, so handle an Apple Workout or another fitness app taking over. This is a proposed design, not device-tested functionality. [Workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions), [HKWorkoutSession](https://developer.apple.com/documentation/healthkit/hkworkoutsession).

Evaluate the existing `fitnessGaming` activity with an indoor configuration. Apple defines that activity for fitness video games. MyPIU can name its own workout experience; do not assume this registers a new system-wide “Pump It Up” activity type. Validate how saved workouts appear in Fitness on a real watch. [Fitness gaming](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/fitnessgaming).

## Automatic intervals and song recognition

| Candidate | Useful experiment | Main uncertainty |
| --- | --- | --- |
| Motion-assisted play/rest | Compare short accelerometer windows with manually marked intervals. | Holding the bar can make wrist movement small during intense play; walking and gestures can look active during rest. |
| Song identification | Try short, user-started ShazamKit samples against representative cabinet audio. | Arcade mixes, short cuts, speed changes, nearby cabinets and menu audio may differ from a commercial recording. |
| Custom audio signatures | Test a small, verified set of exact game cuts and metadata. | Catalog coverage, matching quality, storage, and sourcing suitable reference audio need investigation. |
| Combined suggestion | Use motion and a song match to suggest an interval, with manual correction. | Recognizing a cabinet's song does not establish who played it or which chart they selected. |

Core Motion offers configurable sensor intervals and explicit stop methods. Begin with a low sampling rate and measure accuracy before adding gyroscope work or more frequent processing. Treat the three-song pattern as a suggestion, never a fixed session boundary. [CMMotionManager](https://developer.apple.com/documentation/coremotion/cmmotionmanager).

ShazamKit supports watchOS and both Shazam and custom catalogs. Its result can identify a point within a reference recording, but that alone does not prove the beginning or end of the user's play interval. Custom catalogs store signatures and associated metadata. Confirm the exact APIs' watchOS availability and microphone behavior during a background workout in a small device prototype. [ShazamKit](https://developer.apple.com/documentation/shazamkit), [Custom catalogs](https://developer.apple.com/documentation/shazamkit/shcustomcatalog).

Recognition should be opt-in and brief, with bounded retries and the microphone stopped promptly. Prefer on-device processing where practical; do not retain raw microphone recordings by default. Keep health data local unless a separately explained sync feature is chosen. Apple's guidance explicitly recommends stopping microphone capture as soon as enough audio has been collected. [ShazamKit interface guidance](https://developer.apple.com/design/human-interface-guidelines/shazamkit).

## Integration with Apple's Workout app

WorkoutKit is a separate possibility for publishing a planned round with work and recovery steps into Apple's Workout app. It supports workout compositions and authorized schedule syncing, including app branding. Check `supportsActivity(_:)` on supported OS versions before promising a fitness-gaming interval plan. A scheduled plan would not itself implement live song recognition or replace MyPIU's workout recording logic. [WorkoutKit](https://developer.apple.com/documentation/workoutkit), [Supported custom activities](https://developer.apple.com/documentation/workoutkit/customworkout/supportsactivity(_:)).

## Battery and feasibility gate

Do not promise a battery percentage before testing. Compare the following on the same physical watch, with matched duration, brightness, connectivity and starting charge:

1. Workout recording alone, with no GPS or extra sensors unless required.
2. The same workout with motion-assisted interval suggestions.
3. The same workout with a bounded number of short recognition attempts.

Use repeated sessions, including a 60–90 minute arcade visit, and measure battery change, CPU/energy profiles, recognition latency and success, false play/rest transitions, offline behavior, screen-down operation and interruptions. Record watch model, OS and battery health so results are interpretable. Compare against Apple's built-in fitness-gaming workout where available. The acceptance threshold should be chosen from these measurements with the owner before expanding the feature.

Implement the manual workout only after device qualification. Add automatic suggestions only if they improve the experience without unacceptable battery drain or frequent corrections. Keep this work behind current catalog, image, performance and device-installation fixes.
