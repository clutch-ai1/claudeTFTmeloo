#!/usr/bin/env python3
# Holt die aktuellen PBE-Daten von MetaTFT und baut index.html aus template.html neu.
# Aufruf: python3 update.py <arbeitsordner> <template.html> <ausgabe index.html>
import json,re,glob,os,sys,collections,datetime,urllib.request,concurrent.futures as cf
W=sys.argv[1];TPL=os.path.abspath(sys.argv[2]);OUT=os.path.abspath(sys.argv[3]);HIST=os.path.abspath(sys.argv[4]) if len(sys.argv)>4 else None
HERE=os.path.dirname(os.path.abspath(__file__))
SHEETS=os.path.abspath(os.environ['SHEETS']) if os.environ.get('SHEETS') else None
DOCS=os.path.abspath(os.environ['DOCS']) if os.environ.get('DOCS') else None
os.makedirs(W,exist_ok=True);os.chdir(W)
def dl(url,fn):
    req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
    data=urllib.request.urlopen(req,timeout=60).read();open(fn,'wb').write(data)
dl('https://data.metatft.com/lookups/TFTSet19_pbe_en_us.json','set19.json')
dl('https://api-hc.metatft.com/tft-comps-api/comps_data?queue=PBE','comps_data.json')
dl('https://api-hc.metatft.com/tft-comps-api/comps_stats?queue=PBE&patch=current&days=3&permit_filter_adjustment=true','comps_stats.json')
for f in glob.glob('cd_*.json'): os.remove(f)
ids=list(json.load(open('comps_data.json'))['results']['data']['cluster_details'])
def g(c): dl(f'https://api-hc.metatft.com/tft-comps-api/comp_details?comp={c}&cluster_id=427&queue=PBE',f'cd_{c}.json')
with cf.ThreadPoolExecutor(8) as ex: list(ex.map(g,ids))
z=json.load(open('set19.json'))
units=[x for x in z['units'] if x.get('cost') and x['apiName'].startswith('DA_') and x.get('traits')]
def norm(s):
    s=s.lower().replace('da_','')
    s=re.sub(r'\d+','',s); s=re.sub(r'[^a-z]','',s); return s
alias={}
for x in units:
    nm=x['name'] if x['apiName']!='DA_Akali_TrueDamage19' else 'Akali TD'
    if x['apiName']=='DA_Seraphine19_Indie': nm='Seraphine'
    for a in [x['apiName'],x['characterName']]+(x.get('assetNames') or []):
        alias[norm(a)]=nm
for k,v in (z.get('unitAssetNames') or {}).items():
    for x in units:
        if v==x['apiName'] or v==x['characterName']:
            alias[norm(k)]=alias[norm(x['apiName'])]
alias['seraphineindie']='Seraphine';alias['seraphinerisingstar']='Seraphine';alias['seraphinesuperstar']='Seraphine';alias['gnarsmall']='Gnar'
def uname(a):
    n=norm(a)
    if n in alias: return alias[n]
    # try contains
    for k,v in alias.items():
        if n.endswith(k) or k.endswith(n): return v
    return None
tr={t['apiName']:t['name'] for t in z['traits']}
it={i['apiName']:i['name'] for i in z['items'] if i.get('name')}
cd=json.load(open('comps_data.json'))['results']['data']['cluster_details']
st={s['cluster']:s for s in json.load(open('comps_stats.json'))['results'] if s['cluster']}
total=json.load(open('comps_stats.json'))['results'][0]['places'][0]
rows=[]
for cid,c in cd.items():
    s=st.get(cid); 
    if not s: continue
    p=s['places'][:8]; n=sum(p)
    avg=sum((i+1)*v for i,v in enumerate(p))/n
    name=' '.join(tr.get(e['name']) or uname(e['name']) or e['name'] for e in c['name'])
    rows.append((avg,cid,name,n,n/total*8,sum(p[:4])/n,p[0]/n,c['levelling']))
rows.sort()
for r in []: print(f"{r[0]:.2f} {r[1]} {r[2]:30s} n={r[3]} pick={r[4]:.2f} top4={r[5]:.1%} win={r[6]:.1%} {r[7]}")

# ---- build output ----
import collections
def ulist(s,sep):
    out=[]
    for a in s.split(sep):
        a=a.strip()
        if not a: continue
        n=uname(a)
        if n is None: missing.add(a); continue
        if n not in out: out.append(n)
    return out
missing=set()
def tier(a): return 'S' if a<=4.25 else 'A' if a<=4.6 else 'B' if a<=4.9 else 'C'
comps=[]
itemset=set()
for avg,cid,name,n,pick,top4,win,lev in rows:
    if avg>4.9: continue
    d=json.load(open(f'cd_{cid}.json'))['results']
    c=cd[cid]
    early={}
    for L in ['4','5','6']:
        ops=sorted(d['early_options'].get(L,[]),key=lambda o:-o['count'])[:4]
        early[L]=[{'u':ulist(o['unit_list'],'&'),'avg':round(o['avg'],2),'win':round(o.get('win',0),3),'n':o['count']} for o in ops]
    opts={}
    for L in ['6','7','8','9','10']:
        ops=sorted(d['options'].get(L,[]),key=lambda o:-o['score'])[:3]
        opts[L]=[{'u':ulist(o['units_list'],'&'),'avg':round(o['avg'],2),'n':o['count']} for o in ops if o['count']>=100]
    # positions
    pos={}
    for k,v in d['positioning']['units'].items():
        nm=uname(k)
        if not nm or not v['positions']: continue
        cell=int(v['positions'][0]['cell'].split('_')[1])
        pos[nm]=[3-(cell-1)//7,(cell-1)%7]
    # stars
    stars={}
    for us in d['unit_stats']:
        nm=uname(us['unit']); 
        if not nm: continue
        best=max(us['tiers'],key=lambda t:t['count']); stars[nm]=best['tier']
    # items: best build per unit by score, count>=150
    items={}
    by=collections.defaultdict(list)
    for b in d['builds']:
        if b.get('num_items')==3 and b['count']>=150: by[b['unit']].append(b)
    for u,bs in by.items():
        nm=uname(u)
        if not nm: continue
        b=max(bs,key=lambda b:b.get('adjusted_score',b['score']))
        names=[it.get(x,x) for x in b['buildName']]; itemset.update(names)
        items[nm]={'i':names,'avg':round(b['avg'],2),'n':b['count']}
    lv=[{'l':x['level'],'s':f"{x['stage']}-{x['round']}"} for x in d['levels'] if x['stage']]
    fl=sorted([(int(x['level']),x['count'],x['avg']) for x in d['final_levels']])
    comps.append({'id':cid,'name':name,'tier':tier(avg),'style':lev,'avg':round(avg,2),'top4':round(top4,3),'win':round(win,3),'pick':round(pick,2),'n':n,
      'core':ulist(c['units_string'],','),'early':early,'opts':opts,'pos':pos,'stars':stars,'items':items,'lv':lv,
      'final':[{'l':a,'pct':round(b/sum(x[1] for x in fl),3),'avg':round(cc,2)} for a,b,cc in fl if b/sum(x[1] for x in fl)>0.02]})
print('missing',missing)
print(len(comps))
# global best items per unit (across all comps, builds count>=200, best adjusted score weighted by count)
glob_=collections.defaultdict(lambda:collections.Counter()); gavg={}
for f in glob.glob('cd_*.json'):
    d=json.load(open(f))['results']
    for b in d['builds']:
        if b.get('num_items')!=3: continue
        nm=uname(b['unit']); 
        if not nm: continue
        key=tuple(it.get(x,x) for x in b['buildName'])
        glob_[nm][key]+=b['count']; gavg.setdefault((nm,key),[]).append((b['avg'],b['count']))
best={}
for nm,cnt in glob_.items():
    cands=[(k,c) for k,c in cnt.items() if c>=200] or list(cnt.items())
    def wavg(k): l=gavg[(nm,k)]; return sum(a*c for a,c in l)/sum(c for a,c in l)
    k=min(cands,key=lambda kc: wavg(kc[0]) - 0.15*__import__('math').log10(kc[1]))[0]
    best[nm]=list(k); itemset.update(k)
UN=[]
for x in sorted(units,key=lambda x:(x['cost'],x['name'])):
    nm=alias[norm(x['apiName'])]
    UN.append({'n':nm,'c':x['cost'],'t':x['traits'],'l':1 if x.get('unlock') else 0,'u':(x.get('unlock') or {}).get('manual_conditions','')})
TB={}
for t in z['traits']:
    bp=sorted(set(e['minUnits'] for e in t['effects'] if e['minUnits']>0))
    if t['name'] in ('Mystical Instrument',): continue
    TB[t['name']]=bp or [1]
comp_items=['B.F. Sword','Recurve Bow','Needlessly Large Rod','Tear of the Goddess','Chain Vest','Negatron Cloak',"Giant's Belt",'Sparring Gloves','Spatula','Frying Pan']
allitems=sorted(itemset-set(comp_items))
out={'updated':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='minutes'),'units':UN,'traits':TB,'comps':comps,'best':best,'items':comp_items+allitems,'missing':sorted(missing)}

# ===== Erweiterungen: Rollen, Fähigkeiten, Champion-Stats, Augments, Carry/Tank =====
def clean_desc(desc,cv=None,ct=None,av=None,stars=3):
    if not desc: return ''
    cv=cv or {};ct=ct or {};av=av or {}
    def fmt(v):
        if isinstance(v,(int,float)):
            v=round(v,2); return str(int(v)) if float(v).is_integer() else str(v).replace('.',',')
        return str(v)
    def row(r):
        rows=cv.get(r) or ct.get(r)
        if not rows: return 'X'
        if len(rows)==1 or stars==1: return fmt(rows[0][1])
        vals=[]
        for st in range(1,stars+1):
            v=None
            for lv,val in rows:
                if lv<=st: v=val
            vals.append(fmt(v))
        return vals[0] if len(set(vals))==1 else '/'.join(vals)
    def attr(a):
        v=av.get(a)
        if not v: return 'X'
        vals=[fmt(x) for x in v[:stars]]
        return vals[0] if len(set(vals))==1 else '/'.join(vals)
    t=re.sub(r'<TFTCurveTable row="([^"]+)"\s*/>',lambda m:row(m.group(1)),desc)
    t=re.sub(r'<TFTAttribute[^>]*attributeID="([^"]+)"[^>]*/>',lambda m:attr(m.group(1)),t)
    t=re.sub(r'<img id="Icon\.([^"]+)"\s*/>',lambda m:m.group(1),t)
    t=re.sub(r'<br\s*/?>','\n',t);t=re.sub(r'<rules>','(',t);t=re.sub(r'</rules>',')',t)
    t=re.sub(r'<[^>]+>','',t);t=t.replace('\r\n','\n')
    t=re.sub(r'%i:[a-zA-Z]+%','',t)
    t=re.sub(r'[ \t]+',' ',t);t=re.sub(r'\n{3,}','\n\n',t)
    return t.strip()
ROLE_DE={'Tank':'Tank','Fighter':'Fighter','Marksman':'Schütze','Caster':'Caster','Assassin':'Assassine','Specialist':'Spezialist'}
def role_of(x):
    r=(x.get('role') or '').replace('DA_Role_','')
    dmg='Magie' if r.startswith('Magic') else ('Angriff' if r.startswith('Attack') else '')
    kind=re.sub(r'^(Magic|Attack|Hybrid)','',r)
    return {'raw':r,'tank':'Tank' in r,'label':(ROLE_DE.get(kind,kind) + (f' ({dmg})' if dmg else '')).strip()}
# Deutsche Fähigkeitstexte: Zahlen kommen immer frisch aus den Daten, nur der Text ist übersetzt.
# Ändert Riot den englischen Text, passt das Gerüst nicht mehr und die Seite zeigt Englisch.
try: ABDE=json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'abilities_de.json')))
except Exception: ABDE={}
_NUM=re.compile(r'\d+(?:[.,]\d+)*(?:/\d+(?:[.,]\d+)*)*%?')
def ability_de(name,en):
    e=ABDE.get(name)
    if not e or not en: return ''
    nums=_NUM.findall(en);i=[0]
    def r(m):
        i[0]+=1;return '{%d}'%(i[0]-1)
    if _NUM.sub(r,en)!=e['skel']: return ''
    return re.sub(r'\{(\d+)\}',lambda m:nums[int(m.group(1))],e['de'])
umap={}
for x in units:
    nm=alias[norm(x['apiName'])]
    ab=x.get('ability') or {}
    umap[nm]={'role':role_of(x),'ab':ab.get('name') or '','abd':clean_desc(ab.get('desc',''),x.get('curveValues'),x.get('curveTable'),x.get('attributeValues'))}
    umap[nm]['abdde']=ability_de(nm,umap[nm]['abd'])
# Champion-Stats (units_distribution)
ustats={}
try:
    dl('https://api-hc.metatft.com/tft-stat-api/units_distribution?queue=PBE&patch=current&days=3','units_dist.json')
    ud=json.load(open('units_dist.json'))
    agg=collections.defaultdict(lambda:[0]*8)
    for r in ud['results']:
        n=uname(r['unit'])
        if n:
            for i,v in enumerate(r['places'][:8]): agg[n][i]+=v
    G=max(1,sum(g['count'] for g in ud.get('games',[])))
    for n,p in agg.items():
        s_=sum(p)
        if s_>=200: ustats[n]={'avg':round(sum((i+1)*v for i,v in enumerate(p))/s_,2),'top4':round(sum(p[:4])/s_,3),'win':round(p[0]/s_,3),'freq':round(s_/G,3),'n':s_}
except Exception as e: print('units_dist fehlgeschlagen',e)
for u in UN:
    u.update(umap.get(u['n'],{}))
    if u['n'] in ustats: u['st']=ustats[u['n']]
# Augments
augstats={}
try:
    dl('https://api-hc.metatft.com/tft-explorer-api/augments?formatnoarray=true&compact=true&queue=PBE&patch=current&days=3&permit_filter_adjustment=true','aug_stats.json')
    for r in json.load(open('aug_stats.json')).get('data',[]):
        a=r.get('augments')
        if not a: continue
        p=r['placement_count'][:8];s_=sum(p)
        if s_>=100: augstats[a]={'avg':round(sum((i+1)*v for i,v in enumerate(p))/s_,2),'top4':round(sum(p[:4])/s_,3),'win':round(p[0]/s_,3),'n':s_}
except Exception as e: print('aug stats fehlgeschlagen',e)
trapi={t['apiName']:t['name'] for t in z['traits']}
CAT_DE={'Economic':'Gold','GrantsItems':'Items','Trait':'Trait','RandomAugment':'Zufall','Reroll':'Reroll','Hero':'Hero','GrantsEmblem':'Embleme','Positioning':'Positionierung','NoLowHealth':'Sonstiges'}
AUG=[]
unames=sorted([u['n'] for u in UN],key=len,reverse=True)
for a in z['augments']:
    cats=[]
    for t in a.get('tags',[]):
        if t.startswith('Augment.Category.'):
            c=t.split('.')[2];c=CAT_DE.get(c,c)
            if c not in cats: cats.append(c)
    if not cats: cats=['Kampf' if 'combat' in a.get('manual_tags',[]) else 'Sonstiges']
    desc=clean_desc(a.get('desc',''),a.get('curveValues'),a.get('curveTable'),None,1)
    tr_=[trapi.get(t,t) for t in a.get('associatedTraits',[])]
    hero=[n for n in unames if 'Hero' in cats and re.search(r'\b'+re.escape(n)+r'\b',desc)][:1]
    e={'n':a['name'],'r':a['rarity'],'c':cats,'d':desc,'t':tr_,'h':hero,'rd':a.get('rounds') or []}
    if a['apiName'] in augstats: e['st']=augstats[a['apiName']]
    AUG.append(e)
AUG.sort(key=lambda e:({'Prismatic':0,'Gold':1,'Silver':2}.get(e['r'],3),e['n']))
apiaug={a['apiName']:a['name'] for a in z['augments']}
# pro Comp: Carry, Tank, Augments
for c in comps:
    d=json.load(open(f"cd_{c['id']}.json"))['results']
    late=None
    for L in ['9','8','10','7']:
        if c['opts'].get(L): late=c['opts'][L][0]['u'];break
    pool=list(dict.fromkeys((late or [])+c['core']))
    cand=[(c['items'][u]['n'] if u in c['items'] else 0,u) for u in pool]
    carries=[u for n,u in sorted(cand,reverse=True) if u in umap and not umap[u]['role']['tank'] and n>0]
    tanks=[u for n,u in sorted(cand,reverse=True) if u in umap and umap[u]['role']['tank']]
    if not tanks: tanks=[u for u in pool if c['pos'].get(u,[3])[0]==0]
    # Der Champion im Comp-Namen (z. B. "Slayer Viego") ist der Main Carry, wenn er kein Tank ist
    # (aber nur, wenn er auch wirklich oft Items trägt, sonst ist er nur namensgebend wie Alune bei Heartsteel)
    nn=lambda u:c['items'][u]['n'] if u in c['items'] else 0
    named=[u for u in umap if re.search(r'\b'+re.escape(u)+r'$',c['name']) and not umap[u]['role']['tank']]
    if named and carries and nn(named[0])>=0.3*max(1,nn(carries[0])):
        carries=[named[0]]+[u for u in carries if u!=named[0]]
    # Zweiter Carry nur, wenn er wirklich oft Items trägt (mind. 35 % vom Main Carry)
    if len(carries)>1 and nn(carries[1])<0.35*max(1,nn(carries[0])): carries=carries[:1]
    c['carry']=carries[:2];c['tank']=tanks[:2]
    ca=[]
    for x in d.get('augments') or []:
        if x.get('aug') and x.get('count',0)>=80: ca.append({'a':apiaug.get(x['aug'],x['aug']),'avg':round(x['avg'],2),'n':x['count']})
    c['augs']=sorted(ca,key=lambda x:x['avg'])[:12]
out['units']=UN;out['augs']=AUG;out['comps']=comps;out['augstats']=bool(augstats)

# ===== Rezepte, Unlock-Level, Trends =====
comp_api={i['apiName']:i['name'] for i in z['items']}
RECIPES={}
for i in z['items']:
    c_=i.get('composition') or []
    if len(c_)==2 and all(x.startswith('DA_Component_') for x in c_) and i.get('name'):
        RECIPES[i['name']]=[comp_api.get(x,x) for x in c_]
out['recipes']=RECIPES
lvmap={}
for x in units:
    nm=alias[norm(x['apiName'])]
    if x.get('unlock'): lvmap[nm]=x['unlock'].get('levelRequired') or 0
for u in UN:
    if u['n'] in lvmap: u['lv']=lvmap[u['n']]
out['pool']={str(c):[x['poolCount'] for x in units if x.get('shopUnit') and x['cost']==c][:1][0] if [x for x in units if x.get('shopUnit') and x['cost']==c] else 0 for c in (1,2,3,4,5,7)}
out['poolN']={str(c):len({alias[norm(x['apiName'])] for x in units if x.get('shopUnit') and x['cost']==c}) for c in (1,2,3,4,5,7)}
now=datetime.datetime.now(datetime.timezone.utc)
snap={'t':now.isoformat(timespec='minutes'),'c':{c['name']:c['avg'] for c in comps},'u':{u['n']:u['st']['avg'] for u in UN if u.get('st')}}
hist=[]
if HIST and os.path.exists(HIST):
    try: hist=json.load(open(HIST))
    except Exception: hist=[]
hist=[h for h in hist if h.get('t')]
ref=None
def age(h): return (now-datetime.datetime.fromisoformat(h['t'])).total_seconds()/3600
cands=[h for h in hist if age(h)>=1]
if cands:
    ref=min(cands,key=lambda h:abs(age(h)-24))
    out['trendH']=round(age(ref))
    for c in comps:
        if c['name'] in ref['c']: c['tr']=round(c['avg']-ref['c'][c['name']],2)
    for u in UN:
        if u.get('st') and u['n'] in ref['u']: u['st']['tr']=round(u['st']['avg']-ref['u'][u['n']],2)
hist.append(snap)
hist=[h for h in hist if age(h)<=24*7]
# ausduennen: aelter als 48h nur ein Eintrag pro 6 Stunden
thin=[];seen=set()
for h in hist:
    a=age(h)
    key=h['t'] if a<48 else (h['t'][:10],int(h['t'][11:13])//6)
    if key in seen: continue
    seen.add(key);thin.append(h)
if HIST: json.dump(thin,open(HIST,'w'),separators=(',',':'))

# ===== Nur fuer die GitHub-Seite: Icons aus den Screenshots =====
if SHEETS and DOCS:
    sys.path.insert(0,HERE)
    from sheets import build_icons
    order=[(u['n'],u['c']) for u in sorted(UN,key=lambda u:(u['c'],u['n'].casefold()))]
    um,imap=build_icons(SHEETS,DOCS,order)
    out['siteIcons']=um;out['siteItems']=imap;out['site']=True
    print('Icons:',len(um),'Units,',len(imap),'Items')
json.dump(out,open('data.json','w'),ensure_ascii=False,separators=(',',':'))
import os;print(os.path.getsize('data.json'))
if DOCS:
    import shutil;shutil.copy('data.json',os.path.join(DOCS,'data.json'))  # fuer TFT Boss (Godot)
print([u['n'] for u in UN if u['l']])
print(len(allitems), allitems)

t=open(TPL).read()
assert '__DATA__' in t
t=t.replace('const DATA=__DATA__;','const DATA='+open('data.json').read()+';')
open(OUT,'w').write(t)
print('OK comps',len(comps),'size',len(t))
