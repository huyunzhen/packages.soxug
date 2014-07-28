# /etc/sysconfig/${PROGNAME} may contain configurable
# environment variables:
#   DAEMON    Alternate daemon location and name
#   ADINFO    Alternate location for adinfo command
#   OPTIONS   Daemon command line options. These are combined with any
#             additional command line parameters.

PROGNAME=${PROGNAME:-adclient}
if [ -f /etc/sysconfig/${PROGNAME} ]; then
    . /etc/sysconfig/${PROGNAME}
fi
SERVICE_NAME=${SERVICE_NAME:-centrifydc}

ADINFO=${ADINFO:-/usr/bin/adinfo}
PIDFILE=${PIDFILE:-/var/run/${PROGNAME}.pid}
DAEMON=${DAEMON:-/usr/sbin/${PROGNAME}}
SVC="/lib/svc/bin/svc.startd"

NAME=${NAME:-"Centrify DirectControl"}

# Set up a default search paths
LD_LIBRARY_PATH=/usr/share/centrifydc/lib:/usr/share/centrifydc/kerberos/lib:$LD_LIBRARY_PATH

GREP=${GREP:-/bin/grep}
PS=${PS:-/bin/ps}
INITCTL=${INITCTL:-/sbin/initctl}

NOECHO=${NOECHO:-0}

RC_OK=0
RC_FAIL=1

#
# Upstart uses /bin/sh -e to execute scripts, so no function can return
# non zero return code without terminated the calling scritps
#
wait_adclient () {
        # wait for a maximun of 60 seconds for adclient to be connected
        MAX=${1:-60}
        MODE=`$ADINFO -m` || true
        while [ $MAX -gt 0 ] && [ "$MODE" != "connected" ] && [ "$MODE" != "disconnected" ]; do
            MAX=`expr $MAX - 2`
            sleep 2
            MODE=`$ADINFO -m` || true
        done || true
        echo "adclient state is: $MODE"
}

#
# Check root permission for the program which need to be run as root
#
# params: 1) CMD (e.g. start, stop)
#
program_check_root() {
    CMD=$1
    if [ -z "$UID" ]; then
        UID=`id | sed -e 's/uid=//' -e 's/[^0-9].*$//'`
    fi
    if [ "$UID" -ne "0" ]; then
        echo "Root privilege is required to $CMD ${NAME}."
        exit 1
    fi
    return 0
}

get_program_pid_ps() {

    # on Solaris machine that support zone, when the script is run on global zone
    # ensure that ps only return program's pid run on  global zone. 
    if [ "`uname`" = "SunOS" -a -x /usr/bin/zonename ]; then
        ZONENAME=`zonename`
        PSOUT=`$PS -z "$ZONENAME" -o pid,args`
    else
        if [ "`uname`" = "HP-UX" ]; then
            # to use the XPG4 behavior
            PSOUT=`UNIX95= $PS -e -o pid,args`
        else
            PSOUT=`$PS -e -o pid,args`
        fi
    fi
    echo "$PSOUT" | awk '{if ($2 == PROC) { print $1 }}' PROC="$DAEMON"
}

program_pid () {
    if [ -f "$PIDFILE" ]; then
        PID=`cat $PIDFILE 2> /dev/null`
    else
        PID=`get_program_pid_ps`
    fi
    return 0
}

program_status () {
        program_pid
        # No PID: daemon not running
        if [ -z "$PID" ]; then
            [ $NOECHO -ne 1 ] && echo "$NAME is stopped"
            return 0
        fi

        # Verify PID
	    PID=`get_program_pid_ps`
        if [ -n "$PID" ]; then
            if [ $NOECHO -ne 1 ]; then
                 echo "$NAME (pid $PID) is running..."
            fi
        else
            if [ $NOECHO -ne 1 ]; then
                 echo "$NAME not running but PID file exists"
            fi
            PID=
        fi
}

program_check_no_exit () {
        EXITCODE=0
        if [ "${PROGNAME}" = "adclient" ]; then
            ZONE=`$ADINFO --zone` || true
            if [ -z "$ZONE" ]; then
                echo
                echo "  Failed: machine is not joined."
                EXITCODE=2
                return 0
            fi
        fi

        NOECHO=1
        program_status
        if [ -n "$PID" ]; then
            echo
            echo "daemon is already running (pid $PID)."
            EXITCODE=1
            return 0
        fi
        NOECHO=0

        if [ ! -x $DAEMON ]; then
            echo
            echo "  Failed: daemon '$DAEMON' is not executable."
            EXITCODE=2
            return 0
        fi
        return 0
}

program_check () {
        program_check_no_exit
        if [ $EXITCODE -ne 0 ]; then
            exit $EXITCODE
        fi
        return 0
}


#
# Wait for a netwrok interface to be up or timeout seconds
#
# uses ifconfig -s (Linux version of ifconfig)
# Need modification for other OS'es
#
wait_interface () {
        MAX=${1:-10}
        INTERFACE=
        IFCONFIG=/sbin/ifconfig
        while [ $MAX -gt 0 ]; do
            for itf in `$IFCONFIG -s | awk '{ print $1;}'`
            do
                if [ $itf != "Iface" ] && [ $itf != "lo" ]; then
                    INTERFACE=$itf
                    break;
                fi
            done
            if [ -n "$INTERFACE" ]; then
                break
            else
                MAX=`expr $MAX - 1`
                sleep 1
            fi
        done
        return 0
}

#
# Check whether need to use Upstart and then call it if needed
#
# params: 1) CMD (e.g. start, stop)
#
# Return: 0) if call Upstart in this function
#         1) if not call
#
# Variables: UPSTART_EXITCODE) exit code of upstart
#
run_with_upstart () {
    UPSTART_CONF_DIR="/etc/init"
    CMD="$1"
    if [ -f "${UPSTART_CONF_DIR}/${SERVICE_NAME}.conf" ] \
      && ${INITCTL} version > /dev/null 2>&1; then # if service file exist and upstart is running
        if [ -x "/lib/init/upstart-job" ]; then
            # use upstart-job script to call upstart
            /lib/init/upstart-job $SERVICE_NAME $CMD
            UPSTART_EXITCODE=$?
        else
            echo "Executing via Upstart: ${INITCTL} $CMD $SERVICE_NAME"
            ${INITCTL} $CMD $SERVICE_NAME
            UPSTART_EXITCODE=$?
        fi
        return 0
    else
        return 1
    fi
}
