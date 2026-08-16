#!/usr/bin/env bash
set -euo pipefail
python3 <<'PY'
from pathlib import Path
src=Path('.ci/v1.0.16/run-adversarial-v7.sh').read_text()
# The recurring delete rows expose title + subtitle as one accessibility text node.
# Patch the generated v7 script to add substring-aware helpers and use them in Round 2.
needle="tap_by(){ wait_by \"$1\" \"$2\"; read -r x y < <(center_by \"$1\" \"$2\"); adb shell input tap \"$x\" \"$y\"; }"
replacement=needle+r'''
center_contains(){
  local v="$1"; dump_ui /tmp/ui.xml
  python3 - "$v" <<'PYC'
import re,sys,xml.etree.ElementTree as ET
v=sys.argv[1]
root=ET.parse('/tmp/ui.xml').getroot()
for n in root.iter('node'):
    if v in n.attrib.get('text',''):
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); raise SystemExit(0)
raise SystemExit(2)
PYC
}
wait_contains(){ local v="$1" tries="${2:-30}"; for _ in $(seq 1 "$tries"); do center_contains "$v" >/dev/null 2>&1 && return 0; sleep .5; done; dump_ui wait-failed.xml; echo "WAIT CONTAINS FAILED: $v" >&2; return 1; }
tap_contains(){ wait_contains "$1"; read -r x y < <(center_contains "$1"); adb shell input tap "$x" "$y"; }
'''
if needle not in src: raise SystemExit('helper injection point missing')
src=src.replace(needle,replacement,1)
src=src.replace("wait_by text '仅删除这一天' 20; wait_by text '停止每日重复' 5; wait_by text '取消' 5", "wait_contains '仅删除这一天' 20; wait_contains '停止每日重复' 5; wait_by text '取消' 5")
src=src.replace("tap_by text '仅删除这一天'; sleep .7", "tap_contains '仅删除这一天'; sleep .7")
Path('/tmp/adversarial-v8.sh').write_text(src)
PY
chmod +x /tmp/adversarial-v8.sh
exec /tmp/adversarial-v8.sh
