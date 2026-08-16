#!/usr/bin/env bash
set -euo pipefail
PKG=com.qinghao.qingji

dump_ui(){
  local o="${1:-ui.xml}"
  adb shell uiautomator dump /data/local/tmp/qj.xml >/dev/null 2>&1 || true
  adb exec-out cat /data/local/tmp/qj.xml > "$o" 2>/dev/null || true
}
center_by(){
  local a="$1" v="$2"
  dump_ui /tmp/ui.xml
  python3 - "$a" "$v" <<'PY'
import re,sys,xml.etree.ElementTree as ET
a,v=sys.argv[1:3]
try: root=ET.parse('/tmp/ui.xml').getroot()
except Exception: raise SystemExit(2)
for n in root.iter('node'):
    if n.attrib.get(a,'')==v:
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); raise SystemExit(0)
raise SystemExit(2)
PY
}
wait_by(){
  local a="$1" v="$2" tries="${3:-30}"
  for _ in $(seq 1 "$tries"); do center_by "$a" "$v" >/dev/null 2>&1 && return 0; sleep .5; done
  dump_ui wait-failed.xml
  echo "WAIT FAILED: $a=$v" >&2
  return 1
}
tap_by(){ wait_by "$1" "$2"; read -r x y < <(center_by "$1" "$2"); adb shell input tap "$x" "$y"; }
launch(){
  adb shell input keyevent HOME >/dev/null 2>&1 || true
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
  wait_by content-desc '添加任务，长按打开快捷功能' 40
}
grant_all(){ adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true; adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true; }
reset(){ adb shell pm clear "$PKG" >/dev/null; grant_all; launch; }

set_time(){
  local off="$1" h m now target th tm th2 tm2
  h="$(adb shell date +%H|tr -d '\r')"; m="$(adb shell date +%M|tr -d '\r')"
  now=$((10#$h*60+10#$m)); target=$(((now+off)%1440)); th=$((target/60)); tm=$((target%60))
  printf -v th2 '%02d' "$th"; printf -v tm2 '%02d' "$tm"
  echo "$th2:$tm2" >> reminder-targets.txt
  tap_by text '无'; wait_by content-desc 'Switch to text input mode for the time input.' 20
  tap_by content-desc 'Switch to text input mode for the time input.'; sleep .3
  if center_by resource-id android:id/input_hour >/tmp/hc 2>/dev/null; then read -r x y </tmp/hc; else read -r x y < <(center_by resource-id android:id/hours); fi
  adb shell input tap "$x" "$y"; adb shell input keyevent MOVE_END; adb shell input keyevent DEL DEL DEL || true; adb shell input text "$th2"
  if center_by resource-id android:id/input_minute >/tmp/mc 2>/dev/null; then read -r x y </tmp/mc; else read -r x y < <(center_by resource-id android:id/minutes); fi
  adb shell input tap "$x" "$y"; adb shell input keyevent MOVE_END; adb shell input keyevent DEL DEL DEL || true; adb shell input text "$tm2"
  adb shell input keyevent BACK || true; sleep .2; tap_by text OK; sleep .4
}
create_timed(){
  local name="$1" off="$2"
  tap_by content-desc '添加任务，长按打开快捷功能'; wait_by text '添加' 20
  adb shell input text "$name"; sleep .2; set_time "$off"; tap_by text '添加'; wait_by text "$name" 30
}

# ROUND 1 — geometry and basic page gesture feedback
reset
tap_by content-desc '添加任务，长按打开快捷功能'; wait_by text '添加'; adb shell input text CI_Geometry; tap_by text '添加'; wait_by text CI_Geometry 30
adb exec-out screencap -p > r1-home.png
adb shell input swipe 540 850 540 1500 5000 >/dev/null 2>&1 & p=$!; sleep 2.8; dump_ui r1-prev.xml; adb exec-out screencap -p > r1-prev.png; wait $p || true; sleep .6
adb shell input tap 930 1990 || true; sleep .5
adb shell input swipe 540 1600 540 850 5000 >/dev/null 2>&1 & p=$!; sleep 2.8; dump_ui r1-next.xml; adb exec-out screencap -p > r1-next.png; wait $p || true
python3 <<'PY'
import re,xml.etree.ElementTree as ET
def r(n):
 m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib['bounds']); return tuple(map(int,m.groups()))
def ns(p): return list(ET.parse(p).getroot().iter('node'))
p,q=ns('r1-prev.xml'),ns('r1-next.xml')
hp=next(n for n in p if '查看上一' in n.attrib.get('text',''))
hq=next(n for n in q if '查看下一' in n.attrib.get('text',''))
header=max(r(n)[3] for n in p if n.attrib.get('content-desc') in ('切换今日、本周、本月或本年','设置'))
fab=next(n for n in q if n.attrib.get('content-desc')=='添加任务，长按打开快捷功能')
py=(r(hp)[1]+r(hp)[3])//2; qy=(r(hq)[1]+r(hq)[3])//2
print('geometry prevY/header/nextY/fabTop=',py,header,qy,r(fab)[1])
assert header < py < 900, ('bad previous hint',py,header)
assert qy > 1100, ('next hint too high',qy)
assert r(hq)[3] < r(fab)[1]-20, ('next hint overlaps FAB',r(hq),r(fab))
PY
echo ROUND1_PASS | tee r1-result.txt

# ROUND 2 — recurring delete sheet must expose both destructive scopes
reset
tap_by content-desc '添加任务，长按打开快捷功能'; wait_by text '添加'; adb shell input text CI_Repeat; tap_by text '每日重复'; tap_by text '添加'; wait_by text CI_Repeat 30
read -r tx ty < <(center_by text CI_Repeat); adb shell input swipe 850 "$ty" 300 "$ty" 650; wait_by content-desc 删除 20; tap_by content-desc 删除
wait_by text '仅删除这一天' 20; wait_by text '停止每日重复' 5; wait_by text '取消' 5
dump_ui r2-delete.xml; adb exec-out screencap -p > r2-delete.png
tap_by text '仅删除这一天'; sleep .7; dump_ui r2-after.xml; ! grep -q 'text="CI_Repeat"' r2-after.xml
echo ROUND2_PASS | tee r2-result.txt

# ROUND 3 — exact reminder must survive ordinary process death
reset; adb logcat -c; create_timed CI_Kill 2
adb shell dumpsys alarm > r3-before.txt; grep -q "$PKG" r3-before.txt
adb shell input keyevent HOME; adb shell am kill "$PKG" || true; sleep 1
adb shell dumpsys alarm > r3-after-kill.txt; grep -q "$PKG" r3-after-kill.txt
f=0
for i in $(seq 1 40); do
  adb logcat -d -v brief -s QingJiReminder:I '*:S' > r3-live.txt 2>&1 || true
  if grep -q 'notification posted' r3-live.txt; then f=1; break; fi
  sleep 5
done
test "$f" -eq 1
adb shell dumpsys notification --noredact > r3-notifications.txt; grep -q CI_Kill r3-notifications.txt
adb shell cmd statusbar expand-notifications || true; sleep .6; adb exec-out screencap -p > r3-notification.png || true; adb shell cmd statusbar collapse || true
echo ROUND3_PASS | tee r3-result.txt

# ROUND 4A — deny both notification + exact alarm, task still saves and app stays healthy
adb shell pm clear "$PKG" >/dev/null
adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS || true
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM deny || true
launch
# Create task. Permission UI is allowed to interrupt; task persistence is what matters here.
tap_by content-desc '添加任务，长按打开快捷功能'; wait_by text 添加; adb shell input text CI_Denied; set_time 5; tap_by text 添加; sleep 1
dump_ui r4-permission.xml; adb exec-out screencap -p > r4-permission.png || true
adb shell input keyevent BACK || true; sleep .5
adb shell dumpsys alarm > r4-inexact.txt; grep -q "$PKG" r4-inexact.txt
adb shell pidof "$PKG" > r4-pid.txt; test -s r4-pid.txt
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true
launch; sleep .6; adb shell dumpsys alarm > r4-after-grant.txt; grep -q "$PKG" r4-after-grant.txt

# ROUND 4B — completing before due time must cancel notification
adb shell pm clear "$PKG" >/dev/null; grant_all; launch; adb logcat -c; create_timed CI_Cancel 2
wait_by content-desc 完成任务 20; tap_by content-desc 完成任务; sleep .7
adb shell input keyevent HOME; adb shell am kill "$PKG" || true; sleep 135
adb logcat -d -v brief -s QingJiReminder:I '*:S' > r4-cancel-log.txt 2>&1 || true
adb shell dumpsys notification --noredact > r4-notifications.txt || true
! grep -q CI_Cancel r4-notifications.txt
echo ROUND4_PASS | tee r4-result.txt
