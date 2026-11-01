"""Calibrates the scam similarity check (lib/engine/forensics/scam_similarity.dart).

Same maths as the Dart code: character 3-5 grams inside words, sublinear TF,
smoothed IDF over the reference corpus, cosine similarity. Prints the nearest
scam and genuine similarity for every message in the given CSV files, then how
many scams and genuine messages pass each threshold pair.

    python tool/sim_calibrate.py test/data/labelled_messages.csv test/data/holdout_messages.csv

Never pass holdout_v2_messages.csv here: it is the untouched test set.
"""
import re, math, csv, sys, unicodedata
import os
HERE=os.path.dirname(os.path.abspath(__file__))
src=open(os.path.join(HERE,'..','lib','engine','forensics','scam_corpus.dart'),encoding='utf8').read()
scam_part, legit_part = src.split('const legitCorpus')
scams=re.findall(r"\('([^']*)', '((?:[^'\\]|\\.)*)'\)", scam_part)
legits=re.findall(r"^\s+'((?:[^'\\]|\\.)*)',$", legit_part, re.M)
URL=re.compile(r'(https?://\S+|www\.\S+|\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|my|net|org|xyz|top|info|link|site|online|shop|club|vip|cc|io|co|me|app|live|store|icu|buzz|life|fun|asia|biz|click)\b\S*)')
def norm(t):
    t=t.lower()
    t=URL.sub(' url ',t)
    t=re.sub(r'\d','0',t)
    t=''.join(c if (unicodedata.category(c)[0] in 'LNM' or c.isspace()) else ' ' for c in t)
    return ' '.join(t.split())
def grams(t):
    out={}
    for w in norm(t).split():
        p=' '+w+' '
        for n in (3,4,5):
            if len(p)<n: continue
            for i in range(len(p)-n+1):
                g=p[i:i+n]; out[g]=out.get(g,0)+1
    return out
docs=[g for _,g in [(0,grams(t)) for _,t in scams]]+[grams(t) for t in legits]
N=len(docs)
df={}
for d in docs:
    for g in d: df[g]=df.get(g,0)+1
idfmax=math.log((1+N)/1)+1
def vec(g):
    v={k:(1+math.log(c))*(math.log((1+N)/(1+df.get(k,0)))+1) for k,c in g.items()}
    n=math.sqrt(sum(x*x for x in v.values())) or 1
    return {k:x/n for k,x in v.items()}
S=[vec(d) for d in docs[:len(scams)]]; L=[vec(d) for d in docs[len(scams):]]
def cos(a,b):
    if len(a)>len(b): a,b=b,a
    return sum(x*b.get(k,0) for k,x in a.items())
def score(t):
    q=vec(grams(t))
    s=sorted((cos(q,v),i) for i,v in enumerate(S))[::-1]
    l=max(cos(q,v) for v in L)
    return s[0][0], l, scams[s[0][1]][0]
if __name__=='__main__':
    print(len(scams),'scam and',len(legits),'genuine references')
    rows=[]
    for f in sys.argv[1:]:
        if 'holdout_v2' in f:
            sys.exit('holdout_v2 is the untouched test set; do not calibrate on it')
        for r in csv.DictReader(open(f,encoding='utf8')):
            s,l,typ=score(r['text'])
            rows.append((r['label'],s,l))
            print(f"{r['label']:5} {r['type']:18} scam={s:.3f} genuine={l:.3f} margin={s-l:+.3f} {typ}")
    for S,D in [(0.25,0.13),(0.25,0.15),(0.28,0.15),(0.30,0.18)]:
        tp=sum(1 for lab,s,l in rows if lab=='scam' and s>=S and s-l>=D)
        fp=sum(1 for lab,s,l in rows if lab=='legit' and s>=S and s-l>=D)
        print(f'scam>={S} margin>={D}: {tp}/{sum(r[0]=="scam" for r in rows)} scams, {fp}/{sum(r[0]=="legit" for r in rows)} genuine')
