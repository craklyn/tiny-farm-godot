from PIL import Image
import sys
S = sys.argv[1]
chars = Image.open("assets/sprites/generated/characters.png").convert("RGBA")
G = chars.crop((0, 0, 48, 48)).crop((16, 21, 32, 46))    # 16x25

C = {k: v for k, v in zip("abcdefghij", [
    (92,78,146),(144,98,93),(148,55,31),(191,90,58),(203,161,60),
    (229,184,152),(239,145,182),(240,207,90),(246,221,196),(248,244,230)])}

def defiant(src):
    """Her own pixels, re-posed: elbows out, hands on hips, stance widened.
    Nothing is invented — every colour is one already in her sheet."""
    im = src.copy(); p = im.load()
    def s(x, y, k):
        if 0 <= x < 16 and 0 <= y < 25: p[x, y] = C[k] + (255,)
    def clr(x, y):
        if 0 <= x < 16 and 0 <= y < 25: p[x, y] = (0, 0, 0, 0)

    # lift the old hanging arms off the torso edge
    for y in range(14, 19):
        for x in (2, 3, 11, 12):
            if p[x, y][3] and p[x, y][:3] in (C['j'], C['i'], C['f']):
                clr(x, y)

    # her right arm: shoulder -> elbow out -> hand back in at the waist
    s(3, 14, 'j'); s(2, 15, 'j'); s(1, 16, 'j'); s(2, 17, 'f'); s(3, 18, 'f')
    s(2, 16, 'i')
    # her left arm, mirrored
    s(12, 14, 'j'); s(13, 15, 'j'); s(14, 16, 'j'); s(13, 17, 'f'); s(12, 18, 'f')
    s(13, 16, 'i')

    # chin up: one pixel of shadow under the jaw so the head reads as tilted back
    s(6, 12, 'c'); s(9, 12, 'c')
    return im

D = defiant(G)
D.save(S + "/girl_defiant.png")
cmp = Image.new("RGBA", (16 * 2 + 4, 25), (33, 31, 32, 255))
cmp.paste(G, (0, 0), G); cmp.paste(D, (20, 0), D)
cmp.resize(((16 * 2 + 4) * 10, 250), Image.NEAREST).save(S + "/pose_compare.png")
print("colours:", len({c[1][:3] for c in D.getcolors(4096) if c[1][3] == 255}))
