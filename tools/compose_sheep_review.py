#!/usr/bin/env python3
"""Matched sheep review: viewport pixels only, cropped at 3x or reduced to native.

Capture with tools/capture_sheep_review.tscn in a 540x540 window. No art is
painted onto the sheep; labels sit outside the untouched real-game captures.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse
parser=argparse.ArgumentParser(description="Compose matched real-game sheep review captures")
parser.add_argument("before", type=Path)
parser.add_argument("after", type=Path)
parser.add_argument("--out", type=Path, required=True)
a=parser.parse_args()
root=a.out
root.mkdir(parents=True, exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
names=['Cream, light face','Cream, black face','Cream, brown face','Brown fleece','Black fleece','Grey fleece','Spotted, horns','Cream, horns']
box=(180,294,372,444)
def crop(kind,look,pose):
 return Image.open((a.before if kind == 'old' else a.after)/f'look_{look}_{pose}.png').convert('RGB').crop(box)
sheet=Image.new('RGB',(424,8*180+42),'#272a30');d=ImageDraw.Draw(sheet)
d.text((16,12),'Before',font=font,fill='white');d.text((226,12),'After',font=font,fill='white')
for i,name in enumerate(names):
 y=42+i*180;d.text((14,y),name,font=font,fill='white')
 sheet.paste(crop('old',i,'lick'),(12,y+23));sheet.paste(crop('new',i,'lick'),(222,y+23))
sheet.save(root/'all-eight-before-after.png')
native=Image.new('RGB',(260,8*80+30),'#272a30');d=ImageDraw.Draw(native)
d.text((10,8),'Before                After',font=font,fill='white')
for i,name in enumerate(names):
 y=30+i*80;d.text((8,y),name,font=font,fill='white')
 for j,kind in enumerate(['old','new']):
  native.paste(crop(kind,i,'lick').resize((64,50),Image.Resampling.NEAREST),(25+125*j,y+22))
native.save(root/'all-eight-native.png')
frames=[]
for f in range(36):
 im=Image.new('RGB',(4*204,2*180),'#272a30');d=ImageDraw.Draw(im)
 for i,name in enumerate(names):
  x=(i%4)*204;y=(i//4)*180
  d.text((x+6,y+4),name,font=font,fill='white')
  im.paste(crop('new',i,f'motion_{f:03d}'),(x+6,y+24))
 frames.append(im)
frames[0].save(root/'all-eight-new.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,optimize=False)
# A contact strip of the whole beat, including the smug ending, for each look.
beat=Image.new('RGB',(4*204,8*180+28),'#272a30');d=ImageDraw.Draw(beat)
for j,label in enumerate(['Reach','Stretch','Lick','Smug']):d.text((j*204+6,4),label,font=font,fill='white')
for i,name in enumerate(names):
 for j,pose in enumerate(['reach','stretch','lick','smug']):
  y=28+i*180;d.text((j*204+6,y),name,font=font,fill='white');beat.paste(crop('new',i,pose),(j*204+6,y+24))
beat.save(root/'gags_stretch_frames.png')
print('Review sheets and loop written under',root)
