#!/usr/bin/env python3
import struct,sys,zlib
W=H=512
pixels=bytearray(W*H*3)
def put(x,y,c):
 if 0<=x<W and 0<=y<H:
  i=(y*W+x)*3;pixels[i:i+3]=bytes(c)
for y in range(H):
 for x in range(W):
  v=8+int(7*(1-y/H));put(x,y,(v,v,v+4))
def line(x0,y0,x1,y1,c,width=12):
 dx,dy=abs(x1-x0),abs(y1-y0);sx=1 if x0<x1 else -1;sy=1 if y0<y1 else -1;err=dx-dy
 while True:
  for oy in range(-width//2,width//2+1):
   for ox in range(-width//2,width//2+1):put(x0+ox,y0+oy,c)
  if x0==x1 and y0==y1:break
  e2=2*err
  if e2>-dy:err-=dy;x0+=sx
  if e2<dx:err+=dx;y0+=sy
red=(225,28,63);white=(245,245,250)
for t in range(7):
 for p in range(28,484):put(p,28+t,red);put(p,483-t,red);put(28+t,p,red);put(483-t,p,red)
line(118,174,218,174,red,14);line(218,174,246,208,red,14);line(246,208,394,208,red,14);line(394,208,394,366,red,14);line(394,366,118,366,red,14);line(118,366,118,174,red,14)
line(190,286,244,332,white,20);line(244,332,330,250,white,20)
def chunk(tag,data):return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data)&0xffffffff)
raw=b"".join(b"\0"+bytes(pixels[y*W*3:(y+1)*W*3]) for y in range(H))
png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">2I5B",W,H,8,2,0,0,0))+chunk(b"IDAT",zlib.compress(raw,9))+chunk(b"IEND",b"")
with open(sys.argv[1],"wb") as f:f.write(png)
