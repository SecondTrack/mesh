#!/bin/sh
# build-emoji.sh — Noto-Emoji-Bilder (Google, Bilder Apache 2.0, Schrift OFL 1.1) für die App packen.
#
#   tools/build-emoji.sh <ordner mit emoji_u*.png aus noto-emoji/2D/png/72>
#
# Stand: Tag v2026-09-24-unicode18_0. Verkleinert auf 40 px (20 pt Retina) mit sips und schreibt
# Resources/emoji.pack (PNGs hintereinander) und Resources/emoji.idx ("schlüssel offset länge"
# je Zeile; Schlüssel = Codepunkte in Hex ohne FE0F, mit "_" verbunden, wie die Noto-Dateinamen).
set -e
SRC=${1:?Ordner mit den 72-px-PNGs}
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
for f in "$SRC"/emoji_u*.png; do
  n=$(basename "$f" .png); n=${n#emoji_u}
  sips -Z 40 "$f" --out "$T/$n.png" >/dev/null
done
python3 - "$T" <<'PY'
import os, sys
src = sys.argv[1]
names = sorted(f[:-4] for f in os.listdir(src) if f.endswith('.png'))
off = 0
with open('Resources/emoji.pack', 'wb') as pack, open('Resources/emoji.idx', 'w') as idx:
    for n in names:
        data = open(os.path.join(src, n + '.png'), 'rb').read()
        pack.write(data)
        idx.write('%s %d %d\n' % (n, off, len(data)))
        off += len(data)
print(len(names), 'Emojis,', off // 1024, 'KB')
PY
rm -rf "$T"
