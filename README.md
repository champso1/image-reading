# Image Reading

This is a little project I'm doing to learn what the PNG file format looks like, as well as to learn Zig, because I find it kinda neat. Unfortunately, Zig being in a 0.xx state and not a 1.xx state means that API changes are not only frequent but also massively breaking. For instance, 0.15.1 (which this project now supports) completely reworked Readers and Writers, meaning I had to change around quite a lot. Another example is the removal of the  `pub usingnamespace` feature some time ago. The latter I think is definitely good, and the former so far is fine, but it takes time. I don't know how often this project will be updated until a 1.0 release because of this.

## Status

At the moment, I am able to extract the raw data from a grayscale PNG and an 8-bit RGB image, then display that data to the screen using Raylib.

## Usage (Unix-like)

Raylib is no longer required to manually install. Just run

```
zig build run -- <path-to-png>
```

and it will compile project and open the image with raylib. The path to the png file is relative to `build.zig`.

## TODO

- [x] Display a grayscale image.
- [x] Display an image with a color type of 2, corresponding to an RGB image.
- [X] Implement the Paeth Predictor for a scanline filter-byte of 4.
- [ ] Move rendering to glfw/opengl.
- [ ] Display images with a color depth of something other than 8.

## Future Plans

At some point, I want to be able to have some sort of interface where the user could choose to open/display a png file on the disk, or draw something on the screen and save that as a png file to the disk. At some point as well maybe I'd like to add support for other image formats like jpeg, but I want to focus on just png's at the moment.

I have a repository called [CHlib](https://github.com/champso1/CHlib) which is the beginnings of a super simple OpenGL rendering engine. Some time soon it will be ready to render a grid of some kind on a screen, at which point I'll integrate it into this project and drop Raylib alltogether.

## Windows

I haven't tested this on Windows but now that raylib is pulled dynamically and built on the system it should work just fine.
