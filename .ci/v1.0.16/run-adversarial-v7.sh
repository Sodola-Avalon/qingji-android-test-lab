#!/usr/bin/env bash
set -euo pipefail
python3 <<'PY'
from pathlib import Path
src = Path('.ci/v1.0.16/adversarial-v3.sh').read_text()
start = src.index('# ROUND 1 — geometry and basic page gesture feedback')
end = src.index('# ROUND 2 — recurring delete sheet must expose both destructive scopes')
round1 = r'''# ROUND 1 — vertical paging direction + visual recording of transient hint
reset
# Fresh installs default to horizontal. Select vertical explicitly.
tap_by content-desc '设置'
wait_by text '翻页方式' 30
tap_by text '翻页方式'
wait_by text '上下' 20
tap_by text '上下'
sleep .5
adb shell input keyevent BACK || true
wait_by content-desc '添加任务，长按打开快捷功能' 30

tap_by content-desc '添加任务，长按打开快捷功能'
wait_by text '添加' 20
adb shell input text CI_Geometry
tap_by text '添加'
wait_by text CI_Geometry 30
dump_ui r1-home.xml
adb exec-out screencap -p > r1-home.png
CURDATE="$(adb shell date +%Y-%m-%d | tr -d '\r')"

# Record the full gesture so the transient paging hint can be inspected frame-by-frame.
adb shell rm -f /data/local/tmp/r1-prev.mp4
adb shell screenrecord --time-limit 4 /data/local/tmp/r1-prev.mp4 >/dev/null 2>&1 & rec=$!
sleep .5
adb shell input swipe 540 850 540 1500 900
sleep .6
wait $rec || true
adb pull /data/local/tmp/r1-prev.mp4 r1-prev.mp4 >/dev/null
dump_ui r1-prev.xml
adb exec-out screencap -p > r1-prev.png

# Return to real today before testing the opposite direction.
tap_by content-desc '返回今日'
wait_by text CI_Geometry 20
adb shell rm -f /data/local/tmp/r1-next.mp4
adb shell screenrecord --time-limit 4 /data/local/tmp/r1-next.mp4 >/dev/null 2>&1 & rec=$!
sleep .5
adb shell input swipe 540 1600 540 850 900
sleep .6
wait $rec || true
adb pull /data/local/tmp/r1-next.mp4 r1-next.mp4 >/dev/null
dump_ui r1-next.xml
adb exec-out screencap -p > r1-next.png

python3 - "$CURDATE" <<'P1'
import sys,datetime,xml.etree.ElementTree as ET
cur=datetime.date.fromisoformat(sys.argv[1])
def texts(path): return [n.attrib.get('text','') for n in ET.parse(path).getroot().iter('node')]
def label(d): return f'{d.month}月{d.day}日'
home,prev,nxt=map(texts,['r1-home.xml','r1-prev.xml','r1-next.xml'])
exp_prev=label(cur-datetime.timedelta(days=1)); exp_next=label(cur+datetime.timedelta(days=1)); today=label(cur)
print('expected:',exp_prev,today,exp_next)
assert any(today in t for t in home), ('today title missing',home)
assert any(exp_prev in t for t in prev), ('down-pull did not go to previous day',prev)
assert any(exp_next in t for t in nxt), ('up-pull did not go to next day',nxt)
assert any(n.attrib.get('content-desc')=='返回今日' for n in ET.parse('r1-prev.xml').getroot().iter('node'))
assert any(n.attrib.get('content-desc')=='返回今日' for n in ET.parse('r1-next.xml').getroot().iter('node'))
P1
echo ROUND1_PASS | tee r1-result.txt

'''
script = src[:start] + round1 + src[end:]
# The redesigned recurring actions expose title + subtitle in one accessibility node.
needle = 'tap_by(){ wait_by "$1" "$2"; read -r x y < <(center_by "$1" "$2"); adb shell input tap "$x" "$y"; }'
helpers = needle + r'''
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
if needle not in script:
    raise SystemExit('helper injection point missing')
script = script.replace(needle, helpers, 1)
script = script.replace("wait_by text '仅删除这一天' 20; wait_by text '停止每日重复' 5; wait_by text '取消' 5", "wait_contains '仅删除这一天' 20; wait_contains '停止每日重复' 5; wait_by text '取消' 5")
script = script.replace("tap_by text '仅删除这一天'; sleep .7", "tap_contains '仅删除这一天'; sleep .7")
Path('/tmp/adversarial-v7.sh').write_text(script)
PY
chmod +x /tmp/adversarial-v7.sh
exec /tmp/adversarial-v7.sh
