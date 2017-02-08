#!/bin/bash

# ZFS remote replication over SSH

# 2013-10-09 created by K.Cima

# settings

set -o nounset

export LANG=C
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

datecmd=date
sshcmd=ssh

execdir=$( dirname "$0" )
logdir=${execdir}/log
logfile_link=zfs_replication.log
logfile=${logfile_link}.$( $datecmd +%Y%m%d )
keep_logfile=365

suffix_base=snapshot_for_replication
zfs_recv_args="-uv -o readonly=on -o mountpoint=none"
flag_logging=0
flag_create_snapshot=1
flag_delete_snapshot=1
keep_src_snapshot=1
keep_dst_snapshot=7

# end of settings

# usage
usage() {
    cat <<EOF
Usage: $0 -t hostname -s source -d destination

  Required:
    -t source (remote) hostname
    -s source (remote) dataset
    -d destination (local) dataset

  Optional:
    -l logging to logfile.
    -F force replicate. use "zfs recv -F" option.
    -N do not create source snaphost. use existing last snapshot.
    -D do not delete snaphost after replication.
    -k keep snapshot in source host. (default:1)
    -K keep snapshot in destination host. (default:7)
    -h show this help.

EOF

    exit 1
}

# get snapshot name
get_snapshot_name() {
    dst_suffix_prev=$( 
        zfs list -t snapshot -r -d 1 -H -o name -S creation "$dst_dataset" | 
        sed 's/^.*@//' | egrep "^${suffix_base}" | head -1 
    )
    src_suffix_prev=$( 
        $sshcmd "$target_host" zfs list -t snapshot -r -d 1 -H -o name -S creation "$src_dataset" |
        sed 's/^.*@//' | egrep "^${dst_suffix_prev}" | head -1 
    )

    if [ "$flag_create_snapshot" -eq 1 ]; then
        src_suffix_curr=${suffix_base}-$( $datecmd +%Y%m%d%H%M%S )
    else
        src_suffix_curr=$( 
            $sshcmd "$target_host" zfs list -t snapshot -r -d 1 -H -o name -S creation "$src_dataset" | 
            sed 's/^.*@//' | egrep "^${suffix_base}" | head -1 
        )
    fi

    snapshot_prev=${src_dataset}@${src_suffix_prev}
    snapshot_curr=${src_dataset}@${src_suffix_curr}
}

# create snapshot
create_snapshot() {
    local rettmp
    rettmp=0

    echo creating snapshot
    $sshcmd "$target_host" zfs snapshot -r "$snapshot_curr" || rettmp=$?
    echo return: $rettmp

    return $rettmp
}

# send snapshot
send_snapshot() {
    local rettmp
    rettmp=0

    # check if both src and dst have same snapshot
    if [ -n "$dst_suffix_prev" ] && [ "$src_suffix_prev" = "$dst_suffix_prev" ]; then
        echo sending incremental snapshot
        ( 
            $sshcmd "$target_host" zfs send -Rv -i "$snapshot_prev" "$snapshot_curr" | 
            zfs recv $zfs_recv_args "$dst_dataset"
        ) || rettmp=$?
        echo return: $rettmp
    else
        echo sending whole data
        (
            $sshcmd "$target_host" zfs send -Rv "$snapshot_curr" | 
            zfs recv $zfs_recv_args "$dst_dataset"
        ) || rettmp=$?
        echo return: $rettmp
    fi

    return $rettmp
}

# delete previous snapshot
delete_previous_snaphost() {
    local rettmp1 rettmp2
    rettmp1=0
    rettmp2=0

    echo deleting src snapshot
    (  
        $sshcmd "$target_host" "zfs list -t snapshot -r -d 1 -H -o name -S creation $src_dataset | 
            egrep "@${suffix_base}" | 
            tail +$(( keep_src_snapshot + 1 )) | 
            xargs -n 1 zfs destroy -r" 
    ) || rettmp1=$?
    echo return: $rettmp1

    echo deleting dst snapshot
    (
        zfs list -t snapshot -r -d 1 -H -o name -S creation "$dst_dataset" | 
        egrep "@${suffix_base}" | 
        tail +$(( keep_dst_snapshot + 1 )) | 
        xargs -n 1 zfs destroy -r 
    ) || rettmp2=$?
    echo return: $rettmp2

    return $(( rettmp1 + rettmp2 ))
}

# purge old log
purge_old_log() {
    local rettmp
    rettmp=0

    echo purging old log
    find "$logdir" -type f -mtime +$keep_logfile -print -exec rm {} \; || rettmp=$?
    echo return: $rettmp

    return $rettmp
}

# parse options
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
if [ -z "${target_host:-}" ] || [ -z "${src_dataset:-}" ] || [ -z "${dst_dataset:-}" ]; then
    usage
fi

# open logfile
if [ "$flag_logging" -eq 1 ]; then
    mkdir -p "$logdir"
    exec > >( 
        while IFS= read -r l
        do 
            echo "$( $datecmd "+[%Y-%m-%d %H:%M:%S]" )[$$] $l"
        done >> "$logdir/$logfile" 
    ) 2>&1
    ( cd "$logdir" || ln -sf "$logfile" "$logfile_link" )
fi

# main
echo executed. "$target_host:$src_dataset -> $dst_dataset"

retval=0
(
    get_snapshot_name &&
    if [ "$flag_create_snapshot" -eq 1 ]; then create_snapshot; fi &&
    send_snapshot &&
    if [ "$flag_delete_snapshot" -eq 1 ]; then delete_previous_snaphost; fi &&
    if [ "$flag_logging" -eq 1 ]; then purge_old_log; fi
) || retval=$?

if [ $retval -eq 0 ]; then
    echo finished successfully. "$target_host:$src_dataset -> $dst_dataset"
else
    echo ERROR OCCURRED! "$target_host:$src_dataset -> $dst_dataset"
fi

echo exit: $retval
exit $retval