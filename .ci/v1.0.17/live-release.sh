#!/usr/bin/env bash
set -euo pipefail

wait_text() {
  local text="$1"; local tries="${2:-60}"
  for i in $(seq 1 "$tries"); do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
    adb pull /sdcard/window.xml window.xml >/dev/null 2>&1 || true
    grep -Fq "$text" window.xml 2>/dev/null && return 0
    sleep .5
  done
  echo "missing UI text: $text" >&2
  adb exec-out screencap -p > live-release-failure.png || true
  exit 1
}

scroll_until_text() {
  local text="$1"; local swipes="${2:-8}"
  for i in $(seq 0 "$swipes"); do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
    adb pull /sdcard/window.xml window.xml >/dev/null 2>&1 || true
    grep -Fq "$text" window.xml 2>/dev/null && return 0
    adb shell input swipe 540 2050 540 700 500
    sleep .6
  done
  echo "scroll failed to reveal: $text" >&2
  adb exec-out screencap -p > live-release-failure.png || true
  exit 1
}

tap_contains() {
  local q="$1"
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1
  adb pull /sdcard/window.xml window.xml >/dev/null 2>&1
  python3 - "$q" <<'PY'
import re,sys,xml.etree.ElementTree as ET,subprocess
q=sys.argv[1]
root=ET.parse('window.xml').getroot()
c=[]
for n in root.iter('node'):
    if q in n.attrib.get('text','') or q in n.attrib.get('content-desc',''):
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m: c.append((n.attrib.get('clickable')=='true',m))
if not c: raise SystemExit('not found: '+q)
c.sort(key=lambda x:x[0], reverse=True)
m=c[0][1]
x=(int(m.group(1))+int(m.group(3)))//2; y=(int(m.group(2))+int(m.group(4)))//2
subprocess.check_call(['adb','shell','input','tap',str(x),str(y)])
PY
}

tap_exact_any() {
  local q="$1"
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1
  adb pull /sdcard/window.xml window.xml >/dev/null 2>&1
  python3 - "$q" <<'PY'
import re,sys,xml.etree.ElementTree as ET,subprocess
q=sys.argv[1]
root=ET.parse('window.xml').getroot()
for n in root.iter('node'):
    if n.attrib.get('text','') == q:
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x=(int(m.group(1))+int(m.group(3)))//2; y=(int(m.group(2))+int(m.group(4)))//2
            subprocess.check_call(['adb','shell','input','tap',str(x),str(y)])
            raise SystemExit(0)
raise SystemExit('exact text not found: '+q)
PY
}

adb install -r QingJi-v1.0.17.apk
adb shell monkey -p com.qinghao.qingji -c android.intent.category.LAUNCHER 1 >/dev/null
wait_text '添加任务' 90 || wait_text '今天还没有任务' 90

tap_contains '设置'
wait_text '设置' 30
scroll_until_text '检查更新' 8
wait_text 'V1.0.17' 20

tap_exact_any '检查更新'
wait_text '已是最新版本' 90
wait_text 'V1.0.17' 20
adb exec-out screencap -p > live-release-latest.png

echo LIVE_RELEASE_PASS > live-release-result.txt
