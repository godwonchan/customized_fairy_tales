"""RPG 그림 분석 라우터."""

from fastapi import APIRouter, UploadFile, File, Form, HTTPException

from rpg_asset import describe_sketch

router = APIRouter(prefix="/rpg", tags=["rpg-asset"])


@router.post("/describe")
async def rpg_describe(
    asset_type: str = Form("캐릭터"),
    sketch_file: UploadFile = File(...),
):
    image_bytes = await sketch_file.read()
    mime = sketch_file.content_type or "image/png"
    try:
        desc = describe_sketch(image_bytes, mime, asset_type)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"그림 분석 실패: {e}")
    return {"description": desc, "asset_type": asset_type}
