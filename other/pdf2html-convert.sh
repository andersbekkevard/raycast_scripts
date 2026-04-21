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
python3 - "$OUT_DIR/$OUT_NAME" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
html = p.read_text(encoding='utf-8', errors='ignore')
# Strip any prior injection so we can update it cleanly
html = re.sub(r'<style id="pdf2html-overlay-css">.*?</style>\s*', '', html, flags=re.DOTALL)
html = re.sub(r'<script id="pdf2html-overlay-js">.*?</script>\s*', '', html, flags=re.DOTALL)
snippet = '''<style id="pdf2html-overlay-css">
html,body,#page-container{background:#282828!important}
::selection{background:#99C1DA;color:#000}
::-moz-selection{background:#99C1DA;color:#000}
.pf.pdf2html-force > .pc{display:block!important}
body:not(.sidebar-shown) #sidebar{display:none!important}
body:not(.sidebar-shown) #page-container{left:0!important}
#pdf2html-toggle{position:fixed;top:8px;left:8px;z-index:9999;background:transparent;color:rgba(255,255,255,.18);border:0;border-radius:4px;padding:4px 9px;font:13px -apple-system,sans-serif;cursor:pointer;transition:color .15s,background .15s}
#pdf2html-toggle:hover{background:rgba(255,255,255,.08);color:rgba(255,255,255,.7)}
#pdf2html-cfg{padding:10px 14px;color:#eee;border-bottom:1px solid #444;font:12px -apple-system,sans-serif;background:#1f1f1f}
#pdf2html-cfg label{display:flex;align-items:center;gap:6px}
#pdf2html-cfg input{width:4.5em;background:#3a3a3a;color:#fff;border:1px solid #555;border-radius:3px;padding:2px 5px;font:12px -apple-system,sans-serif}
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
    var sel=window.getSelection();
    if(sel&&!sel.isCollapsed)sel.removeAllRanges();
  },true);
  // Keep the selection focus inside a comfortable viewport band — only recenter when
  // the cursor is about to leave it, so rapid j/k doesn't cause per-keystroke jitter.
  var scrollRAF=null;
  document.addEventListener('selectionchange',function(){
    if(scrollRAF)return;
    scrollRAF=requestAnimationFrame(function(){
      scrollRAF=null;
      var sel=document.getSelection();
      if(!sel||sel.rangeCount===0||sel.isCollapsed||!sel.focusNode)return;
      var r=document.createRange();
      try{r.setStart(sel.focusNode,sel.focusOffset);r.collapse(true);}catch(e){return}
      var rect=r.getBoundingClientRect();
      var vh=window.innerHeight;
      if(rect.top<vh*0.2||rect.bottom>vh*0.8){
        var el=sel.focusNode.nodeType===1?sel.focusNode:sel.focusNode.parentElement;
        if(el&&el.scrollIntoView)el.scrollIntoView({block:'center'});
      }
    });
  });
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
    var raf=null;
    function apply(){
      var st=container.scrollTop,sb=st+container.clientHeight;
      var first=-1,last=-1,best=0,bestOverlap=-1;
      for(var i=0;i<offsets.length;i++){
        var overlap=Math.min(offsets[i].bottom,sb)-Math.max(offsets[i].top,st);
        if(overlap>bestOverlap){bestOverlap=overlap;best=i}
        if(offsets[i].bottom>st&&offsets[i].top<sb){
          if(first===-1)first=i;
          last=i;
        }else if(first!==-1)break;
      }
      if(first===-1){first=last=best}
      var from,to;
      if(buffer===0){from=to=best}
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
      panel.innerHTML='<label>Render ±<input type="number" id="pdf2html-buffer-input" min="0" max="2000"> pages around viewport</label>';
      sidebar.insertBefore(panel,sidebar.firstChild);
      var input=document.getElementById('pdf2html-buffer-input');
      input.value=buffer;
      input.addEventListener('change',function(){
        var n=parseInt(input.value,10);
        if(isNaN(n)||n<0)n=10;
        buffer=n;
        localStorage.setItem('pdf2html-buffer',String(buffer));
        sched();
      });
    }
    apply();
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
