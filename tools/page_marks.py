"""Three printable exhibition page marks and a rotation-aware local decoder."""
from pathlib import Path
CODES=("1001011001011011","0111100010010011","0001110111000010")

def rotations(code):
    grid=[list(code[r:r+4]) for r in range(0,16,4)]
    for _ in range(4):
        yield "".join("".join(row) for row in grid)
        grid=[list(row) for row in zip(*grid[::-1])]

def decode(cells):
    if len(cells)!=6 or any(len(r)!=6 for r in cells):return None
    if any(cells[y][x] for y in range(6) for x in range(6) if y in (0,5) or x in (0,5)):return None
    bits="".join(str(int(bool(cells[y][x]))) for y in range(1,5) for x in range(1,5))
    results=sorted((min(sum(a!=b for a,b in zip(bits,k)) for k in rotations(code)),i+1) for i,code in enumerate(CODES))
    return results[0][1] if results[0][0]<=1 and results[0][0]<results[1][0] else None

def markers(gray,cv,np):
    _,binary=cv.threshold(gray,0,255,cv.THRESH_BINARY_INV|cv.THRESH_OTSU)
    contours=cv.findContours(binary,cv.RETR_LIST,cv.CHAIN_APPROX_SIMPLE)[0]
    found=set()
    for contour in contours:
        if cv.contourArea(contour)<500:continue
        shape=cv.approxPolyDP(contour,0.035*cv.arcLength(contour,True),True)
        if len(shape)!=4 or not cv.isContourConvex(shape):continue
        pts=shape.reshape(4,2).astype("float32")
        # Contour order is cyclic; the decoder checks all four rotations.
        if cv.contourArea(pts,oriented=True)<0:pts=pts[::-1].copy()
        target=np.float32([[0,0],[59,0],[59,59],[0,59]])
        patch=cv.warpPerspective(gray,cv.getPerspectiveTransform(pts,target),(60,60))
        _,patch=cv.threshold(patch,0,255,cv.THRESH_BINARY|cv.THRESH_OTSU)
        cells=[[int(patch[y*10+3:y*10+7,x*10+3:x*10+7].mean()>127) for x in range(6)] for y in range(6)]
        page=decode(cells)
        if page:found.add(page)
    return next(iter(found)) if len(found)==1 else None

def sheet(path):
    rects=[]
    for i,code in enumerate(CODES):
        x0,y0=25+i*190,34
        rects.append(f'<rect x="{x0}" y="{y0}" width="144" height="144" fill="black"/>')
        for j,bit in enumerate(code):
            if bit=="1":rects.append(f'<rect x="{x0+(j%4+1)*24}" y="{y0+(j//4+1)*24}" width="24" height="24" fill="white"/>')
        rects.append(f'<text x="{x0+72}" y="210" text-anchor="middle" font-family="sans-serif" font-size="15">Page {i+1}</text>')
    Path(path).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="84mm" viewBox="0 0 598 240"><rect width="598" height="240" fill="white"/>'+"".join(rects)+'</svg>',encoding="utf8")
if __name__=="__main__":
    import sys
    sheet(sys.argv[1])
