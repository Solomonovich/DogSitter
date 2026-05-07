import re

log_path = "/Users/solofamily/.gemini/antigravity/brain/f85ca6f4-ac64-4b54-9f1b-846ae1e41acb/.system_generated/logs/overview.txt"

with open(log_path, "r") as f:
    content = f.read()

# We are looking for the output of view_file that showed lines 1 to 1127.
# It should look like:
# 1: import SwiftUI
# 2: import MapKit

pattern = r"1: import SwiftUI\n2: import MapKit\n3: import CoreLocation.*?\n447:     \}"
match = re.search(pattern, content, re.DOTALL)

if match:
    lines_text = match.group(0)
    # Remove the line numbers
    clean_lines = []
    for line in lines_text.split('\n'):
        # match `<number>: ` and remove it
        clean_line = re.sub(r'^\d+: ', '', line)
        clean_lines.append(clean_line)
    
    recovered = '\n'.join(clean_lines)
    with open("recovered_top.swift", "w") as out:
        out.write(recovered)
    print("Recovered top successfully!")
else:
    print("Could not find the original top part in logs.")

