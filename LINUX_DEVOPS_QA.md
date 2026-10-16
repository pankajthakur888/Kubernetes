# Linux for DevOps Engineers & SREs: Day-to-Day Production Q&A Guide

A comprehensive, scenario-driven interview and day-to-day operational guide covering **80 practical Linux questions and answers** that every DevOps Engineer, Site Reliability Engineer (SRE), and Platform Engineer must master for production operations.

---

## Table of Contents
1. [Domain 1: Troubleshooting High CPU, Memory & Load Average (Q1 - Q10)](#domain-1-troubleshooting-high-cpu-memory--load-average)
2. [Domain 2: Storage, Disk Full Emergencies & Inodes (Q11 - Q20)](#domain-2-storage-disk-full-emergencies--inodes)
3. [Domain 3: Networking, Firewalls & Socket Diagnostics (Q21 - Q30)](#domain-3-networking-firewalls--socket-diagnostics)
4. [Domain 4: Systemd, Services & Log Management with Journald (Q31 - Q40)](#domain-4-systemd-services--log-management-with-journald)
5. [Domain 5: Security, Permissions, SSH & Access Control (Q41 - Q50)](#domain-5-security-permissions-ssh--access-control)
6. [Domain 6: Text Processing, Shell Scripting & CLI Power Tools (Q51 - Q60)](#domain-6-text-processing-shell-scripting--cli-power-tools)
7. [Domain 7: Kernel Tuning, Sysctl & Container Host Optimization (Q61 - Q70)](#domain-7-kernel-tuning-sysctl--container-host-optimization)
8. [Domain 8: Real-World DevOps Incident Scenarios & Production Runbooks (Q71 - Q80)](#domain-8-real-world-devops-incident-scenarios--production-runbooks)

---

## Domain 1: Troubleshooting High CPU, Memory & Load Average

### Q1: What is the exact difference between CPU Utilization and System Load Average in Linux?
**Answer:**
- **CPU Utilization (%)**: Represents the percentage of time the CPU was non-idle executing user processes (`%us`), kernel system calls (`%sy`), servicing interrupts (`%hi`, `%si`), or waiting for I/O (`%wa`) during a specific sampling interval.
- **System Load Average**: Represents the average number of processes that are either in a **Runnable state (R)** (actively using or waiting for CPU) OR in an **Uninterruptible Sleep state (D)** (usually blocked waiting on disk I/O, NFS, or hardware resources) over 1, 5, and 15 minutes.
- **Production Gotcha**: A 16-core server can have CPU utilization of 10% but a load average of 80 if multiple threads are stuck in **D-state** waiting for a slow or dead NFS mount/SAN storage. Load average measures demand, not just active compute.

---

### Q2: How do you identify which process and which specific thread is consuming 100% CPU on a server?
**Answer:**
1. **Find the Process**:
   ```bash
   top -c -b -n 1 | head -n 20
   # or with pidstat:
   pidstat -u 1 5
   ```
2. **Find the Offending Thread inside the Process**:
   ```bash
   # Display all threads for PID 12345:
   top -H -p 12345
   # Note the Thread ID (TID) consuming the highest CPU (e.g., TID 12399).
   ```
3. **Inspect the Call Stack**:
   ```bash
   # In decimal to hex: printf "%x
" 12399 -> 306f
   # For Java applications:
   jstack 12345 | grep -A 30 "nid=0x306f"
   # For native Linux/Go/C++ applications:
   pstack 12345
   # Or using gdb:
   gdb --batch -ex "thread apply all bt" -p 12345
   ```

---

### Q3: Explain the output of `free -m`. What is the difference between `free` and `available` memory?
**Answer:**
```text
               total        used        free      shared  buff/cache   available
Mem:           31980       12450        1210         450       18320       18620
Swap:           8192         120        8072
```
- **`free`**: Raw, completely unused memory. In modern Linux, having high `free` memory is actually inefficient; Linux aggressively uses spare RAM for disk caching (`buff/cache`).
- **`buff/cache`**:
  - *Buffers*: In-memory block device metadata and raw disk blocks awaiting writeout.
  - *Cache*: Page cache holding cached files read from disk to accelerate subsequent reads.
- **`available`**: **The true operational metric.** The estimated amount of memory that can be immediately allocated to new or existing processes without triggering swapping, by reclaiming page cache and slab memory.
- **Rule of Thumb**: As long as `available` memory is comfortably above 15-20%, the system is healthy even if `free` is low.

---

### Q4: How does the Linux Out-Of-Memory (OOM) Killer work, and how do you protect critical daemons (like `sshd`, `kubelet`, or `containerd`) from being killed?
**Answer:**
- **Mechanism**: When the kernel fails to allocate a page of physical memory and swap is exhausted (or disabled), the kernel triggers `out_of_memory()`. It calculates a score for each process:
  $$	ext{OOM Score} = rac{	ext{RSS Memory Used}}{	ext{Total Available RAM}} 	imes 1000 + 	ext{oom\_score\_adj}$$
  The process with the highest score is terminated with `SIGKILL` (exit code 137).
- **Inspecting OOM Scores**:
  ```bash
  cat /proc/<PID>/oom_score
  cat /proc/<PID>/oom_score_adj   # Range: -1000 to +1000
  ```
- **Protecting Critical Daemons**:
  Set `oom_score_adj` to `-1000` (meaning never kill):
  ```bash
  echo -1000 > /proc/$(pgrep -o kubelet)/oom_score_adj
  ```
- **In Systemd Unit**:
  ```ini
  [Service]
  OOMScoreAdjust=-1000
  ```

---

### Q5: What is a Zombie process vs. an Orphan process? Why does `kill -9 <PID>` fail on a Zombie process?
**Answer:**
- **Orphan Process**: A child process whose parent died before it exited.
  - *Handling*: The Linux kernel immediately re-parents the orphan to `init` or `systemd` (PID 1), which periodically reaps its exit status. Orphans run normally.
- **Zombie Process (State Z)**: A process that has completed execution via `exit()`, but its parent has not yet read its exit status code using `wait()` or `waitpid()`.
  - *Why `kill -9` fails*: The zombie is **already dead**! There is no code or memory allocated to execute a signal. It is merely a remaining row in the kernel process table (`task_struct`).
- **How to Clean a Zombie**:
  1. Identify the parent PID (PPID):
     ```bash
     ps -o pid,ppid,state,comm -p <ZOMBIE_PID>
     ```
  2. Send `SIGCHLD` to the parent to notify it to reap the child:
     ```bash
     kill -s SIGCHLD <PPID>
     ```
  3. If the parent is hanging/broken, terminate the parent process:
     ```bash
     kill -15 <PPID> # or kill -9 <PPID>
     ```
     Once the parent dies, `init` (PID 1) inherits the zombie and instantly reaps it.

---

### Q6: What is a process in Uninterruptible Sleep (D state) and how do you diagnose it?
**Answer:**
- **D State (`TASK_UNINTERRUPTIBLE`)**: The process is waiting for a hardware event, typically synchronous disk I/O, NFS storage response, or a locked kernel mutex.
- **Characteristics**: The kernel guarantees that signals (including `kill -9`) are ignored while in D-state to prevent filesystem or kernel data structure corruption.
- **Diagnosis**:
  1. Find processes in D-state:
     ```bash
     ps aux | awk '$8 ~ /D/ {print $0}'
     ```
  2. Inspect the exact kernel function where the process is blocked:
     ```bash
     cat /proc/<PID>/stack
     cat /proc/<PID>/wchan
     ```
  3. Example output showing an NFS hang:
     `[<0>] nfs_wait_bit_uninterruptible+0x24/0x30 [nfs]`
  4. Fix: If an NFS server is dead, unmount forcefully using `umount -f -l <mountpoint>` (lazy unmount) or recover the underlying storage.

---

### Q7: How do you identify memory leaks on a production Linux node without restarting the application?
**Answer:**
1. **Track Resident Memory Growth over Time**:
   ```bash
   pidstat -r -p <PID> 2 10
   ```
2. **Inspect Process Memory Maps (`smaps`)**:
   ```bash
   # Check Private Dirty memory (memory uniquely held by the process and not backed by a file):
   cat /proc/<PID>/smaps | grep -i Private_Dirty | awk '{sum+=$2} END {print sum " kB"}'
   ```
3. **Inspect Virtual Memory Allocation Blocks (`pmap`)**:
   ```bash
   pmap -x <PID> | sort -k3 -n -r | head -n 20
   ```
4. **Capture Core / Heap Dump**:
   - For Go: `curl http://localhost:6060/debug/pprof/heap > heap.pprof`
   - For Java: `jcmd <PID> GC.heap_dump /tmp/heap.hprof`
   - For C/C++: `gcore <PID>` and analyze with GDB.

---

### Q8: What does `%iowait` in `top` indicate, and what commands pinpoint the culprit disk/process?
**Answer:**
- **Meaning**: `%iowait` (`%wa`) is the percentage of time that the CPU was idle *while at least one I/O request was outstanding to disk or network storage*. It indicates CPU starvation caused by slow storage.
- **Triage Workflow**:
  1. Check disk utilization and latency across all drives:
     ```bash
     iostat -xz 1 5
     ```
     - Key metrics:
       - `%util`: If > 90%, the disk is saturated.
       - `await` / `r_await` / `w_await`: Average time (ms) for I/O requests. Fast SSDs should be < 2-5ms. If `await` is 100ms+, disk is throttling.
  2. Find the specific process driving high read/write throughput:
     ```bash
     iotop -o -P -a
     ```
  3. Inspect per-process I/O statistics:
     ```bash
     cat /proc/<PID>/io
     # rchar, wchar, read_bytes, write_bytes
     ```

---

### Q9: How do you interpret `vmstat 1` output for rapid system health triage?
**Answer:**
```text
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 3  0      0 125020  45200 890400    0    0    12   150 1200 4500 25  5 68  2  0
```
- **`r` (Run queue)**: Processes waiting for CPU time. If `r > number of CPU cores`, CPU is oversubscribed.
- **`b` (Blocked queue)**: Processes in uninterruptible sleep (I/O). If `b > 0`, investigate storage.
- **`si` / `so` (Swap In / Swap Out)**: Pages swapped in/out per second. **If non-zero constantly, the system is thrashing memory.**
- **`bi` / `bo` (Blocks In / Blocks Out)**: Disk read/write throughput (512-byte blocks/sec).
- **`in` / `cs` (Interrupts / Context Switches)**: High context switches (> 50,000/sec) indicates thread contention or lock thrashing.
- **`st` (Steal Time)**: On virtual machines/cloud instances, percentage of CPU stolen by the hypervisor for other noisy neighbor tenants. If `st > 5-10%`, request a different cloud host.

---

### Q10: How do you troubleshoot high CPU caused by software interrupts (`%si`)?
**Answer:**
- **Software Interrupts (`%si`)**: CPU time spent servicing kernel software interrupts, almost always caused by **high network packet processing**.
- **Triage**:
  1. Inspect network interrupts per CPU core:
     ```bash
     cat /proc/interrupts | grep -E "eth|ens|NIC|NET"
     ```
  2. Inspect softirq counters:
     ```bash
     cat /proc/softirqs | grep NET_RX
     ```
  3. If all network packets are processed by a single CPU core (e.g., CPU0 at 100% `%si` while CPU1-15 are idle):
     - Enable **Receive Side Scaling (RSS)** or **Receive Packet Steering (RPS)** to distribute network packet queues across all CPU cores:
       ```bash
       echo "ff" > /sys/class/net/eth0/queues/rx-0/rps_cpus
       ```
     - Start and verify the `irqbalance` daemon: `systemctl status irqbalance`.

---

## Domain 2: Storage, Disk Full Emergencies & Inodes

### Q11: Scenario: `df -h` shows the root filesystem is 100% full, but `du -sh /*` only accounts for 25GB of a 100GB disk. Where is the missing space and how do you fix it?
**Answer:**
- **Cause**: Files were deleted with `rm` while a running process (e.g., NGINX, Java, or an active logging script) still holds an **open file descriptor** to them. The file metadata is unlinked from the directory tree (so `du` cannot see it), but the disk blocks cannot be freed by the kernel until the file descriptor closes.
- **Diagnosis**:
  ```bash
  lsof +L1
  # or specifically:
  lsof | grep -i deleted | sort -k7 -n -r | head -n 10
  ```
- **Remediation**:
  1. *Immediate fix without stopping the process*: Truncate the file descriptor directly through `/proc`:
     ```bash
     # Find PID (e.g., 4521) and File Descriptor (e.g., fd 4):
     > /proc/4521/fd/4
     ```
     This zeroes the file blocks on disk immediately and frees space without service disruption.
  2. *Permanent fix*: Restart or reload the service (`systemctl reload nginx`), and ensure log rotation uses `copytruncate` or sends `USR1` signal to reopen file descriptors.

---

### Q12: Scenario: `df -h` shows 40% disk space free, but applications crash with "No space left on device". What is the cause?
**Answer:**
- **Cause**: **Inode Exhaustion (`df -i`)**. Every file and directory on an ext4/xfs filesystem consumes an inode (metadata record). If a filesystem creates millions of tiny files (e.g., PHP session files, unrotated email queues in `/var/spool/postfix`, or temporary cache files), all inodes can be consumed while gigabytes of raw disk space remain free.
- **Diagnosis**:
  ```bash
  df -i
  # Find which directory holds the millions of files:
  find / -xdev -printf '%h
' | sort | uniq -c | sort -k1 -n -r | head -n 15
  ```
- **Remediation**:
  Delete the millions of files safely without causing `Argument list too long` shell errors:
  ```bash
  find /var/spool/postfix/maildrop -type f -delete
  # or with xargs:
  find /tmp/cache -type f -mtime +7 -print0 | xargs -0 -P 4 rm -f
  ```

---

### Q13: What is the safest way to clear a huge 50GB active log file on a production server without crashing the writing service?
**Answer:**
- **Wrong Approach**: `rm /var/log/huge.log`.
  - The process will continue writing to the unlinked file descriptor, disk space will NOT be freed, and new logs won't be visible.
- **Correct Approaches**:
  1. **Shell Redirection Truncation (Instant & Safe)**:
     ```bash
     : > /var/log/huge.log
     # or
     > /var/log/huge.log
     ```
  2. **Using `truncate`**:
     ```bash
     truncate -s 0 /var/log/huge.log
     ```
  3. **Using `cp /dev/null`**:
     ```bash
     cp /dev/null /var/log/huge.log
     ```
  All three commands preserve the inode number and file permissions, immediately zero the disk blocks, and allow the running service to continue writing without crashing.

---

### Q14: How do you dynamically extend an LVM Logical Volume and resize an ext4 or XFS filesystem online without downtime?
**Answer:**
1. **Extend the Volume Group (if new physical disk added)**:
   ```bash
   pvcreate /dev/sdb
   vgextend vg_data /dev/sdb
   ```
2. **Extend the Logical Volume by +50GB**:
   ```bash
   lvextend -L +50G /dev/vg_data/lv_app
   ```
3. **Resize the Filesystem Online (No Unmounting Required)**:
   - For **XFS** (Default on RHEL/CentOS/Rocky):
     ```bash
     xfs_growfs /mount/point
     # Note: xfs_growfs takes the mount point, NOT the device path!
     ```
   - For **ext4** (Default on Ubuntu/Debian):
     ```bash
     resize2fs /dev/vg_data/lv_app
     ```
4. **Pro-Tip**: You can combine both steps into one single command:
   ```bash
   lvextend -r -L +50G /dev/vg_data/lv_app
   # '-r' flag automatically resizes the underlying ext4 or xfs filesystem.
   ```

---

### Q15: Why does a filesystem suddenly remount as Read-Only (`ro`), and how do you recover it?
**Answer:**
- **Cause**: The Linux kernel encountered an unrecoverable disk I/O error, filesystem metadata corruption, or underlying SAN/EBS detachment. In `/etc/fstab`, the default option `errors=remount-ro` instructs the kernel to immediately protect data integrity by switching to read-only mode.
- **Diagnosis**:
  ```bash
  dmesg -T | grep -E "EXT4|XFS|I/O error|Buffer I/O"
  mount | grep " / "
  ```
- **Recovery Workflow**:
  1. Evacuate or stop non-essential applications to prevent further corruption.
  2. Schedule maintenance window or reboot into single-user / rescue mode.
  3. Run filesystem check:
     ```bash
     # Unmount first (NEVER run fsck on a mounted read-write filesystem):
     umount /dev/mapper/vg_data-lv_app
     fsck -y /dev/mapper/vg_data-lv_app
     ```
  4. If it is the root partition, force an fsck on the next reboot:
     ```bash
     touch /forcefsck && reboot
     # or on modern systemd:
     systemctl reboot --boot-loader-entry=... fsck.mode=force
     ```

---

### Q16: How do you find the top 10 largest files and top 10 largest directories on a server in under 10 seconds?
**Answer:**
1. **Top 10 Largest Files**:
   ```bash
   find / -xdev -type f -exec du -Sh {} + | sort -rh | head -n 10
   ```
2. **Top 10 Largest Directories**:
   ```bash
   du -hx --max-depth=2 / | sort -rh | head -n 10
   ```
   *(The `-x` or `--one-file-system` flag is critical: it prevents `du` from scanning virtual filesystems like `/proc`, `/sys`, `/dev`, or mounted network shares).*
3. **Interactive Tool**:
   ```bash
   ncdu -x /
   ```

---

### Q17: What are the optimal mount options for high-throughput databases and Kubernetes worker nodes?
**Answer:**
In `/etc/fstab`:
```text
UUID=... /var/lib/containerd ext4 defaults,noatime,nodiratime,barrier=0,commit=60 0 2
```
- **`noatime` / `nodiratime`**: Disables writing access timestamps every time a file or directory is read. By default, every HTTP read or database query triggers a metadata write. `noatime` eliminates up to 30% of unnecessary disk write I/O.
- **`barrier=0`** (or `nobarrier`): Disables write barriers for storage with battery-backed write caches (BBWC) or enterprise SANs, boosting throughput.
- **`commit=60`**: Flushes dirty page cache to disk every 60 seconds instead of the default 5 seconds, grouping writes and reducing random I/O.
- **`discard` vs Periodic TRIM**: Do not use continuous `discard` on SSDs; use a weekly systemd timer `fstrim.timer` instead to prevent synchronous write stalls.

---

### Q18: How do you fix a Stale NFS File Handle (`ESTALE`) error without rebooting the server?
**Answer:**
- **Cause**: A client has an open inode reference to an NFS file or directory that was deleted, renamed, or unmounted on the NFS server.
- **Triage & Fix**:
  1. Identify the processes holding open references to the NFS mount:
     ```bash
     lsof /mnt/nfs_share
     fuser -m -v /mnt/nfs_share
     ```
  2. Terminate the blocking processes:
     ```bash
     fuser -k -m /mnt/nfs_share
     ```
  3. Force unmount:
     ```bash
     umount -f /mnt/nfs_share
     ```
  4. If `-f` fails, use **Lazy Unmount (`-l`)**:
     ```bash
     umount -l /mnt/nfs_share
     ```
     Lazy unmount detaches the filesystem immediately from the directory tree and cleans up references once the processes exit.
  5. Remount:
     ```bash
     mount -a
     ```

---

### Q19: What is the difference between Soft Mount and Hard Mount in NFS, and which should DevOps use in production?
**Answer:**
- **Soft Mount (`soft`)**: If an NFS server becomes unreachable, the client attempts the request for `retrans` times and then returns an I/O error (`EIO`) to the calling application.
  - *Risk*: Applications that do not handle I/O errors gracefully can experience silent data corruption or partial writes.
- **Hard Mount (`hard`) with `intr` (Recommended)**: If the NFS server goes down, the client process hangs in uninterruptible sleep (D-state) and retries indefinitely until the NFS server recovers.
  - *Advantage*: Guarantees zero data loss or partial writes. Adding the `intr` option allows administrators to send signals (`Ctrl+C`, `SIGINT`) to cancel hanging requests.

---

### Q20: How do you test the raw sequential and random I/O performance of a disk on a Linux node using `fio`?
**Answer:**
Avoid using `dd` for real benchmarking because it measures buffered memory caches. Use **`fio`** (Flexible I/O Tester):
1. **Random 4K Reads (IOPS Benchmark for Databases)**:
   ```bash
   fio --name=random-read --ioengine=libaio --iodepth=32 --rw=randread        --bs=4k --direct=1 --size=2G --numjobs=4 --runtime=30 --group_reporting
   ```
2. **Sequential 1M Writes (Throughput Benchmark for Logs/Backups)**:
   ```bash
   fio --name=seq-write --ioengine=libaio --iodepth=16 --rw=write        --bs=1M --direct=1 --size=4G --numjobs=2 --runtime=30 --group_reporting
   ```
   *(`--direct=1` bypasses the Linux page cache to test true disk hardware speed).*

---

## Domain 3: Networking, Firewalls & Socket Diagnostics

### Q21: Why is `ss` preferred over `netstat` on modern Linux, and how do you find port listeners with it?
**Answer:**
- **`netstat` (Deprecated)**: Reads through `/proc/net/tcp` line-by-line using slow user-space string parsing. On a server with 50,000 active TCP connections, `netstat` can hang for 30 seconds and peg a CPU core.
- **`ss` (Socket Statistics)**: Directly interfaces with the Linux kernel via the **Netlink protocol (`sock_diag`)**, returning thousands of socket states in milliseconds.
- **Essential Commands**:
  ```bash
  # List all listening TCP and UDP sockets with Process Names and Numeric Ports:
  ss -tulpn

  # Summary of socket memory and connection states:
  ss -s

  # List all established connections to port 443:
  ss -t -a '( dport = :443 or sport = :443 )'

  # Show TCP send and receive queue sizes (backlog):
  ss -t -l -n
  ```

---

### Q22: What causes `TIME_WAIT` and `CLOSE_WAIT` TCP states, and which one indicates a bug in your application code?
**Answer:**
- **`TIME_WAIT` (Normal & Client-Side)**:
  - Occurs on the endpoint that initiates the active close (`FIN`).
  - The socket stays in `TIME_WAIT` for $2 	imes 	ext{MSL}$ (Maximum Segment Lifetime, typically 60 seconds) to ensure stray packets from the old connection do not corrupt a new connection reusing the same port tuple.
  - *DevOps Fix if exhausting ephemeral ports*: Enable TCP socket reuse in `sysctl`:
    ```bash
    sysctl -w net.ipv4.tcp_tw_reuse=1
    ```
- **`CLOSE_WAIT` (Abnormal & Server-Side Bug)**:
  - The remote client sent a `FIN` packet to close the connection, and the Linux kernel acknowledged it with `ACK`.
  - The socket remains in `CLOSE_WAIT` waiting for the **local application process** to call `close()` on the socket descriptor.
  - **`CLOSE_WAIT` is almost always an application code bug**: a thread leaked a database or HTTP connection without closing it in a `finally` block or defer statement.

---

### Q23: How do you capture and filter network packets with `tcpdump` on a production server without flooding the terminal?
**Answer:**
```bash
# Capture 100 packets on eth0 for port 443, printing headers without resolving DNS:
tcpdump -i eth0 -nn -c 100 'port 443'

# Filter by source/destination host and specific TCP flags (SYN packets only):
tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-syn != 0 and host 192.168.1.50'

# Capture full packet payload and save to PCAP file for Wireshark analysis:
tcpdump -i eth0 -nn -s0 -w /tmp/production_trace.pcap 'port 8080 and host 10.0.1.15'

# Inspect ASCII content of HTTP headers in real time:
tcpdump -i eth0 -nn -A -s 1500 'port 80' | grep -E "GET|POST|Host:|HTTP/"
```

---

### Q24: How do you diagnose DNS resolution latency or failures on a Linux machine?
**Answer:**
1. **Trace every step of DNS resolution**:
   ```bash
   dig +trace api.production.com
   ```
2. **Inspect query response time and which Nameserver answered**:
   ```bash
   dig api.production.com
   # Look at ';; Query time: 4 msec' and ';; SERVER: 127.0.0.53#53'
   ```
3. **Verify Host Lookup Resolution Chain (`/etc/nsswitch.conf`)**:
   ```bash
   getent hosts api.production.com
   ```
4. **Inspect `systemd-resolved` cache and status (Ubuntu/Debian)**:
   ```bash
   resolvectl status
   resolvectl statistics
   # Flush local DNS cache:
   resolvectl flush-caches
   ```

---

### Q25: How do you test exact network latency, TTFB, and SSL handshake timing using `curl`?
**Answer:**
Create a custom format template `curl-format.txt`:
```text


    time_namelookup:  %{time_namelookup}s

       time_connect:  %{time_connect}s

    time_appconnect:  %{time_appconnect}s

   time_pretransfer:  %{time_pretransfer}s

      time_redirect:  %{time_redirect}s

 time_starttransfer:  %{time_starttransfer}s

                    ----------

         time_total:  %{time_total}s



```
Execute:
```bash
curl -w "@curl-format.txt" -o /dev/null -s -Iv https://api.enterprise.com/healthz
```
- `time_namelookup`: DNS resolution duration.
- `time_connect`: TCP 3-way handshake duration.
- `time_appconnect`: TLS/SSL handshake completion time.
- `time_starttransfer`: **Time to First Byte (TTFB)** — how long the backend took to process and return the first byte.

---

### Q26: What is MTU mismatch and how do you discover the maximum packet size between two servers?
**Answer:**
- **MTU (Maximum Transmission Unit)**: Maximum size (in bytes) of an IP packet that can be transmitted over a network link without fragmentation (standard Ethernet MTU = 1500; Jumbo Frames = 9000).
- **The Issue**: In Kubernetes overlay networks (Geneve, VXLAN, Cilium, Calico), encapsulation adds 20-50 bytes of header overhead. If the underlying host MTU is 1500, container MTU must be set to 1450. Otherwise, packets with `DF` (Don't Fragment) flag are dropped, causing SSL handshakes to hang.
- **Testing Maximum MTU**:
  ```bash
  # Send ping with Don't Fragment (-M do) and specific payload size:
  ping -M do -s 1472 10.0.1.20
  # Note: 1472 payload + 20 IP header + 8 ICMP header = 1500 total bytes.
  ```
  If it outputs `Frag needed and DF set`, decrement `-s` until packets succeed.

---

### Q27: How do iptables rules work, and what is the difference between `filter` and `nat` tables?
**Answer:**
- **Chains & Flow**: Packets traverse `PREROUTING` $	o$ `INPUT` (local host) or `FORWARD` (routed host) $	o$ `OUTPUT` $	o$ `POSTROUTING`.
- **Tables**:
  - `filter` (Default): Controls access (`ACCEPT`, `DROP`, `REJECT`). Chains: `INPUT`, `OUTPUT`, `FORWARD`.
  - `nat`: Modifies source or destination IP/port addresses. Chains: `PREROUTING` (DNAT), `POSTROUTING` (SNAT/Masquerade), `OUTPUT`.
- **Debugging Commands**:
  ```bash
  # View all filter rules with packet counters and line numbers:
  iptables -L -n -v --line-numbers

  # View all NAT rules (used heavily by Docker and kube-proxy):
  iptables -t nat -L -n -v --line-numbers

  # Block an IP immediately:
  iptables -I INPUT 1 -s 203.0.113.50 -j DROP

  # Delete rule #3 in INPUT chain:
  iptables -D INPUT 3
  ```

---

### Q28: How do you configure Port Forwarding and Reverse SOCKS5 Tunneling with SSH?
**Answer:**
1. **Local Port Forwarding (`-L`)**:
   - Access a remote internal service (e.g., remote Redis on port 6379) from your local workstation:
     ```bash
     ssh -L 6379:localhost:6379 user@remote-bastion.com
     ```
2. **Remote Port Forwarding (`-R`)**:
   - Expose a service running on your local laptop (e.g., port 3000) to a remote server on port 8080:
     ```bash
     ssh -R 8080:localhost:3000 user@remote-server.com
     ```
3. **Dynamic Proxy (SOCKS5 - `-D`)**:
   - Route all browser traffic through a remote server:
     ```bash
     ssh -D 1080 -N -f user@remote-server.com
     ```

---

### Q29: How do you measure network throughput and packet drops between two Linux servers?
**Answer:**
1. **Using `iperf3`**:
   - On Server A (Receiver):
     ```bash
     iperf3 -s
     ```
   - On Server B (Sender):
     ```bash
     iperf3 -c <Server_A_IP> -P 4 -t 30
     # (-P 4 opens 4 parallel TCP streams).
     ```
2. **Checking Interface Drops and Errors**:
   ```bash
   ip -s link show eth0
   # or with ethtool:
   ethtool -S eth0 | grep -iE "drop|error|miss"
   ```

---

### Q30: How do you use `mtr` (My Traceroute) to diagnose packet loss and network routing hops?
**Answer:**
- `traceroute` only sends 3 probe packets per hop and exits.
- **`mtr`** combines `traceroute` and `ping`, sending continuous probes to every intermediate router to show real-time packet loss percentage and jitter.
- **Best Command for DevOps Reports**:
  ```bash
  mtr --report --report-cycles 50 --no-dns api.production.com
  ```
- **Analysis**: If packet loss appears at hop 4 and continues at 100% across all subsequent hops, hop 4 is a point of failure. If packet loss appears at hop 4 but disappears at hop 5, hop 4 simply rate-limits ICMP packets and is NOT causing traffic drops.

---

## Domain 4: Systemd, Services & Log Management with Journald

### Q31: How do you write a robust, production-ready Systemd service unit from scratch?
**Answer:**
Create `/etc/systemd/system/api-service.service`:
```ini
[Unit]
Description=Enterprise API Microservice
After=network.target remote-fs.target
Wants=network-online.target
Documentation=https://wiki.enterprise.com/api

[Service]
Type=simple
User=appuser
Group=appgroup
WorkingDirectory=/opt/enterprise/api
ExecStart=/opt/enterprise/api/bin/server --config /etc/api/config.yaml
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=5s
TimeoutStopSec=30s

# Security Hardening & Resource Limits
LimitNOFILE=65536
LimitNPROC=4096
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
MemoryMax=4G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
```
Activate:
```bash
systemctl daemon-reload
systemctl enable --now api-service.service
```

---

### Q32: What is a Systemd Drop-in Override, and why should you never edit `/lib/systemd/system/*.service` directly?
**Answer:**
- Files in `/lib/systemd/system/` are owned by the OS package manager (`apt` / `yum`). If you modify them directly, package updates will overwrite your changes without warning.
- **Drop-in Overrides (`/etc/systemd/system/<unit>.d/override.conf`)**:
  - Safely modifies only specific directives without touching upstream vendor units.
  - Automatically survives package upgrades.
- **Creation via CLI**:
  ```bash
  systemctl edit docker.service
  ```
  Add the overrides:
  ```ini
  [Service]
  ExecStart=
  ExecStart=/usr/bin/dockerd -H fd:// --bip 172.20.0.1/16
  ```
  *(Note: For lists like `ExecStart`, specify an empty `ExecStart=` first to reset the list, then define the new value).*

---

### Q33: How do you replace legacy crontab with modern Systemd Timers, and what are the benefits?
**Answer:**
- **Why Systemd Timers over Cron?**:
  1. *Execution Logs*: Output goes directly to `journalctl -u <unit>` with millisecond timestamps and exit codes.
  2. *Resource Governance*: Timers run services isolated in cgroups with memory and CPU limits.
  3. *Catch-up Runs (`Persistent=true`)*: If the server was powered off when the job was scheduled, systemd runs it immediately upon boot.
- **Implementation**:
  1. Service Unit (`/etc/systemd/system/db-backup.service`):
     ```ini
     [Unit]
     Description=Daily Database Backup

     [Service]
     Type=oneshot
     ExecStart=/opt/scripts/backup.sh
     ```
  2. Timer Unit (`/etc/systemd/system/db-backup.timer`):
     ```ini
     [Unit]
     Description=Trigger Daily Database Backup

     [Timer]
     OnCalendar=*-*-* 02:00:00
     Persistent=true
     RandomizedDelaySec=300

     [Install]
     WantedBy=timers.target
     ```
  3. Enable: `systemctl enable --now db-backup.timer`.
  4. View timers: `systemctl list-timers`.

---

### Q34: What are the most effective `journalctl` commands for troubleshooting production incidents?
**Answer:**
```bash
# Stream logs for a specific service in real time:
journalctl -u nginx.service -f

# View logs since a specific time:
journalctl -u api-service --since "2026-10-16 08:00:00" --until "2026-10-16 09:30:00"

# View logs only from the current boot:
journalctl -b 0 -u containerd.service

# Filter by log priority (emerg, alert, crit, err, warning, notice, info, debug):
journalctl -p err -b 0

# View kernel dmesg messages via journalctl:
journalctl -k -b 0

# View logs with output in JSON for ingestion/parsing:
journalctl -u api-service -n 10 -o json-pretty
```

---

### Q35: How do you manage and limit journald disk space usage when `/var/log/journal` is filling the disk?
**Answer:**
1. **Check current journald disk usage**:
   ```bash
   journalctl --disk-usage
   ```
2. **Vacuum old logs immediately**:
   ```bash
   # Keep only the last 2 days of logs:
   journalctl --vacuum-time=2d

   # Keep maximum 1GB of logs:
   journalctl --vacuum-size=1G
   ```
3. **Persist the limits in `/etc/systemd/journald.conf`**:
   ```ini
   [Journal]
   SystemMaxUse=2G
   SystemKeepFree=5G
   MaxRetentionSec=14day
   ```
   Apply: `systemctl restart systemd-journald`.

---

### Q36: How do you diagnose boot time delays using `systemd-analyze`?
**Answer:**
1. **Overall Boot Time Summary**:
   ```bash
   systemd-analyze
   # Startup finished in 2.1s (kernel) + 12.4s (userspace) = 14.5s
   ```
2. **List slowest services in descending order**:
   ```bash
   systemd-analyze blame
   # e.g., 6.2s cloud-init.service, 3.1s lvm2-monitor.service
   ```
3. **Inspect the critical dependency chain**:
   ```bash
   systemd-analyze critical-chain
   ```
   Identifies which slow unit blocked the boot sequence from reaching `multi-user.target`.

---

### Q37: What is the difference between `systemctl stop`, `disable`, and `mask`?
**Answer:**
- **`systemctl stop <service>`**: Immediately terminates the running process, but does not prevent it from starting on the next boot or when triggered by another dependency.
- **`systemctl disable <service>`**: Removes the symlink from `/etc/systemd/system/*.wants/`. It will not start automatically at boot, but **can still be started manually** or triggered by socket activation / other services.
- **`systemctl mask <service>`**: Symlinks the service unit file to `/dev/null`. It is **completely impossible to start the service** (manually, automatically, or as a dependency) until `systemctl unmask` is executed.

---

### Q38: How do cgroups v2 resource limits work in Systemd slices?
**Answer:**
Under cgroups v2 (`/sys/fs/cgroup/`), systemd manages resource distribution hierarchically via slices:
- Systemd directives in `[Service]` translate directly to cgroups v2 controllers:
  - `MemoryMax=2G` $	o$ `memory.max` (hard ceiling; triggers OOM if exceeded).
  - `MemoryHigh=1.5G` $	o$ `memory.high` (soft ceiling; throttles process and reclaims page cache aggressively).
  - `CPUQuota=150%` $	o$ `cpu.max` (allocates 1.5 CPU cores equivalent runtime).
  - `IOReadBandwidthMax=/dev/sda 50M` $	o$ `io.max` (throttles disk read rate).

---

### Q39: Why is `systemctl daemon-reload` mandatory after editing unit files?
**Answer:**
- Systemd caches all unit files in memory during initialization for sub-millisecond dependency resolution.
- Modifying a `.service` file on disk does not update systemd's in-memory dependency graph.
- Executing `systemctl daemon-reload` instructs systemd (PID 1) to reread all unit files from disk, regenerate the dependency tree, and apply changes without restarting unrelated services.

---

### Q40: How do you safely pass secrets and dynamic environment variables to a Systemd unit?
**Answer:**
- **In-unit `EnvironmentFile`**:
  ```ini
  [Service]
  EnvironmentFile=/etc/enterprise/api.env
  ```
  Set strict permissions: `chmod 600 /etc/enterprise/api.env` and `chown appuser:appgroup`.
- **Systemd Credential Management (Modern systemd 250+)**:
  ```ini
  [Service]
  LoadCredential=db-pass:/etc/secrets/db_password.txt
  ```
  Systemd mounts the secret inside an in-memory directory accessible via `$CREDENTIALS_DIRECTORY/db-pass`, completely isolated from other processes and invisible in `ps` or `/proc/<pid>/environ`.

---

## Domain 5: Security, Permissions, SSH & Access Control

### Q41: Explain SUID, SGID, and the Sticky Bit with real-world DevOps examples.
**Answer:**
| Permission Bit | Octal Value | Effect on Files | Effect on Directories | Production Example |
| :--- | :---: | :--- | :--- | :--- |
| **SUID** (Set User ID) | `4000` (`rwsr-xr-x`) | Executes with the permissions of the file *owner*, not the running user | No effect | `/usr/bin/passwd` (regular users run it as `root` to edit `/etc/shadow`) |
| **SGID** (Set Group ID) | `2000` (`rwxr-sr-x`) | Executes with the permissions of the file's *group* | Files created inside inherit the directory's group, not user's primary group | Shared deployment directory: `chmod 2775 /var/www/shared` |
| **Sticky Bit** | `1000` (`rwxrwxrwt`) | No effect | Only the file *owner* or `root` can delete files inside | `/tmp` directory (`chmod 1777 /tmp`) |

---

### Q42: How do POSIX Access Control Lists (ACLs) solve standard Linux permission limitations?
**Answer:**
- Standard Linux permissions only allow specifying permissions for ONE owner, ONE group, and others (`rwxrwxrwx`).
- **ACLs** allow granting granular permissions to multiple individual users and groups on the same file:
  ```bash
  # Grant user 'deployer' read, write, execute on /var/www without changing owner:
  setfacl -m u:deployer:rwx /var/www

  # View ACLs:
  getfacl /var/www

  # Set DEFAULT ACLs on a directory so all future files automatically inherit them:
  setfacl -d -m u:deployer:rwx /var/www
  setfacl -d -m g:developers:rx /var/www

  # Remove all ACLs:
  setfacl -b /var/www
  ```

---

### Q43: How do you safely configure `/etc/sudoers` for least privilege without breaking syntax?
**Answer:**
- **Always use `visudo`**: It validates syntax before saving and locks the file to prevent concurrent edit corruption. If syntax is invalid, it warns you before exiting.
- **Granular Least Privilege Example**:
  ```sudoers
  # Define Aliases:
  User_Alias DEVOPS_ENGINEERS = alice, bob, charlie
  Cmnd_Alias DOCKER_KUBE = /usr/bin/docker, /usr/bin/kubectl, /usr/bin/systemctl restart containerd

  # Allow DevOps to run container commands without password:
  DEVOPS_ENGINEERS ALL=(root) NOPASSWD: DOCKER_KUBE

  # Drop-in directory:
  # Best practice: place files in /etc/sudoers.d/devops with chmod 0440.
  ```

---

### Q44: What are the mandatory SSH server hardening directives for production bastion hosts?
**Answer:**
In `/etc/ssh/sshd_config`:
```ini
# Disable root password login:
PermitRootLogin prohibit-password

# Enforce Public Key Authentication only:
PasswordAuthentication no
ChallengeResponseAuthentication no

# Limit failed attempts and brute-force timeouts:
MaxAuthTries 3
LoginGraceTime 30

# Whitelist allowed users or groups:
AllowGroups ssh-users

# Disable legacy weak crypto:
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com

# Disable X11 forwarding:
X11Forwarding no
```
Validate syntax before restart: `sshd -t && systemctl restart sshd`.

---

### Q45: Why is Ed25519 preferred over RSA for SSH keys, and how do you generate one?
**Answer:**
- **RSA (Legacy)**: Requires 3072 or 4096-bit key lengths to be secure; slower mathematical verification; vulnerable to timing attacks if not padded properly.
- **Ed25519 (Modern)**:
  - Based on the Twisted Edwards Curve (Curve25519).
  - Compact key size (only 256 bits).
  - Significantly faster key generation and cryptographic verification.
  - Constant-time execution prevents cache and timing side-channel attacks.
- **Generation Command**:
  ```bash
  ssh-keygen -t ed25519 -a 100 -C "devops-engineer@enterprise.com" -f ~/.ssh/id_ed25519
  ```
  *(`-a 100` performs 100 Key Derivation Function rounds to resist brute-forcing).*

---

### Q46: How do you troubleshoot and fix SELinux denials in production without disabling SELinux?
**Answer:**
Never run `setenforce 0` permanently in production!
1. **Check SELinux mode**:
   ```bash
   getenforce # Enforcing, Permissive, or Disabled
   ```
2. **Search for recent AVC (Access Vector Cache) denials**:
   ```bash
   ausearch -m avc -ts recent
   ```
3. **Parse denials into human-readable recommendations**:
   ```bash
   audit2why < /var/log/audit/audit.log
   ```
4. **Fix Incorrect File Contexts**:
   - If NGINX cannot read `/data/web`:
     ```bash
     ls -Z /data/web
     # Set correct context permanently:
     semanage fcontext -a -t httpd_sys_content_t "/data/web(/.*)?"
     restorecon -Rv /data/web
     ```
5. **Enable SELinux Booleans (e.g., allowing NGINX to proxy network connections)**:
   ```bash
   setsebool -P httpd_can_network_connect 1
   ```

---

### Q47: What is AppArmor, and how does it differ from SELinux in Kubernetes worker nodes?
**Answer:**
- **SELinux (RHEL/CentOS/Fedora)**: Label-based mandatory access control (MAC). Every file, process, socket, and port has a security context (`system_u:system_r:container_t:s0`). Incredibly granular, but complex.
- **AppArmor (Ubuntu/Debian/SUSE)**: Path-based mandatory access control. Profiles define exactly what file paths, capabilities, and network calls a specific binary can access.
- **Commands**:
  ```bash
  # Check AppArmor status:
  aa-status

  # Put a profile into complaint mode (logs warnings without blocking):
  aa-complain /etc/apparmor.d/usr.sbin.nginx

  # Enforce profile:
  aa-enforce /etc/apparmor.d/usr.sbin.nginx
  ```
- In Kubernetes, Pods specify AppArmor profiles via annotations (`container.apparmor.security.beta.kubernetes.io/<container-name>: runtime/default`).

---

### Q48: How do you investigate unauthorized logins and check currently active users on a Linux system?
**Answer:**
```bash
# Who is currently logged in, what terminal, and what command are they running?
w
who -u

# View recent successful user logins:
last -n 20

# View recent failed login attempts (potential brute-force):
lastb -n 20

# Search authentication logs for brute-force SSH attacks:
# On Ubuntu/Debian:
grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | sort -nr | head -n 10
# On RHEL/CentOS:
grep "Failed password" /var/log/secure | awk '{print $11}' | sort | uniq -c | sort -nr | head -n 10
```

---

### Q49: What is the Immutable bit (`chattr +i`) and when should a DevOps engineer use it?
**Answer:**
- Setting the immutable attribute (`+i`) on a file prevents anyone — **including the root superuser** — from modifying, deleting, renaming, truncating, or creating symlinks to it.
- **Usage in Production**:
  Protect critical configuration files from accidental deletion by automation scripts or unauthorized modification by compromised web processes:
  ```bash
  chattr +i /etc/resolv.conf
  chattr +i /etc/passwd
  chattr +i /etc/shadow

  # View file attributes:
  lsattr /etc/resolv.conf

  # Remove attribute to perform legitimate edits:
  chattr -i /etc/resolv.conf
  ```

---

### Q50: How do you lock a Linux user account immediately during an offboarding or incident response?
**Answer:**
```bash
# 1. Lock the user password (prepends '!' to password hash in /etc/shadow):
usermod -L baduser

# 2. Expire account immediately:
chage -E 0 baduser

# 3. Change shell to nologin:
usermod -s /sbin/nologin baduser

# 4. Terminate all active processes owned by the user:
pkill -u baduser
killall -u baduser -9

# 5. Remove any active SSH keys from authorized_keys:
rm -f /home/baduser/.ssh/authorized_keys
```

---

## Domain 6: Text Processing, Shell Scripting & CLI Power Tools

### Q51: How do you parse an NGINX access log using `awk` to find the top 10 requesting IP addresses?
**Answer:**
Assuming standard NGINX log format where IP is the 1st field:
```bash
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -n 10
```
- **Find top 10 URLs returning HTTP 500 errors**:
  ```bash
  awk '($9 ~ /50[0-9]/) {print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -n 10
  ```
- **Calculate total bandwidth transferred in megabytes**:
  ```bash
  awk '{sum+=$10} END {print sum/(1024*1024) " MB"}' /var/log/nginx/access.log
  ```

---

### Q52: How do you perform safe in-place string replacements across multiple files using `sed`?
**Answer:**
```bash
# Replace 'staging.internal.net' with 'prod.enterprise.com' in all *.conf files:
sed -i.bak 's/staging\.internal\.net/prod\.enterprise\.com/g' /etc/nginx/conf.d/*.conf
```
- `-i.bak` creates a backup copy (`file.conf.bak`) before modifying the original.
- **Delete matching lines**:
  ```bash
  sed -i '/DEBUG_MODE=true/d' config.env
  ```
- **Insert a line after a matching pattern**:
  ```bash
  sed -i '/\[Service\]/a RestartSec=10s' /etc/systemd/system/app.service
  ```

---

### Q53: What does `set -euo pipefail` do in Bash scripts, and why is it mandatory for production CI/CD pipelines?
**Answer:**
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'
	'
```
1. **`-e` (`errexit`)**: The script exits immediately if any command returns a non-zero exit status (failure), preventing cascade errors.
2. **`-u` (`nounset`)**: Treats unset/uninitialized variables as an error and exits immediately (prevents catastrophic disasters like `rm -rf /${UNSET_VAR}`).
3. **`-o pipefail`**: By default, a pipeline (e.g., `cmd1 | cmd2 | cmd3`) only returns the exit status of the *last* command (`cmd3`). With `pipefail`, if `cmd1` fails, the whole pipeline is considered failed even if `cmd3` succeeds.
4. **`IFS=$'
	'`**: Prevents word splitting on spaces, ensuring filenames with spaces are handled safely.

---

### Q54: How do you implement robust cleanup routines using `trap` in Bash scripts?
**Answer:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Create a temporary working directory:
TEMP_DIR=$(mktemp -d /tmp/deploy.XXXXXX)

# Define cleanup function:
cleanup() {
    local exit_code=$?
    echo "Running cleanup routine for ${TEMP_DIR}..."
    rm -rf "${TEMP_DIR}"
    echo "Exiting with code ${exit_code}"
}

# Trap EXIT (always runs), INT (Ctrl+C), and TERM (kill):
trap cleanup EXIT INT TERM

# Script logic:
echo "Downloading deployment artifacts..."
tar -xzf /tmp/app.tar.gz -C "${TEMP_DIR}"
# If any command fails here, cleanup() executes automatically!
```

---

### Q55: How do you process millions of items in parallel using `xargs -P`?
**Answer:**
- Standard `xargs` processes items sequentially on a single CPU core.
- **`-P <NUM>`** executes multiple processes in parallel:
  ```bash
  # Compress 10,000 log files using 8 parallel cores:
  find /var/log/archives -name "*.log" -print0 | xargs -0 -P 8 -I {} gzip {}

  # Download a list of 500 URLs with 10 concurrent curl jobs:
  cat urls.txt | xargs -n 1 -P 10 -I {} curl -s -O {}
  ```
  *(`-print0` and `-0` ensure safe handling of whitespace and special characters).*

---

### Q56: How do you extract and transform JSON data from APIs using `jq` on the command line?
**Answer:**
```bash
# Extract specific fields into tabular format:
curl -s https://api.github.com/repos/kubernetes/kubernetes/releases |   jq -r '.[] | [.tag_name, .published_at, .prerelease] | @tsv'

# Filter array objects based on condition:
cat pods.json | jq '.items[] | select(.status.phase=="Failed") | .metadata.name'

# Convert JSON array to comma-separated list:
cat servers.json | jq -r '.servers | map(.ip) | join(",")'

# Update a JSON field in place:
jq '.replicas = 5' deployment.json > deployment_new.json
```

---

### Q57: How do you monitor file changes across multiple servers or watch log files with log rotation?
**Answer:**
- **Standard `tail -f file.log`**: Attaches to the *file descriptor*. When `logrotate` moves the file and creates a new one, `tail -f` stops reading new lines!
- **Correct Command (`tail -F`)**:
  ```bash
  tail -F /var/log/nginx/access.log
  ```
  *(Capital `-F` tracks by **filename**, reopening the file automatically when log rotation replaces it).*
- **`watch -d -n 2 <command>`**: Runs a command every 2 seconds and highlights differences on screen (e.g., `watch -d -n 1 'kubectl get pods'`).

---

### Q58: How do you synchronize directories with `rsync` preserving permissions, symlinks, and timestamps?
**Answer:**
```bash
rsync -avzP --delete /local/source/ user@remote:/remote/backup/
```
- `-a` (`archive`): Preserves recursive files, symlinks, permissions, timestamps, owner, and group.
- `-v` (`verbose`): Detailed transfer output.
- `-z` (`compress`): Compresses data during transfer over the network.
- `-P` (`progress` + `partial`): Shows progress bar and resumes interrupted transfers.
- `--delete`: Deletes files in target that no longer exist in source (exact mirror).
- **Dry-Run Test**: Always test with `--dry-run` (`-n`) first:
  ```bash
  rsync -avzPn --delete /local/source/ user@remote:/remote/backup/
  ```

---

### Q59: How do you find files modified in the last 60 minutes and larger than 50MB?
**Answer:**
```bash
find /var/log -type f -mmin -60 -size +50M -exec ls -lh {} +
```
- `-mmin -60`: Modified less than 60 minutes ago.
- `-mtime +7`: Modified more than 7 days ago.
- `-size +100M`: Greater than 100 megabytes.
- `-name "*.log"`: Glob matching pattern.
- `-delete`: Deletes matched files directly in the kernel without spawning subshells.

---

### Q60: How do you compare two directories or configuration files recursively?
**Answer:**
```bash
# Compare two configuration files side-by-side:
diff -u -w /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Recursively compare two directories and report differences:
diff -r -u /opt/app-v1/config /opt/app-v2/config

# Visual terminal diff tool:
colordiff -u file1.conf file2.conf
```

---

## Domain 7: Kernel Tuning, Sysctl & Container Host Optimization

### Q61: What are the mandatory `sysctl` kernel parameters for Kubernetes worker nodes and why?
**Answer:**
In `/etc/sysctl.d/99-kubernetes.conf`:
```ini
# Enable packet forwarding between network interfaces (mandatory for CNI routing):
net.ipv4.ip_forward = 1

# Bridge netfilter: ensure iptables sees bridged container traffic:
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Prevent memory swapping (Kubernetes kubelet requires swap off or tuned):
vm.swappiness = 0

# Increase max inotify file watchers (prevents "too many open files" in large pods):
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# Increase max file descriptors:
fs.file-max = 2097152

# Increase network connection backlogs:
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 16384
```
Apply: `sysctl --system`.

---

### Q62: What is the difference between `fs.file-max` and `ulimit -n`? How do you fix "Too many open files"?
**Answer:**
1. **`fs.file-max` (System-Wide Kernel Limit)**:
   - The absolute maximum number of open file descriptors allocated by the kernel across all processes.
   - Check current usage: `cat /proc/sys/fs/file-nr` (Format: allocated, free, max).
2. **`ulimit -n` (Per-Process / Per-Session Limit)**:
   - The maximum file descriptors a single process can open.
   - Soft limit: `ulimit -Sn` (can be raised by process).
   - Hard limit: `ulimit -Hn` (ceiling enforced by root).
3. **Fixing Permanently**:
   - In `/etc/security/limits.conf`:
     ```text
     * soft nofile 65536
     * hard nofile 65536
     root soft nofile 65536
     root hard nofile 65536
     ```
   - In Systemd services: `LimitNOFILE=65536`.
   - Update running process without restarting:
     ```bash
     prlimit --pid <PID> --nofile=65536:65536
     ```

---

### Q63: How do Linux Namespaces implement container isolation under the hood?
**Answer:**
Containers are not VMs; they are standard Linux processes isolated by **6 core kernel namespaces**:
1. **PID Namespace**: Isolates process IDs. The container process thinks it is PID 1, while the host sees it as PID 24590.
2. **NET Namespace**: Isolates network interfaces, IP addresses, routing tables, and firewall rules (creates `veth` pairs).
3. **MNT (Mount) Namespace**: Isolates filesystem mount points (provides container rootfs via `pivot_root`).
4. **IPC Namespace**: Isolates inter-process communication, System V message queues, and POSIX shared memory.
5. **UTS Namespace**: Isolates hostname and domain name.
6. **USER Namespace**: Maps container root UID 0 to an unprivileged non-zero UID on the host for security.

---

### Q64: How do you use `nsenter` to inject yourself into a container's network namespace for troubleshooting?
**Answer:**
If a container image has no debugging tools (`curl`, `tcpdump`, `ip`, `netstat` are missing):
1. Find the container's host PID:
   ```bash
   docker inspect --format '{{.State.Pid}}' <container_id>
   # or with crictl:
   crictl inspect <container_id> | grep -i pid
   ```
2. Enter the container's network namespace using the host's tools:
   ```bash
   nsenter -t <CONTAINER_PID> -n ip addr
   nsenter -t <CONTAINER_PID> -n ss -tulpn
   nsenter -t <CONTAINER_PID> -n tcpdump -i eth0 -nn
   ```
   *(This gives you access to the container's network interfaces while using your host's native utilities!)*

---

### Q65: How do you trace system calls of a hanging process in real-time using `strace`?
**Answer:**
```bash
strace -p <PID> -f -s 256 -T -tt -e trace=network,file
```
- `-p <PID>`: Attaches to the running process.
- `-f`: Traces all child threads spawned by the process.
- `-s 256`: Prints up to 256 bytes of string arguments (e.g., file paths, SQL queries).
- `-T`: Displays the time spent in each system call (locates blocking I/O calls).
- `-tt`: Prints microsecond timestamps on every line.
- `-e trace=network,file`: Filters out noise, tracing only file operations (`open`, `read`, `write`) and network calls (`connect`, `sendto`).
- **Summary of slow system calls**:
  ```bash
  strace -c -p <PID>
  ```

---

### Q66: What is `vm.swappiness` and what value should you set for production database and Kubernetes servers?
**Answer:**
- **`vm.swappiness`** (Range: `0` to `200` on modern kernels, default `60`):
  - Controls the kernel's aggressiveness in paging anonymous memory out to swap space versus reclaiming page cache.
  - A value of `60` means the kernel aggressively swaps out idle memory pages even when plenty of RAM remains.
- **Production Recommendation**:
  - For **Kubernetes worker nodes**: Set to `0` (or disable swap completely via `swapoff -a`) to ensure kubelet accurate resource scheduling.
  - For **Databases (PostgreSQL, MySQL, Redis)**: Set to `1` (or `10`).
    - Setting `vm.swappiness = 1` tells the kernel: *Avoid swapping at all costs, but if the system is completely out of memory, swap as an absolute last resort to prevent the OOM Killer from murdering the database.*

---

### Q67: What are Transparent Huge Pages (THP) and why do Redis and MongoDB mandate disabling them?
**Answer:**
- Standard Linux memory pages are 4KB. **HugePages** are 2MB or 1GB.
- **Transparent Huge Pages (THP)** is a background kernel thread (`khugepaged`) that automatically groups 4KB pages into 2MB blocks.
- **The Problem for Redis/MongoDB**:
  - Redis uses Copy-on-Write (CoW) for background BGSAVE persistence.
  - With standard 4KB pages, modifying a byte copies only 4KB of RAM.
  - With 2MB THP, modifying a single byte forces the kernel to copy the entire 2MB block, causing massive memory bloat, high allocation latency, and severe database latency spikes.
- **Disabling THP**:
  ```bash
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
  ```

---

### Q68: How do you adjust the CPU Frequency Governor to `performance` mode for low-latency workloads?
**Answer:**
By default, most Linux distros use `powersave` or `ondemand` governor, which throttles CPU clock speed when idle. The CPU takes hundreds of microseconds to ramp up frequency when traffic bursts arrive:
1. **Check current governor**:
   ```bash
   cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```
2. **Switch to performance mode (locks CPU cores at maximum frequency)**:
   ```bash
   cpupower frequency-set -g performance
   # or via sysfs loop:
   for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
       echo performance > "$i"
   done
   ```

---

### Q69: What is the significance of `/proc/sys/vm/overcommit_memory`?
**Answer:**
Controls the kernel's memory allocation strategy:
- **`0` (Heuristic Overcommit - Default)**: The kernel allows processes to request more memory than physically available, guessing whether memory will actually be touched.
- **`1` (Always Overcommit)**: The kernel always approves `malloc()` requests, assuming processes will never use all requested memory. **Mandatory for Redis** to allow fork-based snapshotting.
- **`2` (Strict No-Overcommit)**: The kernel never allocates more than:
  $$	ext{Commit Limit} = 	ext{Swap Space} + (	ext{RAM} 	imes 	ext{overcommit\_ratio})$$
  Prevents any OOM conditions; optimal for strict real-time and mission-critical systems.

---

### Q70: How do you identify disk hardware errors using `smartctl`?
**Answer:**
```bash
# Check overall disk health status:
smartctl -H /dev/sda

# Run full SMART short test:
smartctl -t short /dev/sda

# View SMART attributes and error counts:
smartctl -A /dev/sda | grep -E "Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable"
```
- If `Reallocated_Sector_Ct` or `Current_Pending_Sector` is greater than 0 and continuously increasing, the physical drive is failing and must be replaced immediately.

---

## Domain 8: Real-World DevOps Incident Scenarios & Production Runbooks

### Q71: Scenario: A production server suddenly becomes completely unresponsive via SSH. How do you recover and debug?
**Answer:**
1. **Out-of-Band Access**:
   - Access the server via cloud serial console (AWS EC2 Serial Console, GCP Cloud Shell Serial Port, Azure Serial Console) or bare-metal IPMI/iDRAC/iLO.
2. **Identify Resource Lock**:
   - If serial console responds: check if CPU is pegged (`top`), disk is full (`df -h`), or kernel is in OOM loop (`dmesg`).
3. **Magic SysRq Emergency Recovery (If kernel is alive but userspace is frozen)**:
   - Send Magic SysRq commands in sequence: **`S - U - B`**
     - `Alt + SysRq + s`: Synchronizes dirty memory caches to disk safely.
     - `Alt + SysRq + u`: Remounts all filesystems as read-only.
     - `Alt + SysRq + b`: Immediately reboots the server without corrupting data.
4. **Post-Mortem Root Cause Analysis**:
   - Inspect `/var/log/messages`, `/var/log/syslog`, or `journalctl -b -1` (previous boot logs).

---

### Q72: Scenario: System Load Average spikes to 80 on a 16-core machine, but CPU usage is only 12%. What is happening and how do you fix it?
**Answer:**
- **Root Cause**: Load average counts processes in **D-state (Uninterruptible Sleep)**. The CPUs are mostly idle, but 70+ worker threads are blocked waiting for an I/O resource (storage, network socket, or dead NFS server).
- **Triage Steps**:
  1. Verify D-state processes:
     ```bash
     ps aux | awk '$8 ~ /D/'
     ```
  2. Inspect `/proc/<PID>/stack` on multiple blocked processes.
  3. If they are blocked in `nfs_wait_bit_uninterruptible`:
     - Test connectivity to the NFS/SAN server: `rpcinfo -p <nfs_server_ip>`.
     - If the NFS server is unresponsive, perform a lazy unmount:
       ```bash
       umount -f -l /mnt/nfs_mount
       ```
     - Load average will immediately plunge back to normal.

---

### Q73: Scenario: A Kubernetes node enters `NotReady` with `DiskPressure`. How do you rapidly triage and clear space on the Linux node?
**Answer:**
1. **Identify the Full Mount Point**:
   ```bash
   df -h
   ```
2. **Clean Containerd / Docker Images & Dead Containers**:
   ```bash
   # For containerd:
   crictl rmi --prune
   # For docker:
   docker system prune -a --volumes -f
   ```
3. **Clean Kubernetes Pod Logs**:
   ```bash
   find /var/log/pods -name "*.log" -size +100M -exec truncate -s 0 {} +
   ```
4. **Identify Deleted Open Files**:
   ```bash
   lsof +L1
   ```
5. **Verify Inodes**:
   ```bash
   df -i
   ```

---

### Q74: Scenario: An application crashes with "java.io.IOException: Too many open files". How do you resolve it immediately without restarting the service?
**Answer:**
1. Find current limits and open file count:
   ```bash
   cat /proc/<PID>/limits | grep "Max open files"
   ls -1 /proc/<PID>/fd | wc -l
   ```
2. **Increase the limit dynamically on the live running process**:
   ```bash
   prlimit --pid <PID> --nofile=65536:65536
   ```
3. Verify the change took effect:
   ```bash
   cat /proc/<PID>/limits | grep "Max open files"
   ```
4. **Persist the change**:
   - In `/etc/systemd/system/app.service.d/override.conf`:
     ```ini
     [Service]
     LimitNOFILE=65536
     ```
   - Run `systemctl daemon-reload`.

---

### Q75: Scenario: DNS queries on an Ubuntu server intermittently take exactly 5.0 seconds. What is the cause?
**Answer:**
- **Cause**: The **glibc DNS resolver parallel query flaw**.
- Glibc sends both `A` (IPv4) and `AAAA` (IPv6) DNS queries simultaneously from the same socket.
- Many enterprise firewalls, NAT routers, or misconfigured DNS servers drop `AAAA` queries instead of responding with `NOERROR` or `NXDOMAIN`.
- The client waits for the full 5-second DNS timeout before falling back to the `A` record.
- **Fix in `/etc/resolv.conf`**:
  ```text
  options single-request-reopen
  options timeout:1 attempts:2
  ```
  `single-request-reopen` forces the resolver to send `A` and `AAAA` queries over distinct sockets sequentially, eliminating the 5-second stall completely.

---

### Q76: Scenario: A developer accidentally ran `rm -f /opt/app/production.conf`. The application is still running. How do you recover the file from memory?
**Answer:**
As long as the application is still running, the Linux kernel preserves the open file descriptor in `/proc`:
1. Find the PID of the application:
   ```bash
   pgrep -f "app-binary" # e.g., PID 9821
   ```
2. Find the file descriptor linked to the deleted file:
   ```bash
   ls -l /proc/9821/fd | grep "production.conf"
   # Output: lrwx------ 1 app app 64 Oct 16 08:00 7 -> /opt/app/production.conf (deleted)
   ```
3. **Copy the file directly back from `/proc`**:
   ```bash
   cp /proc/9821/fd/7 /opt/app/production.conf
   ```
4. Restore permissions:
   ```bash
   chown appuser:appgroup /opt/app/production.conf && chmod 644 /opt/app/production.conf
   ```

---

### Q77: Scenario: A high-traffic web server experiences network packet drops (`rx_dropped` increasing in `ip -s link`). How do you tune the network ring buffers?
**Answer:**
- **Cause**: Incoming network packets arrive faster than the network card driver can transfer them into the kernel socket buffers.
- **Triage & Tuning**:
  1. Inspect ring buffer limits:
     ```bash
     ethtool -g eth0
     # Shows: Maximum RX: 4096, Current RX: 512
     ```
  2. Increase the RX ring buffer to the maximum supported by the hardware:
     ```bash
     ethtool -G eth0 rx 4096 tx 4096
     ```
  3. Increase kernel socket receive buffer limits in `sysctl`:
     ```ini
     net.core.netdev_max_backlog = 100000
     net.core.rmem_max = 16777216
     net.core.wmem_max = 16777216
     ```

---

### Q78: Scenario: Disk space is 100% full, preventing root from logging in or creating temporary files in `/tmp`. How do you recover?
**Answer:**
1. Log in via SSH or serial console. If bash fails to open because `/tmp` or history cannot write, login with sh:
   ```bash
   ssh -t root@server "sh --noprofile"
   ```
2. **Free space immediately without creating temporary files**:
   ```bash
   # Truncate old syslog files:
   > /var/log/syslog
   > /var/log/messages
   # Clean apt/yum package caches:
   apt-get clean || yum clean all
   ```
3. Identify top culprits:
   ```bash
   du -hx --max-depth=1 /var | sort -rh | head -n 5
   ```
4. **Prevent future lockouts**: Reserve 5% disk blocks specifically for the `root` superuser:
   ```bash
   tune2fs -m 5 /dev/mapper/vg-root
   ```
   *(Regular users will be blocked at 95% full, leaving 5% space for root to log in and remediate).*

---

### Q79: Scenario: A multithreaded Go or Java application crashes silently with exit code 137. How do you prove it was the Linux kernel OOM Killer?
**Answer:**
- Exit code **137** $= 128 + 9$ (`SIGKILL`), meaning the process was forcefully killed by a signal 9.
- **Verification Commands**:
  1. Check kernel ring buffer for OOM events:
     ```bash
     dmesg -T | grep -iE "oom[-_]killer|killed process"
     ```
  2. Check system log files:
     ```bash
     journalctl -k | grep -i oom
     grep -i "killed process" /var/log/messages /var/log/syslog
     ```
  3. Typical OOM log entry:
     `Out of memory: Killed process 14290 (java) total-vm:8542000kB, anon-rss:4120000kB, file-rss:0kB, shmem-rss:0kB`
  4. Fix: Increase container memory limits, tune JVM `-Xmx`, or investigate memory leaks.

---

### Q80: How do you build an automated Linux OS compliance and hardening pipeline for production cloud AMIs?
**Answer:**
1. **Base Image Selection**: Use official minimal, hardened base AMIs (e.g., Ubuntu Minimal, Amazon Linux 2023, RHEL Minimal).
2. **Automated Build Tooling**:
   - Use **HashiCorp Packer** to build cloud images declaratively.
   - Use **Ansible** playbooks to apply CIS (Center for Internet Security) Linux Benchmark Level 1 or Level 2 profiles.
3. **Hardening Steps Applied**:
   - Disable unused legacy filesystems (`cramfs`, `freevxfs`, `jffs2`, `hfs`).
   - Restrict `/tmp` and `/dev/shm` mount options (`nodev,nosuid,noexec`).
   - Enable `auditd` logging on all privileged system calls (`execve`, `chmod`, `settimeofday`).
   - Enforce strict SSH hardening and disable password authentication.
4. **Security Vulnerability Scanning**:
   - Scan the built AMI with **OpenSCAP**, **Trivy**, or **Wazuh** in the CI/CD pipeline before promoting to production.
