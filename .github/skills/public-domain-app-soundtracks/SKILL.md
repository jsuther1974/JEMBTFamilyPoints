---
name: public-domain-app-soundtracks
description: Select public-domain music, create a newly produced performance with GarageBand, MainStage, or local rendering tools, document provenance, integrate audio resources, and verify the result.
---

# Public-domain app soundtracks

Use this skill when selecting, arranging, recording, replacing, or auditing music and sound effects for an app.

## Objective

Create a newly produced recording of a legally suitable composition instead of bundling a third-party recording. Preserve enough source, production, provenance, and verification information for another developer or agent to reproduce or replace it safely.

This workflow reduces copyright risk but is not legal advice. Escalate uncertain rights questions rather than assuming that old, freely downloadable, or uncredited material is reusable.

## Rights model

Treat these as separate rights questions:

1. **Composition** — melody, harmony, and lyrics.
2. **Source edition or arrangement** — sheet music, transcription, or MIDI used as production input.
3. **Sound recording** — the particular recorded performance.
4. **Production assets** — software instruments, Apple Loops, samples, impulse responses, and presets.

A public-domain composition does not make a modern recording, arrangement, MIDI transcription, or sample public domain.

Before production:

- Verify that the composition is public domain in every intended distribution territory, or obtain permission.
- Use a source edition/MIDI explicitly marked public domain or carrying a compatible license.
- Record/render a new performance; never copy audio from a commercial or historical recording unless its recording rights are independently cleared.
- Use GarageBand/MainStage instruments, loops, and samples only as permitted by their current license. Incorporate them into a musical work; do not redistribute isolated source assets.
- Do not rely only on a search result, upload age, filename, or “royalty-free” claim.
- Record the evidence and source URL in the project provenance document.

## Repository conventions

For this project:

- Provenance: `SOUNDTRACK_PROVENANCE.md`
- Retained source MIDI and source notes: `Tools/SoundtrackSources/`
- Reproducible fallback renderer: `Tools/render_soundtracks.swift`
- Render/encoding wrapper: `Tools/render_soundtracks.sh`
- Download preparation: `Tools/prepare_public_domain_music.py`
- Bundled app audio: `JEMBT Family Points Tracker/Audio/`
- Runtime audio ownership and scene behavior: `SoundscapeDirector.swift`

Preserve existing resource basenames when replacing a performance unless a code change is intentional. Stable names allow a GarageBand or MainStage bounce to replace an automated render without changing app logic.

## Workflow

### 1. Define the musical brief

Record:

- App scene and emotional purpose.
- Desired style, tempo, instrumentation, and intensity.
- Target duration and whether playback loops.
- Relationship to the other app soundtracks.
- Required transitions, stingers, or interaction effects.

Keep related rooms in one recognizable musical family while giving each room a distinct purpose.

### 2. Select and verify the composition

Prefer reputable public-domain libraries that state the status of each edition. Capture:

- Composition title.
- Composer and relevant dates.
- First-publication date when known.
- Source organization and direct source URL.
- Stated status/license for the exact edition or MIDI.
- Date accessed.
- Intended distribution territories or any unresolved uncertainty.

Retain the exact source file when its license permits redistribution. Otherwise retain metadata and reproducible retrieval instructions.

### 3. Produce a new performance

#### GarageBand

1. Start a new project and set the intended tempo, meter, and key.
2. Import the cleared MIDI or enter the public-domain score manually.
3. Assign licensed software instruments.
4. Create an original production by adjusting instrumentation, voicing, dynamics, articulation, phrasing, tempo, structure, and mix.
5. Avoid imitating a specific protected recording or copying its distinctive arrangement.
6. Add only production assets whose license permits use in a distributed musical work.
7. Preserve the GarageBand project or detailed production notes when practical.
8. Bounce a new mix rather than recording audio from another release.

#### MainStage

1. Build a concert/patch using licensed instruments and effects.
2. Import or perform the cleared MIDI/score.
3. Map articulations and expressive controls deliberately.
4. Record a fresh performance or route the performance to a DAW for editing and mixing.
5. Preserve the concert/patch notes and any non-default dependency requirements.
6. Export a clean new recording using the established app resource basename.

MainStage is especially useful for performance and orchestration; GarageBand is useful for arrangement, editing, mixing, and final bounce. They may be used together.

#### Reproducible local renderer

Use the repository renderer when a deterministic, dependency-light performance is preferred:

```bash
python3 Tools/prepare_public_domain_music.py
bash Tools/render_soundtracks.sh
```

The automated renderer is a fallback and reproducibility path, not a requirement to avoid richer GarageBand/MainStage performances.

### 4. Prepare the app asset

- Trim unintended silence while preserving musical pickup notes.
- Add short fades where needed to prevent clicks.
- For loops, audition the boundary repeatedly and avoid clipped reverberation tails.
- Export a lossless master before creating the app delivery file.
- Encode the app copy in a platform-supported format such as AAC/M4A.
- Preserve channel count, sample rate, duration, and target loudness notes.
- Avoid clipping and excessive loudness relative to effects, speech, and other rooms.
- Keep the app bundle size appropriate.

Do not overwrite the only lossless master with the compressed delivery file.

### 5. Document provenance and production

Update `SOUNDTRACK_PROVENANCE.md` in the same change as the audio replacement. Include:

- App scene/resource name.
- Composition and composer.
- Publication/public-domain basis.
- Exact source edition/MIDI and URL.
- Source license/status and access date.
- Confirmation that the bundled file is a newly produced recording.
- Production method: GarageBand, MainStage, local renderer, or combination.
- Instruments/assets used and any relevant license notes.
- Producer/performer and production date when appropriate.
- Export format and location of retained source/project files.

Recommended entry template:

```markdown
### <scene/resource>
- Composition: <title> — <composer> (<publication year>)
- Composition status: <public-domain basis/territories checked>
- Source edition/MIDI: <provider, URL, stated status/license, accessed date>
- Recording: Newly performed/rendered for this app; no third-party recording used
- Production: <GarageBand/MainStage/rendering workflow and instruments>
- Master/delivery: <master location>; <app resource path and format>
- Notes: <loop, duration, dependencies, unresolved concerns>
```

### 6. Integrate without breaking lifecycle behavior

- Confirm the resource is included in the intended target.
- Confirm `Bundle` lookup succeeds using the exact basename and extension.
- Preserve mute settings, scene ownership, interruption behavior, and scene-stack restoration.
- Ensure overlays return to the prior room soundtrack when dismissed.
- Keep effects and soundtrack volume balanced.
- Do not add an entitlement merely to play bundled audio.

### 7. Verify

At minimum:

1. Inspect format, duration, channel count, and sample rate with an Apple audio inspection tool.
2. Check every delivery file for clipping (for example, with `afclip`).
3. Audition the beginning, loop boundary, and ending with headphones and device speakers.
4. Build the affected app target.
5. Run soundtrack resource-mapping and lifecycle tests.
6. Launch the app and visit every affected scene.
7. Check logs for missing-resource, decoding, and AVFoundation errors.
8. Confirm sounds-off behavior and restoration after sheets/overlays.
9. Run `git diff --check` and ensure provenance/source files accompany the binary change.

For this project, retain tests that verify every musical scene maps to an existing bundled resource.

## Sound effects

Prefer newly synthesized effects, personally recorded effects, or assets with explicit app-distribution rights. Apply the same provenance separation to sample source and final recording. Do not assume that a familiar bell, register, scanner, typewriter, or crowd recording is safe because it is short.

## Stop conditions

Stop and request clarification or legal review when:

- Public-domain status varies by intended territory and distribution scope is unknown.
- The exact source edition/MIDI license cannot be established.
- A modern arrangement is the only available source.
- A GarageBand/MainStage dependency includes unclear third-party sample rights.
- The requested result imitates a particular protected recording rather than the underlying composition or genre.
- Provenance cannot be recorded accurately.

Never describe this workflow as a legal guarantee. Describe the result precisely as a newly produced recording based on a verified public-domain composition and cleared source materials.
