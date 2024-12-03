# Image Reading

This is a little project I'm doing to learn what the PNG file format looks like, as well as to learn Zig, because I find it kinda neat. The PNG spec is in the `res` directory.

## Status

At the moment, I am able to extract the raw image data from a grayscale PNG file, and put it into a matrix of bytes. Then, with Raylib, I am able to draw a bunch of rectangles with those byte values to display the image.

## Usage (Unix-like)

Download and install [Raylib](https://github.com/raysan5/raylib). Ensure that the header and library files are available. Once this is done, just do:

```
zig build run
```

## TODO

- Allow for colors of any type, RGB, RGBA, etc. This corresponds to choices other than 0 (grayscale) for the 10th bit in the header chunk. This also goes along with the 9th bit corresponding to the bit depth. The other bits don't matter quite as much so I won't worry about them yet.
- Do this with glfw rather than Raylib. There is no performance reason for this, I just want to get more familiar with glfw, and this would be a decent way, perhaps.
- Add support for Windows. See [Windows](#windows).



## Windows

Presumably, by providing x86_64 binaries in the `./deps` folder, building on Windows should work fine. I am able to link with the library file(s), but I can't get Zig to find the header file for some reason. In principle there should be something like `addLibraryPath()` like in `build.zig`, but I haven't been able to find something for it yet. And passing a relative file path inside the `@cInclude` doesn't seem to work.


## Current Commit

Putting this here for this commit and this commit only (assuming I remember to delete it later!) The reason for this is that I've already made a ton of changes, so I want to go ahead and commit/save those before starting on more.

The next big overhaul I'm going to make in the pursuit of readability and nice structure is to make the user create the file handle to the png file, then they can pass that handle into the `PNGFile`'s init function. That way, I don't have to bother with my own Reader stuff and can just use the file reader. Then, I'll do all the parsing there.

Currently, well, it's a mess!
