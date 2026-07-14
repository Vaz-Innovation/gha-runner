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

if [ -z "$REGISTRATION_TOKEN" ]; then
    echo "Error: REGISTRATION_TOKEN environment variable is required"
    echo "Get token from: $REPO_URL/settings/actions/runners/new"
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
        ./config.sh remove --token "$REGISTRATION_TOKEN"
    else
        echo "Ephemeral runner - no manual cleanup needed"
    fi
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "Starting GitHub Actions Runner $RUNNER_NAME"

./run.sh & wait $!
