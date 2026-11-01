"""Summarize six CPU captures with frame=1..300; protect existing metrics.json."""
from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import asdict
from pathlib import Path
from typing import TYPE_CHECKING

CHECKER_DIRECTORY = Path(__file__).resolve().parents[1] / "_teacher_check"
if CHECKER_DIRECTORY.is_dir():
    sys.path.insert(0, str(CHECKER_DIRECTORY))
if TYPE_CHECKING:
    from .._teacher_check.check_submission import InvalidSubmission, calculate_metrics, read_run
else:
    from check_submission import InvalidSubmission, calculate_metrics, read_run


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args(argv)
    output = args.folder / "metrics.json"
    try:
        if output.is_file() and not args.overwrite:
            raise InvalidSubmission(output, "уже существует; используйте --overwrite")
        calculated = calculate_metrics(args.folder)
        metrics: dict[str, object] = dict(calculated)
        metrics["iqr_method"] = "inclusive"
        metrics["per_run"] = {
            f"{phase}_{index}.csv": asdict(read_run(args.folder / f"{phase}_{index}.csv"))
            for phase in ("before", "after") for index in range(1, 4)
        }
        with output.open("w" if args.overwrite else "x", encoding="utf-8") as stream:
            stream.write(json.dumps(metrics, ensure_ascii=False, allow_nan=False, indent=2) + "\n")
    except (InvalidSubmission, UnicodeError, csv.Error, FileExistsError) as error:
        print(f"Ошибка данных: {error}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"Ошибка окружения: {error}", file=sys.stderr)
        return 2
    if calculated["speedup"] <= 1:
        print("Предупреждение: ускорение не получено.")
    print(f"Записано: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
