"""
BAR Caster OBS Overlay – Writes game status as text file for OBS
====================================================================
Reads [CasterOBS] lines from infolog.txt and writes them to a
text file that OBS can read as a "Text (GDI+)" source.

Usage:
    python caster_obs_overlay.py

OBS Setup:
    1. Start this script
    2. In OBS: Sources > + > Text (GDI+)
    3. Enable "Read from file"
    4. Select file: C:\Program Files\Beyond-All-Reason\data\caster_obs.txt
    5. Set font/color as desired

Optional: Discord webhook for auto-post after game end:
    set DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
"""

import os
import re
import time
from pathlib import Path

BAR_DATA_DIR = Path(r"C:\Program Files\Beyond-All-Reason\data")
INFOLOG_PATH = BAR_DATA_DIR / "infolog.txt"
OBS_FILE_PATH = BAR_DATA_DIR / "caster_obs.txt"
POLL_INTERVAL = 3

def main():
    print("=" * 50)
    print("  BAR Caster OBS Overlay v1.0")
    print("=" * 50)
    print(f"  Infolog: {INFOLOG_PATH}")
    print(f"  OBS file: {OBS_FILE_PATH}")
    print()

    if not INFOLOG_PATH.exists():
        print("Waiting for BAR to start...")
        while not INFOLOG_PATH.exists():
            time.sleep(5)

    print("infolog.txt found! Waiting for game data...")
    last_file_size = 0
    last_status = ""

    # Discord webhook (optional)
    discord_url = os.environ.get("DISCORD_WEBHOOK_URL")
    if discord_url:
        print("Discord webhook active!")

    while True:
        try:
            time.sleep(POLL_INTERVAL)

            current_size = INFOLOG_PATH.stat().st_size
            if current_size == last_file_size:
                continue
            last_file_size = current_size

            # Read last 3000 characters
            with open(INFOLOG_PATH, "r", encoding="utf-8", errors="ignore") as f:
                f.seek(max(0, current_size - 3000))
                tail = f.read()

            # Find latest [CasterOBS] line
            obs_lines = re.findall(r"\[CasterOBS\]\s*(.*)", tail)
            warn_lines = re.findall(r"\[CasterOBS:WARN\]\s*(.*)", tail)

            if obs_lines:
                status = obs_lines[-1].strip()
                warn = warn_lines[-1].strip() if warn_lines else ""

                if status != last_status:
                    last_status = status
                    # Write OBS file
                    content = status
                    if warn:
                        content += "\n" + warn
                    OBS_FILE_PATH.write_text(content, encoding="utf-8")
                    print(f"[OBS] {status}")

            # Discord: detect post-game summary
            if discord_url and "[CasterExport]" in tail:
                exports = re.findall(r"\[CasterExport\]\s*(.*)", tail)
                if exports:
                    pass  # Can be extended later

        except KeyboardInterrupt:
            print("\nStopped.")
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
