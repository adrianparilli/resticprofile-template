#!/bin/sh

# This script can be invoked by any other script prio to its run, to get environmental variables
# that aren't directly (or securely) provided by the running system.

# Detect when resticprofile runs inside a docker container
[ -f "/.dockerenv" ] \
    && DOCKERIZED="true" \
    || DOCKERIZED="false"
