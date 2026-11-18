#!/bin/sh

# Exit on any error
set -e

# Read parameters until all arguments has been consumed
while [ $# -gt 0 ]; do

  case $1 in

    --db-container-name=*)
      DB_CONTAINER_NAME="${1#*=}"
    ;;
    --db-engine=*)
      DB_ENGINE="${1#*=}"
    ;;

    --db-name=*)
      DB_NAME="${1#*=}"
    ;;

    --db-user=*)
      DB_USER="${1#*=}"
    ;;

    --db-password=*)
      DB_PASSWD="${1#*=}"
    ;;

    --db-extension=*)
      DB_SUFFIX="${1#*=}"
    ;;

    --dump-args=*)
      DB_DUMP_ARGS="${1#*=}"
    ;;

    --dump-path=*)
      DB_DUMP_PATH="${1#*=}"
    ;;

    *)
      echo "WARNING: Unrecognized parameter '$1'"
    ;;
  esac

  shift
done

# Validate if DB_CONTAINER_NAME was passed
if [ -z $DB_CONTAINER_NAME ]; then
  echo "ERROR: Parameter '--db-container-name=<container_name>' is required"
  missing_parameters=1

# Validate if DB_CONTAINER_NAME exists and is running
elif [ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
  echo "ERROR: Container '$DB_CONTAINER_NAME' is not running, or does not exist."
  missing_parameters=1
fi

# Validate DB_ENGINE
if [ -z $DB_ENGINE ]; then
  # If DB_ENGINE was not passed, attempt to guess it by parsing the image name from the container
  DB_ENGINE=$(docker inspect -f {{.Config.Image}} $DB_CONTAINER_NAME  | grep -i -o -e  "mariadb" -e "mysql" -e "postgres" -e "mongo" -e "mssql")

  # Re-check DB_ENGINE
  if [ -z $DB_ENGINE ]; then
    echo "ERROR: Could not recognize the database engine of container '$DB_CONTAINER_NAME'. Parameter --db-engine' is required."
    missing_parameters=1
  else
    echo "INFO: Database engine of container '$DB_CONTAINER_NAME' was auto-detected as '$DB_ENGINE'"
  fi

else

  # Validate if DB_ENGINE is valid and mandatory arguments/variables as per engine case
  case $DB_ENGINE in

    mariadb|mysql|postgres|mongo)
    ;;

    mssql)
      if [ -z "$DB_DUMP_PATH" ]; then
        echo "ERROR: Database Engine '$DB_ENGINE' requires the parameter '--dump-path' (as seen from inside container '$DB_CONTAINER_NAME') in order to proceed."
        missing_parameters=1
      fi
    ;;

    *)
      echo "ERROR: Unsupported database engine: '$DB_ENGINE' for parameter --db-engine."
      missing_parameters=1
    ;;
  esac
fi


# If there are no missing parameters, remaining variables are taken (or guessed) and passed in this order of precendence:
# - If corresponding arguments were passed, it will take these values directly
# - If no corresponding arguments were passed, it will try to get them from the inherited environment
# - If no corresponding environment exists, it will pass the corresponding variable names as arguments to the container
if [ -z $missing_parameters ]; then
  case $DB_ENGINE in

    mariadb)
      DB_NAME=${DB_NAME:-${MARIADB_DATABASE:-"\$MARIADB_DATABASE"}}
      DB_USER=${DB_USER:-${MARIADB_USER:-"\$MARIADB_USER"}}

      [ $DB_USER = "root" ] \
        && DB_PASSWD=${DB_PASSWD:-${MARIADB_ROOT_PASSWORD:-"\$MARIADB_ROOT_PASSWORD"}} \
        || DB_PASSWD=${DB_PASSWD:-${MARIADB_PASSWORD:-"\$MARIADB_PASSWORD"}}

      DB_DUMP_ARGS=${DB_DUMP_ARGS:-"--single-transaction"}
      DB_SUFFIX=${DB_SUFFIX:-"sql"}

      # Defaults to image's mountpoint to be restored in a fresh start
      DB_DUMP_PATH=${DB_DUMP_PATH:-"/docker-entrypoint-initdb.d"}

      # Create base dump command for MariaDB
      BASE_DB_DUMP_COMMAND="mariadb-dump $DB_DUMP_ARGS --user=\"$DB_USER\" --password=\"$DB_PASSWD\" --result-file=\"$DB_DUMP_PATH/__DB_DUMP_FILENAME__\" \"$DB_NAME\""
    ;;

    mysql)
      DB_NAME=${DB_NAME:-${MYSQL_DATABASE:-"\$MYSQL_DATABASE"}}
      DB_USER=${DB_USER:-${MYSQL_USER:-"\$MYSQL_USER"}}

      [[ $DB_USER = "root" ]] \
        && DB_PASSWD=${DB_PASSWD:-${MYSQL_ROOT_PASSWORD:-"\$MYSQL_ROOT_PASSWORD"}} \
        || DB_PASSWD=${DB_PASSWD:-${MYSQL_PASSWORD:-"\$MYSQL_PASSWORD"}}

      DB_DUMP_ARGS=${DB_DUMP_ARGS:-"--single-transaction"}
      DB_SUFFIX=${DB_SUFFIX:-"sql"}

      # Defaults to image's mountpoint to be restored in a fresh start
      DB_DUMP_PATH=${DB_DUMP_PATH:-"/docker-entrypoint-initdb.d"}

      # Create base dump command for MySQL
      BASE_DB_DUMP_COMMAND="mysqldump $DB_DUMP_ARGS --user=\"$DB_USER\" --password=\"$DB_PASSWD\" --result-file=\"$DB_DUMP_PATH/__DB_DUMP_FILENAME__\" \"$DB_NAME\""
    ;;

    postgres)
      DB_USER=${DB_USER:-${POSTGRES_USER:-"\$POSTGRES_USER"}}
      DB_NAME=${DB_NAME:-${POSTGRES_DB:-"\$POSTGRES_DB"}}
      DB_PASSWD=${DB_PASSWD:-"$POSTGRES_PASSWORD"}
      DB_DUMP_ARGS=${DB_DUMP_ARGS:-""}
      DB_SUFFIX=${DB_SUFFIX:-"sql"}

      # Set password env only if it exists, supporting POSTGRES_HOST_AUTH_METHOD=trust
      [ -n "$DB_PASSWD" ] && PG_ENV_PREFIX="env PGPASSWORD=\"$DB_PASSWD\""

      # Defaults to image's mountpoint to be restored in a fresh start
      DB_DUMP_PATH=${DB_DUMP_PATH:-"/docker-entrypoint-initdb.d"}

      # Create base dump command for PostgreSQL
      BASE_DB_DUMP_COMMAND="$PG_ENV_PREFIX pg_dump $DB_DUMP_ARGS -U \"$DB_USER\" --file=\"$DB_DUMP_PATH/__DB_DUMP_FILENAME__\" \"$DB_NAME\""
    ;;

    mongo)
      DB_USER=${DB_USER:-"$MONGO_INITDB_ROOT_USERNAME"}
      DB_PASSWD=${DB_PASSWD:-"$MONGO_INITDB_ROOT_PASSWORD"}

      # Strict fallback to 'all_dbs' for retention compatibility
      DB_NAME=${DB_NAME:-${MONGO_INITDB_DATABASE:-"all_dbs"}}

      DB_DUMP_ARGS=${DB_DUMP_ARGS:-"--quiet"}
      DB_SUFFIX=${DB_SUFFIX:-"bson"}
      [ -n "$DB_USER" ] && [ -n "$DB_PASSWD" ] && MONGO_AUTH="--username=\"$DB_USER\" --password=\"$DB_PASSWD\" --authenticationDatabase=admin"
      [ "$DB_NAME" != "all_dbs" ] && MONGO_DB_ARG="-d \"$DB_NAME\""

      # Defaults to image's mountpoint to be restored in a fresh start
      DB_DUMP_PATH=${DB_DUMP_PATH:-"/docker-entrypoint-initdb.d"}

      # Create base dump command for MongoDB
      BASE_DB_DUMP_COMMAND="mongodump $MONGO_AUTH $MONGO_DB_ARG $DB_DUMP_ARGS --archive=\"$DB_DUMP_PATH/__DB_DUMP_FILENAME__\""
    ;;

    mssql)
      DB_NAME=${DB_NAME:-"\$DATABASE"}
      DB_USER=${DB_USER:-"SA"}

      # Capture modern official MSSQL var, fallback to legacy SA_PASSWORD
      DB_PASSWD=${DB_PASSWD:-${MSSQL_SA_PASSWORD:-${SA_PASSWORD:-"\$SA_PASSWORD"}}}

      DB_DUMP_ARGS=${DB_DUMP_ARGS:-"-C -b -V16"}
      DB_SUFFIX=${DB_SUFFIX:-"bak"}

      # Create base dump command for MSSQL
      BASE_DB_DUMP_COMMAND="/opt/mssql-tools18/bin/sqlcmd $DB_DUMP_ARGS -S localhost -U \"$DB_USER\" -P \"$DB_PASSWD\" -Q \"BACKUP DATABASE $DB_NAME TO DISK = '$DB_DUMP_PATH/__DB_DUMP_FILENAME__' WITH INIT, NAME='$DB_NAME', NOSKIP, NOFORMAT;\""
    ;;
  esac

  # Establish the name for the dump based upon DB_NAME, current timestamp and DB_SUFFIX
  DB_DUMP_FILENAME=$DB_NAME.$(read -r uptime _ < /proc/uptime && echo "$(date +%Y-%m-%d+%H_%M_%S).${uptime#*.}").$DB_SUFFIX

  # Parse BASE_DB_DUMP_COMMAND into the definitive dump command using DB_DUMP_FILENAME
  DB_DUMP_COMMAND=${BASE_DB_DUMP_COMMAND%%__DB_DUMP_FILENAME__*}$DB_DUMP_FILENAME${BASE_DB_DUMP_COMMAND#*__DB_DUMP_FILENAME__}

  # Dump the database
  echo "Dumping database before $PROFILE_COMMAND operation..."
  docker exec "$DB_CONTAINER_NAME" sh -c "$DB_DUMP_COMMAND"

  if [ $? -eq 0 ]; then

    echo "Database backup '$DB_DUMP_FILENAME' created sucessfully."

    # Delete previously saved backup(s) if name syntax matches exactly (ignoring any other files)
    echo "Searching for previous local DB backups (and deleting if found)..."
    docker exec "$DB_CONTAINER_NAME" sh -c "find \"$DB_DUMP_PATH\" -type f -name \"*.$DB_SUFFIX\" ! -name \"$DB_DUMP_FILENAME\" | grep -E \"/$DB_NAME\.[0-9]{4}-[0-9]{2}-[0-9]{2}\+[0-9]{2}_[0-9]{2}_[0-9]{2}\.[0-9]{2}\.$DB_SUFFIX$\" | xargs -I {} sh -c 'rm -f \"{}\" && echo \"\$(basename \"{}\") deleted\"'"

  else
    echo "ERROR: Database backup failed with exit code: $?"
    exit $?
  fi

else
  exit 1
fi
