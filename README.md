# Space Harrier GS

This is based on the source code of the FTA Space Harrier demo. Most of the code is re-used but the purpose here is to make a proper port of Space Harrier for the Apple IIGS, with levels, bosses, music and sound. 

The program is now a GS/OS program and should work on a ROM 3 Apple IIGS, which the original demo did not support.

## Development

I've been using Claude Code to build up the program using the FTA implementation as a reference. I'm not an experienced assembly language programmer and I'm defering a lot of the heavy lifting to Claude.

I have no idea how to implement sound yet, nor anything about composing/porting the music to the GS.

## Building

### macOS

The cadius and Merlin32 binaries are in the repo. Run:

```
./build.sh
```

A disk image called `SpaceHarrier.2mg` will be created. Use your preferred emulator or mount the disk on a real IIGS, and run System 6, and run the SpaceHarrier program on the disk.
