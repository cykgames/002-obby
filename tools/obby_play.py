"""002-obby A57 tap-driven verification: select -> play L1 -> finish -> unlock.

A57 portrait 1080x2340, viewport 1280x2773 @ scale 0.84375 (canvas_items/expand).
Geometry (canvas -> physical = *0.84375):
  Level 1-1 button center ~ (186, 368) physical (from screenshot).
  START/NEXT primary (540, 1276); JOY home (160, 2129); J (915, 2182).
  Camera is fixed 3/4 at (+6.5,+9,+6.5): joystick up-right (+0.707,-0.707)
  maps to pure world -Z (the L1 path direction).
L1 path from spawn z=-3: gap edges z=-6, -18.5, -31.5; goal pad -45..-51.
  Run -Z at 6 m/s -> jump takeoff (0.4m before edge) t=0.43 / 2.45 / 4.62 s.
  Single jumps suffice (gaps 2.5/3/3.5 <= 4.64m range). Finish ~8.5s.

Run: set OBBY_ADB_SERIAL then python tools/obby_play.py [full|select|run|finish]
"""
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ADB = os.environ.get("ADB_PATH") or r"C:\Android\platform-tools\adb.exe"
SER = os.environ.get("OBBY_ADB_SERIAL", "")
BUILD = str(Path(__file__).resolve().parent.parent / "build")
PKG = "com.cykagent.obby"
if not SER:
    sys.exit("set OBBY_ADB_SERIAL to your adb serial or ip:port first")
os.makedirs(BUILD, exist_ok=True)

L1_BTN = (186, 368)
START = (540, 1276)
JOY = (160, 2129)
JOY_DX, JOY_DY = 71, -71   # up-right = world -Z with the 3/4 camera
J = (915, 2182)
PAUSE = (840, 34)
LEVELS_IN_PAUSE = (540, 1300)
LEAD = float(os.environ.get("OBBY_LEAD", "0.2"))
LOG = []
_THREADS = []


def _log(msg):
    line = "%.3f %s" % (time.time(), msg)
    LOG.append(line)
    print(line, flush=True)


def sh(cmd, wait=True):
    if not wait:
        subprocess.Popen([ADB, "-s", SER, "shell", cmd],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return ""
    r = subprocess.run([ADB, "-s", SER, "shell", cmd], capture_output=True, text=True)
    return r.stdout.strip()


def tap(pt):
    _log("tap %d %d" % pt)
    sh("input tap %d %d" % pt, wait=False)


def hold(pt, ms):
    x, y = pt
    _log("hold %d %d %dms" % (x, y, ms))
    sh("input motionevent DOWN %d %d; sleep %.3f; input motionevent UP %d %d"
       % (x, y, ms / 1000.0, x, y), wait=False)


def shot(name):
    p = os.path.join(BUILD, name + ".png")

    def _cap():
        with open(p, "wb") as f:
            subprocess.run([ADB, "-s", SER, "exec-out", "screencap", "-p"],
                           stdout=f, check=True)
    t = threading.Thread(target=_cap, daemon=True)
    t.start()
    _THREADS.append(t)
    _log("shot %s" % name)
    return p


def fresh():
    sh("am force-stop " + PKG)
    sh("monkey -p " + PKG + " -c android.intent.category.LAUNCHER 1")
    time.sleep(4.0)


def select():
    fresh()
    shot("a57_01_select")
    tap(L1_BTN)
    time.sleep(2.0)
    shot("a57_02_title")


def run():
    """Assumes the L1 title gate is showing (after select())."""
    t0 = time.time() + LEAD
    tap(START)
    # Hold the stick up-right for the whole run.
    sh("input motionevent DOWN %d %d; input motionevent MOVE %d %d"
       % (JOY[0], JOY[1], JOY[0] + JOY_DX, JOY[1] + JOY_DY), wait=False)
    for tj in (0.43, 2.45, 4.62):
        target = t0 + tj
        now = time.time()
        if target > now:
            time.sleep(target - now)
        # Jump via SPACE keyevent: adb single-pointer touch cannot hold the
        # stick and tap J at once (pointer 0 conflict), but key events are a
        # separate stream and map to the same "jump" action.
        sh("input keyevent 62", wait=False)
    for ts, name in ((1.5, "a57_03_run"), (3.2, "a57_04_mid"), (9.0, "a57_05_finish")):
        target = t0 + ts
        now = time.time()
        if target > now:
            time.sleep(target - now)
        shot(name)
    sh("input motionevent UP %d %d" % (JOY[0] + JOY_DX, JOY[1] + JOY_DY), wait=False)
    _log("RUN_DONE t0=%.3f" % t0)


def finish():
    """At the finish screen: capture, NEXT LEVEL -> L2 title, pause -> LEVELS,
    capture the select screen (must show stars on 1-1 and 1-2 unlocked)."""
    time.sleep(1.0)
    shot("a57_06_finish_buttons")
    tap(START)          # NEXT LEVEL
    time.sleep(2.0)
    shot("a57_07_l2_title")
    tap(PAUSE)
    time.sleep(0.8)
    shot("a57_08_pause")
    tap(LEVELS_IN_PAUSE)
    time.sleep(2.0)
    shot("a57_09_select_stars")
    _log("FINISH_DONE")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "full"
    sh("settings put system screen_off_timeout 600000")
    sh("input keyevent KEYCODE_WAKEUP")
    if cmd in ("select", "full"):
        select()
    if cmd in ("run", "full"):
        run()
    if cmd in ("finish", "full"):
        finish()
    for t in _THREADS:
        t.join(timeout=15)
    with open(os.path.join(BUILD, "obby_play_log.txt"), "a", encoding="utf-8") as f:
        f.write("\n".join(LOG) + "\n")
    print("DONE")
