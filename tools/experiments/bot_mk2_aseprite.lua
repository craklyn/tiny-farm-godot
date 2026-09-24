-- Comparison specimen for docs/design/spritesmith.md. NOT RUN: Aseprite is
-- unavailable in this workspace. Source and output are passed by --script-param.
-- This remaps exact RGBA values in a loaded PNG; a later indexed .aseprite
-- project would have to assign stable palette indices for these four colours.

local source = app.params.source
local output = app.params.output
assert(source and output, "pass --script-param source=... and output=...")
local sprite = assert(Sprite{ fromFile=source }, "cannot open source")
assert(#sprite.cels == 1, "expected one PNG cel")
local cel = sprite.cels[1]
local image = Image(cel.image)
local pc = app.pixelColor
local mapping = {
  [pc.rgba(92, 78, 146, 255)] = pc.rgba(146, 67, 72, 255),
  [pc.rgba(113, 99, 137, 255)] = pc.rgba(137, 93, 95, 255),
  [pc.rgba(63, 63, 77, 255)] = pc.rgba(77, 60, 61, 255),
  [pc.rgba(79, 78, 93, 255)] = pc.rgba(93, 75, 76, 255),
}
for y = 0, image.height - 1 do
  for x = 0, image.width - 1 do
    local pixel = image:getPixel(x, y)
    local replacement = mapping[pixel]
    if replacement then image:putPixel(x, y, replacement) end
  end
end
cel.image = image
sprite:saveCopyAs(output)
