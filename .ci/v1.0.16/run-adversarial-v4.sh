#!/usr/bin/env bash
set -euo pipefail
python3 <<'PY'
from pathlib import Path
src = Path('.ci/v1.0.16/adversarial-v3.sh').read_text()
old = "# ROUND 1 — geometry and basic page gesture feedback\nreset\n"
new = """# ROUND 1 — geometry and basic page gesture feedback
reset
# Fresh installs default to horizontal paging. Explicitly select vertical mode before testing vertical gestures.
tap_by content-desc '设置'
wait_by text '翻页方式' 30
tap_by text '翻页方式'
wait_by text '上下' 20
tap_by text '上下'
sleep .5
adb shell input keyevent BACK || true
wait_by content-desc '添加任务，长按打开快捷功能' 30
"""
if old not in src:
    raise SystemExit('could not patch Round 1 precondition')
Path('/tmp/adversarial-v4.sh').write_text(src.replace(old, new, 1))
PY
chmod +x /tmp/adversarial-v4.sh
exec /tmp/adversarial-v4.sh
