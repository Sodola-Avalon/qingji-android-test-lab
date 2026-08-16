#!/usr/bin/env bash
set -euo pipefail
python3 <<'PY'
from pathlib import Path
import re
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
# Extract frames for manual visual inspection of transient hint position.
mkdir -p r1-prev-frames r1-next-frames
ffmpeg -hide_banner -loglevel error -i r1-prev.mp4 -vf fps=5 r1-prev-frames/f-%02d.png || true
ffmpeg -hide_banner -loglevel error -i r1-next.mp4 -vf fps=5 r1-next-frames/f-%02d.png || true
echo ROUND1_PASS | tee r1-result.txt

'''
Path('/tmp/adversarial-v7.sh').write_text(src[:start] + round1 + src[end:])
PY
chmod +x /tmp/adversarial-v7.sh
exec /tmp/adversarial-v7.sh
