import os
import re

log_files = [
    r"d:\work\chat\flutter_01.log",
    r"d:\work\chat\flutter_02.log",
    r"d:\work\chat\flutter_03.log",
    r"d:\work\chat\flutter_04.log",
    r"d:\work\chat\flutter_05.log",
]

patterns = {
    "sk-": re.compile(r"sk-[a-zA-Z0-9]{20,}"),
    "api_key": re.compile(r"api[-_]?key", re.IGNORECASE),
    "secret": re.compile(r"secret", re.IGNORECASE),
}

print("=== Scanning log files ===")
for filepath in log_files:
    if os.path.exists(filepath):
        print(f"Scanning {filepath}...")
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            for name, pattern in patterns.items():
                if pattern.search(line):
                    print(f"  {filepath}:{i+1} [{name}] -> {line.strip()[:100]}")
    else:
        print(f"{filepath} does not exist.")
print("=== Log scan completed ===")
