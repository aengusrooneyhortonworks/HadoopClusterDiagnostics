#!/bin/env bash

# A. Run the shell script hive_template.sh each time for "HiveServer2","HiveMetastore", and "hive" PID's.
# 
# B. Gather following details:
#
# 1. Collect the following logs:
#
# ·   HiveServer2 Logs.
# ·   HiveMetaStore Logs. 
# ·   Zookeeper Logs (from all the Zookeeper nodes).
#     
# 2.  Collect the "Hadoop configuration files" and "Hive configuration files":
#
# ·   /etc/hadoop/conf/*
# ·   /etc/hive/conf.server/* 
# 
# 3. Provide output of following:
#
# ·   From "hive cli"
#       hive -e 'set -v'   
# ·   From beeline 
#       set -v 
#           
# C. Provide the following details about the "hive" queries:
#
# ·   'explain' plan on the query
# ·   An isolated query, ideally a narrowed-down smaller query that shows the problem.
# ·   'describe formatted' on all tables in the query, if they are views, get describe formatted on the source tables of the views.

function syschk() {
    local __doc__="Execute OS command to check system for triage"
    local _p="$1"       # Java PID ex: `cat /var/run/hive/hive.pid` or `cat /var/run/hive/hive-server.pid`
    local _work_dir="$2"
    [ -z "${_work_dir}" ] && _work_dir="/hadoop/${FUNCNAME}_tmp_dir"
    if [ ! -d "$_work_dir" ] && ! mkdir $_work_dir; then
        echo "ERROR: Couldn't create $_work_dir directory"; return 1
    fi
    
    chmod 777 $_work_dir

    if [ -n "$_p" ]; then
        echo "Collecting java PID $_p related information..."
        local _j="$(dirname `readlink /proc/${_p}/exe`)" 2>/dev/null
            local _u="`stat -c '%U' /proc/${_p}`"
            for i in {1..3};do su ${_u} -c "jstack -l ${_p}"; sleep 5; done &> ${_work_dir%/}/jstack_${_p}.out &
            su ${_u} -c "jstat -gccause ${_p} 1000 5" &> ${_work_dir%/}/jstat_${_p}.out &
            su ${_u} -c "jmap -histo:live ${_p}" &> ${_work_dir%/}/jmap_histo_live_${_p}.out &
        
        ps -eLo user,pid,lwp,nlwp,ruser,pcpu,stime,etime,args | grep -w "${_p}" &> ${_work_dir%/}/pseLo_${_p}.out
        lsof -P -p ${_p}  &> ${_work_dir%/}/lsof_${_p}.out
        cat /proc/${_p}/limits &> ${_work_dir%/}/proc_limits_${_p}.out
        cat /proc/${_p}/status &> ${_work_dir%/}/proc_status_${_p}.out
        cat /proc/${_p}/io &> ${_work_dir%/}/proc_io_${_p}.out;sleep 5;cat /proc/${_p}/io >> ${_work_dir%/}/proc_io_${_p}.out
        cat /proc/${_p}/environ | tr '\0' '\n' > ${_work_dir%/}/proc_environ_${_p}.out
        pmap -x ${_p} &> ${_work_dir%/}/pmap_${_p}.out
        jstat -gc ${_p} |tail -n 1| awk '{split($0,a," "); sum=a[3]+a[4]+a[6]+a[8]; print sum}' > ${_work_dir%/}/heap_usedby_${_p}.out
    fi

    echo "Collecting OS related information..."
    vmstat 1 3 &> ${_work_dir%/}/vmstat.out &
    pidstat -dl 3 3 &> ${_work_dir%/}/pstat.out &
    sysctl -a &> ${_work_dir%/}/sysctl.out
    top -b -n 1 -c &> ${_work_dir%/}/top.out
    ps auxwwwf &> ${_work_dir%/}/ps.out
    netstat -aopen &> ${_work_dir%/}/netstat.out
    netstat -i &> ${_work_dir%/}/netstat_i.out
    netstat -s &> ${_work_dir%/}/netstat_s.out
    ifconfig &> ${_work_dir%/}/ifconfig.out
    nscd -g &> ${_work_dir%/}/nscd.out
    ntpq -p &> ${_work_dir%/}/ntp.out
    ps -fL  &> ${_work_dir%/}/threadcount.out
    set -x
    su ${_u} -c "jmap -dump:live,format=b,file=${_work_dir%/}/jmap_live_dump_${_p}.out ${_p}"
    wait
    echo "Creating tar.gz file..."
    local _file_path="./chksys_$(hostname)_$(date +"%Y%m%d%H%M%S").tar.gz"
    tar --remove-files -czf ${_file_path} ${_work_dir%/}/*.out
    echo "Completed! (${_file_path})"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ -z "$1" ]; then
        echo "$BASH_SOURCE PID [workspace dir]"
        echo "Example:"
        echo "    "$BASH_SOURCE '"`cat /var/run/hive/hive.pid`"'
        echo "    "$BASH_SOURCE '"`cat /var/run/hive/hive-server.pid`"'
        exit
    fi

    if [ "$USER" != "root" ]; then
        echo "Please run as 'root' user"
        exit 1
    fi
    syschk "$1" "$2" "$3"
fi
