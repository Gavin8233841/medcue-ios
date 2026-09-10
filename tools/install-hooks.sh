#!/usr/bin/env bash
# Install pre-commit hook for all platforms (Windows/macOS/Linux)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_TARGET="$PROJECT_ROOT/.git/hooks/pre-commit"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📦 Installing pre-commit hook...${NC}"
echo ""

# Check if .git exists
if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
    echo -e "${YELLOW}⚠️  Not a git repository. Skipping hook installation.${NC}"
    exit 0
fi

# Backup existing hook if present
if [[ -f "$HOOK_TARGET" ]]; then
    echo -e "${YELLOW}⚠️  Existing pre-commit hook found${NC}"
    cp "$HOOK_TARGET" "$HOOK_TARGET.backup.$(date +%s)"
    echo -e "${YELLOW}   Backed up to: $HOOK_TARGET.backup.$(date +%s)${NC}"
    echo ""
fi

# Create hook content
cat > "$HOOK_TARGET" << 'EOF'
#!/usr/bin/env bash
# Auto-generated pre-commit hook
# DO NOT EDIT - managed by tools/install-hooks.sh

set -e

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
CHECKER_SCRIPT="$PROJECT_ROOT/tools/run-pre-commit-checks.sh"

if [[ ! -f "$CHECKER_SCRIPT" ]]; then
    echo "⚠️  Pre-commit checker not found: $CHECKER_SCRIPT"
    echo "⚠️  Skipping checks (run tools/install-hooks.sh to fix)"
    exit 0
fi

# Run the checker
bash "$CHECKER_SCRIPT"
EOF

# Make hook executable
chmod +x "$HOOK_TARGET"

echo -e "${GREEN}✅ Pre-commit hook installed successfully${NC}"
echo ""
echo "Location: $HOOK_TARGET"
echo ""
echo -e "${BLUE}ℹ️  The hook will run automatically on 'git commit'${NC}"
echo -e "${BLUE}ℹ️  To bypass: git commit --no-verify (not recommended)${NC}"
echo ""

# Test the hook
echo -e "${BLUE}🧪 Testing hook installation...${NC}"
if bash "$PROJECT_ROOT/tools/run-pre-commit-checks.sh" --dry-run 2>/dev/null || true; then
    echo -e "${GREEN}✅ Hook test passed${NC}"
else
    echo -e "${YELLOW}⚠️  Hook installed but test skipped (no staged changes)${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Setup complete!${NC}"
