# LumenPass icon assets

The .deb build pipeline expects PNG icons at the following sizes inside this
directory:

```
linux/packaging/assets/icons/16x16/lumenpass.png
linux/packaging/assets/icons/32x32/lumenpass.png
linux/packaging/assets/icons/48x48/lumenpass.png
linux/packaging/assets/icons/64x64/lumenpass.png
linux/packaging/assets/icons/128x128/lumenpass.png
linux/packaging/assets/icons/256x256/lumenpass.png
linux/packaging/assets/icons/512x512/lumenpass.png
```

The build script `scripts/build-deb.sh` will populate them automatically by
resizing `linux/packaging/assets/icons/source/lumenpass.png` (the high
resolution master icon) using either `convert` (ImageMagick) or `rsvg-convert`
when an SVG master is provided.

To rotate the icon set, replace `source/lumenpass.png` (recommended size:
1024x1024) and re-run the build. The previously generated PNGs will be
regenerated.
