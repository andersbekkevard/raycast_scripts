#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title PDF2HTML Convert
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📑
# @raycast.description Convert file:// PDF tab to localhost HTML via pdf2htmlEX

PORT=7433
CACHE_DIR="$HOME/.cache/pdf2html-serve"
LOG_FILE="$CACHE_DIR/log"
MAP_FILE="$CACHE_DIR/mappings.tsv"
IMAGE="pdf2htmlex/pdf2htmlex:0.18.8.rc2-master-20200820-ubuntu-20.04-x86_64"

mkdir -p "$CACHE_DIR"
# Silence stdout/stderr so Raycast can't raise notifications from subprocess output
exec >>"$LOG_FILE" 2>&1
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

notify() {
    osascript -e "display notification \"$1\" with title \"PDF2HTML\"" >/dev/null 2>&1
}

fail() {
    log "FAIL: $1"
    osascript -e 'do shell script "afplay /System/Library/Sounds/Basso.aiff &"' >/dev/null 2>&1
    notify "$1"
    exit 1
}

# Get active tab URL from Comet
TAB_URL=$(osascript -e 'tell application "Comet" to return URL of active tab of front window' 2>/dev/null)

# Validate file:// *.pdf
if [[ ! "$TAB_URL" =~ ^file://.*\.[pP][dD][fF]$ ]]; then
    fail "Active tab is not a file:// PDF"
fi

# Decode path for filesystem access
ENCODED_PATH="${TAB_URL#file://}"
LOCAL_PATH=$(python3 -c "import sys, urllib.parse as u; print(u.unquote(sys.argv[1]))" "$ENCODED_PATH")

if [[ ! -f "$LOCAL_PATH" ]]; then
    fail "PDF not found on disk"
fi

# Need docker daemon
if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon not running — start Docker.app"
fi

# Stable per-file cache key (content hash, survives moves/renames)
HASH=$(shasum -a 256 "$LOCAL_PATH" | awk '{print $1}' | head -c 16)
PDF_NAME=$(basename "$LOCAL_PATH")
OUT_NAME="${PDF_NAME%.*}.html"
OUT_DIR="$CACHE_DIR/$HASH"
mkdir -p "$OUT_DIR"

# Convert on miss
if [[ ! -f "$OUT_DIR/$OUT_NAME" ]]; then
    notify "Converting $PDF_NAME…"
    log "convert start: $LOCAL_PATH -> $OUT_DIR/$OUT_NAME"
    PDF_DIR=$(dirname "$LOCAL_PATH")
    docker run --rm --platform linux/amd64 \
        -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 \
        -v "$PDF_DIR":/pdf:ro \
        -v "$OUT_DIR":/out \
        -w /pdf \
        "$IMAGE" \
        --dest-dir /out \
        "$PDF_NAME" \
        > >(grep -v 'perl: warning\|Setting locale failed' >>"$LOG_FILE") \
        2> >(grep -v 'perl: warning\|Setting locale failed' >>"$LOG_FILE") \
        || fail "pdf2htmlEX conversion failed (see $LOG_FILE)"
    log "convert done: $OUT_NAME"
fi

# Inject sidebar toggle (idempotent, self-updating — retrofits cached outputs)
python3 - "$OUT_DIR/$OUT_NAME" "${PDF_NAME%.*}" <<'PY'
import sys, re, pathlib, html as _html, urllib.parse as _up
p = pathlib.Path(sys.argv[1])
stem = _html.escape(sys.argv[2])
html = p.read_text(encoding='utf-8', errors='ignore')
# Replace document title with the original PDF stem
if re.search(r'<title>.*?</title>', html, flags=re.DOTALL):
    html = re.sub(r'<title>.*?</title>', f'<title>{stem}</title>', html, count=1, flags=re.DOTALL)
else:
    html = html.replace('</head>', f'<title>{stem}</title></head>', 1)
# Replace favicon: strip any existing icon link + insert ours
html = re.sub(r'<link[^>]*\brel\s*=\s*["\']?(?:shortcut\s+)?icon["\'][^>]*>\s*', '', html, flags=re.IGNORECASE)
_svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y=".9em" font-size="90">📑</text></svg>'
_favicon = f'<link id="pdf2html-favicon" rel="icon" href="data:image/svg+xml;utf8,{_up.quote(_svg)}">'
if 'id="pdf2html-favicon"' in html:
    html = re.sub(r'<link id="pdf2html-favicon"[^>]*>\s*', '', html)
html = html.replace('</head>', _favicon + '</head>', 1)
# Strip any prior injection so we can update it cleanly
html = re.sub(r'<style id="pdf2html-overlay-css">.*?</style>\s*', '', html, flags=re.DOTALL)
html = re.sub(r'<script id="pdf2html-overlay-js">.*?</script>\s*', '', html, flags=re.DOTALL)
snippet = '''<style id="pdf2html-overlay-css">
html,body,#page-container{background:#282828!important}
::selection{background:#99C1DA;color:#000}
::-moz-selection{background:#99C1DA;color:#000}
.pf > .pc{display:none!important}
.pf.pdf2html-force > .pc{display:block!important}
body:not(.sidebar-shown) #sidebar{display:none!important}
body:not(.sidebar-shown) #page-container{left:0!important}
#pdf2html-toggle{position:fixed;top:8px;left:8px;z-index:9999;background:transparent;color:rgba(255,255,255,.18);border:0;border-radius:4px;padding:4px 9px;font:13px -apple-system,sans-serif;cursor:pointer;transition:color .15s,background .15s}
#pdf2html-toggle:hover{background:rgba(255,255,255,.08);color:rgba(255,255,255,.7)}
#sidebar{background:#1e1e1e!important;color:#e0e0e0!important;padding:0!important;border:0!important}
#outline{background:transparent!important;padding:6px 4px!important;margin:0!important;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif!important}
#outline ul{list-style:none!important;padding:0 0 0 14px!important;margin:0!important}
#outline>ul{padding-left:0!important}
#outline li{margin:0!important}
#outline a,#outline a.l{display:block!important;padding:9px 14px!important;margin:1px 4px!important;border-radius:6px!important;color:#e0e0e0!important;text-decoration:none!important;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif!important;font-weight:400!important;line-height:1.35!important;transition:background .1s ease}
#outline a:hover{background:rgba(255,255,255,.06)!important}
#outline a.pdf2html-active{background:rgba(255,255,255,.13)!important;font-weight:500!important}
#pdf2html-cfg{padding:38px 16px 14px;color:#e0e0e0;border-bottom:1px solid #333;font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif;background:#181818}
#pdf2html-cfg label{display:flex;align-items:center;gap:8px;margin:2px 0}
#pdf2html-cfg input[type=number]{width:4.5em;background:#2a2a2a;color:#fff;border:1px solid #3a3a3a;border-radius:4px;padding:3px 6px;font:13px -apple-system,sans-serif}
#pdf2html-cfg input[disabled]{opacity:.35}
#pdf2html-cheatsheet{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:10000;display:flex;align-items:center;justify-content:center;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif;color:#e0e0e0}
#pdf2html-cheatsheet-panel{background:#1e1e1e;border:1px solid #333;border-radius:10px;padding:24px 32px;max-width:640px;box-shadow:0 20px 60px rgba(0,0,0,.6);max-height:80vh;overflow:auto}
#pdf2html-cheatsheet h3{margin:0 0 10px;font-size:11px;font-weight:700;color:#99C1DA;letter-spacing:.08em}
#pdf2html-cheatsheet h3:not(:first-child){margin-top:20px}
#pdf2html-cheatsheet table{border-collapse:collapse;width:100%;margin:0}
#pdf2html-cheatsheet td{padding:4px 0;vertical-align:top;font-size:13px}
#pdf2html-cheatsheet td:first-child{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:#f5deb3;padding-right:28px;white-space:nowrap}
</style>
<script id="pdf2html-overlay-js">
document.addEventListener('DOMContentLoaded',function(){
  var b=document.createElement('button');
  b.id='pdf2html-toggle';b.textContent='☰';b.title='Toggle sidebar (⌘. or s)';
  b.onclick=function(){document.body.classList.toggle('sidebar-shown')};
  document.body.appendChild(b);
  document.addEventListener('keydown',function(e){
    if(['INPUT','TEXTAREA'].includes(e.target.tagName))return;
    if(e.metaKey&&e.key==='.'){e.preventDefault();document.body.classList.toggle('sidebar-shown');return}
    if(e.key==='s'&&!e.metaKey&&!e.ctrlKey&&!e.altKey){document.body.classList.toggle('sidebar-shown')}
  });
  document.addEventListener('keydown',function(e){
    if(e.key!=='Escape')return;
    if(['INPUT','TEXTAREA'].includes(e.target.tagName))return;
    var cs=document.getElementById('pdf2html-cheatsheet');
    if(cs){cs.remove();return}
    var sel=window.getSelection();
    if(sel&&!sel.isCollapsed)sel.removeAllRanges();
  },true);
  // ? — toggle cheatsheet overlay
  document.addEventListener('keydown',function(e){
    if(e.key!=='?')return;
    if(['INPUT','TEXTAREA'].includes(e.target.tagName))return;
    e.preventDefault();e.stopPropagation();
    var ex=document.getElementById('pdf2html-cheatsheet');
    if(ex){ex.remove();return}
    var bg=document.createElement('div');
    bg.id='pdf2html-cheatsheet';
    bg.innerHTML='<div id="pdf2html-cheatsheet-panel">'
      +'<h3>OUR SHORTCUTS</h3><table>'
      +'<tr><td>s or ⌘.</td><td>Toggle sidebar</td></tr>'
      +'<tr><td>A</td><td>Toggle render-all pages</td></tr>'
      +'<tr><td>?</td><td>Toggle this help</td></tr>'
      +'<tr><td>Esc</td><td>Close overlay / clear selection</td></tr>'
      +'</table>'
      +'<h3>USEFUL VIMIUM</h3><table>'
      +'<tr><td>v</td><td>Visual mode (extend selection with j/k/w/b)</td></tr>'
      +'<tr><td>/  n  N</td><td>Find (only scans rendered pages)</td></tr>'
      +'<tr><td>m{a-z}  &#x27;{a-z}</td><td>Set / jump to bookmark</td></tr>'
      +'<tr><td>gg  G</td><td>Top / bottom of document</td></tr>'
      +'<tr><td>zi  zo  z0</td><td>Zoom in / out / reset</td></tr>'
      +'</table>'
      +'<h3>SIDEBAR CONTROLS</h3><table>'
      +'<tr><td>Render all</td><td>Force every page visible (inflates find)</td></tr>'
      +'<tr><td>Render ±N</td><td>Pages kept in DOM around viewport</td></tr>'
      +'<tr><td>Cursor pin N%</td><td>Where selection focus anchors during scroll</td></tr>'
      +'</table></div>';
    bg.addEventListener('click',function(ev){if(ev.target===bg)bg.remove()});
    document.body.appendChild(bg);
  },true);
  // A — toggle render-all pages
  document.addEventListener('keydown',function(e){
    if(e.key!=='A')return;
    if(['INPUT','TEXTAREA'].includes(e.target.tagName))return;
    var cb=document.getElementById('pdf2html-all-input');
    if(!cb)return;
    e.preventDefault();
    cb.checked=!cb.checked;
    cb.dispatchEvent(new Event('change'));
  });
  // Pin the selection focus to a fixed fraction of the viewport. Each selection
  // change scrolls #page-container by the exact delta so the cursor stays put and
  // the page flows past — Vim's scrolloff=999 feel.
  var pinFraction=parseFloat(localStorage.getItem('pdf2html-pin')||'0.5');
  if(isNaN(pinFraction)||pinFraction<0||pinFraction>1)pinFraction=0.5;
  var scrollRAF=null;
  document.addEventListener('selectionchange',function(){
    if(scrollRAF)return;
    scrollRAF=requestAnimationFrame(function(){
      scrollRAF=null;
      var sel=document.getSelection();
      if(!sel||sel.rangeCount===0||sel.isCollapsed||!sel.focusNode)return;
      var pc=document.getElementById('page-container');
      if(!pc)return;
      var r=document.createRange();
      try{r.setStart(sel.focusNode,sel.focusOffset);r.collapse(true);}catch(e){return}
      var rect=r.getBoundingClientRect();
      var pcRect=pc.getBoundingClientRect();
      var cursorY=rect.top-pcRect.top;
      var desired=pc.clientHeight*pinFraction;
      var delta=cursorY-desired;
      if(Math.abs(delta)>=1)pc.scrollTop+=delta;
    });
  });
  window.__pdf2htmlSetPin=function(f){pinFraction=f};
  // Rolling render window — keep N pages visible above and below viewport so
  // cross-page selection works, without inflating DOM for find-mode.
  (function(){
    var container=document.getElementById('page-container');
    if(!container)return;
    var pages=Array.prototype.slice.call(container.querySelectorAll('.pf'));
    if(!pages.length)return;
    var offsets=pages.map(function(p){return{top:p.offsetTop,bottom:p.offsetTop+p.offsetHeight}});
    var buffer=parseInt(localStorage.getItem('pdf2html-buffer')||'10',10);
    if(isNaN(buffer)||buffer<0)buffer=10;
    var renderAll=localStorage.getItem('pdf2html-render-all')==='1';
    var raf=null;
    function apply(){
      var st=container.scrollTop,sb=st+container.clientHeight;
      var vh=sb-st;
      var threshold=Math.max(20,vh*0.05);
      var first=-1,last=-1,best=0,bestOverlap=-1;
      for(var i=0;i<offsets.length;i++){
        var overlap=Math.min(offsets[i].bottom,sb)-Math.max(offsets[i].top,st);
        if(overlap>bestOverlap){bestOverlap=overlap;best=i}
        if(overlap>threshold){
          if(first===-1)first=i;
          last=i;
        }else if(first!==-1)break;
      }
      if(first===-1){first=last=best}
      var from,to;
      if(renderAll){from=0;to=pages.length-1}
      else{from=Math.max(0,first-buffer);to=Math.min(pages.length-1,last+buffer)}
      for(var i=0;i<pages.length;i++){
        var want=i>=from&&i<=to;
        if(want!==pages[i].classList.contains('pdf2html-force'))pages[i].classList.toggle('pdf2html-force',want);
      }
    }
    function sched(){if(raf)return;raf=requestAnimationFrame(function(){raf=null;apply()})}
    container.addEventListener('scroll',sched,{passive:true});
    window.addEventListener('resize',sched);
    // Sidebar config control
    var sidebar=document.getElementById('sidebar');
    if(sidebar){
      var panel=document.createElement('div');
      panel.id='pdf2html-cfg';
      panel.innerHTML='<label><input type="checkbox" id="pdf2html-all-input"> Render all pages</label><label>Render ±<input type="number" id="pdf2html-buffer-input" min="0" max="2000"> pages around viewport</label><label>Cursor pin <input type="number" id="pdf2html-pin-input" min="0" max="100" step="5">% from top</label>';
      sidebar.insertBefore(panel,sidebar.firstChild);
      var input=document.getElementById('pdf2html-buffer-input');
      input.value=buffer;
      input.disabled=renderAll;
      input.addEventListener('change',function(){
        var n=parseInt(input.value,10);
        if(isNaN(n)||n<0)n=10;
        buffer=n;
        localStorage.setItem('pdf2html-buffer',String(buffer));
        sched();
      });
      var allInput=document.getElementById('pdf2html-all-input');
      allInput.checked=renderAll;
      allInput.addEventListener('change',function(){
        renderAll=allInput.checked;
        localStorage.setItem('pdf2html-render-all',renderAll?'1':'0');
        input.disabled=renderAll;
        sched();
      });
      var pinInput=document.getElementById('pdf2html-pin-input');
      pinInput.value=Math.round(pinFraction*100);
      pinInput.addEventListener('change',function(){
        var p=parseInt(pinInput.value,10);
        if(isNaN(p))p=50;p=Math.max(0,Math.min(100,p));
        pinFraction=p/100;
        localStorage.setItem('pdf2html-pin',String(pinFraction));
      });
    }
    apply();
  })();
  // Highlight the outline entry whose target page is the deepest one still ≤ current page
  (function(){
    var outline=document.getElementById('outline');
    var pc=document.getElementById('page-container');
    if(!outline||!pc)return;
    var links=Array.prototype.slice.call(outline.querySelectorAll('a[href^="#pf"]'));
    if(!links.length)return;
    var targets=links.map(function(a){
      var m=(a.getAttribute('href')||'').match(/#pf([0-9a-f]+)/i);
      return m?parseInt(m[1],16):NaN;
    });
    var pages=document.querySelectorAll('.pf');
    var offs=Array.prototype.map.call(pages,function(p){return{t:p.offsetTop,b:p.offsetTop+p.offsetHeight}});
    var lastActive=-1;
    function update(){
      var st=pc.scrollTop,sb=st+pc.clientHeight,bestIdx=0,bestO=-1;
      for(var i=0;i<offs.length;i++){
        var o=Math.min(offs[i].b,sb)-Math.max(offs[i].t,st);
        if(o>bestO){bestO=o;bestIdx=i}
      }
      var cur=bestIdx+1,active=-1;
      for(var i=0;i<targets.length;i++){if(!isNaN(targets[i])&&targets[i]<=cur)active=i}
      if(active===lastActive)return;
      if(lastActive>=0)links[lastActive].classList.remove('pdf2html-active');
      if(active>=0){
        links[active].classList.add('pdf2html-active');
        // Keep the active entry in view within the sidebar
        try{links[active].scrollIntoView({block:'nearest'})}catch(e){}
      }
      lastActive=active;
    }
    var raf=null;
    function sched(){if(raf)return;raf=requestAnimationFrame(function(){raf=null;update()})}
    pc.addEventListener('scroll',sched,{passive:true});
    update();
  })();
});
</script>
'''
html = html.replace('</head>', snippet + '</head>', 1)
p.write_text(html, encoding='utf-8')
PY

# Ensure static server is up
if ! curl -sf "http://localhost:${PORT}/" >/dev/null 2>&1; then
    log "starting http.server on :$PORT rooted at $CACHE_DIR"
    (cd "$CACHE_DIR" && nohup python3 -m http.server "$PORT" >>"$LOG_FILE" 2>&1 &)
    for i in $(seq 1 25); do
        sleep 0.2
        curl -sf "http://localhost:${PORT}/" >/dev/null 2>&1 && break
    done
fi

ENCODED_NAME=$(python3 -c "import sys, urllib.parse as u; print(u.quote(sys.argv[1]))" "$OUT_NAME")
URL="http://localhost:${PORT}/${HASH}/${ENCODED_NAME}"

# Upsert pdf→html mapping (dedupe on PDF path)
{
    if [[ -f "$MAP_FILE" ]]; then
        awk -F'\t' -v p="$LOCAL_PATH" '$2 != p' "$MAP_FILE"
    fi
    printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$LOCAL_PATH" "$HASH" "$OUT_DIR/$OUT_NAME"
} > "$MAP_FILE.tmp" && mv "$MAP_FILE.tmp" "$MAP_FILE"

# Navigate current tab in-place so back-button returns to the source PDF
osascript -e "
tell application \"Comet\"
    set URL of active tab of front window to \"${URL}\"
end tell
" >/dev/null 2>&1

osascript -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff &"' >/dev/null 2>&1
