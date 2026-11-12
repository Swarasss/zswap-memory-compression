

# ZSWAP Memory Compression

Linux memory-compression experiments using **ZSWAP**, controlled compressible and incompressible workloads, and a non-GUI **QEMU Ubuntu virtual machine**.

This project investigates how Linux behaves under memory pressure when workloads have very different compressibility characteristics. It measures how much data is retained in ZSWAP, how much reaches backing swap, and how effectively compressed memory reduces the overall workload footprint.

---

## 🎯 Project Goals

The main goals of this project are to:

- Evaluate Linux **ZSWAP behavior under memory pressure**
- Compare highly compressible and high-entropy workloads
- Measure the relationship between:
  - Resident memory
  - Compressed ZSWAP memory
  - Backing swap usage
  - Stored pages
  - Swap writeback
- Calculate both:
  - **Effective ZSWAP storage ratio**
  - **Whole-program compression ratio**
- Build a reproducible baseline for further Linux memory-management experiments

---

## 🧪 Workloads

Two controlled memory patterns are used.

### Compressible workload

The compressible workload repeatedly fills memory using the byte pattern:

```text
1, 2, 3, 4, 5, 1, 2, 3, 4, 5, ...
```

This creates highly compressible memory pages and allows ZSWAP to retain a large amount of original data using relatively little physical memory.

### Incompressible workload

The incompressible workload uses a fixed **64 MiB high-entropy seed**:

```text
incompressible_seed.bin
```

The seed is copied cyclically until the requested workload size is filled.

Using a fixed seed keeps the experiment reproducible while still producing pages that are difficult to compress.

---

## 📏 Tested Workload Sizes

Experiments were performed using memory allocations larger than the VM's available physical RAM.

```text
10 GiB
12 GiB
16 GiB
```

The QEMU guest contains approximately:

```text
RAM:  ~3.8 GiB
Swap: 10–24 GiB depending on experiment series
```

This intentionally creates memory pressure and forces Linux to reclaim pages.

---

## ⚙️ Experimental Environment

The experiments run inside an Ubuntu Server virtual machine using QEMU.

```text
Host
 └── QEMU
      └── Ubuntu Server
           ├── Linux 6.8 kernel
           ├── ZSWAP
           ├── zsmalloc
           ├── swap file
           └── memory_test workload
```

Relevant ZSWAP configuration:

```text
ZSWAP enabled
zpool = zsmalloc
max_pool_percent = 80
vm.swappiness = 80
vm.overcommit_memory = 1
```

---

## 🔬 Experiment Flow

```text
memory_test SIZE TYPE
        │
        ▼
Enable ZSWAP
        │
        ▼
Allocate requested workload
        │
        ▼
Fill memory with selected pattern
        │
        ▼
Memory pressure triggers reclaim
        │
        ▼
Pages may remain in RAM,
enter ZSWAP, or reach backing swap
        │
        ▼
Measurement script collects metrics
        │
        ▼
Calculate compression ratios
```

---

## 📊 Metrics Collected

### Process memory

```text
RSS
```

Collected from:

```text
/proc/<PID>/status
```

RSS represents the portion of the workload still resident in physical RAM.

---

### ZSWAP statistics

Collected from:

```text
/sys/kernel/debug/zswap/
```

Metrics include:

```text
stored_pages
pool_total_size
same_filled_pages
written_back_pages
reject_compress_poor
pool_limit_hit
```

---

### System memory statistics

Collected from:

```text
/proc/meminfo
```

Including:

```text
Zswap
Zswapped
SwapTotal
SwapFree
MemAvailable
```

---

### Cgroup memory statistics

Collected from:

```text
/sys/fs/cgroup/...
```

Including:

```text
memory.current
memory.swap.current
memory.zswap.current
```

---

## 📐 Compression Metrics

### Effective ZSWAP Storage Ratio

The effective ZSWAP storage ratio measures how much original memory is represented by the physical memory consumed by ZSWAP.

```text
Effective ZSWAP Storage Ratio
=
Zswapped Original
──────────────────────
Physical ZSWAP Memory
```

Equivalent Linux fields:

```text
Zswapped / Zswap
```

A larger value indicates that ZSWAP is storing the original pages efficiently.

---

### Backing Swap Used

Backing swap is estimated using:

```text
Backing Swap Used
=
Swap Used - Zswapped Original
```

where:

```text
Swap Used = SwapTotal - SwapFree
```

This separates pages represented inside ZSWAP from pages that are actually occupying backing swap.

---

### Whole-Program Compression Ratio

The whole-program ratio estimates the effective footprint of the complete workload:

```text
Whole-Program Compression Ratio
=
Original Workload Size
──────────────────────────────────────────────
RSS + Physical ZSWAP Memory + Backing Swap Used
```

Unlike the ZSWAP-only ratio, this metric considers the entire workload footprint.

---

## 📈 Example Results

A 16 GiB compressible workload produced:

```text
Original footprint:                 16384 MB
RSS:                              ~3045.59 MB
Physical ZSWAP memory:             ~224.81 MB
Backing swap used:                ~2253.77 MB
Total footprint:                  ~5524.18 MB

Whole-program compression ratio:      2.96:1
Effective ZSWAP storage ratio:        49.74:1
```

A 16 GiB high-entropy workload produced:

```text
Original footprint:                 16384 MB
RSS:                              ~3404.92 MB
Physical ZSWAP memory:              ~50.88 MB
Backing swap used:               ~13028.61 MB
Total footprint:                 ~16484.41 MB

Whole-program compression ratio:      0.99:1
Effective ZSWAP storage ratio:         0.57:1
```

The results show a clear difference between compressible and high-entropy memory.

Highly compressible pages remain effectively represented inside ZSWAP, while high-entropy pages receive very little benefit from memory compression and primarily occupy backing swap.

---

## 🛠️ Build

Compile the benchmark using GCC:

```bash
gcc -g -O0 -o memory_test memory_test.c
```

`-O0` is intentionally used so that the compiler does not optimize away the memory-fill operations used by the benchmark.

---

## ▶️ Running the Benchmark

### Compressible workload

Example: 12 GiB

```bash
sudo -v

systemd-run --user --scope \
  --unit=memory-test-scope \
  bash -c 'echo -500 | sudo tee /proc/$$/oom_score_adj >/dev/null; exec ./memory_test 12288 o'
```

### Incompressible workload

```bash
sudo -v

systemd-run --user --scope \
  --unit=memory-test-scope \
  bash -c 'echo -500 | sudo tee /proc/$$/oom_score_adj >/dev/null; exec ./memory_test 12288 r'
```

Workload types:

```text
o = compressible repeating pattern
r = high-entropy random workload
```

---

## 🗂️ Project Structure

```text
zswap-memory-compression/
│
├── memory_test.c
│   └── Main C workload generator and experiment driver
│
├── test_ones_on.sh
│   └── Collects ZSWAP and memory metrics for compressible workloads
│
├── test_random.sh
│   └── Collects ZSWAP and memory metrics for high-entropy workloads
│
├── incompressible_seed.bin
│   └── Fixed 64 MiB high-entropy seed used for reproducible random workloads
│
├── .gitignore
│   └── Excludes generated binaries and object files
│
└── README.md
```

---

## 🔍 Key Observations

- Highly compressible workloads can achieve very high effective ZSWAP storage ratios.
- High-entropy workloads provide little benefit from ZSWAP compression.
- ZSWAP usage and backing-swap usage must be interpreted separately.
- `written_back_pages` is a cumulative diagnostic counter and should not be treated as current backing-swap occupancy.
- The overall memory footprint must account for resident memory, compressed memory, and backing swap.
- Memory pressure and ZSWAP pool configuration can significantly affect observed behavior.

---

## 🚧 Current Extension

The next stage of this project investigates **proactive memory reclamation**.

The goal is to extend the benchmark beyond passive observation and study whether application-guided memory reclamation can reduce memory pressure while preserving the active working set.

Potential areas include:

```text
Hot vs. cold memory regions
MADV_PAGEOUT
Adaptive reclamation policies
Page-fault overhead
Working-set preservation
VM memory oversubscription
```

---

## 🧰 Technologies

- **C**
- **Linux**
- **ZSWAP**
- **Virtual Memory**
- **QEMU**
- **Bash**
- **cgroup v2**
- **Linux `/proc` and debugfs interfaces**
- **GCC**
- **Git**

---

## 📚 Areas Explored

This project touches several systems topics:

```text
Operating Systems
Virtual Memory
Memory Reclamation
Memory Compression
Swap Management
Linux Kernel Interfaces
Performance Measurement
Resource Management
Virtualization
```

---

## 👩‍💻 Author

**Swara Shinde**

Computer Science  
Virginia Tech

Research interests:

```text
Systems Software
Operating Systems
Linux Memory Management
Computer Architecture
GPU Systems
High-Performance Computing
```
