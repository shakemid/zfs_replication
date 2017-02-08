zfs_replication
=================
ZFS remote replication over SSH

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
ToDo

# Author
K.Cima k-cima[at]kendama.asia

# Lisence
GPLv2
