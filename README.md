# Image Reading

This is a little project I'm doing to learn what the PNG file format looks like, as well as to learn Zig, because I find it kinda neat.

## Status

At the moment, I am able to extract the raw data from a grayscale PNG and an 8-bit RGB image, then display that data to the screen using Raylib.

## Usage (Unix-like)

Download and install [Raylib](https://github.com/raysan5/raylib). Ensure that the header and library files are available to the system. Once this is done, just do:

```
zig build run
```

Maybe since I provide binaries for Windows already I can do the same for Linux as well, and maybe give the option to use those or user-provided ones.

## TODO

- [x] Display a grayscale image.
- [x] Display an image with a color type of 2, corresponding to an RGB image.
- [X] Implement the Paeth Predictor for a scanline filter-byte of 4.
- [ ] Move rendering to glfw/opengl.
- [ ] Display images with a color depth of something other than 8.

## Future Plans

At some point, I want to be able to have some sort of interface where the user could choose to open/display a png file on the disk, or draw something on the screen and save that as a png file to the disk. At some point as well maybe I'd like to add support for other image formats like jpeg, but I want to focus on just png's at the moment.

## Windows

I have packaged prebuilt binaries for windows in the `deps` folder. In principle Windows users shouldn't have to do anything, assuming you are running a moderately recent version of Windows 11. If it doesn't work, then download and build Raylib yourself, and add the library and include paths to `build.zig`.
