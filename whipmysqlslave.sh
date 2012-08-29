#!/bin/bash
## Tool to unstick MySQL Replicators.
## Set to run from cron once a minute.
#
# */1 * * * * /root/scripts/whipmysqlslave.sh > /dev/null 2>&1
#
# Last updated: 28/08/2012
##

COMMANDS="awk cat cut date grep head hostname ifconfig logger mail mysql tail"

export PATH='/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin'

# Define Commands
for i in $COMMANDS
do
        X=`echo $i | tr '[a-z]' '[A-Z]'`
        export $X=`type -p $i`
done

# Define variables
HOST=127.0.0.1
PORT=3307
EMAILS="username@domain.com,username2@domain.com"

MYUSERNAME=MYSQLUSER
MYPASSWORD=MYSQLUSERPASSWORD
MYSOCKET=
MYSQLLOG=/var/log/mysqld1.log

TIMESTAMP=$($DATE "+%e-%m-%Y %R:%S")
EXTIP=`$IFCONFIG eth0 | $HEAD -n2 | $TAIL -n1 | $CUT -d' ' -f12 | $CUT -c 6-`

## Are we using Sockets or ports?
if [[ $SOCKET ]]
then
	LOCATION="-S $SOCKET"
	LOCATIONMSG="$SOCKET on `$HOSTNAME -s`[$EXTIP]"
else
	LOCATION="-h $HOST -P $PORT"
	LOCATIONMSG="$PORT on `$HOSTNAME -s`[$EXTIP]"
fi

# Define Functions
## Obtain MySQL slave server status
function SLAVE()
{
        STATUS=`$MYSQL $LOCATION -u $USERNAME -p$PASSWORD -e \
                "SHOW SLAVE STATUS \G" |
                $GREP Seconds_Behind_Master |
                $AWK '{print $2}'`

        ERROR=`$MYSQL $LOCATION -u $USERNAME -p$PASSWORD -e \
                "SHOW SLAVE STATUS \G" |
                $GREP Last_Error |
                $AWK -F \: '{print $2}'`
}

## Mail Alert
function MAILALERT() {
        ERRORLOG=`$CAT $MYSQLLOG | $GREP "\[ERROR\] Slave SQL:" | $TAIL -1`
        BODY="MySQL Slave $LOCATIONMSG has stopped replicating on $TIMESTAMP.\n\nLast_Error: $ERROR.\n\nFrom $MYSQLLOG:\n\n$ERRORLOG"
        SUBJECT="ERROR: Slave $LOCATIONMSG has stopped replicating!"

        echo -e $BODY | $MAIL -s "$SUBJECT" $EMAILS
}

## Skip errors
function UNSTICK()
{
        $MYSQL $LOCATION -u $USERNAME -p$PASSWORD -e \
                "STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1; START SLAVE;"
        sleep 5
        # Check everything again
        CHECK
}

## Decide what to do...
function CHECK()
{
        # Obtain status
        SLAVE
        if [ $STATUS = NULL ]
        then
                # I think the replicator is broken
                echo "MySQL Slave $LOCATIONMSG replication broken! Last_Error: $ERROR" | $LOGGER
                MAILALERT
                echo "MySQL Slave $LOCATIONMSG is not replicating! Fixing..." | $LOGGER
                UNSTICK
        else
                # Everything should be fine
                echo "MySQL Slave $LOCATIONMSG is $STATUS seconds behind its Master..." | $LOGGER
        fi
}

## Are we running?
function ALIVE()
{
        UP=`$MYSQL $LOCATION -u $USERNAME -p$PASSWORD -e \
                "SHOW SLAVE STATUS \G" |
                $GREP Slave_IO_Running |
                $AWK '{print $2}'`

        if [ $UP = Yes ]
        then
                # Let's check if everything is good, then...
                CHECK
        else
                # Uh oh...let's not do anything.
                echo "MySQL Slave IO in $LOCATIONMSG is not running!" | $LOGGER
                exit 1
        fi
}

# How is everything?
ALIVE

#EoF
exit 0
