#!/usr/bin/bash

# zfs replication over ssh

# 2013-10-09 created by K.Cima

export LANG=C
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

# settings

datecmd=date
sshcmd='ssh -c arcfour'

execdir=$( dirname $0 )
logdir=$execdir/log
logfile_link=zfs_replication.log
logfile=$logfile_link.$( $datecmd +%Y%m%d )
keep_logfile=365

suffix_base=snapshot_for_replication

# end of settings

# usage
function usage() {
    echo "Usage: $0 -t hostname -s source -d destination"
    echo
    echo '  Required:'
    echo '    -t source hostname'
    echo '    -s source dataset'
    echo '    -d destination dataset'
    echo
    echo '  Optional:'
    echo '    -l logging to logfile.'
    echo '    -F force replicate. use "zfs recv -F" option.'
    echo '    -N do not create source snaphost. use existing last snapshot.'
    echo '    -D do not delete snaphost after replication.'
    echo '    -k keep snapshot in source host. (default:1)'
    echo '    -K keep snapshot in destination host. (default:7)'
    echo '    -h show this help.'
    echo

    exit 1
}

# get snapshot name
function get_snapshot_name() {
    dst_suffix_prev=$( zfs list -t snapshot -r -d 1 -H -S creation $dst_dataset | cut -f1 | sed 's/^.*@//' | egrep "^${suffix_base}" | head -1 )
    src_suffix_prev=$( $sshcmd $target_host zfs list -t snapshot -r -d 1 -H -S creation $src_dataset | cut -f1 | sed 's/^.*@//' | egrep "^${dst_suffix_prev}" | head -1 )

    if [ "$flag_create_snapshot" -eq 1 ]
    then
        src_suffix_curr=${suffix_base}-$( $datecmd +%Y%m%d%H%M%S )
    else
        src_suffix_curr=$( $sshcmd $target_host zfs list -t snapshot -r -d 1 -H -S creation $src_dataset | cut -f1 | sed 's/^.*@//' | egrep "^${suffix_base}" | head -1 )
    fi

    snapshot_prev=$src_dataset@${src_suffix_prev}
    snapshot_curr=$src_dataset@${src_suffix_curr}
}

# create snapshot
function create_snapshot() {
    rettmp=0

    echo creating snapshot
    $sshcmd $target_host zfs snapshot -r $snapshot_curr || rettmp=$?
    echo return: $rettmp

    return $rettmp
}

# send snapshot
function send_snapshot() {
    rettmp=0

    # check if both src and dst have same snapshot
    if [ -n "$dst_suffix_prev" -a "$src_suffix_prev" = "$dst_suffix_prev" ]
    then
        echo sending incremental snapshot
        ( $sshcmd $target_host zfs send -Rv -i $snapshot_prev $snapshot_curr | zfs recv $zfs_recv_args $dst_dataset ) || rettmp=$?
        echo return: $rettmp
    else
        echo sending whole data
        ( $sshcmd $target_host zfs send -Rv $snapshot_curr | zfs recv $zfs_recv_args $dst_dataset ) || rettmp=$?
        echo return: $rettmp
    fi

    return $rettmp
}

# delete previous snapshot
function delete_previous_snaphost() {
    rettmp1=0
    rettmp2=0

    echo deleting src snapshot
    ( $sshcmd $target_host "zfs list -t snapshot -r -d 1 -H -S creation $src_dataset | cut -f1 | egrep "@${suffix_base}" | tail +$(( $keep_src_snapshot + 1 )) | xargs -n 1 zfs destroy -r" ) || rettmp1=$?
    echo return: $rettmp1

    echo deleting dst snapshot
    ( zfs list -t snapshot -r -d 1 -H -S creation $dst_dataset | cut -f1 | egrep "@${suffix_base}" | tail +$(( $keep_dst_snapshot + 1 )) | xargs -n 1 zfs destroy -r ) || rettmp2=$?
    echo return: $rettmp2

    return $(( $rettmp1 + $rettmp2 ))
}

# purge old log
function purge_old_log() {
    rettmp=0

    echo purging old log
    find $logdir -type f -mtime +$keep_logfile -print -exec rm {} \; || rettmp=$?
    echo return: $rettmp

    return $rettmp
}

# parse options
zfs_recv_args="-uv -o readonly=on -o mountpoint=none"
flag_logging=0
flag_create_snapshot=1
flag_delete_snapshot=1
keep_src_snapshot=1
keep_dst_snapshot=7

while getopts t:s:d:k:K:lFNDh opt
do
    case $opt in
    t)
        target_host=$OPTARG
        ;;
    s)
        src_dataset=$OPTARG
        ;;
    d)
        dst_dataset=$OPTARG
        ;;
    k)
        keep_src_snapshot=$OPTARG
        ;;
    K)
        keep_dst_snapshot=$OPTARG
        ;;
    l)
        flag_logging=1
        ;;
    F)
        zfs_recv_args="$zfs_recv_args -F"
        ;;
    N)
        flag_create_snapshot=0
        ;;
    D)
        flag_delete_snapshot=0
        ;;
    h|*)
        usage
        ;;
    esac
done

# show usage
if [ -z "$target_host" -o -z "$src_dataset" -o -z "$dst_dataset" ]
then
    usage
fi

# open logfile
if [ "$flag_logging" -eq 1 ]
then
    mkdir -p $logdir
    exec >>$logdir/$logfile 2>&1
    ( cd $logdir ; ln -sf $logfile $logfile_link )
fi

# main
echo $( $datecmd '+%Y-%m-%d %H:%M:%S' ) executed. "$target_host:$src_dataset -> $dst_dataset"

retval=0
(
    get_snapshot_name &&
    if [ "$flag_create_snapshot" -eq 1 ]; then create_snapshot; fi &&
    send_snapshot &&
    if [ "$flag_delete_snapshot" -eq 1 ]; then delete_previous_snaphost; fi &&
    if [ "$flag_logging" -eq 1 ]; then purge_old_log; fi
) || retval=$?

if [ $retval -eq 0 ]
then
    echo $( $datecmd '+%Y-%m-%d %H:%M:%S' ) finished successfully. "$target_host:$src_dataset -> $dst_dataset"
else
    echo $( $datecmd '+%Y-%m-%d %H:%M:%S' ) ERROR OCCURRED! "$target_host:$src_dataset -> $dst_dataset"
fi

echo exit: $retval
exit $retval
