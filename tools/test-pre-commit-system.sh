#!/usr/bin/env bash
# Test the pre-commit check system
# Usage: bash tools/test-pre-commit-system.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Testing Pre-Commit Check System${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test 1: Check if files exist
echo -e "${BLUE}[1/5] Checking required files...${NC}"
REQUIRED_FILES=(
    "tools/install-hooks.sh"
    "tools/run-pre-commit-checks.sh"
    "tools/pre-commit-checks.json"
    "tools/add-check.sh"
    "docs/pre-commit-checks.md"
    "docs/collaborator-setup-prompt.md"
    "CODEX_DEPLOY_PROMPT.md"
)

ALL_EXIST=true
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
        echo -e "${RED}  ❌ Missing: $file${NC}"
        ALL_EXIST=false
    fi
done

if [[ "$ALL_EXIST" == true ]]; then
    echo -e "${GREEN}  ✅ All required files exist${NC}"
fi
echo ""

# Test 2: Check if scripts are executable
echo -e "${BLUE}[2/5] Checking script permissions...${NC}"
SCRIPTS=(
    "tools/install-hooks.sh"
    "tools/run-pre-commit-checks.sh"
    "tools/add-check.sh"
)

ALL_EXECUTABLE=true
for script in "${SCRIPTS[@]}"; do
    if [[ ! -x "$PROJECT_ROOT/$script" ]]; then
        echo -e "${YELLOW}  ⚠️  Not executable: $script${NC}"
        chmod +x "$PROJECT_ROOT/$script"
        echo -e "${GREEN}  ✅ Fixed: $script${NC}"
    fi
done

echo -e "${GREEN}  ✅ All scripts are executable${NC}"
echo ""

# Test 3: Validate JSON config
echo -e "${BLUE}[3/5] Validating JSON configuration...${NC}"
if command -v python3 &> /dev/null; then
    if python3 -c "import json; json.load(open('$PROJECT_ROOT/tools/pre-commit-checks.json'))" 2>&1; then
        echo -e "${GREEN}  ✅ JSON configuration is valid${NC}"
    else
        echo -e "${RED}  ❌ JSON configuration is invalid${NC}"
    fi
elif command -v node &> /dev/null; then
    if node -e "JSON.parse(require('fs').readFileSync('$PROJECT_ROOT/tools/pre-commit-checks.json', 'utf8'))" 2>&1; then
        echo -e "${GREEN}  ✅ JSON configuration is valid${NC}"
    else
        echo -e "${RED}  ❌ JSON configuration is invalid${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠️  No JSON validator found (Python/Node.js)${NC}"
fi
echo ""

# Test 4: Check GitHub Actions workflow
echo -e "${BLUE}[4/5] Checking GitHub Actions workflow...${NC}"
if grep -q "quick-syntax:" "$PROJECT_ROOT/.github/workflows/native-verification.yml"; then
    echo -e "${GREEN}  ✅ quick-syntax job found in workflow${NC}"
else
    echo -e "${RED}  ❌ quick-syntax job not found in workflow${NC}"
fi
echo ""

# Test 5: Test hook installation (dry-run)
echo -e "${BLUE}[5/5] Testing hook installation...${NC}"
if [[ -f "$PROJECT_ROOT/.git/hooks/pre-commit" ]]; then
    echo -e "${GREEN}  ✅ Pre-commit hook is already installed${NC}"
    echo -e "${BLUE}  ℹ️  Location: .git/hooks/pre-commit${NC}"
else
    echo -e "${YELLOW}  ⚠️  Pre-commit hook not installed${NC}"
    echo -e "${BLUE}  ℹ️  Run: bash tools/install-hooks.sh${NC}"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Pre-Commit Check System Test Complete${NC}"
echo ""
echo "Next steps:"
echo "  1. Install hook: bash tools/install-hooks.sh"
echo "  2. Test with a commit that has trailing whitespace"
echo "  3. Read docs: docs/pre-commit-checks.md"
echo ""
echo "Share with collaborators:"
echo "  CODEX_DEPLOY_PROMPT.md"
