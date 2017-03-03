#!/bin/bash

# ZFS remote replication over SSH

# Created by K.Cima https://github.com/shakemid/zfs_replication

# settings

set -o nounset 
set -o pipefail

export LANG=C

sshcmd=ssh

execdir=$( dirname "$0" )
logdir=$execdir/log
logfile_link=zfs_replication.log
logfile=$logfile_link.$( date +%Y%m%d )
keep_logfile=365

suffix_base=snapshot_for_replication
zfs_recv_args="-uv -o readonly=on -o mountpoint=none"
flag_logging=0
flag_create_snapshot=1
flag_delete_snapshot=1
keep_src_snapshot=1
keep_dst_snapshot=7

zfs_list_snapshot='zfs list -t snapshot -r -d 1 -H -o name -S creation'

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
        $zfs_list_snapshot "$dst_dataset" | 
        sed 's/^.*@//' | egrep "^$suffix_base" | head -1 
    )
    src_suffix_prev=$( 
        $sshcmd "$target_host" $zfs_list_snapshot "$src_dataset" |
        sed 's/^.*@//' | egrep "^$dst_suffix_prev" | head -1 
    )

    if [ "$flag_create_snapshot" -eq 1 ]; then
        src_suffix_curr=$suffix_base-$( date +%Y%m%d%H%M%S )
    else
        src_suffix_curr=$( 
            $sshcmd "$target_host" $zfs_list_snapshot "$src_dataset" | 
            sed 's/^.*@//' | egrep "^$suffix_base" | head -1 
        )
    fi

    snapshot_prev=$src_dataset@$src_suffix_prev
    snapshot_curr=$src_dataset@$src_suffix_curr
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
        $sshcmd "$target_host" "$zfs_list_snapshot $src_dataset | 
            egrep "@$suffix_base" | 
            sed '1,${keep_src_snapshot}d' | 
            xargs -n 1 -i sh -c \"echo deleting {}; test -n '{}' && zfs destroy -r '{}'\"" 
    ) || rettmp1=$?
    echo return: $rettmp1

    echo deleting dst snapshot
    (
        $zfs_list_snapshot "$dst_dataset" | 
        egrep "@$suffix_base" | 
        sed "1,${keep_dst_snapshot}d" | 
        xargs -n 1 -i sh -c "echo deleting {}; test -n '{}' && zfs destroy -r '{}'"
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

# save command line
command_line="$0 $@"

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

shift $(( OPTIND - 1 ))

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
            echo "$( date "+[%FT%T%z]" )[$$] $l"
        done >> "$logdir/$logfile" 
    ) 2>&1
    ( cd "$logdir" && ln -sf "$logfile" "$logfile_link" )
fi

# main
echo executed. "$target_host:$src_dataset -> $dst_dataset"
echo command line: "$command_line"

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
