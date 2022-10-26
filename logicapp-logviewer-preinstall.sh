#!/bin/bash

if ! command -v apt-get > /dev/null 2>&1; then
    echo -e '\033[0;31m\nLogic App Log Viewer installed.  In order to use the Logic App Log Viewer, dialog, jq, and less.  Add the following to your Dockerfile to include in your container image.\n\nRUN \\\n\tapt-get update && \\\n\tapt-get install less dialog -y && \\\n\tcurl -L \"https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64\" -o /usr/bin/jq && \\\n\tchmod a+x /usr/bin/jq\n\n\033[0m'
    exit 0
fi

#check dependencies
if command -v sudo > /dev/null 2>&1; then
    SUDO_CMD="sudo"
fi
if ! command -v curl > /dev/null 2>&1; then
    echo '"curl" is required to use this script but was not found.  Installing curl. '
    $SUDO_CMD apt-get install curl -y
fi
if ! command -v dialog > /dev/null 2>&1; then
    echo '"dialog" is required to use this script but was not found.  Installing dialog.'
    $SUDO_CMD apt-get install dialog -y
fi
if ! command -v jq > /dev/null 2>&1; then
    echo '"jq" is required to use this script but was not found.  Installing jq. '
    $SUDO_CMD curl -L "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" -o /usr/bin/jq
    $SUDO_CMD chmod a+x /usr/bin/jq
fi
if ! command -v less > /dev/null 2>&1; then
    echo '"less" is required to use this script but was not found.  Installing less. '
    $SUDO_CMD apt-get install less -y
fi

echo -e "All dependencies checked and valid.\n"