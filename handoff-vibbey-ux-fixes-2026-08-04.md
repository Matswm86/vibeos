# Handoff: Vibbey UX fixes + rebuild (2026-08-04)

User tested the installed MSI system (June 11 image): Vibbey replies overflowed the
bubble, the `y`-confirm cancelled, and the model "didn't understand shit" (that one =
no network on the June image → silent fallback to local qwen2.5:3b instead of Groq
llama-3.3-70b; networking was already fixed in `a28c13f` 08-03).

## Shipped — commit `7e07794` on v2 (pushed)

- `vibbey/static/style.css`: speech bubble wraps (`pre-wrap` + `overflow-wrap:
  anywhere`), grows to 45vh (50vh widget) and scrolls; widget-mode
  `pointer-events: none` removed — long replies were unscrollable/unreadable.
- `vibbey/static/main.js`: y-confirm protocol REMOVED. Natural-language yes/no
  (EN + NO: ja/jo/kjør/nei/ikke/avbryt...), negation wins ("dont run that" never
  executes — regex-tested), off-topic reply routes to the model as normal chat.
  Bubble strips markdown (`**`, backticks, headings); system prompt bans markdown.

## Image rebuilt 08-04 13:2x — GREEN

- `mkosi.output/vibeos.raw` 16.7G, all 20 verify-iso checks passed (incl. wifi/
  netplan/apt/sudo guards). New main.js confirmed inside
  `packages/local/vibeos-vibbey_2.0.0-day3_all.deb` (built 12:42 from source).
- Build used `VIBEOS_SCRATCH=/home/mats/vibeos-scratch` (ENOSPC lesson from 08-03).

## Next: flash + reinstall (user runs, needs sudo password)

USB verified present: sdc = usb-SanDisk_Ultra_4C530001170104122363 (old VibeOS
stick, ESP + root-x86-64 — safe to overwrite). Do NOT touch sdb (233G backup USB).

```bash
cd ~/MWM-AI/projects/vibeos
sudo dd if=mkosi.output/vibeos.raw \
  of=/dev/disk/by-id/usb-SanDisk_Ultra_4C530001170104122363-0:0 \
  bs=4M oflag=direct conv=fsync status=progress
sync
```

Then on the MSI: boot USB → Install VibeOS (Erase → Kingston) → reboot without
USB → Vibbey onboarding → "Start Coding with Claude".

## Open

- Vibbey chat POST not exercised against live Groq in this session (server boot +
  /api/config + /api/tier + static verified locally; regexes unit-tested).
- If the small local model still misbehaves offline, next lever = bake qwen2.5:7b
  (image grows ~4G) or force Groq-only onboarding.
