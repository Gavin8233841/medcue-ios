#!/usr/bin/env bash
# Cross-platform pre-commit syntax checker
# Runs on Windows (Git Bash), macOS, and Linux

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/pre-commit-checks.json"

# Colors for output (works in Git Bash on Windows)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect platform
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="windows"
        ;;
    Darwin*)
        PLATFORM="darwin"
        ;;
    Linux*)
        PLATFORM="linux"
        ;;
    *)
        PLATFORM="unknown"
        ;;
esac

echo -e "${BLUE}🔍 Running pre-commit checks on $PLATFORM...${NC}"
echo ""

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Check if jq is available for JSON parsing (fallback to Python if not)
if command -v jq &> /dev/null; then
    JSON_PARSER="jq"
elif command -v python3 &> /dev/null; then
    JSON_PARSER="python3"
elif command -v python &> /dev/null; then
    JSON_PARSER="python"
else
    echo -e "${RED}❌ Neither jq nor Python found. Please install one of them.${NC}"
    exit 1
fi

# Function to parse JSON with fallback
parse_json() {
    local key="$1"
    if [[ "$JSON_PARSER" == "jq" ]]; then
        jq -r "$key" "$CONFIG_FILE"
    else
        "$JSON_PARSER" -c "import json; data=json.load(open('$CONFIG_FILE')); print(json.dumps($key))"
    fi
}

# Get number of checks
if [[ "$JSON_PARSER" == "jq" ]]; then
    CHECK_COUNT=$(jq '.checks | length' "$CONFIG_FILE")
else
    CHECK_COUNT=$("$JSON_PARSER" -c "import json; print(len(json.load(open('$CONFIG_FILE'))['checks']))")
fi

FAILED_CHECKS=0
TOTAL_CHECKS=0

# Check 1: Trailing Whitespace
echo -e "${BLUE}[1/$CHECK_COUNT]${NC} Checking for trailing whitespace..."
if git diff --cached --check 2>&1 | grep -q "trailing whitespace"; then
    echo -e "${RED}❌ Found trailing whitespace${NC}"
    echo -e "${YELLOW}Fix with: git diff --cached --name-only | xargs sed -i 's/[ \\t]*\$//'${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    echo -e "${GREEN}✅ No trailing whitespace${NC}"
fi
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
echo ""

# Check 2: Absolute Paths
echo -e "${BLUE}[2/$CHECK_COUNT]${NC} Checking for absolute local paths..."
if git diff --cached | grep -qE 'C:\\|D:\\|/Users/|/home/|/private/|/Volumes/'; then
    echo -e "${RED}❌ Found absolute local paths (C:\\, D:\\, /Users/, /home/)${NC}"
    echo -e "${YELLOW}Replace with <PROJECT_ROOT> placeholder${NC}"
    git diff --cached | grep -E 'C:\\|D:\\|/Users/|/home/|/private/|/Volumes/' | head -5
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    echo -e "${GREEN}✅ No absolute paths${NC}"
fi
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
echo ""

# Check 3: Allowlist Paths
echo -e "${BLUE}[3/$CHECK_COUNT]${NC} Checking file paths against allowlist..."
ALLOWED_PREFIXES=(
    ".github/"
    "checklists/"
    "cloudfunctions/medcue-ai-broker/"
    "coreai/"
    "docs/"
    "ios-app/"
    "Packages/"
    "swift-core/"
    "templates/"
    "tools/"
)

ALLOWED_ROOT_FILES=(
    ".gitignore"
    "AGENTS.md"
    "CONTEXT.md"
    "design-qa.md"
    "README.md"
    "README.zh-CN.md"
    "CHANGELOG.md"
    "LICENSE"
    "LICENSE.md"
    "LICENSE.txt"
    "NOTICE"
    "NOTICE.md"
    "NOTICE.txt"
    "ATTRIBUTION.md"
    "Package.swift"
    "Package.resolved"
)

ALLOWLIST_FAILED=0
while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    ALLOWED=false

    # Check root files
    for root_file in "${ALLOWED_ROOT_FILES[@]}"; do
        if [[ "$file" == "$root_file" ]]; then
            ALLOWED=true
            break
        fi
    done

    # Check directory prefixes
    if [[ "$ALLOWED" == false ]]; then
        for prefix in "${ALLOWED_PREFIXES[@]}"; do
            if [[ "$file" == "$prefix"* ]]; then
                ALLOWED=true
                break
            fi
        done
    fi

    if [[ "$ALLOWED" == false ]]; then
        echo -e "${RED}❌ File not in allowlist: $file${NC}"
        ALLOWLIST_FAILED=1
    fi
done < <(git diff --cached --name-only --diff-filter=ACM)

if [[ $ALLOWLIST_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All files in allowlist${NC}"
else
    echo -e "${YELLOW}Hint: Work files should be in docs/ or added to .gitignore${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
echo ""

# Check 4: JavaScript Syntax
if command -v node &> /dev/null; then
    echo -e "${BLUE}[4/$CHECK_COUNT]${NC} Checking JavaScript syntax..."
    JS_FAILED=0
    while IFS= read -r js_file; do
        [[ -z "$js_file" ]] && continue
        if [[ -f "$js_file" ]]; then
            if ! node --check "$js_file" 2>&1; then
                echo -e "${RED}❌ JavaScript syntax error in: $js_file${NC}"
                JS_FAILED=1
            fi
        fi
    done < <(git diff --cached --name-only --diff-filter=ACM | grep '\.js$' || true)

    if [[ $JS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ JavaScript syntax OK${NC}"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo ""
fi

# Check 5: JSON Syntax
if command -v node &> /dev/null; then
    echo -e "${BLUE}[5/$CHECK_COUNT]${NC} Checking JSON syntax..."
    JSON_FAILED=0
    while IFS= read -r json_file; do
        [[ -z "$json_file" ]] && continue
        if [[ -f "$json_file" ]]; then
            if ! node -e "JSON.parse(require('fs').readFileSync('$json_file', 'utf8'))" 2>&1; then
                echo -e "${RED}❌ JSON syntax error in: $json_file${NC}"
                JSON_FAILED=1
            fi
        fi
    done < <(git diff --cached --name-only --diff-filter=ACM | grep '\.json$' || true)

    if [[ $JSON_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ JSON syntax OK${NC}"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo ""
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAILED_CHECKS -eq 0 ]]; then
    echo -e "${GREEN}✅ All checks passed ($TOTAL_CHECKS/$TOTAL_CHECKS)${NC}"
    echo -e "${GREEN}✅ Safe to commit${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED_CHECKS/$TOTAL_CHECKS checks failed${NC}"
    echo -e "${RED}❌ Please fix the issues above before committing${NC}"
    echo ""
    echo -e "${YELLOW}To bypass these checks (not recommended):${NC}"
    echo -e "${YELLOW}  git commit --no-verify${NC}"
    exit 1
fi
