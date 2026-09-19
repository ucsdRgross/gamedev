import urllib.request, urllib.parse, json, time, re, os, html, sys
from html.parser import HTMLParser
UA={"User-Agent":"Mozilla/5.0 solatro-research (effect review)"}
API="https://balatromods.miraheze.org/w/api.php?"
def api(**p):
    p['format']='json'
    for i in range(4):
        try:
            req=urllib.request.Request(API+urllib.parse.urlencode(p), headers=UA)
            return json.load(urllib.request.urlopen(req, timeout=60))
        except Exception as e:
            time.sleep(2*(i+1)); err=e
    raise err

INDEX_NAMES={'jokers','decks','boss blinds','blinds','card modifiers','tarot cards','spectral cards','planet cards',
 'poker hands','sleeves','stakes','tags','vouchers','challenges','booster packs','suits','ranks','consumables',
 'enhancements','seals','editions','stickers','partners','hands','relics','items','item cards','energy cards',
 'code cards','omen cards','runes','pacts','star cards','command cards','fraud cards','loteria cards','mythos cards',
 'zodiac cards','coupons','patches','quips','minor arcana cards','umbral cards','replicant cards','alphabet cards',
 'polymino cards','e.g.o gifts','aesthetic cards','inverted planet cards','inverted spectral cards','inverted code cards',
 'spectral? cards','tarot? cards','code? cards','stickers','achievements','deck skins','audio','texture packs','registry'}
SKIP_NAMES={'audio','texture packs','registry','deck skins','achievements','joker retexture'}

class T(HTMLParser):
    def __init__(s):
        super().__init__(); s.links=[]; s.out=[]; s.skip=0; s.cell=[]; s.incell=False; s.row=[]
    def handle_starttag(s,tag,attrs):
        a=dict(attrs)
        if tag=='a' and a.get('href','').startswith('http') and 'miraheze.org' not in a.get('href',''):
            s.links.append(a['href'])
        if tag in ('style','script'): s.skip+=1
        if tag in ('td','th'): s.incell=True; s.cell=[]
        if tag=='tr': s.row=[]
        if tag=='br' and s.incell: s.cell.append(' ')
        if tag in ('p','li','h1','h2','h3','h4','div') and not s.incell: s.out.append('\n')
        if tag in ('h2','h3'): s.out.append('\n## ')
    def handle_endtag(s,tag):
        if tag in ('style','script'): s.skip-=1
        if tag in ('td','th'):
            s.incell=False; s.row.append(re.sub(r'\s+',' ',''.join(s.cell)).strip())
        if tag=='tr':
            r=[c for c in s.row if c]
            if r: s.out.append('\n| '+' | '.join(r))
        if tag in ('p','li','h1','h2','h3','h4'): s.out.append('\n')
    def handle_data(s,d):
        if s.skip: return
        if s.incell: s.cell.append(d)
        else: s.out.append(d)
def to_text(h):
    p=T(); p.feed(h); t=''.join(p.out)
    t=re.sub(r'\[edit\]','',t); t=re.sub(r'[ \t]+',' ',t); t=re.sub(r'\n\s*\n+','\n',t)
    links=sorted(set(p.links))
    if links: t+=chr(10)*2+'## External links on this page'+chr(10)+chr(10).join(links)
    return t.strip()

mods=json.load(open('wiki/mods_keep.json'))
os.makedirs('wiki/pages',exist_ok=True)
plan={}
if os.path.exists('wiki/plan.json'): plan=json.load(open('wiki/plan.json'))
for m in mods:
    if m in plan: continue
    d=api(action='query',list='allpages',apprefix=m+'/',aplimit=500)
    subs=[p['title'] for p in d['query']['allpages']]
    names=[s[len(m)+1:] for s in subs]
    idx=[s for s,n in zip(subs,names) if n.lower() in INDEX_NAMES and n.lower() not in SKIP_NAMES]
    if idx: pages=[m]+idx
    else: pages=[m]+[s for s,n in zip(subs,names) if n.lower() not in SKIP_NAMES]
    plan[m]={'subpages':len(subs),'pages':pages}
    json.dump(plan,open('wiki/plan.json','w'),indent=1)
    print('plan',m,len(subs),len(pages),flush=True)

def slug(t): return re.sub(r'[^A-Za-z0-9._-]+','_',t)
for m,info in plan.items():
    for pg in info['pages']:
        fn='wiki/pages/'+slug(pg)+'.txt'
        if os.path.exists(fn): continue
        try:
            d=api(action='parse',page=pg,prop='text',disablelimitreport=1)
        except Exception as e:
            print('ERR',pg,e,flush=True); continue
        if 'error' in d: print('ERR',pg,d['error'].get('code'),flush=True); open(fn,'w',encoding='utf-8').write(''); continue
        t=to_text(d['parse']['text']['*'])
        open(fn,'w',encoding='utf-8').write('# '+pg+'\n'+t)
        print('got',pg,len(t),flush=True)
        time.sleep(0.15)
print('DONE')
