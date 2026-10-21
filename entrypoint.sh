#!/bin/bash

echo "Starting..."

set -e

# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock

if [ -z "$REPO_URL" ]; then
    echo "Error: REPO_URL environment variable is required"
    echo "Example: https://github.com/owner/repo"
    exit 1
fi

# Registration tokens expire after one hour, so a fixed REGISTRATION_TOKEN
# breaks the runner on its next restart. With ACCESS_TOKEN (a PAT allowed to
# manage self-hosted runners) a fresh token is requested on every start.
# REPO_URL https://github.com/org        -> orgs/org
# REPO_URL https://github.com/owner/repo -> repos/owner/repo
REPO_PATH=$(echo "${REPO_URL%/}" | sed -E 's#^https?://[^/]+/##')
if [[ "$REPO_PATH" == */* ]]; then
    API_SCOPE="repos/${REPO_PATH}"
else
    API_SCOPE="orgs/${REPO_PATH}"
fi
GITHUB_API_URL=${GITHUB_API_URL:-"https://api.github.com"}

# Usage: fetch_token registration-token | remove-token
fetch_token() {
    local token
    token=$(curl -fsS -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL}/${API_SCOPE}/actions/runners/$1" | jq -r '.token // empty')
    if [ -z "$token" ]; then
        echo "Error: could not get a $1 from ${GITHUB_API_URL}/${API_SCOPE}" >&2
        echo "Check that ACCESS_TOKEN is valid and can manage self-hosted runners" >&2
        return 1
    fi
    echo "$token"
}

if [ -n "$ACCESS_TOKEN" ]; then
    echo "Requesting a registration token for ${API_SCOPE}..."
    REGISTRATION_TOKEN=$(fetch_token registration-token)
fi

if [ -z "$REGISTRATION_TOKEN" ]; then
    echo "Error: ACCESS_TOKEN or REGISTRATION_TOKEN environment variable is required"
    echo "Get a registration token from: $REPO_URL/settings/actions/runners/new"
    exit 1
fi

if [ -z "$RUNNER_NAME" ]; then
    RUNNER_NAME="docker-runner-$(hostname)"
else
    RUNNER_NAME="${RUNNER_NAME}-$(hostname)"
fi

EPHEMERAL=${EPHEMERAL:-"false"}
DISABLE_UPDATE=${DISABLE_UPDATE:-"false"}

# Get Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)

# Get runner version from the installed runner
RUNNER_VERSION=$(./bin/Runner.Listener --version | head -1 | cut -d' ' -f3)

# Build labels with version info always included
DEFAULT_LABELS="docker,ubuntu-${UBUNTU_VERSION},runner-${RUNNER_VERSION}"
USER_LABELS=${RUNNER_LABELS:-""}

if [ -n "$USER_LABELS" ]; then
    RUNNER_LABELS="${DEFAULT_LABELS},${USER_LABELS}"
else
    RUNNER_LABELS="$DEFAULT_LABELS"
fi

echo "Configuring GitHub Actions Runner..."
echo "Runner Version: $RUNNER_VERSION"
echo "Repository: $REPO_URL"
echo "Runner Name: $RUNNER_NAME"
echo "Labels: $RUNNER_LABELS"
echo "Ephemeral: $EPHEMERAL"
echo "Disable Update: $DISABLE_UPDATE"

CONFIG_ARGS="--url $REPO_URL --token $REGISTRATION_TOKEN --name $RUNNER_NAME --labels $RUNNER_LABELS --work _work --unattended --replace"

if [ "$EPHEMERAL" = "true" ]; then
    CONFIG_ARGS="$CONFIG_ARGS --ephemeral"
fi

if [ "$DISABLE_UPDATE" = "true" ]; then
    CONFIG_ARGS="$CONFIG_ARGS --disableupdate"
fi

sed -i 's/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x55\x00\x52\x00\x4C\x00/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x4F\x00\x52\x00\x4C\x00/g' /runner/bin/Runner.Worker.dll

./config.sh $CONFIG_ARGS

cleanup() {
    if [ "$EPHEMERAL" != "true" ]; then
        echo "Removing runner..."
        REMOVE_TOKEN=$REGISTRATION_TOKEN
        if [ -n "$ACCESS_TOKEN" ]; then
            REMOVE_TOKEN=$(fetch_token remove-token) || REMOVE_TOKEN=$REGISTRATION_TOKEN
        fi
        ./config.sh remove --token "$REMOVE_TOKEN"
    else
        echo "Ephemeral runner - no manual cleanup needed"
    fi
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "Starting GitHub Actions Runner $RUNNER_NAME"

./run.sh & wait $!
