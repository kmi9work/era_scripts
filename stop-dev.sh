#!/bin/bash
# Stop all development services

SESSION_NAME="era-dev"

if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo "Stopping ERA development session..."
    tmux kill-session -t $SESSION_NAME
    echo "✓ Session stopped"
else
    echo "No active ERA development session found"
fi

