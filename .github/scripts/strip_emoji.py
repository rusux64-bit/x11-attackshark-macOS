#!/usr/bin/env python3
"""Removes emoji and pictographic symbols from text read on stdin and writes the result to stdout."""
import re
import sys

EMOJI_PATTERN = re.compile(
    "["
    "\U0001F000-\U0001FAFF"  # pictographs, emoticons, transport, supplemental symbols
    "\U0001F1E6-\U0001F1FF"  # regional indicators (flags)
    "\u2300-\u23FF"          # misc technical (watch, hourglass, etc.)
    "\u2600-\u27BF"          # misc symbols and dingbats
    "\u2B00-\u2BFF"          # misc symbols and arrows (stars, check marks)
    "\u200D"                 # zero width joiner
    "\uFE0E\uFE0F"           # variation selectors
    "]+"
)


def main() -> None:
    text = sys.stdin.read()
    cleaned_lines = []
    for line in text.splitlines():
        cleaned = EMOJI_PATTERN.sub("", line)
        cleaned = re.sub(r"[ \t]+$", "", cleaned)
        cleaned = re.sub(r"(?<=\S)  +(?=\S)", " ", cleaned)
        cleaned_lines.append(cleaned)
    sys.stdout.write("\n".join(cleaned_lines) + "\n")


if __name__ == "__main__":
    main()
