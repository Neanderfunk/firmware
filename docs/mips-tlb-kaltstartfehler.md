# MIPS TLB: cold start failure on kernels 5.15.190 to 5.15.203

Findings, measurements and the possible fixes. Last updated 2026-09-24.

## The bug

`35ad7e181541` ("MIPS: mm: tlb-r4k: Uniquify TLB entries on init"), present
from 5.15.190 onwards, calls `r4k_tlb_uniquify()` from `r4k_tlb_configure()`.
That function operates on whatever the bootloader left behind in the TLB. On
affected boards this results in a TLB shutdown.

Where it happens in the boot path:

```
init/main.c:1008   vfs_caches_init_early()   last output before the hang
init/main.c:1009   sort_main_extable()
init/main.c:1010   trap_init() -> traps.c:2309 tlb_init()
init/main.c:1011   mm_init()                 would print "Memory: ..."
```

**Cold start only.** After a warm restart the TLB has already been uniquified.
Affected devices therefore survive any number of sysupgrades and fail to come
back after a power cut.

`9f048fa48740` (in 5.15.197) does not fix it. Nothing further landed up to
5.15.203. The real fix arrived later, in **5.15.209**, see arm E below.

## What has been measured

Cold starts over a remotely switched mains socket, images loaded over TFTP into
RAM, so the flash stayed untouched.

| Device | SoC | Core | RAM | unpatched | patched |
| --- | --- | --- | ---: | --- | --- |
| TP-Link Archer C25 v1 | QCA956X | 74Kc | 64 MB | **0 of 21** | 21 of 21 |
| TP-Link TL-WR1043ND v2 | QCA9558 | 74Kc | 64 MB | **0 of 20** | 20 of 20 |
| TP-Link TL-WDR3600 v1 | AR9344 | 74Kc | 128 MB | 11 of 11 | - |
| Ubiquiti EdgeRouter X | MT7621 | 1004Kc | 256 MB | 11 of 11 | - |
| Xiaomi Mi Router 4A Gigabit | MT7621 | 1004Kc | 128 MB | 11 of 11 | - |

Both 5.15.198 arms come from the same build tree and differ only by the patch.

**The CPU core predicts nothing.** The WDR3600 is a 74Kc just like the two
affected devices and boots 11 of 11. The behaviour is deterministic per device,
not per core, which fits the mechanism: what the bootloader leaves in the TLB
differs from board to board.

An observation without proof: both affected devices have 64 MB of RAM, all
unaffected ones have more. With five devices that is not an explanation.

## Scope

Outage in March 2026, 57 nodes:

| Count | Target | SoC | Core |
| ---: | --- | --- | --- |
| 50 | ath79 | qca9563 / qca9558 / ar9344 | 74Kc |
| 4 | ath79 | ar7241 | 24Kc |
| 2 | lantiq | vr9 | 34Kc |
| 1 | ramips | mt7628an | 24KEc |

No non-MIPS node was affected. The patch therefore lives under
`target/linux/generic/`: `tlb-r4k.c` is built for every r4k-class MIPS core,
and restricting it to a single target would be guesswork.

## The candidate fixes

All of them address the same bug on the same kernel with the same outcome.

| Arm | | booted | hung |
|---|---|---:|---:|
| A | 5.15.198, no TLB patch | 0 | 21 |
| B | 5.15.198 with the arm B patch | 21 | 0 |
| C | 6.6.144 (OpenWrt 24.10.8) | 21 | 0 |
| D | 5.15.198, 6.6 solution backported | 20 | 0 |
| **E** | **5.15.198 with the 5.15.209 backport** | **20** | **0** |

Arms A to D were measured on the Archer C25 v1 in September 2026. **Arm E was
measured on 2026-09-23 on the TL-WR1043ND v2**, together with two controls from
the same rig, which is what makes the run trustworthy: a build without any TLB
patch hung 3 of 3, and the shipping release `26091920sta`, which carries the
arm B patch, booted 3 of 3. So the rig detects both states, and none of the 26
runs was lost to the test setup.

They differ in size:

| | Arm B | Arm D | Arm E |
|---|---:|---:|---:|
| changed lines of code | 3 | 277 | 330 |
| hunks | 2 | 7 | 13 |
| files | 1 | 5 | 6 |

Arm D and arm E touch:

```
arch/mips/include/asm/cpu-features.h   (E only)
arch/mips/include/asm/cpu-info.h
arch/mips/include/asm/mipsregs.h
arch/mips/kernel/cpu-probe.c
arch/mips/kernel/cpu-r3k-probe.c
arch/mips/mm/tlb-r4k.c
```

Arm B only changes `tlb-r4k.c`. Arms D and E also touch CPU detection and thus
sit in the boot path of every MIPS device, not just the affected ones. What is
measured is 20 cold starts on one device model: enough to show the fix works,
not enough to rule out regressions across the rest of the fleet.

The four 6.6 commits arm D is based on: `231ac951faba`, `43fa022b56dc`,
`591f030449ad`, `811b3dccfb0a`. The last one is a rewrite and depends on
`current_cpu_data.vmbits`, `VPN2_SHIFT`, `struct tlbent`, `memblock_alloc_raw`
and `slab_is_available`, none of which exist in the 5.15 file.

## Arm E: what upstream actually did

**This is the one to use.** Arm E is not our own backport but the stable series
from **5.15.209**, released 2026-06-01. Five commits:

| # | stable 5.15 | upstream | Title |
|---|---|---|---|
| 01 | `da0f6cd551dc` | `841ecc979b18` | MIPS: mm: kmalloc tlb_vpn array to avoid stack overflow |
| 02 | `2eadfb3b649e` | `01cc50ea5167` | mips: mm: Allocate tlb_vpn array atomically |
| 03 | `0e39d8dd8762` | `8374c2cb83b9` | MIPS: Always record SEGBITS in cpu_data.vmbits |
| 04 | `88af0913282f` | `74283cfe2163` | MIPS: mm: Suppress TLB uniquification on EHINV hardware |
| 05 | `79ad8f65712f` | `540760b77b8f` | MIPS: mm: Rewrite TLB uniquification for the hidden bit feature |

Number 05 carries `Fixes: 9f048fa48740`, that is exactly the commit which this
document records as insufficient. Its description matches our findings: the
bootloader hands over the TLB as it was at reset, with the hidden bit set and
possibly duplicate entries; resetting the page sizes in `r4k_tlb_uniquify()`
then raises a machine check exception and the boot stops. Rozycki names the
Mikrotik RB532 as an example. That fits our observation that the failure
depends on the board and not on the core.

**Note this is not arm D.** Three of arm D's four 6.6 commits do not appear in
5.15.209 at all.

**Why we missed it:** the analysis stopped at 5.15.203 and only ever looked
at the OpenWrt tree that **Gluon v2023.2.6** pins, commit `7f61f96255`, which
carries `LINUX_VERSION-5.15 = .198`. That was not the state of OpenWrt 23.05
itself: the `openwrt-23.05` branch went from 5.15.201 all the way to 5.15.211 on
2026-07-11, fix included, two months before this analysis. An earlier version
of this document claimed "OpenWrt 23.05 pins .198"; that was wrong, it was
Gluon's pin.

**Gluon has since caught up.** freifunk-gluon/gluon#3841, merged into the
`v2023.2.x` branch on 2026-09-22, moves the pin to `33063b4ccf` and thus to
5.15.211. There is no tagged release with it yet; the branch sits three
commits after v2023.2.6.

The five patches apply cleanly to v5.15.198, in that order, without fuzz and
without a reject, and no OpenWrt 23.05 patch touches the same files. They live
in `experiments/mips-tlb-arm-e/` together with an installer script; see the
README there for how to turn them into a build.

### Arm B in full

```diff
From: Freifunk im Neanderland <projekt@neanderfunk.de>
Subject: MIPS: tlb-r4k: drop the call to r4k_tlb_uniquify()

5.15.198 hangs in tlb_init() on every cold start of a TP-Link Archer C25 v1
(QCA956X). 63 cold starts, mains switched remotely, images loaded over TFTP
into RAM so the flash stayed untouched:

  5.15.198 stock             0 of 21 booted
  5.15.198 with this patch  21 of 21 booted
  6.6.144 (OpenWrt 24.10.8) 21 of 21 booted

Both 5.15.198 arms come from the same build tree and differ only by this patch.
Also reproduced on a TL-WR1043ND v2 (QCA9558).

Which boards are hit cannot be predicted from the CPU core. Unpatched 5.15.198
booted 11 of 11 cold starts on each of a TL-WDR3600 v1 (AR9344, also 74Kc), a
Ubiquiti EdgeRouter X and a Xiaomi Mi Router 4A Gigabit (both MT7621, 1004Kc).
The behaviour is deterministic per device but not per core, which fits the
mechanism: r4k_tlb_uniquify() operates on what the bootloader left in the TLB,
and that differs per board.

This reverts the call added in 5.15.190 by 35ad7e181541 ("MIPS: mm: tlb-r4k:
Uniquify TLB entries on init"), restoring 5.15.189 behaviour. The last output
before the hang comes from vfs_caches_init_early(), the next would come from
mm_init(); trap_init() sits between them and reaches r4k_tlb_uniquify() via
tlb_init() and r4k_tlb_configure().

Cold start only: the function operates on whatever the bootloader left in the
TLB - arbitrary on power-up, already uniquified after a warm reset. From the
follow-up 9f048fa48740, which is in 5.15.197 and does not suffice here: "a TLB
shutdown may occur if multiple matching entries are detected ... Given that we
don't know what entries we have been handed". Devices therefore survive any
number of sysupgrades and never come back after a power cut.

Nothing further landed in 5.15 through .203. The 6.6 line received four more
commits (231ac951faba, 43fa022b56dc, 591f030449ad, 811b3dccfb0a), the last a
rewrite depending on current_cpu_data.vmbits, VPN2_SHIFT, struct tlbent,
memblock_alloc_raw and slab_is_available - none of them present in the 5.15
file, so backporting was rejected. 35ad7e181541 addresses microAptiv/M5150,
cores we do not deploy.

Under target/linux/generic/ because tlb-r4k.c is built for every r4k-class MIPS
core: our March 2026 outage hit 57 nodes across ath79 (74Kc and 24Kc), lantiq
(34Kc) and ramips (24KEc), and no non-MIPS node at all. Since affected boards
cannot be told apart by their core, restricting the patch to one target would
be guesswork.

Drop this on Gluon 2025.1.1 or newer, whose 6.6.144 measured clean above - but
not on v2025.1, which carries 6.6.119.

--- a/arch/mips/mm/tlb-r4k.c
+++ b/arch/mips/mm/tlb-r4k.c
@@ -512,7 +512,7 @@ static int r4k_vpn_cmp(const void *a, co
  * Initialise all TLB entries with unique values that do not clash with
  * what we have been handed over and what we'll be using ourselves.
  */
-static void r4k_tlb_uniquify(void)
+static void __maybe_unused r4k_tlb_uniquify(void)
 {
 	unsigned long tlb_vpns[1 << MIPS_CONF1_TLBS_SIZE];
 	int tlbsize = current_cpu_data.tlbsize;
@@ -616,7 +616,6 @@ static void r4k_tlb_configure(void)
 	temp_tlb_entry = current_cpu_data.tlbsize - 1;
 
 	/* From this point on the ARC firmware is dead.	 */
-	r4k_tlb_uniquify();
 	local_flush_tlb_all();
 
 	/* Did I tell you that ARC SUCKS?  */
```

### Arm D in full

```diff
From: Neanderfunk build environment
Subject: [PATCH] MIPS: backport the 6.6 TLB uniquification to 5.15

PROOF OF CONCEPT -- not in use. Our production patch
999-mips-tlb-r4k-no-uniquify.patch removes the call to r4k_tlb_uniquify()
instead. This one brings the 6.6 implementation over, to show what that
would cost.

Background: 35ad7e181541 ("MIPS: mm: tlb-r4k: Uniquify TLB entries on
init") entered 5.15.190 and hangs several ath79 boards on every cold
start. 9f048fa48740 followed in 5.15.197 and does not suffice: measured
0 of 21 cold starts on a TP-Link Archer C25 v1 and 0 of 20 on a
TL-WR1043ND v2, both running 5.15.198, which contains that fix. Nothing
further has landed up to 5.15.203. The 6.6 line received four more
commits and boots cleanly (21 of 21 on the C25 with 6.6.144).

The interesting part is not the copied code but the preconditions. Three
had to be met, and each one is a separate upstream change:

 1. read_c0_entryhi_64()/write_c0_entryhi_64() do not exist in 5.15.
    Added to mipsregs.h on top of the existing 64-bit accessors.

 2. memblock_free() takes a pointer only from 5.17 onwards; in 5.15 the
    function is called memblock_free_ptr(). Renamed.

 3. cpuinfo_mips.vmbits sits behind #ifdef CONFIG_64BIT in 5.15, so on
    every 32-bit board -- which is all of ours -- the field does not
    exist at all. Exposing it is not enough: nothing would fill it. 6.6
    defaults it to 31 and only probes it on 64-bit CPUs, so
    cpu_probe_vmbits() had to be taken over as well, and the R3000 path
    sets it explicitly.

Deliberately NOT taken over: the pte_offset_map()/pte_unmap() changes
around update_mmu_cache(), which are unrelated 6.6 drift.

Compile-tested for mips_24kc (ath79-generic, gcc 12.3.0): tlb-r4k.o and
cpu-probe.o build without warnings. NOT tested on hardware.

--- a/arch/mips/include/asm/cpu-info.h	2026-09-08 22:13:23.218937683 +0200
+++ b/arch/mips/include/asm/cpu-info.h	2026-09-08 22:13:03.127811155 +0200
@@ -80,9 +80,7 @@
 	int			srsets; /* Shadow register sets */
 	int			package;/* physical package number */
 	unsigned int		globalnumber;
-#ifdef CONFIG_64BIT
 	int			vmbits; /* Virtual memory size in bits */
-#endif
 	void			*data;	/* Additional data */
 	unsigned int		watch_reg_count;   /* Number that exist */
 	unsigned int		watch_reg_use_cnt; /* Usable by ptrace */
--- a/arch/mips/include/asm/mipsregs.h	2026-09-08 22:13:23.218445579 +0200
+++ b/arch/mips/include/asm/mipsregs.h	2026-09-08 22:13:03.122393496 +0200
@@ -1719,6 +1719,8 @@
 
 #define read_c0_entryhi()	__read_ulong_c0_register($10, 0)
 #define write_c0_entryhi(val)	__write_ulong_c0_register($10, 0, val)
+#define read_c0_entryhi_64()	__read_64bit_c0_register($10, 0)
+#define write_c0_entryhi_64(val) __write_64bit_c0_register($10, 0, val)
 
 #define read_c0_guestctl1()	__read_32bit_c0_register($10, 4)
 #define write_c0_guestctl1(val)	__write_32bit_c0_register($10, 4, val)
--- a/arch/mips/kernel/cpu-probe.c	2026-09-08 22:13:23.222288965 +0200
+++ b/arch/mips/kernel/cpu-probe.c	2026-09-08 22:13:03.133496044 +0200
@@ -208,11 +208,14 @@
 
 static inline void cpu_probe_vmbits(struct cpuinfo_mips *c)
 {
-#ifdef __NEED_VMBITS_PROBE
-	write_c0_entryhi(0x3fffffffffffe000ULL);
-	back_to_back_c0_hazard();
-	c->vmbits = fls64(read_c0_entryhi() & 0x3fffffffffffe000ULL);
-#endif
+	int vmbits = 31;
+
+	if (cpu_has_64bits) {
+		write_c0_entryhi_64(0x3fffffffffffe000ULL);
+		back_to_back_c0_hazard();
+		vmbits = fls64(read_c0_entryhi_64() & 0x3fffffffffffe000ULL);
+	}
+	c->vmbits = vmbits;
 }
 
 static void set_isa(struct cpuinfo_mips *c, unsigned int isa)
--- a/arch/mips/kernel/cpu-r3k-probe.c	2026-09-08 22:13:23.223856584 +0200
+++ b/arch/mips/kernel/cpu-r3k-probe.c	2026-09-08 22:13:03.138926977 +0200
@@ -160,6 +160,8 @@
 	else
 		cpu_set_nofpu_opts(c);
 
+	c->vmbits = 31;
+
 	reserve_exception_space(0, 0x400);
 }
 
--- a/arch/mips/mm/tlb-r4k.c	2026-09-08 22:13:23.216519647 +0200
+++ b/arch/mips/mm/tlb-r4k.c	2026-09-08 22:13:03.116808705 +0200
@@ -12,6 +12,8 @@
 #include <linux/init.h>
 #include <linux/sched.h>
 #include <linux/smp.h>
+#include <linux/memblock.h>
+#include <linux/minmax.h>
 #include <linux/mm.h>
 #include <linux/hugetlb.h>
 #include <linux/export.h>
@@ -23,6 +25,7 @@
 #include <asm/hazards.h>
 #include <asm/mmu_context.h>
 #include <asm/tlb.h>
+#include <asm/tlbdebug.h>
 #include <asm/tlbmisc.h>
 
 extern void build_tlb_refill_handler(void);
@@ -500,81 +503,266 @@
 __setup("ntlb=", set_ntlb);
 
 
-/* Comparison function for EntryHi VPN fields.  */
-static int r4k_vpn_cmp(const void *a, const void *b)
+/* The start bit position of VPN2 and Mask in EntryHi/PageMask registers.  */
+#define VPN2_SHIFT 13
+
+/* Read full EntryHi even with CONFIG_32BIT.  */
+static inline unsigned long long read_c0_entryhi_native(void)
+{
+	return cpu_has_64bits ? read_c0_entryhi_64() : read_c0_entryhi();
+}
+
+/* Write full EntryHi even with CONFIG_32BIT.  */
+static inline void write_c0_entryhi_native(unsigned long long v)
 {
-	long v = *(unsigned long *)a - *(unsigned long *)b;
-	int s = sizeof(long) > sizeof(int) ? sizeof(long) * 8 - 1: 0;
-	return s ? (v != 0) | v >> s : v;
+	if (cpu_has_64bits)
+		write_c0_entryhi_64(v);
+	else
+		write_c0_entryhi(v);
 }
 
+/* TLB entry state for uniquification.  */
+struct tlbent {
+	unsigned long long wired:1;
+	unsigned long long global:1;
+	unsigned long long asid:10;
+	unsigned long long vpn:51;
+	unsigned long long pagesz:5;
+	unsigned long long index:14;
+};
+
 /*
- * Initialise all TLB entries with unique values that do not clash with
- * what we have been handed over and what we'll be using ourselves.
+ * Comparison function for TLB entry sorting.  Place wired entries first,
+ * then global entries, then order by the increasing VPN/ASID and the
+ * decreasing page size.  This lets us avoid clashes with wired entries
+ * easily and get entries for larger pages out of the way first.
+ *
+ * We could group bits so as to reduce the number of comparisons, but this
+ * is seldom executed and not performance-critical, so prefer legibility.
  */
-static void r4k_tlb_uniquify(void)
+static int r4k_entry_cmp(const void *a, const void *b)
 {
-	unsigned long tlb_vpns[1 << MIPS_CONF1_TLBS_SIZE];
-	int tlbsize = current_cpu_data.tlbsize;
-	int start = num_wired_entries();
-	unsigned long vpn_mask;
-	int cnt, ent, idx, i;
-
-	vpn_mask = GENMASK(cpu_vmbits - 1, 13);
-	vpn_mask |= IS_ENABLED(CONFIG_64BIT) ? 3ULL << 62 : 1 << 31;
+	struct tlbent ea = *(struct tlbent *)a, eb = *(struct tlbent *)b;
 
-	htw_stop();
+	if (ea.wired > eb.wired)
+		return -1;
+	else if (ea.wired < eb.wired)
+		return 1;
+	else if (ea.global > eb.global)
+		return -1;
+	else if (ea.global < eb.global)
+		return 1;
+	else if (ea.vpn < eb.vpn)
+		return -1;
+	else if (ea.vpn > eb.vpn)
+		return 1;
+	else if (ea.asid < eb.asid)
+		return -1;
+	else if (ea.asid > eb.asid)
+		return 1;
+	else if (ea.pagesz > eb.pagesz)
+		return -1;
+	else if (ea.pagesz < eb.pagesz)
+		return 1;
+	else
+		return 0;
+}
 
-	for (i = start, cnt = 0; i < tlbsize; i++, cnt++) {
-		unsigned long vpn;
+/*
+ * Fetch all the TLB entries.  Mask individual VPN values retrieved with
+ * the corresponding page mask and ignoring any 1KiB extension as we'll
+ * be using 4KiB pages for uniquification.
+ */
+static void __ref r4k_tlb_uniquify_read(struct tlbent *tlb_vpns, int tlbsize)
+{
+	int start = num_wired_entries();
+	unsigned long long vpn_mask;
+	bool global;
+	int i;
+
+	vpn_mask = GENMASK(current_cpu_data.vmbits - 1, VPN2_SHIFT);
+	vpn_mask |= cpu_has_64bits ? 3ULL << 62 : 1 << 31;
+
+	for (i = 0; i < tlbsize; i++) {
+		unsigned long long entryhi, vpn, mask, asid;
+		unsigned int pagesz;
 
 		write_c0_index(i);
 		mtc0_tlbr_hazard();
 		tlb_read();
 		tlb_read_hazard();
-		vpn = read_c0_entryhi();
-		vpn &= vpn_mask & PAGE_MASK;
-		tlb_vpns[cnt] = vpn;
 
-		/* Prevent any large pages from overlapping regular ones.  */
-		write_c0_pagemask(read_c0_pagemask() & PM_DEFAULT_MASK);
-		mtc0_tlbw_hazard();
-		tlb_write_indexed();
-		tlbw_use_hazard();
+		global = !!(read_c0_entrylo0() & ENTRYLO_G);
+		entryhi = read_c0_entryhi_native();
+		mask = read_c0_pagemask();
+
+		asid = entryhi & cpu_asid_mask(&current_cpu_data);
+		vpn = (entryhi & vpn_mask & ~mask) >> VPN2_SHIFT;
+		pagesz = ilog2((mask >> VPN2_SHIFT) + 1);
+
+		tlb_vpns[i].global = global;
+		tlb_vpns[i].asid = global ? 0 : asid;
+		tlb_vpns[i].vpn = vpn;
+		tlb_vpns[i].pagesz = pagesz;
+		tlb_vpns[i].wired = i < start;
+		tlb_vpns[i].index = i;
 	}
+}
 
-	sort(tlb_vpns, cnt, sizeof(tlb_vpns[0]), r4k_vpn_cmp, NULL);
+/*
+ * Write unique values to all but the wired TLB entries each, using
+ * the 4KiB page size.  This size might not be supported with R6, but
+ * EHINV is mandatory for R6, so we won't ever be called in that case.
+ *
+ * A sorted table is supplied with any wired entries at the beginning,
+ * followed by any global entries, and then finally regular entries.
+ * We start at the VPN and ASID values of zero and only assign user
+ * addresses, therefore guaranteeing no clash with addresses produced
+ * by UNIQUE_ENTRYHI.  We avoid any VPN values used by wired or global
+ * entries, by increasing the VPN value beyond the span of such entry.
+ *
+ * When a VPN/ASID clash is found with a regular entry we increment the
+ * ASID instead until no VPN/ASID clash has been found or the ASID space
+ * has been exhausted, in which case we increase the VPN value beyond
+ * the span of the largest clashing entry.
+ *
+ * We do not need to be concerned about FTLB or MMID configurations as
+ * those are required to implement the EHINV feature.
+ */
+static void __ref r4k_tlb_uniquify_write(struct tlbent *tlb_vpns, int tlbsize)
+{
+	unsigned long long asid, vpn, vpn_size, pagesz;
+	int widx, gidx, idx, sidx, lidx, i;
 
-	write_c0_pagemask(PM_DEFAULT_MASK);
+	vpn_size = 1ULL << (current_cpu_data.vmbits - VPN2_SHIFT);
+	pagesz = ilog2((PM_4K >> VPN2_SHIFT) + 1);
+
+	write_c0_pagemask(PM_4K);
 	write_c0_entrylo0(0);
 	write_c0_entrylo1(0);
 
-	idx = 0;
-	ent = tlbsize;
-	for (i = start; i < tlbsize; i++)
-		while (1) {
-			unsigned long entryhi, vpn;
+	asid = 0;
+	vpn = 0;
+	widx = 0;
+	gidx = 0;
+	for (sidx = 0; sidx < tlbsize && tlb_vpns[sidx].wired; sidx++)
+		;
+	for (lidx = sidx; lidx < tlbsize && tlb_vpns[lidx].global; lidx++)
+		;
+	idx = gidx = sidx + 1;
+	for (i = sidx; i < tlbsize; i++) {
+		unsigned long long entryhi, vpn_pagesz = 0;
 
-			entryhi = UNIQUE_ENTRYHI(ent);
-			vpn = entryhi & vpn_mask & PAGE_MASK;
+		while (1) {
+			if (WARN_ON(vpn >= vpn_size)) {
+				dump_tlb_all();
+				/* Pray local_flush_tlb_all() will cope.  */
+				return;
+			}
 
-			if (idx >= cnt || vpn < tlb_vpns[idx]) {
-				write_c0_entryhi(entryhi);
-				write_c0_index(i);
-				mtc0_tlbw_hazard();
-				tlb_write_indexed();
-				ent++;
-				break;
-			} else if (vpn == tlb_vpns[idx]) {
-				ent++;
-			} else {
+			/* VPN must be below the next wired entry.  */
+			if (widx < sidx && vpn >= tlb_vpns[widx].vpn) {
+				vpn = max(vpn,
+					  (tlb_vpns[widx].vpn +
+					   (1ULL << tlb_vpns[widx].pagesz)));
+				asid = 0;
+				widx++;
+				continue;
+			}
+			/* VPN must be below the next global entry.  */
+			if (gidx < lidx && vpn >= tlb_vpns[gidx].vpn) {
+				vpn = max(vpn,
+					  (tlb_vpns[gidx].vpn +
+					   (1ULL << tlb_vpns[gidx].pagesz)));
+				asid = 0;
+				gidx++;
+				continue;
+			}
+			/* Try to find a free ASID so as to conserve VPNs.  */
+			if (idx < tlbsize && vpn == tlb_vpns[idx].vpn &&
+			    asid == tlb_vpns[idx].asid) {
+				unsigned long long idx_pagesz;
+
+				idx_pagesz = tlb_vpns[idx].pagesz;
+				vpn_pagesz = max(vpn_pagesz, idx_pagesz);
+				do
+					idx++;
+				while (idx < tlbsize &&
+				       vpn == tlb_vpns[idx].vpn &&
+				       asid == tlb_vpns[idx].asid);
+				asid++;
+				if (asid > cpu_asid_mask(&current_cpu_data)) {
+					vpn += vpn_pagesz;
+					asid = 0;
+					vpn_pagesz = 0;
+				}
+				continue;
+			}
+			/* VPN mustn't be above the next regular entry.  */
+			if (idx < tlbsize && vpn > tlb_vpns[idx].vpn) {
+				vpn = max(vpn,
+					  (tlb_vpns[idx].vpn +
+					   (1ULL << tlb_vpns[idx].pagesz)));
+				asid = 0;
 				idx++;
+				continue;
 			}
+			break;
 		}
 
+		entryhi = (vpn << VPN2_SHIFT) | asid;
+		write_c0_entryhi_native(entryhi);
+		write_c0_index(tlb_vpns[i].index);
+		mtc0_tlbw_hazard();
+		tlb_write_indexed();
+
+		tlb_vpns[i].asid = asid;
+		tlb_vpns[i].vpn = vpn;
+		tlb_vpns[i].pagesz = pagesz;
+
+		asid++;
+		if (asid > cpu_asid_mask(&current_cpu_data)) {
+			vpn += 1ULL << pagesz;
+			asid = 0;
+		}
+	}
+}
+
+/*
+ * Initialise all TLB entries with unique values that do not clash with
+ * what we have been handed over and what we'll be using ourselves.
+ */
+static void __ref r4k_tlb_uniquify(void)
+{
+	int tlbsize = current_cpu_data.tlbsize;
+	bool use_slab = slab_is_available();
+	phys_addr_t tlb_vpn_size;
+	struct tlbent *tlb_vpns;
+
+	tlb_vpn_size = tlbsize * sizeof(*tlb_vpns);
+	tlb_vpns = (use_slab ?
+		    kmalloc(tlb_vpn_size, GFP_ATOMIC) :
+		    memblock_alloc_raw(tlb_vpn_size, sizeof(*tlb_vpns)));
+	if (WARN_ON(!tlb_vpns))
+		return; /* Pray local_flush_tlb_all() is good enough. */
+
+	htw_stop();
+
+	r4k_tlb_uniquify_read(tlb_vpns, tlbsize);
+
+	sort(tlb_vpns, tlbsize, sizeof(*tlb_vpns), r4k_entry_cmp, NULL);
+
+	r4k_tlb_uniquify_write(tlb_vpns, tlbsize);
+
+	write_c0_pagemask(PM_DEFAULT_MASK);
+
 	tlbw_use_hazard();
 	htw_start();
 	flush_micro_tlb();
+	if (use_slab)
+		kfree(tlb_vpns);
+	else
+		memblock_free_ptr(tlb_vpns, tlb_vpn_size);
 }
 
 /*
```

## Result

`patches/kernel/999-mips-tlb-r4k-no-uniquify.patch` takes the call back out and
restores the behaviour of 5.15.189. Across both affected devices that is
**0 of 41** cold starts unpatched against **41 of 41** patched. This is what
ships today, in `26091920sta`.

**It is no longer the best answer.** Upstream fixed the bug properly in
5.15.209, and arm E carries that fix: 20 of 20 cold starts on the
TL-WR1043ND v2, measured against two controls from the same rig. Removing a
call is a local deviation we have to keep explaining; the upstream rewrite is
the thing everyone else will be running. The open question is not whether it
works on the affected boards but whether it is free of regressions on the rest
of the MIPS fleet, since arms D and E also touch CPU detection. That is a
question of coverage, not of this measurement.

**What this means for the next build.** Moving to the current `v2023.2.x`
base brings 5.15.211 and with it the upstream fix. At that point the arm B
patch **must go**, not just may: it removes a call in `r4k_tlb_configure()`,
a part of `tlb-r4k.c` that 5.15.209 rewrote, so it either no longer applies or
would switch off the corrected code. Arm E becomes unnecessary for the same
reason, the kernel already contains it. Worth one cold start run on the
TL-WR1043ND v2 with the first build on the new base, as a check that nothing
else in the bump undoes the fix.

From Gluon 2025.1.1 onwards the patch can go entirely, since that runs 6.6.144,
measured above at 21 of 21. Not on v2025.1 itself, which carries 6.6.119.
