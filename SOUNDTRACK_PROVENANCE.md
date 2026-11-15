# Soundtrack provenance

The app's room soundtracks are newly generated performances of public-domain compositions. No third-party sound recording is bundled.

| App room | Composition | Composer | First published | Source edition/MIDI |
| --- | --- | --- | ---: | --- |
| Store | *The Entertainer* | Scott Joplin | 1902 | [Mutopia](https://www.mutopiaproject.org/ftp/JoplinS/entertainer/entertainer.mid) |
| Rules | *The Easy Winners* | Scott Joplin | 1901 | [Mutopia](https://www.mutopiaproject.org/ftp/JoplinS/winners/winners.mid) |
| Ledger | *Magnetic Rag* | Scott Joplin | 1914 | [Mutopia](https://www.mutopiaproject.org/ftp/JoplinS/magnetic/magnetic.mid) |
| Stats | *The Liberty Bell March* | John Philip Sousa | 1893 | [Mutopia](https://www.mutopiaproject.org/ftp/SousaJP/TheLibertyBell/TheLibertyBell.mid) |
| Family | *Maple Leaf Rag* | Scott Joplin | 1899 | [Mutopia](https://www.mutopiaproject.org/ftp/JoplinS/maple/maple.mid) |

Mutopia marks each listed source edition as **Public Domain**. The MIDI sources are retained in `Tools/SoundtrackSources` for reproducibility.

## Performance generation

The bundled performances were rendered locally from those MIDI sources with Apple's General MIDI/DLS software instrument, then encoded as AAC/M4A. They are not copies of historical or commercially released recordings.

Run the preparation and rendering tools from the repository root:

```bash
python3 Tools/prepare_public_domain_music.py
bash Tools/render_soundtracks.sh
```

GarageBand and MainStage can import the same MIDI files for future arrangement, performance, and re-orchestration. Export replacements with the existing resource names so no app-code changes are required. When producing a replacement, retain the GarageBand project, MainStage concert/patch details, or sufficient production notes to reproduce the recording, and record the production method here.

The reusable selection, rights-review, production, integration, and verification workflow is documented in `.github/skills/public-domain-app-soundtracks/SKILL.md`.

## Sound effects

Interaction effects in `SoundscapeDirector.swift` are synthesized by the app from mathematical waveforms and deterministic noise. They do not incorporate third-party samples.

This file records provenance for project maintenance and is not legal advice.
