"""Quiz deck validation, deterministic marking and public question projections."""
import base64
import math
import unicodedata

GRADED = {"choice", "multiple", "text", "number", "order", "match", "category"}
TYPES = GRADED | {"poll", "scale", "cloud", "slide"}
WITH_OPTIONS = {"choice", "multiple", "order", "match", "category", "poll"}
PUBLIC = ("type", "prompt", "options", "labels", "seconds", "points", "image")


class Invalid(ValueError):
    pass


def string(value, limit, label):
    if not isinstance(value, str) or not 0 < len(value.strip()) <= limit:
        raise Invalid(f"{label} needs 1–{limit} characters.")
    return value.strip()


def normal(value):
    return " ".join(unicodedata.normalize("NFKC", value).casefold().split())


def strings(values, label, least=1, most=24, length=120, distinct=True):
    if not isinstance(values, list) or not least <= len(values) <= most:
        raise Invalid(f"{label} needs {least}–{most} entries.")
    result = [string(v, length, label) for v in values]
    if distinct and len({normal(v) for v in result}) != len(result):
        raise Invalid(f"{label} contains duplicate entries.")
    return result


def finite(value):
    return type(value) in (int, float) and math.isfinite(value) and abs(value) < 1e15


def integer(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise Invalid(f"{label} must be an integer from {low} to {high}.")
    return value


def question(raw):
    if not isinstance(raw, dict) or raw.get("type") not in TYPES:
        raise Invalid("Unknown round type.")
    typ = raw["type"]
    q = {"type": typ, "prompt": string(raw.get("prompt"), 500, "Prompt"),
         "seconds": integer(raw.get("seconds", 30), 3, 600, "Time limit"),
         "points": integer(raw.get("points", 1000), 0, 10000, "Points") if typ in GRADED else 0}
    if typ in {"poll","scale","cloud"}:
        show=raw.get("live_results",typ in {"poll","scale"})
        if type(show) is not bool:raise Invalid("Live results must be on or off.")
        q["live_results"]=show
    if raw.get("explanation"):
        q["explanation"] = string(raw["explanation"], 600, "Explanation")
    if typ in WITH_OPTIONS:
        q["options"] = strings(raw.get("options"), "Choices", 2, 12)
    if typ in {"match", "category"}:
        q["labels"] = strings(raw.get("labels"), "Left-hand items", 2, 12)
    if typ == "text":
        q["answer"] = strings(raw.get("answer"), "Accepted answers", length=180)
    elif typ == "number":
        a, t = raw.get("answer"), raw.get("tolerance", 0)
        if not finite(a) or not finite(t) or t < 0:
            raise Invalid("Numeric answer and nonnegative tolerance must be finite.")
        q.update(answer=a, tolerance=t)
    elif typ in GRADED:
        q["answer"] = response(q, raw.get("answer"))
    image = raw.get("image")
    if image:
        if not isinstance(image, str) or len(image) > 700_000:
            raise Invalid("Question images must be under 512 KiB.")
        meta, sep, encoded = image.partition(",")
        headers = {"data:image/png;base64": b"\x89PNG\r\n\x1a\n", "data:image/jpeg;base64": b"\xff\xd8\xff"}
        if not sep or meta not in headers:
            raise Invalid("Use a local PNG or JPEG.")
        try:
            binary = base64.b64decode(encoded, validate=True)
        except ValueError as exc:
            raise Invalid("Invalid image encoding.") from exc
        if len(binary) > 524288 or not binary.startswith(headers[meta]):
            raise Invalid("Invalid image type or size.")
        q["image"] = image
    return q


def validate(raw):
    if not isinstance(raw, dict) or raw.get("format") != "oes-quiz" or raw.get("version") != 1:
        raise Invalid("Expected an oes-quiz version 1 deck.")
    qs = raw.get("questions")
    if not isinstance(qs, list) or not 1 <= len(qs) <= 150:
        raise Invalid("A contest needs 1–150 rounds.")
    if type(raw.get("speed_bonus", True)) is not bool:
        raise Invalid("Speed bonus must be on or off.")
    return {"format": "oes-quiz", "version": 1, "title": string(raw.get("title"), 120, "Title"),
            "speed_bonus": raw.get("speed_bonus", True),
            "teams": strings(raw.get("teams", []), "Teams", 0, 32, 40),
            "questions": [question(q) for q in qs]}


def response(q, value):
    typ = q["type"]
    options = q.get("options", [])
    if typ in {"choice", "poll"} and isinstance(value, str) and value in options:
        return value
    if typ == "scale":
        return integer(value, 1, 5, "Rating")
    if typ in {"cloud", "text"}:
        return string(value, 48 if typ == "cloud" else 180, "Answer")
    if typ == "number" and finite(value):
        return value
    if typ in {"multiple", "order", "match", "category"} and isinstance(value, list):
        if any(not isinstance(v, str) or v not in options for v in value):
            raise Invalid("An answer is outside the available choices.")
        if typ == "multiple" and 0 < len(value) == len(set(value)) <= len(options):
            return sorted(value)
        if typ == "order" and len(value) == len(options) and set(value) == set(options):
            return value
        if typ in {"match", "category"} and len(value) == len(q["labels"]):
            if typ == "category" or len(set(value)) == len(value):
                return value
    raise Invalid("Complete the answer using the choices for this round.")


def correct(q, answer):
    typ = q["type"]
    if typ == "text":
        return normal(answer) in {normal(v) for v in q["answer"]}
    if typ == "number":
        return abs(answer - q["answer"]) <= q["tolerance"] + 1e-12
    return typ in GRADED and answer == q["answer"]


def public_question(q):
    return {k: q[k] for k in PUBLIC if k in q}
