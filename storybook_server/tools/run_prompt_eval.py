"""
일러스트 프롬프트 비교 테스트 스크립트

PROMPT_EVAL_CAPTURE=1 로 서버를 실행해 저장된 입력(prompt_eval/inputs/<시각>/)을
현재 코드의 프롬프트로 다시 생성하고, 저장 당시 이미지(before)와 나란히 비교하는 HTML을 만든다.
줄거리(장면 설명)와 그림 분석 결과(blueprints.json)는 저장된 값을 그대로 쓰므로
이미지 차이는 프롬프트 변경에서만 나온다.

사용법 (storybook_server 폴더에서):
    python tools/run_prompt_eval.py prompt_eval/inputs/<시각> --label after
    python tools/run_prompt_eval.py prompt_eval/inputs/<시각> --label after --dry-run   # 이미지 생성 없이 프롬프트만 저장
"""
import argparse
import asyncio
import html
import json
import sys
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SERVER_DIR))

from routers import story_image as si  # noqa: E402


def _load_input(input_dir: Path):
    request = json.loads((input_dir / "request.json").read_text(encoding="utf-8"))
    blueprints = json.loads((input_dir / "blueprints.json").read_text(encoding="utf-8"))
    req = si.StoryIllustrationBatchRequest(**request)
    hero_name, _ = si._asset_name_and_desc((req.asset_descriptions or {}).get("hero"))
    return req, blueprints, hero_name


async def _generate(req, blueprints, hero_name, dry_run):
    # 그림 없는 에셋의 디자인 시트는 저장값이 없으므로 실행할 때마다 새로 생성
    design_sheets = await si.design_undrawn_assets(blueprints, req.asset_descriptions)
    if dry_run:
        return design_sheets, [
            si.PageIllustrationResponse(page_number=p.page_number, image_url="", error="dry-run") for p in req.pages
        ]
    print(f"이미지 {len(req.pages)}장을 생성합니다 (모델: {si.IMAGE_MODEL})")
    tasks = [
        si._generate_single_page(p, blueprints, hero_name, req.asset_descriptions, design_sheets)
        for p in req.pages
    ]
    return design_sheets, list(await asyncio.gather(*tasks))


def _scene_line(prompt_path: Path) -> str:
    if not prompt_path.exists():
        return ""
    for line in prompt_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("Scene Action & Composition:") or line.startswith("Narrative Flow:"):
            return line
    return ""


def _image_cell(folder: Path, page_number: int, base: Path) -> str:
    png = folder / f"page_{page_number}.png"
    if png.exists():
        return f'<img src="{png.relative_to(base).as_posix()}">'
    err = folder / f"page_{page_number}_error.txt"
    if err.exists():
        return f'<div class="err">생성 실패: {html.escape(err.read_text(encoding="utf-8"))}</div>'
    return '<div class="err">이미지 없음</div>'


def _prompt_cell(folder: Path, page_number: int) -> str:
    prompt_path = folder / f"page_{page_number}_prompt.txt"
    scene = html.escape(_scene_line(prompt_path))
    full = html.escape(prompt_path.read_text(encoding="utf-8")) if prompt_path.exists() else ""
    return f'<p class="scene">{scene}</p><details><summary>프롬프트 전문</summary><pre>{full}</pre></details>'


def _write_compare_html(input_dir: Path, req, label: str) -> Path:
    before_dir = input_dir / "before"
    after_dir = input_dir / label
    rows = []
    for p in req.pages:
        n = p.page_number
        rows.append(
            f"<h2>{n}페이지 <small>{html.escape(p.layout_type)} · 등장: {html.escape(', '.join(p.active_asset_ids))}</small></h2>"
            f'<p class="orig">원래 장면 설명: {html.escape(p.scene_prompt)}</p>'
            '<div class="row">'
            f'<div class="col"><h3>before</h3>{_image_cell(before_dir, n, input_dir)}{_prompt_cell(before_dir, n)}</div>'
            f'<div class="col"><h3>{html.escape(label)}</h3>{_image_cell(after_dir, n, input_dir)}{_prompt_cell(after_dir, n)}</div>'
            "</div>"
        )

    page = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>프롬프트 비교</title>
<style>
body {{ font-family: sans-serif; margin: 16px; background: #faf8fd; color: #2c2440; }}
.row {{ display: flex; gap: 16px; flex-wrap: wrap; }}
.col {{ flex: 1 1 420px; background: #fff; border: 1px solid #e5def0; border-radius: 12px; padding: 12px; }}
img {{ width: 100%; border-radius: 8px; }}
.scene {{ font-size: 13px; background: #f3edfa; padding: 8px; border-radius: 8px; }}
.orig {{ font-size: 13px; color: #6b5f80; }}
.err {{ padding: 40px 8px; text-align: center; color: #b00020; background: #fdecee; border-radius: 8px; }}
pre {{ white-space: pre-wrap; font-size: 12px; }}
small {{ font-weight: normal; color: #7e57c2; font-size: 13px; }}
</style></head><body>
<h1>프롬프트 비교: before vs {html.escape(label)}</h1>
<p>입력: {html.escape(input_dir.name)} · 줄거리와 그림 분석 결과는 동일하게 고정</p>
{''.join(rows)}
</body></html>"""
    out = input_dir / f"compare_{label}.html"
    out.write_text(page, encoding="utf-8")
    return out


def main():
    parser = argparse.ArgumentParser(description="일러스트 프롬프트 비교 테스트")
    parser.add_argument("input_dir", help="prompt_eval/inputs/<시각> 폴더")
    parser.add_argument("--label", default="after", help="결과를 저장할 하위 폴더 이름 (기본: after)")
    parser.add_argument("--dry-run", action="store_true", help="이미지 생성 없이 프롬프트만 저장")
    args = parser.parse_args()

    input_dir = Path(args.input_dir).resolve()
    req, blueprints, hero_name = _load_input(input_dir)
    out_dir = input_dir / args.label

    design_sheets, results = asyncio.run(_generate(req, blueprints, hero_name, args.dry_run))

    si.save_page_outputs(out_dir, req.pages, blueprints, hero_name, req.asset_descriptions, results, design_sheets)
    (out_dir / "design_sheets.json").write_text(json.dumps(design_sheets, ensure_ascii=False, indent=2), encoding="utf-8")
    html_path = _write_compare_html(input_dir, req, args.label)
    print(f"결과 폴더: {out_dir}")
    print(f"비교 화면: {html_path}")


if __name__ == "__main__":
    main()
