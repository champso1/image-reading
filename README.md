# Image Reading

This is a little project I'm doing to learn what the PNG file format looks like, as well as to learn Zig, because I find it kinda neat. The PNG spec is in the `res` directory.

## Status

At the moment, I am able to extract the raw image data from a grayscale PNG file, and put it into a matrix of bytes. Then, with Raylib, I am able to draw a bunch of rectangles with those byte values to display the image.

## Usage

Download and install [Raylib](https://github.com/raysan5/raylib). Once this is done, just do:

```
zig build run
```

## TODO

- Allow for colors of any type, RGB, RGBA, etc. This corresponds to choices other than 0 (grayscale) for the 10th bit in the header chunk. This also goes along with the 9th bit corresponding to the bit depth. The other bits don't matter much so I won't worry about them yet.
- Do this with glfw rather than Raylib. There is no performance reason for this, I just want to get more familiar with glfw, and this would be a decent way, perhaps.
