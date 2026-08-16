#!/usr/bin/env bash
set -euo pipefail

stage() {
  printf '%s\n' "$1" | tee stage.txt
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "stage-${1}.xml" >/dev/null 2>&1 || true
  adb exec-out screencap -p > "stage-${1}.png" 2>/dev/null || true
}

wait_text() {
  local text="$1"; local tries="${2:-40}"
  for i in $(seq 1 "$tries"); do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
    adb pull /sdcard/window.xml window.xml >/dev/null 2>&1 || true
    grep -Fq "$text" window.xml 2>/dev/null && return 0
    sleep .5
  done
  echo "missing UI text: $text" >&2
  cp window.xml wait-failed.xml 2>/dev/null || true
  adb exec-out screencap -p > failure.png || true
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
  cp window.xml wait-failed.xml 2>/dev/null || true
  adb exec-out screencap -p > failure.png || true
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
candidates=[]
for n in root.iter('node'):
    text=n.attrib.get('text',''); desc=n.attrib.get('content-desc','')
    if q in text or q in desc:
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            candidates.append((n.attrib.get('clickable')=='true',n,m))
if not candidates: raise SystemExit('not found: '+q)
candidates.sort(key=lambda x: x[0], reverse=True)
n,m=candidates[0][1],candidates[0][2]
x=(int(m.group(1))+int(m.group(3)))//2; y=(int(m.group(2))+int(m.group(4)))//2
subprocess.check_call(['adb','shell','input','tap',str(x),str(y)])
PY
}

tap_exact_clickable() {
  local q="$1"
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1
  adb pull /sdcard/window.xml window.xml >/dev/null 2>&1
  python3 - "$q" <<'PY'
import re,sys,xml.etree.ElementTree as ET,subprocess
q=sys.argv[1]
root=ET.parse('window.xml').getroot()
for n in root.iter('node'):
    if n.attrib.get('text','') == q and n.attrib.get('clickable') == 'true':
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x=(int(m.group(1))+int(m.group(3)))//2; y=(int(m.group(2))+int(m.group(4)))//2
            subprocess.check_call(['adb','shell','input','tap',str(x),str(y)])
            raise SystemExit(0)
raise SystemExit('exact clickable text not found: '+q)
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

stage install_v1016
adb install QingJi-v1.0.16.apk
adb shell pm grant com.qinghao.qingji android.permission.POST_NOTIFICATIONS || true

stage launch_v1016
adb shell monkey -p com.qinghao.qingji -c android.intent.category.LAUNCHER 1 >/dev/null
wait_text '添加任务' 60 || wait_text '今天还没有任务' 60

stage open_add
tap_contains '添加任务'
wait_text '添加' 30

stage fill_task
adb shell input text Upgrade_Persist
sleep .5

stage save_upgrade_persist
tap_exact_clickable '添加'
wait_text 'Upgrade_Persist' 30

stage verify_v1016_task
wait_text 'Upgrade_Persist' 10

stage upgrade_v1017
adb install -r QingJi-v1.0.17.apk
adb shell monkey -p com.qinghao.qingji -c android.intent.category.LAUNCHER 1 >/dev/null

stage verify_v1017_task
wait_text 'Upgrade_Persist' 60
adb shell dumpsys package com.qinghao.qingji | grep -q 'versionName=1.0.17'

stage open_settings
tap_contains '设置'
wait_text '设置' 30
scroll_until_text '检查更新' 8
wait_text 'V1.0.17' 20

stage check_update
tap_exact_any '检查更新'
wait_text '暂时没有正式发布版本' 60

stage verify_no_release
adb exec-out screencap -p > update-channel-result.png

echo SMOKE_PASS > result.txt
stage complete
