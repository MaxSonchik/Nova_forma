#!/usr/bin/env python3
"""
Safely remove single-line comments that are NOT numbered lists (like "# 1.")
from files under the Nova_forma directory.

Rules:
- For Python files: use the `tokenize` module and drop COMMENT tokens unless they are:
  - shebang (start with #!),
  - encoding comments (# -*- coding: ... or # coding: ...),
  - numbered list comments: '# 1.' or '#1.' (optional spaces),
  - comments that start with '# N.' where N is digits.
- For other text files (.sql, .md, .txt, .yml, .ini): drop lines starting with '#' unless they match the numbered pattern or are shebang/encoding.
- Skip directories: .venv, .git, .pytest_cache, __pycache__, .ruff_cache

Backs up each file as <file>.bak before modifying.
"""

import os
import re
import sys
import io
import tokenize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_DIR = os.path.join(ROOT)
IGNORE_DIRS = {".venv", ".git", ".pytest_cache", "__pycache__", ".ruff_cache"}
TEXT_EXTS = {".sql", ".md", ".txt", ".yml", ".yaml", ".ini", ".conf"}

num_pattern = re.compile(r"^\s*#\s*\d+\.")
encoding_pattern = re.compile(r"#.*coding[:=]", re.I)

removed_count = 0
processed_files = []

for dirpath, dirnames, filenames in os.walk(TARGET_DIR):
    # skip ignored dirs
    parts = set(dirpath.split(os.sep))
    if parts & IGNORE_DIRS:
        continue

    # only process inside Nova_forma
    if 'Nova_forma' not in dirpath:
        continue

    for fn in filenames:
        path = os.path.join(dirpath, fn)
        ext = os.path.splitext(fn)[1].lower()
        # skip binary files
        if ext in {'.pyc', '.png', '.jpg', '.jpeg', '.db', '.sqlite', '.dll', '.so'}:
            continue

        try:
            if ext == '.py':
                # Read and tokenize
                with open(path, 'rb') as f:
                    src = f.read()
                try:
                    tokens = list(tokenize.tokenize(io.BytesIO(src).readline))
                except tokenize.TokenError:
                    # fallback: skip file
                    print(f"Skipping (tokenize error): {path}")
                    continue

                new_tokens = []
                changed = False
                for tok in tokens:
                    ttype = tok.type
                    tstring = tok.string
                    if ttype == tokenize.COMMENT:
                        txt = tstring
                        # keep shebang and encoding and numbered
                        if txt.startswith('#!') or encoding_pattern.search(txt) or num_pattern.match(txt):
                            new_tokens.append(tok)
                        else:
                            # drop comment
                            changed = True
                            removed_count += 1
                    else:
                        new_tokens.append(tok)

                if changed:
                    # untokenize
                    new_src = tokenize.untokenize(new_tokens)
                    # backup
                    bak = path + '.bak'
                    if not os.path.exists(bak):
                        open(bak, 'wb').write(src)
                    with open(path, 'w', encoding='utf-8') as f:
                        f.write(new_src)
                    processed_files.append(path)

            elif ext in TEXT_EXTS:
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                new_lines = []
                changed = False
                for i, line in enumerate(lines):
                    if line.lstrip().startswith('#'):
                        txt = line.lstrip()
                        if txt.startswith('#!') or encoding_pattern.search(txt) or num_pattern.match(txt):
                            new_lines.append(line)
                        else:
                            changed = True
                            removed_count += 1
                    else:
                        new_lines.append(line)
                if changed:
                    bak = path + '.bak'
                    if not os.path.exists(bak):
                        open(bak, 'w', encoding='utf-8').write(''.join(lines))
                    with open(path, 'w', encoding='utf-8') as f:
                        f.write(''.join(new_lines))
                    processed_files.append(path)
            else:
                # skip other extensions
                continue
        except Exception as e:
            print(f"Error processing {path}: {e}")

print(f"Processed {len(processed_files)} files, removed ~{removed_count} comments")
if processed_files:
    print("Files modified:")
    for p in processed_files:
        print(p)
