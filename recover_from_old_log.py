import re

log_path = "/Users/solofamily/.gemini/antigravity/brain/285adbd9-70ab-4dd4-b00f-b6cdc9fe37be/.system_generated/logs/overview.txt"

with open(log_path, "r") as f:
    content = f.read()

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

