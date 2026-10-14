"""아이폰 시뮬레이터 화면 찍기 — 화면 확인과 앱스토어 스크린샷(6.9형 1320×2868).

    ~/flutter/bin/flutter build ios --simulator --debug
    SHOT_SAVE=100 ~/flutter/bin/flutter test test/shot_save_test.dart   # 키운 가게 저장(없으면 새 가게)
    python3 tool/ios_shots.py <시뮬레이터 UDID> [--langs ko,en] [--shots game,build] [--out build/ios-shots]

이 맥의 시뮬레이터는 탭이 앱에 안 닿아서, 디버그 빌드가 실행 인자 `-shot <화면> -lang <언어>` 로
화면을 연다(lib/ui/debug_shot.dart). 같은 맥의 다른 작업이 시뮬레이터를 끄면 다시 켜고 찍는다.
"""
import argparse
import os
import shutil
import subprocess
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build/ios/iphonesimulator/Runner.app")
BUNDLE = "com.peep.mart"
SHOTS = ["game", "build", "closed", "map", "regulars", "dex", "title", "story", "help"]
LANGS = ["en", "ko", "ja", "zh", "zh_Hant", "es", "fr", "de", "it", "pt", "ru", "th", "vi", "id"]
WAIT = {"game": 9, "build": 9, "closed": 9}


def run(*a, check=True):
    return subprocess.run(a, check=check, capture_output=True, text=True).stdout


def ensure_booted(udid):
    if "Booted" not in run("xcrun", "simctl", "list", "devices", udid):
        run("xcrun", "simctl", "boot", udid, check=False)
        run("xcrun", "simctl", "bootstatus", udid, "-b")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("udid")
    ap.add_argument("--langs", default="ko")
    ap.add_argument("--shots", default=",".join(SHOTS))
    ap.add_argument("--out", default=os.path.join(ROOT, "build/ios-shots"))
    a = ap.parse_args()
    ensure_booted(a.udid)
    run("xcrun", "simctl", "install", a.udid, APP)
    run("xcrun", "simctl", "status_bar", a.udid, "override", "--time", "9:41", "--batteryState", "charged",
        "--batteryLevel", "100", "--cellularBars", "4", "--wifiBars", "3")
    data = run("xcrun", "simctl", "get_app_container", a.udid, BUNDLE, "data").strip()
    save = os.path.join(ROOT, "build/shot_save.json")
    docs = os.path.join(data, "Documents")
    os.makedirs(docs, exist_ok=True)
    if os.path.exists(save):
        shutil.copy(save, os.path.join(docs, "shot_save.json"))
    for lang in a.langs.split(","):
        os.makedirs(os.path.join(a.out, lang), exist_ok=True)
        for i, shot in enumerate(a.shots.split(",")):
            out = os.path.join(a.out, lang, f"{i + 1:02d}_{shot}.png")
            for _ in range(3):
                ensure_booted(a.udid)
                run("xcrun", "simctl", "terminate", a.udid, BUNDLE, check=False)
                run("xcrun", "simctl", "launch", a.udid, BUNDLE, "-shot", shot, "-lang", lang)
                time.sleep(WAIT.get(shot, 6))
                run("xcrun", "simctl", "io", a.udid, "screenshot", out, check=False)
                if os.path.exists(out) and os.path.getsize(out) > 100_000:
                    break
            print(out)
    run("xcrun", "simctl", "terminate", a.udid, BUNDLE, check=False)


if __name__ == "__main__":
    main()
