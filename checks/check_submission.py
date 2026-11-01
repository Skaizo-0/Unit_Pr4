"""Check submitted evidence, not the authenticity of Unity captures or screenshots."""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class InvalidSubmission(Exception):
    path: Path
    reason: str

    def __str__(self) -> str:
        return f"{self.path}: {self.reason}"


@dataclass(frozen=True, slots=True)
class RunSummary:
    median_ms: float
    iqr_ms: float


def require_file(path: Path, minimum: int = 1) -> None:
    if not path.is_file() or path.stat().st_size < minimum:
        raise InvalidSubmission(path, f"нужен файл размером не менее {minimum} байт")


def read_run(path: Path) -> RunSummary:
    require_file(path)
    samples: list[float] = []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = csv.reader(stream, strict=True)
        if next(rows, None) != ["frame", "elapsed_ms", "checksum", "queries", "valid"]:
            raise InvalidSubmission(path, "неверный заголовок CSV")
        for index, row in enumerate(rows, 1):
            if len(row) != 5 or index > 300 or row[0] != str(index):
                raise InvalidSubmission(path, "нужны 5 столбцов и frame=1..300 подряд")
            try:
                elapsed = float(row[1])
            except ValueError as error:
                raise InvalidSubmission(path, "elapsed_ms не число") from error
            if not math.isfinite(elapsed) or elapsed < 0:
                raise InvalidSubmission(path, "elapsed_ms должен быть конечным и >= 0")
            if row[2:4] != ["6168064", "1024"] or row[4].casefold() != "true":
                raise InvalidSubmission(path, "нужны checksum=6168064, queries=1024, valid=true")
            samples.append(elapsed)
    if len(samples) != 300:
        raise InvalidSubmission(path, "нужно ровно 300 строк данных")
    median = statistics.median(samples)
    quartiles = statistics.quantiles(samples, method="inclusive")
    iqr = quartiles[2] - quartiles[0]
    if not math.isfinite(median) or median <= 0 or not math.isfinite(iqr):
        raise InvalidSubmission(path, "медиана должна быть конечной и > 0; IQR конечным")
    return RunSummary(median, iqr)


def calculate_metrics(folder: Path) -> dict[str, float]:
    before, after = (
        statistics.median(read_run(folder / f"{phase}_{number}.csv").median_ms for number in range(1, 4))
        for phase in ("before", "after")
    )
    result = {"before_median_ms": before, "after_median_ms": after,
              "speedup": before / after, "reduction_percent": (1 - after / before) * 100}
    if not all(math.isfinite(value) for value in result.values()):
        raise InvalidSubmission(folder, "отношение медиан не является конечным числом")
    return result


def read_object(path: Path) -> dict[str, object]:
    require_file(path)
    document: object = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(document, dict) or not all(isinstance(key, str) for key in document):
        raise InvalidSubmission(path, "нужен JSON-объект")
    return document


def number(document: dict[str, object], field: str, path: Path) -> float:
    value = document.get(field)
    if type(value) not in (int, float) or not isinstance(value, (int, float)):
        raise InvalidSubmission(path, f"{field}: нужно число, не bool")
    try:
        result = float(value)
    except OverflowError as error:
        raise InvalidSubmission(path, f"{field}: слишком большое число") from error
    if not math.isfinite(result):
        raise InvalidSubmission(path, f"{field}: нужно конечное число")
    return result


def check_png(path: Path) -> None:
    from PIL import Image, UnidentifiedImageError

    require_file(path)
    try:
        with Image.open(path) as image:
            if image.format != "PNG" or image.width < 640 or image.height < 360:
                raise InvalidSubmission(path, "нужен PNG не менее 640x360")
            image.verify()
        with Image.open(path) as image:
            image.load()
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as error:
        raise InvalidSubmission(path, f"повреждённый PNG: {error}") from error


def check_41(folder: Path) -> None:
    for stem in ("До", "После"):
        candidates = [folder / f"{stem}.{suffix}" for suffix in ("data", "raw")]
        present = [path for path in candidates if path.exists()]
        if len(present) != 1 or not present[0].is_file() or present[0].stat().st_size < 128:
            raise InvalidSubmission(folder / stem, "нужен ровно один .data или .raw размером >=128 байт")
    for name in ("LookupExercise.cs", "Вывод.txt"):
        require_file(folder / name)
    check_png(folder / "CPU.png")
    expected = calculate_metrics(folder)
    path = folder / "metrics.json"
    supplied = read_object(path)
    for field, value in expected.items():
        if not math.isclose(number(supplied, field, path), value, rel_tol=0, abs_tol=1e-6):
            raise InvalidSubmission(path, f"{field}: ожидается {value:.12g}")


def check_report(path: Path, verdict: str) -> None:
    report = read_object(path)
    for field, expected in (("records", 4096), ("checksum", 6168064), ("queries", 1024), ("budget", 8192)):
        value = report.get(field)
        if type(value) is not int or value != expected:
            raise InvalidSubmission(path, f"{field}: ожидается целое {expected}")
    inspections = report.get("inspections")
    if not isinstance(inspections, int) or isinstance(inspections, bool) or inspections < 0:
        raise InvalidSubmission(path, "inspections: нужно неотрицательное целое")
    measured = "good" if inspections <= 8192 else "bad"
    if report.get("verdict") != verdict or measured != verdict:
        raise InvalidSubmission(path, f"verdict должен быть {verdict} и соответствовать inspections")


def check_42(folder: Path) -> None:
    for name in ("bisect.log", "first_bad.txt", "Вывод.txt"):
        require_file(folder / name)
    for name, verdict in (("known_good", "good"), ("reported_bad", "bad"),
                          ("parent", "good"), ("culprit", "bad")):
        check_report(folder / f"{name}.json", verdict)
    sha_pattern = r"(?<![0-9a-fA-F])[0-9a-fA-F]{40}(?![0-9a-fA-F])"
    sha = (folder / "first_bad.txt").read_text(encoding="utf-8-sig").strip()
    logged = re.findall(r"^# first bad commit: \[([0-9a-fA-F]{40})\]",
                        (folder / "bisect.log").read_text(encoding="utf-8-sig"), re.MULTILINE)
    if re.fullmatch(sha_pattern, sha) is None or len(logged) != 1 or sha.lower() != logged[0].lower():
        raise InvalidSubmission(folder / "first_bad.txt", "нужен только полный SHA из итоговой строки first bad commit в bisect.log")
    check_png(folder / "bisect.png")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--practice", required=True, choices=("4.1", "4.2"))
    parser.add_argument("folder", type=Path)
    args = parser.parse_args(argv)
    try:
        if not args.folder.is_dir():
            raise InvalidSubmission(args.folder, "папка сдачи не найдена")
        match args.practice:
            case "4.1":
                check_41(args.folder)
            case "4.2":
                check_42(args.folder)
    except (InvalidSubmission, UnicodeError, csv.Error, json.JSONDecodeError) as error:
        print(f"Ошибка данных: {error}", file=sys.stderr)
        return 1
    except (OSError, ImportError) as error:
        print(f"Ошибка окружения: {error}", file=sys.stderr)
        return 2
    print("Проверка файлов пройдена. Подлинность снимков и качество решения оценивает преподаватель.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
