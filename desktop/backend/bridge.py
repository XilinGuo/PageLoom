"""One translation per process, with newline-delimited JSON on stdio."""

import asyncio
from contextlib import aclosing
from ctypes import WinDLL, wintypes
import json
import logging
import msvcrt
from pathlib import Path
import shutil
import sys
from tempfile import TemporaryDirectory
from typing import get_args


def emit(kind, **fields):
    print("PDFMATH " + json.dumps({"type": kind, **fields}, default=str), flush=True)


def settings_schema():
    from pdf2zh_next.config.model import PDFSettings, TranslationSettings
    from pdf2zh_next.config.translate_engine_model import (
        GUI_PASSWORD_FIELDS,
        GUI_SENSITIVE_FIELDS,
        TRANSLATION_ENGINE_METADATA,
    )
    from pdf2zh_next.ui_settings import lang_map

    engines = []
    for metadata in TRANSLATION_ENGINE_METADATA:
        fields = []
        for name, field in metadata.setting_model_type.model_fields.items():
            if name in {"translate_engine_type", "support_llm"} or field.default_factory:
                continue
            gui = (field.json_schema_extra or {}).get("gui", {})
            types = get_args(field.annotation) or (field.annotation,)
            fields.append({
                "name": name,
                "label": field.description or name,
                "type": next(kind.__name__ for kind in (str, int, bool) if kind in types),
                "default": gui.get("default_on_show", field.get_default()),
                "secret": name in GUI_PASSWORD_FIELDS,
                "sensitive": name in GUI_SENSITIVE_FIELDS,
                "choices": gui.get("choices"),
                "visibleWhen": gui.get("visible_when"),
            })
        engines.append({
            "id": metadata.translate_engine_type,
            "llm": metadata.support_llm,
            "fields": fields,
        })
    return {
        "engines": engines,
        "languages": lang_map,
        "pdf": PDFSettings().model_dump(),
        "translation": TranslationSettings().model_dump(),
    }


def build_settings(request, output, glossaries):
    from pdf2zh_next.config.model import SettingsModel
    from pdf2zh_next.ui_settings import calculate_rate_limit_params

    translation = {
        **request["translation"],
        "lang_in": request["from"],
        "lang_out": request["to"],
        "output": str(output),
        "glossaries": ",".join(glossaries) or None,
    }
    main_engine = request["engine"]
    term_engine = request.get("termEngine")
    if main_engine["translate_engine_type"] != "SiliconFlowFree":
        rate = request["rate"]
        translation["qps"], translation["pool_max_workers"] = (
            calculate_rate_limit_params(rate["mode"], rate)
        )
    if not translation.get("no_auto_extract_glossary"):
        term_rate = request.get("termRate")
        if term_rate and term_rate["mode"] != "inherit":
            translation["term_qps"], translation["term_pool_max_workers"] = (
                calculate_rate_limit_params(term_rate["mode"], term_rate)
            )
    else:
        term_engine = None

    settings = SettingsModel.model_validate({
        "report_interval": 0.2,
        "translation": translation,
        "pdf": {
            **request["pdf"],
            "pages": request.get("pages") or None,
            "no_dual": request["format"] == "mono",
            "no_mono": request["format"] == "dual",
        },
        "translate_engine_settings": main_engine,
        "term_extraction_engine_settings": term_engine,
    })
    settings.parse_pages()
    return settings


async def translate(request):
    emit("stage", stage="正在加载翻译引擎")
    from babeldoc.assets import assets

    source = Path(request["source"]).resolve(strict=True)
    output = Path(request["output"]).resolve()
    if not source.is_file() or source.suffix.lower() != ".pdf":
        raise ValueError("请选择有效的 PDF 文件。")
    emit("stage", stage="正在准备排版模型和字体")
    engine_dir = Path(__file__).resolve().parent
    if any(engine_dir.glob("offline_assets_*.zip")):
        # The upstream restore validates its cache and skips files already present.
        try:
            await assets.restore_offline_assets_package_async(engine_dir)
        except SystemExit as error:
            raise RuntimeError("便携版的离线模型或字体资源缺失或损坏。") from error

    with TemporaryDirectory(prefix="pdfmath-glossary-") as temporary:
        glossaries = []
        for index, filename in enumerate(request.get("glossaries", [])):
            original = Path(filename)
            copied = Path(temporary) / f"{index}-{original.name.replace(',', '_')}"
            shutil.copyfile(original, copied)
            glossaries.append(str(copied))
        settings = build_settings(request, output, glossaries)
        output.mkdir(parents=True, exist_ok=False)
        await translate_file(source, settings)


async def translate_file(source, settings):
    from pdf2zh_next.high_level import do_translate_async_stream

    emit("stage", stage="正在连接翻译服务")
    result = None
    async with aclosing(do_translate_async_stream(settings, source)) as events:
        async for event in events:
            if event["type"].startswith("progress_"):
                emit("progress", stage=event.get("stage", ""), progress=event.get("overall_progress", 0))
            elif event["type"] == "finish":
                result = event["translate_result"]
                usage = event.get("token_usage")
                if usage:
                    logging.info("Token usage: %s", json.dumps(usage))
            # The upstream API raises after emitting an error event.

    paths = [] if result is None else [
        {"kind": kind, "path": str(path)}
        for kind, path in (("mono", result.mono_pdf_path), ("dual", result.dual_pdf_path))
        if path and Path(path).is_file() and Path(path).stat().st_size > 0
    ]
    expected = {kind for kind, disabled in (("mono", settings.pdf.no_mono),
                                            ("dual", settings.pdf.no_dual)) if not disabled}
    if {file["kind"] for file in paths} != expected:
        raise RuntimeError("翻译引擎没有生成所选的输出文件。")
    glossary = getattr(result, "auto_extracted_glossary_path", None)
    if glossary and Path(glossary).is_file():
        paths.append({"kind": "glossary", "path": str(glossary)})
    emit("finish", files=paths)


async def run(request):
    task = asyncio.create_task(translate(request))
    stdin_handle = wintypes.HANDLE(msvcrt.get_osfhandle(sys.stdin.fileno()))
    peek = WinDLL("kernel32").PeekNamedPipe

    async def listen_for_cancel():
        # The GUI closes the pipe to cancel. Poll it without a pending read,
        # so native extensions can still inspect the process's standard handles.
        while peek(stdin_handle, None, 0, None, None, None):
            await asyncio.sleep(0.15)
        task.cancel()

    cancellation = asyncio.create_task(listen_for_cancel())
    try:
        await task
    except asyncio.CancelledError:
        emit("cancelled")
        return 2
    finally:
        cancellation.cancel()
    return 0


def main():
    if sys.stderr is not None:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    logging.basicConfig(level=logging.INFO, stream=sys.stderr,
                        format="%(levelname)s %(name)s: %(message)s")
    for name in ("httpx", "httpcore", "openai", "pdfminer", "peewee"):
        logging.getLogger(name).setLevel(logging.CRITICAL)
    if sys.argv[1:] == ["--check"]:
        from importlib.metadata import version

        from pdf2zh_next.high_level import do_translate_async_stream

        assert callable(do_translate_async_stream)
        emit("ready", version=version("pdf2zh-next"), babeldoc=version("babeldoc"))
        return 0

    request = {}
    try:
        if sys.argv[1:2] == ["--schema"]:
            schema = settings_schema()
            if len(sys.argv) == 3:
                Path(sys.argv[2]).write_text(
                    json.dumps(schema, ensure_ascii=False), encoding="utf-8"
                )
            else:
                emit("schema", **schema)
            return 0
        if len(sys.argv) == 4 and sys.argv[1] == "--glossary":
            from babeldoc.glossary import Glossary

            glossary = Glossary.from_csv(Path(sys.argv[2]), sys.argv[3])
            emit("glossary", count=len(glossary.entries),
                 rows=[[entry.source, entry.target] for entry in glossary.entries[:100]])
            return 0
        request = json.loads(sys.stdin.buffer.readline())
        if sys.argv[1:] == ["--validate"]:
            build_settings(request, Path.cwd(), []).validate_settings()
            emit("valid")
            return 0
        return asyncio.run(run(request))
    except Exception as error:
        details = str(error)
        if "429" in details and ("HTTPError" in details or "status code" in details):
            message = "翻译服务返回 HTTP 429（请求受限）。可以稍后重试或切换翻译服务。"
        else:
            message = details.partition("\nTraceback:")[0].strip() or type(error).__name__
        emit("error", message=message[:1200])
        return 1


if __name__ == "__main__":
    sys.exit(main())
