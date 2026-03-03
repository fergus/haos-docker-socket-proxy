#!/usr/bin/env bash
# Test suite for HA Docker Socket Proxy add-on
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDON_DIR="${REPO_ROOT}/socket-proxy"

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  SKIP: $1"; }

section() { echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------------------
section "Structural checks"
# ---------------------------------------------------------------------------

for f in \
    socket-proxy/config.yaml \
    socket-proxy/build.yaml \
    socket-proxy/Dockerfile \
    socket-proxy/translations/en.yaml \
    socket-proxy/rootfs/etc/services.d/socket-proxy/run \
    socket-proxy/rootfs/etc/services.d/socket-proxy/finish \
    socket-proxy/rootfs/templates/haproxy.cfg \
    repository.yaml; do
    if [[ -f "${REPO_ROOT}/${f}" ]]; then
        pass "${f} exists"
    else
        fail "${f} missing"
    fi
done

for f in \
    socket-proxy/rootfs/etc/services.d/socket-proxy/run \
    socket-proxy/rootfs/etc/services.d/socket-proxy/finish; do
    if [[ -x "${REPO_ROOT}/${f}" ]]; then
        pass "${f} is executable"
    else
        fail "${f} is NOT executable"
    fi
done

# ---------------------------------------------------------------------------
section "YAML validity"
# ---------------------------------------------------------------------------

yaml_files=(
    socket-proxy/config.yaml
    socket-proxy/build.yaml
    socket-proxy/translations/en.yaml
    repository.yaml
)

if command -v python3 &>/dev/null; then
    for f in "${yaml_files[@]}"; do
        if python3 -c "import yaml; yaml.safe_load(open('${REPO_ROOT}/${f}'))" 2>/dev/null; then
            pass "${f} is valid YAML"
        else
            fail "${f} is invalid YAML"
        fi
    done
else
    skip "python3 not available — skipping YAML validation"
fi

# ---------------------------------------------------------------------------
section "ShellCheck"
# ---------------------------------------------------------------------------

RUN_SCRIPT="${ADDON_DIR}/rootfs/etc/services.d/socket-proxy/run"
if command -v shellcheck &>/dev/null; then
    if shellcheck --severity=warning --shell=bash "${RUN_SCRIPT}" 2>/dev/null; then
        pass "run script passes shellcheck"
    else
        fail "run script has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

# ---------------------------------------------------------------------------
section "Hadolint"
# ---------------------------------------------------------------------------

DOCKERFILE="${ADDON_DIR}/Dockerfile"
if command -v hadolint &>/dev/null; then
    if hadolint "${DOCKERFILE}" 2>/dev/null; then
        pass "Dockerfile passes hadolint"
    else
        fail "Dockerfile has hadolint warnings"
    fi
else
    skip "hadolint not installed"
fi

# ---------------------------------------------------------------------------
section "Config consistency"
# ---------------------------------------------------------------------------

if command -v python3 &>/dev/null; then

    # Every option in config.yaml has a translation in en.yaml
    missing_translations=$(python3 -c "
import yaml
config = yaml.safe_load(open('${ADDON_DIR}/config.yaml'))
trans = yaml.safe_load(open('${ADDON_DIR}/translations/en.yaml'))
trans_keys = set(trans.get('configuration', {}).keys())
missing = [k for k in config.get('options', {}) if k not in trans_keys]
if missing:
    print(' '.join(missing))
")
    if [[ -z "${missing_translations}" ]]; then
        pass "all options have translations"
    else
        fail "options missing translations: ${missing_translations}"
    fi

    # Every option has a schema entry
    missing_schema=$(python3 -c "
import yaml
config = yaml.safe_load(open('${ADDON_DIR}/config.yaml'))
options = set(config.get('options', {}).keys())
schema = set(config.get('schema', {}).keys())
missing = options - schema
if missing:
    print(' '.join(sorted(missing)))
")
    if [[ -z "${missing_schema}" ]]; then
        pass "all options have schema entries"
    else
        fail "options missing schema entries: ${missing_schema}"
    fi

    # Every bool option in schema is referenced in the run script
    unreferenced=$(python3 -c "
import yaml
config = yaml.safe_load(open('${ADDON_DIR}/config.yaml'))
run_content = open('${RUN_SCRIPT}').read()
schema = config.get('schema', {})
bool_opts = [k for k, v in schema.items() if v == 'bool']
missing = [k for k in bool_opts if k not in run_content]
if missing:
    print(' '.join(sorted(missing)))
")
    if [[ -z "${unreferenced}" ]]; then
        pass "all bool schema options referenced in run script"
    else
        fail "bool options not in run script: ${unreferenced}"
    fi

    # Architectures match between config.yaml and build.yaml
    arch_mismatch=$(python3 -c "
import yaml
config = yaml.safe_load(open('${ADDON_DIR}/config.yaml'))
build = yaml.safe_load(open('${ADDON_DIR}/build.yaml'))
config_arch = set(config.get('arch', []))
build_arch = set(build.get('build_from', {}).keys())
if config_arch != build_arch:
    print(f'config={sorted(config_arch)} build={sorted(build_arch)}')
")
    if [[ -z "${arch_mismatch}" ]]; then
        pass "architectures match between config.yaml and build.yaml"
    else
        fail "architecture mismatch: ${arch_mismatch}"
    fi

    # Version follows semver format
    version_ok=$(python3 -c "
import yaml, re
config = yaml.safe_load(open('${ADDON_DIR}/config.yaml'))
v = config.get('version', '')
if re.match(r'^\d+\.\d+\.\d+$', v):
    print('ok')
")
    if [[ "${version_ok}" == "ok" ]]; then
        pass "version '$(python3 -c "import yaml; print(yaml.safe_load(open('${ADDON_DIR}/config.yaml')).get('version',''))")' is valid semver"
    else
        fail "version does not match semver format"
    fi

else
    skip "python3 not available — skipping config consistency checks"
fi

# ---------------------------------------------------------------------------
section "Docker build"
# ---------------------------------------------------------------------------

if command -v docker &>/dev/null; then
    if docker build \
        --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21 \
        -t socket-proxy-test \
        "${ADDON_DIR}" &>/dev/null; then
        pass "docker build succeeds"
    else
        fail "docker build failed"
    fi
else
    skip "docker not available"
fi

# ---------------------------------------------------------------------------
section "Summary"
# ---------------------------------------------------------------------------

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
