import re
import json
import os

files_to_check = [
    r'D:\work\chat\.agents\orchestrator_gen7\AGENT_TOOLS_TAXONOMY.md',
    r'D:\work\chat\.agents\orchestrator_gen7\TOOL_REGISTRY_ARCHITECTURE.md',
    r'D:\work\chat\.agents\orchestrator_gen7\MCP_AND_NATIVE_INTEGRATION_SPEC.md',
    r'D:\work\chat\.agents\orchestrator_gen7\MILESTONE_EVOLUTION_ROADMAP.md',
    r'D:\work\chat\.agents\orchestrator_gen7\PROJECT.md',
    r'D:\work\chat\.agents\explorer_taxonomy_gen7\report.md',
]

total_blocks = 0
valid_blocks = 0
invalid_blocks = []

for file_path in files_to_check:
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        continue
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    json_blocks = re.findall(r'```json\s*(.*?)\s*```', content, re.DOTALL)
    print(f"\nChecking {os.path.basename(file_path)}: found {len(json_blocks)} JSON blocks")
    for idx, block in enumerate(json_blocks):
        total_blocks += 1
        try:
            parsed = json.loads(block)
            valid_blocks += 1
            func_name = ""
            if isinstance(parsed, dict):
                if "function" in parsed and isinstance(parsed["function"], dict):
                    func_name = parsed["function"].get("name", "")
                elif "name" in parsed:
                    func_name = parsed.get("name", "")
            print(f"  [PASS] Block {idx+1}: valid JSON (name: '{func_name}')")
        except Exception as err:
            invalid_blocks.append((file_path, idx+1, str(err), block[:100]))
            print(f"  [FAIL] Block {idx+1}: INVALID - {err}")

print(f"\n=== SCHEMA VALIDATION SUMMARY ===")
print(f"Total JSON Blocks Analyzed: {total_blocks}")
print(f"Valid: {valid_blocks}")
print(f"Invalid: {len(invalid_blocks)}")

if invalid_blocks:
    for f, idx, err, snippet in invalid_blocks:
        print(f"ERROR in {f} block {idx}: {err}\nSnippet: {snippet}...\n")
else:
    print("ALL JSON SCHEMAS AND BLOCKS ARE 100% VALID!")
