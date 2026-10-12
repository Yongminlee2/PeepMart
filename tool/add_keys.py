"""새 문장 열쇠를 i18n/*.json 에 넣고 lib/l10n 을 다시 만든다.

    python tool/add_keys.py keys.json

keys.json = {"열쇠": ["한국어", "English"], ...}. 다른 언어는 나중에 한꺼번에 번역할 때까지 영어를 넣어 둔다.
이미 있는 열쇠는 한국어·영어만 덮어쓴다.
"""
import collections
import glob
import json
import os
import subprocess
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
keys = json.load(open(sys.argv[1], encoding='utf-8'))
for f in glob.glob(os.path.join(root, 'i18n', '*.json')):
    lang = os.path.basename(f)[:-5]
    d = json.load(open(f, encoding='utf-8'), object_pairs_hook=collections.OrderedDict)
    for k, (ko, en) in keys.items():
        if lang == 'ko':
            d[k] = ko
        elif lang == 'en' or k not in d:
            d[k] = en
    with open(f, 'w', encoding='utf-8', newline='\n') as o:
        json.dump(d, o, ensure_ascii=False, indent=2)
        o.write('\n')
gen = os.path.join(os.path.dirname(root), 'common', 'i18n', 'gen.py')
subprocess.run([sys.executable, gen, os.path.join(root, 'i18n'), '--to', 'flutter', '--out', os.path.join(root, 'lib', 'l10n')],
               check=True, stdout=subprocess.DEVNULL)
print('keys', len(keys))
