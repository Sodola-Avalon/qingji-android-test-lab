#!/usr/bin/env bash
set -euo pipefail

wait_text() {
  local text="$1"; local tries="${2:-40}"
  for i in $(seq 1 "$tries"); do
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
    adb pull /sdcard/window.xml window.xml >/dev/null 2>&1 || true
    grep -Fq "$text" window.xml 2>/dev/null && return 0
    sleep .5
  done
  echo "missing UI text: $text" >&2
  adb exec-out screencap -p > failure.png || true
  exit 1
}

tap_text() {
  local text="$1"
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1
  adb pull /sdcard/window.xml window.xml >/dev/null 2>&1
  python3 - "$text" <<'PY'
import re,sys,xml.etree.ElementTree as ET,subprocess
q=sys.argv[1]
root=ET.parse('window.xml').getroot()
for n in root.iter('node'):
    if q in n.attrib.get('text','') or q in n.attrib.get('content-desc',''):
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x=(int(m.group(1))+int(m.group(3)))//2
            y=(int(m.group(2))+int(m.group(4)))//2
            subprocess.check_call(['adb','shell','input','tap',str(x),str(y)])
            raise SystemExit(0)
raise SystemExit('not found: '+q)
PY
}

adb install QingJi-v1.0.16.apk
adb shell pm grant com.qinghao.qingji android.permission.POST_NOTIFICATIONS || true
adb shell monkey -p com.qinghao.qingji -c android.intent.category.LAUNCHER 1 >/dev/null
wait_text '添加任务' 60 || wait_text '今天还没有任务' 60
tap_text '添加任务'
wait_text '添加' 30
adb shell input text Upgrade_Persist
tap_text '添加'
wait_text 'Upgrade_Persist' 30

adb install -r QingJi-v1.0.17.apk
adb shell monkey -p com.qinghao.qingji -c android.intent.category.LAUNCHER 1 >/dev/null
wait_text 'Upgrade_Persist' 60
adb shell dumpsys package com.qinghao.qingji | grep -q 'versionName=1.0.17'

tap_text '设置'
wait_text '检查更新' 60
wait_text 'V1.0.17' 30
tap_text '检查更新'
wait_text '暂时没有正式发布版本' 60
adb exec-out screencap -p > update-channel-result.png

echo SMOKE_PASS > result.txt
