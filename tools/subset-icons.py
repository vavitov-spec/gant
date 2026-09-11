#!/usr/bin/env python3
"""Пересборка подрезанного шрифта иконок.

Полный tabler-icons содержит 6001 иконку (809 КБ woff2), приложению нужно ~75.
Скрипт вытаскивает имена ti-* из construction_gantt.html, добавляет те, что
собираются в шаблонах (их в исходнике целиком нет), и режет шрифт под них.

Запуск из корня проекта:  /root/.venvs/fonttools/bin/python tools/subset-icons.py
Нужны: vendor/fonts/tabler-icons.ttf и vendor/tabler-icons.min.css (полные версии).
"""
import io, re, sys
from fontTools import subset
from fontTools.ttLib import TTFont

# имена, которые в коде собираются из кусков: `ti-eye${t.hidden?'-off':''}`,
# `ti-chevron-${open?'down':'right'}` — статическим поиском они не находятся
DYNAMIC = {'ti-eye-off', 'ti-chevron-right', 'ti-chevron-down'}

html = io.open('construction_gantt.html', encoding='utf-8').read()
css  = io.open('vendor/tabler-icons.min.css', encoding='utf-8').read()

used = set(re.findall(r'\bti-[a-z0-9-]+', html)) | DYNAMIC
mapping = dict(re.findall(r'\.(ti-[a-z0-9-]+):before\{content:"\\([0-9a-f]+)"\}', css))
keep = {n: cp for n, cp in mapping.items() if n in used}

missing = sorted(n for n in used if n not in mapping and n != 'ti-chevron-')
if missing:
    print('ВНИМАНИЕ: нет в шрифте:', missing, file=sys.stderr)

font = TTFont('vendor/fonts/tabler-icons.ttf')
opts = subset.Options(); opts.flavor='woff2'; opts.desubroutinize=True
opts.layout_features=[]; opts.notdef_outline=False
s = subset.Subsetter(options=opts)
s.populate(unicodes=[int(cp,16) for cp in keep.values()])
s.subset(font)
font.flavor='woff2'
font.save('vendor/fonts/tabler-icons-subset.woff2')

head = ('/* Tabler Icons 3.34.1 — подрезанный набор: только иконки, используемые в приложении.\n'
        '   Пересобрать: tools/subset-icons.py (нужен полный tabler-icons.ttf + tabler-icons.min.css) */\n'
        '@font-face{font-family:"tabler-icons";font-style:normal;font-weight:400;'
        'font-display:swap;src:url("./fonts/tabler-icons-subset.woff2") format("woff2")}\n'
        '.ti{font-family:"tabler-icons" !important;speak:none;font-style:normal;font-weight:normal;'
        'font-variant:normal;text-transform:none;line-height:1;-webkit-font-smoothing:antialiased;'
        '-moz-osx-font-smoothing:grayscale}\n')
rules = ''.join('.%s:before{content:"\\%s"}' % (n, keep[n]) for n in sorted(keep))
io.open('vendor/tabler-icons-subset.css','w',encoding='utf-8').write(head + rules + '\n')
print('иконок в наборе: %d из %d' % (len(keep), len(mapping)))
