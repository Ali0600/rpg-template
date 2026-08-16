# Audio

Drop `.ogg`, `.wav` or `.mp3` files here and they become playable by name — a file called
`footstep.ogg` is `AudioBus.play_sfx(&"footstep")`, with no code change anywhere.

The template ships no audio: sound is one of the things a game brings, and a placeholder
beep committed to a template is a placeholder beep shipped in somebody's game. What the
template does provide is the seam — every system asks for sounds by name from the start, so
turning audio on is a matter of adding files rather than of finding every place that should
have made a noise.

An id with no file behind it warns once and carries on.
