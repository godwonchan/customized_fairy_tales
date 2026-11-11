"""'# %%' 로 나눈 .py 를 .ipynb 로. '# %% [writefile name]' 은 그 파일 내용을 %%writefile 셀로 넣는다."""
import json, os, re, sys

src_path, out_path = sys.argv[1], sys.argv[2]
base = os.path.dirname(os.path.abspath(src_path))
src = open(src_path, encoding="utf-8").read()
parts = re.split(r"^# %%(.*)$", src, flags=re.M)


def lines(text):
    ls = text.split("\n")
    return [l + "\n" for l in ls[:-1]] + ls[-1:]


cells = []
for i in range(1, len(parts), 2):
    kind, body = parts[i], parts[i + 1].strip("\n")
    m = re.search(r"\[writefile (.+?)\]", kind)
    if m:
        content = open(os.path.join(base, m.group(1)), encoding="utf-8").read().rstrip("\n")
        cells.append({"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
                      "source": lines(f"%%writefile {m.group(1)}\n{content}")})
    elif "[markdown]" in kind:
        cells.append({"cell_type": "markdown", "metadata": {},
                      "source": lines("\n".join(re.sub(r"^# ?", "", l) for l in body.split("\n")))})
    else:
        cells.append({"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [], "source": lines(body)})
nb = {"cells": cells, "metadata": {"kernelspec": {"name": "python3", "display_name": "Python 3", "language": "python"},
                                   "language_info": {"name": "python"}}, "nbformat": 4, "nbformat_minor": 5}
json.dump(nb, open(out_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(cells), "cells")
