#!/bin/bash

notify_method=$1

# Load system environmental variables
source "$SCRIPTS_PATH/_system_env.sh"

# When argument is passed, will proceed according the type
case $notify_method in
    '')
        # Silently exit if no notification method has been set
        exit 0
    ;;
    send-notify)
        if [[ -n $NOTIFY_SEND_USER ]]; then
            notify_command="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u $NOTIFY_SEND_USER)/bus notify-send -a Resticprofile -u critical \"$HOSTNAME Status: $PROFILE_NAME $PROFILE_COMMAND operation failed\" \"Command $ERROR_COMMANDLINE ended with $ERROR_MESSAGE\""
        else
            echo "WARNING: No user has been set to send notifications"
            exit 1
        fi
    ;;

    mail)
        if [[ -n $NOTIFY_MAIL_ADDR ]]; then
            notify_command="echo \"Command $ERROR_COMMANDLINE ended with $ERROR_MESSAGE\" | mail -s \"$HOSTNAME Status: $PROFILE_NAME $PROFILE_COMMAND operation failed\" $NOTIFY_MAIL_ADDR\""
        else
            echo "WARNING: No destiation email has been set in order to send notifications"
            exit 1
        fi
    ;;

    unraid-notify)
        notify_command="/usr/local/emhttp/plugins/dynamix/scripts/notify -i \"warning\" -e \"Resticprofile\" -s \"$PROFILE_NAME $PROFILE_COMMAND operation failed\" -d \"Command $ERROR_COMMANDLINE ended with $ERROR_MESSAGE\""
    ;;

    *)  # Any other unrecognized argument will make the script to fail
        echo "Incorrect argument '$1'"
        exit 1
    ;;
esac

if [[ $DOCKERIZED == "true" ]]; then

    # Verify both SSH related variables has been set
    if [[ -n "$SSH_OPTIONS" && -n "$SSH_LOGIN" ]]; then
        notice="Attempting to send notification via SSH through chosen method ($notify_method)..."
        notify_command="ssh $SSH_OPTIONS $SSH_LOGIN $notify_command"
    else
        echo "WARNING: Cannot proceed because not all SSH parameters has been set"
        exit 1
else
    notice="Attempting to send notification through chosen method ($notify_method)..."
fi

if [[ -n "$notify_command" ]]; then
    # Run the resulting notification
    $notify_command

    # Get the exit code of the operation
    notify_status=$?

    [[ $notify_status -ne 0 ]] \
        && echo "WARNING: Notification method '$notify_method' failed (exit code: $notify_status)"
fi

# Exit with the resulting code (if any)
exit $notify_status
