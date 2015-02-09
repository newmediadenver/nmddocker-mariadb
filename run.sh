#!/bin/bash

set -e
set -u


# User-provided env variables
MARIADB_USER=${MARIADB_USER:="admin"}
MARIADB_PASS=${MARIADB_PASS:-"admin"}

# Other variables
mkdir -p /var/log/mysql
VOLUME_HOME="/var/lib/mysql"
ERROR_LOG="/var/log/mysql/error.log"
MYSQLD_PID_FILE="/var/lib/mysql/mysql.pid"


#########################################################
# Check in the loop (every 1s) if the database backend
# service is already available for connections.
#########################################################
function wait_for_db() {
  set +e
  local res=1
  while [[ $res != 0 ]]; do
    mysql -uroot -e "status" > /dev/null 2>&1
    res=$?
    if [[ $res != 0 ]]; then echo "Waiting for DB service..." && sleep 1; fi
    # If mysql process died at this stage (which might happen if e.g. wrong
    # config was provided), break the loop. Otherwise the loop never ends!
    if [[ ! -f $MYSQLD_PID_FILE ]]; then break; fi
  done
  set -e
}


#########################################################
# Check in the loop (every 1s) if the database backend
# service is already available for connections.
#########################################################
function terminate_db() {
  local pid=$(cat /var/lib/mysql/mysql.pid)
  echo "Caught SIGTERM signal, shutting down DB..."
  kill -TERM $pid
  
  while true; do
    if tail $ERROR_LOG | grep -s -E "mysqld .+? ended" $ERROR_LOG; then break; else sleep 0.5; fi
  done
}


#########################################################
# Cals `mysql_install_db` if empty volume is detected.
# Globals:
#   $VOLUME_HOME
#   $ERROR_LOG
#########################################################
function install_db() {
  if [ ! -d $VOLUME_HOME/mysql ]; then
    echo "=> An empty/uninitialized MariaDB volume is detected in $VOLUME_HOME"
    echo "=> Installing MariaDB..."
    mysql_install_db --user=mysql > /dev/null 2>&1
    echo "=> Done!"
  else
    echo "=> Using an existing volume of MariaDB."
  fi
  
  # Move previous error log (which might be there from previously running container
  # to different location. We do that to have error log from the currently running
  # container only.
  if [ -f $ERROR_LOG ]; then
    echo "----------------- Previous error log -----------------"
    tail -n 20 $ERROR_LOG
    echo "----------------- Previous error log ends -----------------" && echo
    mv -f $ERROR_LOG "${ERROR_LOG}.old";
  fi

  touch $ERROR_LOG && chown mysql $ERROR_LOG
}

#########################################################
# Check in the loop (every 1s) if the database backend
# service is already available for connections.
# Globals:
#   $MARIADB_USER
#   $MARIADB_PASS
#########################################################
function create_admin_user() {
  local users=$(mysql -s -e "SELECT count(User) FROM mysql.user WHERE User='$MARIADB_USER'")
  if [[ $users == 0 ]]; then
    echo "=> Creating MariaDB user '$MARIADB_USER' with '$MARIADB_PASS' password."
    mysql -uroot -e "CREATE USER '$MARIADB_USER'@'%' IDENTIFIED BY '$MARIADB_PASS'"
  else
    echo "=> User '$MARIADB_USER' exists, updating its password to '$MARIADB_PASS'"
    mysql -uroot -e "SET PASSWORD FOR '$MARIADB_USER'@'%' = PASSWORD('$MARIADB_PASS')"
  fi;
  
  mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '$MARIADB_USER'@'%' WITH GRANT OPTION"

  echo "========================================================================"
  echo "You can now connect to this MariaDB Server using:                       "
  echo "                                                                        "
  echo "    mysql -u$MARIADB_USER -p$MARIADB_PASS -h<host>                      "
  echo "                                                                        "
  echo "For security reasons, you might want to change the above password.      "
  echo "MariaDB user 'root' has no password but only allows local connections   "
  echo "========================================================================"
}

function show_db_status() {
  mysql -uroot -e "status"
}

function secure_and_tidy_db() {
  mysql -uroot -e "DROP DATABASE IF EXISTS test"
  mysql -uroot -e "DELETE FROM mysql.user where User = ''"
  
  # Remove warning about users with hostnames (as DB is configured with skip_name_resolve)
  mysql -uroot -e "DELETE FROM mysql.user where User = 'root' AND Host NOT IN ('127.0.0.1','::1')"
  mysql -uroot -e "DELETE FROM mysql.proxies_priv where User = 'root' AND Host NOT IN ('127.0.0.1','::1')"
}

# Trap INT and TERM signals to do clean DB shutdown
trap terminate_db SIGINT SIGTERM

install_db
tail -F $ERROR_LOG & # tail all db logs to stdout 

/usr/bin/mysqld_safe & # Launch DB server in the background
MYSQLD_SAFE_PID=$!

wait_for_db
secure_and_tidy_db
show_db_status
create_admin_user

# Do not exit this script untill mysqld_safe exits gracefully
wait $MYSQLD_SAFE_PID
