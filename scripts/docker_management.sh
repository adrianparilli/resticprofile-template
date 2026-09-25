#!/bin/bash

docker_command=$1
shift

flag_file_path="/var/tmp"
docker_status=0

# Load system environmental variables
source "$SCRIPTS_PATH/_system_env.sh"

case $docker_command in

  '')
    exit 0
  ;;

  stop)
    for container in "$@"; do

      if [[ "$(docker container inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == "true" ]]; then

        docker stop "$container" >/dev/null
        docker_status=$?

        if [[ $docker_status -eq 0 ]]; then
          touch "$flag_file_path/.restic_stopped_$container"
        else
          break
        fi
      fi
    done
  ;;

    start)
      for container in "$@"; do

        if [[ -f "$flag_file_path/.restic_stopped_$container" ]]; then

          docker start "$container" >/dev/null
          docker_status=$?

          if [[ $docker_status -eq 0 ]]; then
            rm -f "$flag_file_path/.restic_stopped_$container"

          else
            break
          fi

        else
          echo "INFO: Container '$container' was not running before $RESTICPROFILE_COMMAND of profile $RESTICPROFILE_PROFILE, so it will not be started"
        fi
      done
    ;;

  *)
    echo "Incorrect argument '$docker_command'"
    exit 1
  ;;
esac

if [[ $docker_status -ne 0 ]]; then
  echo "WARNING: Docker command '$docker_command' failed (exit code: $docker_status)"
fi

exit $docker_status
