# Codea-Docs

Craft was an update for Codea released back in 2016, since then various undocumented features were added but not all of them were properly documented. This repository serves as a hub for correcting that mistake, allowing contributors from [Codea-Talk](https://codea.io/talk/) who have been extremely patient and creative in figuring out what the heck some of these things do

Lets update the Codea documentation! I've included here the complete source for both the Codea documentation (written in YAML) and the Craft Lua bindings (`Source/Bindings/LuaBindings.mm`, written in Objective-C++ mostly using the LuaIntf library)

The `LuaBindings.mm` file contains all Craft API bindings available in Codea, and as much as I don't want to reveal how the sausage is made, here it is! The code is quite a mess so I apologise in advance

Feel free to ask me any questions about the API and I'll try to answer as best I can

## YAML documentation sources

The `Source/YAML` directory structure contains `.yaml` files for each of the main documentation categories. The formatting we use is as old as Codea, so some stuff will look a bit janky. I'll be accepting pull requests if anyone wants to make changes or add things. I'm not doing this to be lazy, I just find it difficult to keep everything up to date and I feel like this will help motivate me to do so

## List of Undocumented Types

[ ] `bounds`

A geometric utility type representing the rectangular bounding volume. Create a new bounds by giving it a minimum and maximum range as `vec3()`s

`b = bounds(min, max)`
`b = bounds(vec3(0, 0, 0), vec3(1, 1, 1))`

*Properties:*
- [ ] `min` vec3, the minimum x,y,z range of the area encapsulated by the bounding volume
- [ ] `max` vec3, the maximum x,y,z range of the area encapsulated by the bounding volume
- [ ] `valid` boolean, whether or not this bounds is valid (i.e. has zero or greater volume)
- [ ] `center` vec3, the center of the volume (i.e. half way between `min` and `max`)
- [ ] `offset` vec3, the offset of the volume (i.e. `min`)
- [ ] `size` vec3, the size of the volume (i.e. `max - min`)

*Methods:*
- [ ] `intersects(other)` boolean, checks to see if this bounding volume intersects another
- [ ] `intersects(origin, dir)` boolean, checks to see if this bounding is intersected by the given ray
- [ ] `encapsulate(point)` expands the bounds to include the given point
- [ ] `translate(offset)` moves the bounds by the given offset
- [ ] `set(min, max)` reset the bounds given new min and max values

---

[ ] `soundsource`

Created when calling the `sound()` command, represents a live sound currently playing. Can be controlled to alter the playing sound:

*Properties:*
- [ ] `volume` number, the current volume of the sound source
- [ ] `pitch` number, the current pitch of the sound source
- [ ] `pan` number, the 2D spatial location of the sound (-1 left, +1 right, 0 centre)
- [ ] `looping` boolean, whether to loop the sound when it reaches the end of playback
- [ ] `paused` boolean, whether the sound source is currently paused
- [ ] `muted` boolean, whether the sound source is currently muted

*Methods:*
- [ ] `stop()`
- [ ] `rewind()`
- [ ] `fadeTo(volume, duration)` animates the volume of the sound source over a time
- [ ] `stopFade()` cancels the current fading action
- [ ] `pitchTo()` animates the pitch of the sound source over time
- [ ] `stopPitch()` cancels the current pitch action
- [ ] `panTo()` animates the pan of the sound source over time
- [ ] `stopPan()` cancels the panning action
- [ ] `stopActions()` cancels all actions on the sound source
