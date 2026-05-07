import re

log_path = "/Users/solofamily/.gemini/antigravity/brain/f85ca6f4-ac64-4b54-9f1b-846ae1e41acb/.system_generated/logs/overview.txt"

with open(log_path, "r") as f:
    content = f.read()

# We only care about lines 1 to 447.
# They look like: "1: import SwiftUI", "2: import MapKit", etc.
# We can find them by looking for lines that start with 1: to 447:

lines_dict = {}

for line in content.split('\n'):
    m = re.match(r'^(\d+): (.*)', line)
    if m:
        num = int(m.group(1))
        text = m.group(2)
        if 1 <= num <= 447:
            lines_dict[num] = text

missing = []
for i in range(1, 448):
    if i not in lines_dict:
        missing.append(i)

if len(missing) == 0:
    print("Found all lines!")
    out_lines = []
    for i in range(1, 448):
        out_lines.append(lines_dict[i])
    
    with open("recovered_top.swift", "w") as out:
        out.write('\n'.join(out_lines))
else:
    print(f"Missing {len(missing)} lines: {missing[:10]}")

