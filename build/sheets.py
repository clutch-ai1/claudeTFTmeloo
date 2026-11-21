"""Schneidet die Screenshots in sheets/ in einzelne Icons.
units.png: kompletter Unit-Pool, sortiert nach Kosten, dann Name (wie im Planer / bei MetaTFT).
items.png: Item-Liste mit den Gruppen Tank, Utility, Flex, AD+AP, Mana+Fighter, Components."""
import os, numpy as np
from PIL import Image

ITEM_SHEET=["Protector's Vow","Steadfast Heart","Gargoyle Stoneplate","Bramble Vest","Spirit Visage","Warmog's Armor","Crownguard","Dragon's Claw",
"Sunfire Cape","Morellonomicon","Ionic Spark","Evenshroud","Last Whisper","Red Buff","Hextech Gunblade","Striker's Flail","Guinsoo's Rageblade","Giant Slayer","Thief's Gloves","Hand of Justice",
"Infinity Edge","Deathblade","Kraken's Fury","Archangel's Staff","Rabadon's Deathcap","Void Staff","Nashor's Tooth","Jeweled Gauntlet","Blue Buff","Adaptive Helm","Spear of Shojin","Bloodthirster","Sterak's Gage","Edge of Night","Quicksilver","Titan's Resolve",
"B.F. Sword","Recurve Bow","Needlessly Large Rod","Tear of the Goddess","Chain Vest","Negatron Cloak","Giant's Belt","Spatula","Sparring Gloves","Frying Pan"]

def slug(n): return ''.join(ch for ch in n.lower() if ch.isalnum())

def _runs(prof,th,minlen):
    r=[];s=None
    for i,v in enumerate(list(prof)+[0]):
        if v>th and s is None: s=i
        if v<=th and s is not None:
            if i-s>=minlen: r.append((s,i))
            s=None
    return r

def _load(path,thr):
    img=Image.open(path).convert('RGB');im=np.asarray(img).astype(int)
    edge=np.concatenate([im[0],im[-1],im[:,0],im[:,-1]]);bg=np.median(edge,axis=0)
    return img,im,(np.abs(im-bg).sum(2)>thr)

def unit_cells(path):
    img,im,m=_load(path,60);H,W,_=im.shape
    rp=m.mean(1);rows=_runs(rp,rp.max()*0.45,8)
    y0,y1=rows[0];S=y1-y0;py=rows[1][0]-rows[0][0]
    cp=m[y0:y1].mean(0)
    xs=[a for a,b in _runs(cp,0.6,int(S*0.5)) if abs((b-a)-S)<=max(3,S*0.08)]
    d=np.diff(xs);px=int(np.median(d[d<S*2]));x0=xs[0]%px
    cells=[];y=y0
    while y+S<=H:
        x=x0
        while x+S<=W:
            if m[y:y+S,x:x+S].mean()>0.25: cells.append((x,y))
            x+=px
        y+=py
    return img,cells,S

def item_cells(path):
    img,im,m=_load(path,35);H,W,_=im.shape
    rp=m.mean(1);rows=_runs(rp,rp.max()*0.3,10)
    S=int(np.median([b-a for a,b in rows]))
    starts=[]
    for y0,y1 in rows:
        if abs((y1-y0)-S)>S*0.2: continue
        cp=m[y0:y1].mean(0)
        starts+=[a for a,b in _runs(cp,0.5,int(S*.5)) if abs(b-a-S)<=S*0.12]
    starts=sorted(set(starts));d=np.diff(starts);d=d[(d>S*0.9)&(d<S*1.8)]
    px=float(np.median(d));x0=float(min(starts))
    while x0-px>=0: x0-=px
    boxes=[];x=x0
    while x+S<=W:
        cx=int(round(x));vp=m[:,cx+2:cx+S-2].mean(1)
        for a,b in _runs(vp,0.4,int(S*0.7)):
            if b-a<=S*1.3: boxes.append((cx,max(0,(a+b)//2-S//2)))
        x+=px
    boxes.sort(key=lambda t:(t[1],t[0]));rows_=[]
    for b in boxes:
        if rows_ and abs(rows_[-1][0][1]-b[1])<S*0.5: rows_[-1].append(b)
        else: rows_.append([b])
    return img,[b for r in rows_ for b in sorted(r)],S

def _save(img,cells,S,names,outdir,prefix):
    os.makedirs(outdir,exist_ok=True);ins=max(1,round(S*0.05));out={}
    for (x,y),n in zip(cells,names):
        if not n: continue
        crop=img.crop((x+ins,y+ins,x+S-ins,y+S-ins))
        fn=slug(n)+'.png';crop.save(os.path.join(outdir,fn),optimize=True);out[n]=prefix+fn
    return out

def build_icons(sheets_dir,docs_dir,unit_order):
    """unit_order: Unit-Namen sortiert nach Kosten, dann Name. Gibt (units_map, items_map) zurueck."""
    um,imap={},{}
    up=os.path.join(sheets_dir,'units.png')
    if os.path.exists(up):
        try:
            img,cells,S=unit_cells(up);order=list(unit_order)
            if len(cells)==len(order)+1:  # Golem o. ae. nach dem letzten 5-Coster
                last5=max(i for i,n in enumerate(order) if n[1]==5);order=order[:last5+1]+[None]+order[last5+1:]
            if len(cells)==len(order): um=_save(img,cells,S,[o[0] if o else None for o in order],os.path.join(docs_dir,'icons','units'),'icons/units/')
            else: print(f'Unit-Screenshot: {len(cells)} Icons erkannt, erwartet {len(order)}. Uebersprungen.')
        except Exception as e: print('Unit-Screenshot fehlgeschlagen:',e)
    ip=os.path.join(sheets_dir,'items.png')
    if os.path.exists(ip):
        try:
            img,cells,S=item_cells(ip)
            if len(cells)==len(ITEM_SHEET): imap=_save(img,cells,S,ITEM_SHEET,os.path.join(docs_dir,'icons','items'),'icons/items/')
            else: print(f'Item-Screenshot: {len(cells)} Icons erkannt, erwartet {len(ITEM_SHEET)}. Uebersprungen.')
        except Exception as e: print('Item-Screenshot fehlgeschlagen:',e)
    return um,imap
