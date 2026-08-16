#!/usr/bin/env bash
set -euo pipefail
PKG=com.qinghao.qingji

dump_ui(){ local o="${1:-ui.xml}"; adb shell uiautomator dump /data/local/tmp/qj.xml >/dev/null 2>&1 || true; adb exec-out cat /data/local/tmp/qj.xml > "$o"; }
center_by(){ local a="$1" v="$2"; dump_ui /tmp/ui.xml; python3 - "$a" "$v" <<'PY'
import re,sys,xml.etree.ElementTree as ET
a,v=sys.argv[1:3]
for n in ET.parse('/tmp/ui.xml').getroot().iter('node'):
    if n.attrib.get(a,'')==v:
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); raise SystemExit(0)
raise SystemExit(2)
PY
}
tap_by(){ read -r x y < <(center_by "$1" "$2"); adb shell input tap "$x" "$y"; }
launch(){ adb shell input keyevent HOME >/dev/null 2>&1 || true; adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 1; }
grant_all(){ adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true; adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true; }
reset(){ adb shell pm clear "$PKG" >/dev/null; grant_all; launch; }

set_time(){
  local off="$1" h m now target th tm th2 tm2
  h="$(adb shell date +%H|tr -d '\r')"; m="$(adb shell date +%M|tr -d '\r')"; now=$((10#$h*60+10#$m)); target=$(((now+off)%1440)); th=$((target/60)); tm=$((target%60)); printf -v th2 '%02d' "$th"; printf -v tm2 '%02d' "$tm"
  echo "$th2:$tm2" >> reminder-targets.txt
  tap_by text '无'; sleep .5; tap_by content-desc 'Switch to text input mode for the time input.'; sleep .4
  if center_by resource-id android:id/input_hour >/tmp/hc 2>/dev/null; then read -r x y </tmp/hc; else read -r x y < <(center_by resource-id android:id/hours); fi
  adb shell input tap "$x" "$y"; adb shell input keyevent MOVE_END; adb shell input keyevent DEL DEL DEL || true; adb shell input text "$th2"
  if center_by resource-id android:id/input_minute >/tmp/mc 2>/dev/null; then read -r x y </tmp/mc; else read -r x y < <(center_by resource-id android:id/minutes); fi
  adb shell input tap "$x" "$y"; adb shell input keyevent MOVE_END; adb shell input keyevent DEL DEL DEL || true; adb shell input text "$tm2"; adb shell input keyevent BACK || true; sleep .2; tap_by text OK; sleep .5
}
create_timed(){ local name="$1" off="$2"; tap_by content-desc '添加任务，长按打开快捷功能'; sleep .3; adb shell input text "$name"; sleep .2; set_time "$off"; tap_by text '添加'; sleep .8; }

# Round 1: geometry and launch regression
reset
tap_by content-desc '添加任务，长按打开快捷功能'; adb shell input text CI_Geometry; tap_by text '添加'; sleep .5
adb exec-out screencap -p > r1-home.png
adb shell input swipe 540 850 540 1500 5000 >/dev/null 2>&1 & p=$!; sleep 2.8; dump_ui r1-prev.xml; adb exec-out screencap -p > r1-prev.png; wait $p || true; sleep .5
adb shell input tap 930 1990 || true; sleep .4
adb shell input swipe 540 1600 540 850 5000 >/dev/null 2>&1 & p=$!; sleep 2.8; dump_ui r1-next.xml; adb exec-out screencap -p > r1-next.png; wait $p || true
python3 <<'PY'
import re,xml.etree.ElementTree as ET
def r(n):
 m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib['bounds']); return tuple(map(int,m.groups()))
def ns(p): return list(ET.parse(p).getroot().iter('node'))
p,q=ns('r1-prev.xml'),ns('r1-next.xml')
hp=next(n for n in p if '查看上一' in n.attrib.get('text','')); hq=next(n for n in q if '查看下一' in n.attrib.get('text',''))
header=max(r(n)[3] for n in p if n.attrib.get('content-desc') in ('切换今日、本周、本月或本年','设置'))
fab=next(n for n in q if n.attrib.get('content-desc')=='添加任务，长按打开快捷功能')
py=(r(hp)[1]+r(hp)[3])//2; qy=(r(hq)[1]+r(hq)[3])//2
print('geometry',py,header,qy,r(fab)[1]); assert header < py < 900; assert 1100 < qy; assert r(hq)[3] < r(fab)[1]-20
PY
echo ROUND1_PASS | tee r1-result.txt

# Round 2: daily-repeat delete dialog cannot lose its actions
reset
tap_by content-desc '添加任务，长按打开快捷功能'; adb shell input text CI_Repeat; tap_by text '每日重复'; tap_by text '添加'; sleep .7
read -r tx ty < <(center_by text CI_Repeat); adb shell input swipe 850 "$ty" 300 "$ty" 650; sleep .5; tap_by content-desc 删除; sleep .5
dump_ui r2-delete.xml; adb exec-out screencap -p > r2-delete.png; grep -q '仅删除这一天' r2-delete.xml; grep -q '停止每日重复' r2-delete.xml; grep -q '取消' r2-delete.xml
tap_by text '仅删除这一天'; sleep .7; dump_ui r2-after.xml; ! grep -q 'text="CI_Repeat"' r2-after.xml
echo ROUND2_PASS | tee r2-result.txt

# Round 3: exact alarm survives process death and really posts
reset; adb logcat -c; create_timed CI_Kill 2
adb shell dumpsys alarm > r3-before.txt; grep -q "$PKG" r3-before.txt; adb shell input keyevent HOME; adb shell am kill "$PKG" || true; sleep 1; adb shell dumpsys alarm > r3-after-kill.txt; grep -q "$PKG" r3-after-kill.txt
f=0; for i in $(seq 1 36); do adb logcat -d -v brief -s QingJiReminder:I '*:S' > r3-live.txt 2>&1 || true; grep -q 'notification posted' r3-live.txt && { f=1; break; }; sleep 5; done; test "$f" -eq 1
adb shell dumpsys notification --noredact > r3-notifications.txt; grep -q CI_Kill r3-notifications.txt; adb shell cmd statusbar expand-notifications || true; sleep .5; adb exec-out screencap -p > r3-notification.png || true; adb shell cmd statusbar collapse || true
echo ROUND3_PASS | tee r3-result.txt

# Round 4A: hostile permissions - task must save and app must stay healthy
adb shell pm clear "$PKG" >/dev/null; adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS || true; adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM deny || true; launch
create_timed CI_Denied 5 || true; sleep .5; dump_ui r4-permission.xml; adb exec-out screencap -p > r4-permission.png || true; adb shell input keyevent BACK || true; sleep .4
adb shell dumpsys alarm > r4-inexact.txt; grep -q "$PKG" r4-inexact.txt; adb shell pidof "$PKG" > r4-pid.txt; test -s r4-pid.txt
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true; adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true; launch; adb shell dumpsys alarm > r4-after-grant.txt; grep -q "$PKG" r4-after-grant.txt

# Round 4B: completion must cancel future task notification
adb shell pm clear "$PKG" >/dev/null; grant_all; launch; adb logcat -c; create_timed CI_Cancel 2; tap_by content-desc 完成任务; sleep .7; adb shell input keyevent HOME; adb shell am kill "$PKG" || true; sleep 135
adb logcat -d -v brief -s QingJiReminder:I '*:S' > r4-cancel-log.txt 2>&1 || true; adb shell dumpsys notification --noredact > r4-notifications.txt || true
! grep -q CI_Cancel r4-notifications.txt
echo ROUND4_PASS | tee r4-result.txt
