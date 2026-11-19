"""Deck validation, deterministic marking, public slide projections and text import.

A deck is an ordered list of slides. Graded slides (quiz questions) score points; every other
slide type is an audience activity (poll, word cloud, rating, ranking, open-ended ideas, Q&A,
spinner wheel) or plain content. The format stays "oes-quiz" version 1: 0.3 only adds optional
fields, so 0.2 decks load unchanged.
"""
import base64
import math
import re
import unicodedata

GRADED = {"choice", "multiple", "text", "number", "order", "match", "category"}
AUDIENCE = {"poll", "scale", "cloud", "rank", "open", "qa", "spinner"}
TYPES = GRADED | AUDIENCE | {"slide"}
WITH_OPTIONS = {"choice", "multiple", "order", "match", "category", "poll", "rank"}
LIVE_DEFAULT = {"poll", "scale", "rank", "open"}           # results visible while answering
PUBLIC = ("type", "prompt", "options", "labels", "seconds", "points", "image", "body", "layout",
          "scale_max", "low_label", "high_label", "max_entries", "source", "live_results")
LAYOUTS = ("auto", "title", "image-left", "image-right", "big")
LABELS = {
    "slide": "Content slide", "choice": "Pick one", "multiple": "Pick several", "text": "Type an answer",
    "number": "Numeric answer", "order": "Correct order", "match": "Match pairs", "category": "Categorise",
    "poll": "Poll", "scale": "Rating scale", "cloud": "Word cloud", "rank": "Ranking poll",
    "open": "Open-ended ideas", "qa": "Audience Q&A", "spinner": "Spinner wheel",
}
DECK_SETTINGS = {  # name: (default, allowed values or type)
    "speed_bonus": (True, bool), "anonymous": (False, bool), "auto_close": (True, bool),
    "reactions": (True, bool), "qa": (True, bool), "leaderboard": ("each", ("each", "end", "never")),
    "theme": ("dark", ("dark", "light")),
}


class Invalid(ValueError):
    pass


def string(value, limit, label):
    if not isinstance(value, str) or not 0 < len(value.strip()) <= limit:
        raise Invalid(f"{label} needs 1–{limit} characters.")
    return value.strip()


def optional_string(raw, key, limit, label):
    value = raw.get(key)
    if value in (None, ""):
        return None
    return string(value, limit, label)


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


def image_data(image):
    if not isinstance(image, str) or len(image) > 700_000:
        raise Invalid("Slide images must be under 512 KiB.")
    meta, sep, encoded = image.partition(",")
    headers = {"data:image/png;base64": b"\x89PNG\r\n\x1a\n", "data:image/jpeg;base64": b"\xff\xd8\xff",
               "data:image/webp;base64": b"RIFF"}
    if not sep or meta not in headers:
        raise Invalid("Use a local PNG, JPEG or WebP image.")
    try:
        binary = base64.b64decode(encoded, validate=True)
    except ValueError as exc:
        raise Invalid("Invalid image encoding.") from exc
    if len(binary) > 524288 or not binary.startswith(headers[meta]):
        raise Invalid("Invalid image type or size.")
    return image


def question(raw):
    if not isinstance(raw, dict) or raw.get("type") not in TYPES:
        raise Invalid("Unknown slide type.")
    typ = raw["type"]
    # Audience activities may be untimed (0 seconds): they stay open until the presenter moves on.
    timed = typ in GRADED
    q = {"type": typ, "prompt": string(raw.get("prompt"), 500, "Prompt"),
         "seconds": integer(raw.get("seconds", 30 if timed else 0), 3 if timed else 0, 600, "Time limit"),
         "points": integer(raw.get("points", 1000), 0, 10000, "Points") if typ in GRADED else 0}
    if typ in {"poll", "scale", "cloud", "rank", "open"}:
        show = raw.get("live_results", typ in LIVE_DEFAULT)
        if type(show) is not bool:
            raise Invalid("Live results must be on or off.")
        q["live_results"] = show
    for key, limit, label in (("explanation", 600, "Explanation"), ("notes", 2000, "Presenter notes"),
                              ("body", 1500, "Slide text")):
        value = optional_string(raw, key, limit, label)
        if value:
            q[key] = value
    if typ == "slide":
        layout = raw.get("layout", "auto")
        if layout not in LAYOUTS:
            raise Invalid("Unknown slide layout.")
        q["layout"] = layout
    if typ in WITH_OPTIONS:
        q["options"] = strings(raw.get("options"), "Choices", 2, 12)
    if typ in {"match", "category"}:
        q["labels"] = strings(raw.get("labels"), "Left-hand items", 2, 12)
    if typ == "scale":
        q["scale_max"] = integer(raw.get("scale_max", 5), 2, 10, "Scale maximum")
        for key in ("low_label", "high_label"):
            value = optional_string(raw, key, 40, "Scale label")
            if value:
                q[key] = value
    if typ == "open":
        q["max_entries"] = integer(raw.get("max_entries", 3), 1, 10, "Ideas per person")
        if type(raw.get("moderate", False)) is not bool:
            raise Invalid("Moderation must be on or off.")
        q["moderate"] = raw.get("moderate", False)
    if typ == "spinner":
        source = raw.get("source", "entries")
        if source not in ("entries", "players"):
            raise Invalid("Spinner entries come from a list or from the participants.")
        q["source"] = source
        if source == "entries":
            q["options"] = strings(raw.get("options"), "Spinner entries", 2, 40, 60, distinct=False)
        if type(raw.get("remove_winner", False)) is not bool:
            raise Invalid("Remove-winner must be on or off.")
        q["remove_winner"] = raw.get("remove_winner", False)
    if typ == "text":
        q["answer"] = strings(raw.get("answer"), "Accepted answers", length=180)
    elif typ == "number":
        a, t = raw.get("answer"), raw.get("tolerance", 0)
        if not finite(a) or not finite(t) or t < 0:
            raise Invalid("Numeric answer and nonnegative tolerance must be finite.")
        q.update(answer=a, tolerance=t)
    elif typ in GRADED:
        q["answer"] = response(q, raw.get("answer"))
    if raw.get("image"):
        q["image"] = image_data(raw["image"])
    return q


def validate(raw):
    if not isinstance(raw, dict) or raw.get("format") != "oes-quiz" or raw.get("version") != 1:
        raise Invalid("Expected an oes-quiz version 1 deck.")
    qs = raw.get("questions")
    if not isinstance(qs, list) or not 1 <= len(qs) <= 150:
        raise Invalid("A deck needs 1–150 slides.")
    deck = {"format": "oes-quiz", "version": 1, "title": string(raw.get("title"), 120, "Title"),
            "teams": strings(raw.get("teams", []), "Teams", 0, 32, 40)}
    for key, (default, allowed) in DECK_SETTINGS.items():
        value = raw.get(key, default)
        if (allowed is bool and type(value) is not bool) or (allowed is not bool and value not in allowed):
            raise Invalid(f"Invalid deck setting: {key}.")
        deck[key] = value
    deck["questions"] = [question(q) for q in qs]
    return deck


def response(q, value):
    typ = q["type"]
    options = q.get("options", [])
    if typ in {"choice", "poll"} and isinstance(value, str) and value in options:
        return value
    if typ == "scale":
        return integer(value, 1, q.get("scale_max", 5), "Rating")
    if typ in {"cloud", "text"}:
        return string(value, 48 if typ == "cloud" else 180, "Answer")
    if typ == "number" and finite(value):
        return value
    if typ in {"multiple", "order", "match", "category", "rank"} and isinstance(value, list):
        if any(not isinstance(v, str) or v not in options for v in value):
            raise Invalid("An answer is outside the available choices.")
        if typ == "multiple" and 0 < len(value) == len(set(value)) <= len(options):
            return sorted(value)
        if typ in {"order", "rank"} and len(value) == len(options) and set(value) == set(options):
            return value
        if typ in {"match", "category"} and len(value) == len(q["labels"]):
            if typ == "category" or len(set(value)) == len(value):
                return value
    raise Invalid("Complete the answer using the choices for this slide.")


def correct(q, answer):
    typ = q["type"]
    if typ == "text":
        return normal(answer) in {normal(v) for v in q["answer"]}
    if typ == "number":
        return abs(answer - q["answer"]) <= q["tolerance"] + 1e-12
    return typ in GRADED and answer == q["answer"]


def public_question(q):
    return {k: q[k] for k in PUBLIC if k in q}


# --------------------------------------------------------------------------- text import
_AIKEN_OPTION = re.compile(r"^\s*([A-Za-z])\s*[.)]\s+(.+?)\s*$")
_AIKEN_ANSWER = re.compile(r"^\s*ANSWER\s*:\s*([A-Za-z](?:\s*,\s*[A-Za-z])*)\s*$", re.I)


def from_text(text, title="Imported questions"):
    """Read Moodle Aiken format, plus two small extensions teachers ask for.

        What is the chemical symbol for gold?      <- question
        A. Ag                                      <- options (A. or A) )
        B. Au
        ANSWER: B                                  <- one letter: pick one; "A, C": pick several

    A block without an ANSWER line becomes a poll. A block of plain lines with no options becomes a
    content slide (first line = heading, the rest = text). Blocks are separated by blank lines.
    """
    if not isinstance(text, str) or len(text) > 400_000:
        raise Invalid("Paste up to 400 KB of text.")
    slides = []
    for block in re.split(r"\n\s*\n", text.replace("\r\n", "\n").strip()):
        lines = [ln.rstrip() for ln in block.split("\n") if ln.strip()]
        if not lines:
            continue
        prompt, options, answer = [], [], None
        for ln in lines:
            opt, ans = _AIKEN_OPTION.match(ln), _AIKEN_ANSWER.match(ln)
            if ans:
                answer = [a.strip().upper() for a in ans.group(1).split(",")]
            elif opt and (options or prompt):
                options.append((opt.group(1).upper(), opt.group(2)))
            elif not options:
                prompt.append(ln.strip())
            else:
                options[-1] = (options[-1][0], options[-1][1] + " " + ln.strip())
        if not options:
            slides.append({"type": "slide", "prompt": prompt[0][:500], "body": "\n".join(prompt[1:])[:1500]})
            continue
        letters = {k: v for k, v in options}
        labels = [v for _, v in options]
        if answer and all(a in letters for a in answer):
            if len(answer) == 1:
                slides.append({"type": "choice", "prompt": " ".join(prompt)[:500], "options": labels,
                               "answer": letters[answer[0]], "seconds": 30, "points": 1000})
            else:
                slides.append({"type": "multiple", "prompt": " ".join(prompt)[:500], "options": labels,
                               "answer": sorted(letters[a] for a in answer), "seconds": 45, "points": 1000})
        else:
            slides.append({"type": "poll", "prompt": " ".join(prompt)[:500], "options": labels, "seconds": 60})
    if not slides:
        raise Invalid("No questions were found. Separate questions with a blank line.")
    return validate({"format": "oes-quiz", "version": 1, "title": title[:120] or "Imported questions",
                     "teams": [], "questions": slides[:150]})
