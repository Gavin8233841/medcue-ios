#!/usr/bin/env bash
# Add a new CI error check to the pre-commit configuration
# Usage: bash tools/add-check.sh <check-id> <check-name> <error-pattern> <fix-message>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/pre-commit-checks.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [[ $# -lt 4 ]]; then
    echo -e "${RED}Usage: $0 <check-id> <check-name> <error-pattern> <fix-message>${NC}"
    echo ""
    echo "Example:"
    echo "  $0 secret-keys \"Secret Keys\" \"sk-[A-Za-z0-9]{20,}\" \"Remove secret keys from code\""
    exit 1
fi

CHECK_ID="$1"
CHECK_NAME="$2"
ERROR_PATTERN="$3"
FIX_MESSAGE="$4"

echo -e "${BLUE}📝 Adding new check: $CHECK_NAME${NC}"
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo -e "${RED}❌ Python not found. Cannot modify JSON config.${NC}"
    exit 1
fi

PYTHON_CMD="python3"
if ! command -v python3 &> /dev/null; then
    PYTHON_CMD="python"
fi

# Add the check using Python
$PYTHON_CMD << EOF
import json
import sys

try:
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        config = json.load(f)

    # Check if check-id already exists
    for check in config['checks']:
        if check['id'] == '$CHECK_ID':
            print('❌ Check ID already exists: $CHECK_ID')
            sys.exit(1)

    # Add new check
    new_check = {
        'id': '$CHECK_ID',
        'name': '$CHECK_NAME',
        'enabled': True,
        'severity': 'error',
        'type': 'grep',
        'pattern': '$ERROR_PATTERN',
        'errorMessage': '$FIX_MESSAGE',
        'platforms': ['windows', 'darwin', 'linux'],
        'exitOnFail': True
    }

    config['checks'].append(new_check)

    # Write back
    with open('$CONFIG_FILE', 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)

    print('✅ Check added successfully')
    print('')
    print('Check details:')
    print(f'  ID: $CHECK_ID')
    print(f'  Name: $CHECK_NAME')
    print(f'  Pattern: $ERROR_PATTERN')
    print('')
    print('⚠️  You need to update tools/run-pre-commit-checks.sh manually')
    print('⚠️  Or run: bash tools/generate-check-script.sh')

except Exception as e:
    print(f'❌ Error: {e}')
    sys.exit(1)
EOF

echo ""
echo -e "${GREEN}🎉 New check added to configuration${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${YELLOW}1. Update tools/run-pre-commit-checks.sh to implement the check${NC}"
echo -e "${YELLOW}2. Update .github/workflows/native-verification.yml quick-syntax job${NC}"
echo -e "${YELLOW}3. Test with: bash tools/run-pre-commit-checks.sh${NC}"
echo -e "${YELLOW}4. Commit the changes${NC}"
