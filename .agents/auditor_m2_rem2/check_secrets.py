import os
import re

lib_dir = r"d:\work\chat\lib"
patterns = {
    "sk-": re.compile(r"sk-[a-zA-Z0-9]{20,}"),
    "mock": re.compile(r"\bmock\b", re.IGNORECASE),
    "bypass": re.compile(r"\bbypass\b", re.IGNORECASE),
    "hardcode": re.compile(r"\bhardcode\b", re.IGNORECASE),
    "dummy": re.compile(r"\bdummy\b", re.IGNORECASE),
    "facade": re.compile(r"\bfacade\b", re.IGNORECASE),
    "todo": re.compile(r"TODO", re.IGNORECASE),
    "fake": re.compile(r"\bfake\b", re.IGNORECASE),
}

print("=== Scanning production code under lib/ ===")
for root, dirs, files in os.walk(lib_dir):
    for file in files:
        if file.endswith(".dart"):
            filepath = os.path.join(root, file)
            with open(filepath, "r", encoding="utf-8") as f:
                lines = f.readlines()
            for i, line in enumerate(lines):
                # ignore comments if they are not interesting, but search everything
                for name, pattern in patterns.items():
                    if pattern.search(line):
                        print(f"{filepath}:{i+1} [{name}] -> {line.strip()}")

print("=== Scan completed ===")
