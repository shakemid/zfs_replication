zfs_replication
=================
ZFS remote replication over SSH (Tested with Solaris 11.3)

# Usage
```
Usage: zfs_replication.sh -t hostname -s source -d destination

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
```

# Examples

## Initial replication
Whole data will be sent when initial run.

```
Command:

dsthost# ./zfs_replication.sh -t srchost -s epool/reptest/src -d epool/reptest/dst
```

```
Before:

srchost# zfs list -r epool/reptest
NAME                              USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                     ...K   ...T   ...K  /epool/reptest
epool/reptest/src                 ...K   ...T   ...K  /epool/reptest/src

dsthost# zfs list -r epool/reptest
NAME                              USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                     ...K   ...T   ...K  /epool/reptest
```

```
After:

srchost# zfs list -r epool/reptest
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                                              ...K   ...T   ...K  /epool/reptest
epool/reptest/src                                          ...K   ...T   ...K  /epool/reptest/src
epool/reptest/src@snapshot_for_replication-20170208000000     0      -   ...K  -

dsthost# zfs list -r epool/reptest
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                                              ...K   ...T   ...K  /epool/reptest
epool/reptest/dst                                          ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170208000000  ...K      -   ...K  -
```

## Incremental replication
If both sourse and destination have same snapshot, only incremental data will be sent.

```
Command: (same as initial replication)

dsthost# ./zfs_replication.sh -t srchost -s epool/reptest/src -d epool/reptest/dst
```

```
Before:

srchost# zfs list -r epool/reptest/src
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/src                                          ...K   ...T   ...K  /epool/reptest/src
epool/reptest/src@snapshot_for_replication-20170208000000  ...K      -   ...K  -

dsthost# zfs list -r epool/reptest/dst
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/dst                                          ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170208000000  ...K      -   ...K  -
```

```
After:

srchost# zfs list -r epool/reptest/src
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/src                                          ...K   ...T   ...K  /epool/reptest/src
epool/reptest/src@snapshot_for_replication-20170209000000  ...K      -   ...K  -

dsthost# zfs list -r epool/reptest/dst
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/dst                                          ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170208000000  ...K      -   ...K  -
epool/reptest/dst@snapshot_for_replication-20170209000000  ...K      -   ...K  -
```

## Complecated dataset
Hierachical or cloned datasets can be replicated.

```
Command: (same as simple replication)

dsthost# ./zfs_replication.sh -t srchost -s epool/reptest/src -d epool/reptest/dst
```

```
Before:

srchost# zfs list -r -t all epool/reptest/src
NAME                                         USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/src                            ...K   ...T   ...K  /epool/reptest/src
epool/reptest/src/child1                     ...K   ...T   ...K  /epool/reptest/src/child1
epool/reptest/src/child1@snapshot_for_clone  ...K      -   ...K  -
epool/reptest/src/child1/child2              ...K   ...T   ...K  /epool/reptest/src/child1/child2
epool/reptest/src/child1_clone               ...K   ...T   ...K  /epool/reptest/src/child1_clone

dsthost# zfs list -r epool/reptest
NAME                              USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                     ...K   ...T   ...K  /epool/reptest
```

```
After:

srchost# zfs list -r -t all epool/reptest/src
NAME                                                                     USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/src                                                        ...K   ...T   ...K  /epool/reptest/src
epool/reptest/src@snapshot_for_replication-20170209000000                ...K      -   ...K  -
epool/reptest/src/child1                                                 ...K   ...T   ...K  /epool/reptest/src/child1
epool/reptest/src/child1@snapshot_for_replication-20170209000000         ...K      -   ...K  -
epool/reptest/src/child1@snapshot_for_clone                              ...K      -   ...K  -
epool/reptest/src/child1/child2                                          ...K   ...T   ...K  /epool/reptest/src/child1/child2
epool/reptest/src/child1/child2@snapshot_for_replication-20170209000000  ...K      -   ...K  -
epool/reptest/src/child1_clone                                           ...K   ...T   ...K  /epool/reptest/src/child1_clone
epool/reptest/src/child1_clone@snapshot_for_replication-20170209000000   ...K      -   ...K  -

dsthost# zfs list -r -t all epool/reptest/dst
NAME                                                                      USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/dst                                                         ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170209000000                 ...K      -   ...K  -
epool/reptest/dst/child1                                                  ...K   ...T   ...K  none
epool/reptest/dst/child1@snapshot_for_clone                               ...K      -   ...K  -
epool/reptest/dst/child1@snapshot_for_replication-20170209000000          ...K      -   ...K  -
epool/reptest/dst/child1/child2                                           ...K   ...T   ...K  none
epool/reptest/dst/child1/child2@snapshot_for_replication-20170209000000   ...K      -   ...K  -
epool/reptest/dst/child1_clone                                            ...K   ...T   ...K  none
epool/reptest/dst/child1_clone@snapshot_for_replication-20170209000000    ...K      -   ...K  -

```

## Multiple replication
If you would like to replicate already replicated data, -FND options are useful.

```
Command: 

dsthost2# ./zfs_replication.sh -t dsthost -s epool/reptest/dst -d epool/reptest/dst -FND
```

```
Before:

dsthost# zfs list -r epool/reptest/dst
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/dst                                          ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170208000000  ...K      -   ...K  -
epool/reptest/dst@snapshot_for_replication-20170209000000  ...K      -   ...K  -

dsthost2# zfs list -r epool/reptest
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                                              ...K   ...T   ...K  none
```

```
After:

dsthost# zfs list -r epool/reptest/dst
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest/dst                                          ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170208000000  ...K      -   ...K  -
epool/reptest/dst@snapshot_for_replication-20170209000000  ...K      -   ...K  -

dsthost2# zfs list -r epool/reptest
NAME                                                       USED  AVAIL  REFER  MOUNTPOINT
epool/reptest                                              ...K   ...T   ...K  none
epool/reptest/dst                                          ...K   ...T   ...K  none
epool/reptest/dst@snapshot_for_replication-20170208000000  ...K      -   ...K  -
epool/reptest/dst@snapshot_for_replication-20170209000000  ...K      -   ...K  -
```

# Author
K.Cima k-cima[at]kendama.asia

# Lisence
GPLv2
