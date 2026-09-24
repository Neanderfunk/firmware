# Arm E: TLB-Uniquification aus 5.15.209 statt unseres Entfernungs-Patches

Stand 23.09.2026. Liegt bewusst **ausserhalb von `patches/`**, siehe unten.

## Worum es geht

Der Kaltstart-Haenger auf MIPS 74Kc ist in `docs/mips-tlb-kaltstartfehler.md`
beschrieben. Unsere Produktionsloesung
`patches/kernel/999-mips-tlb-r4k-no-uniquify.patch` entfernt den Aufruf von
`r4k_tlb_uniquify()` und stellt damit das Verhalten von 5.15.189 wieder her.
Das wirkt, ist aber eine lokale Abweichung.

**Upstream hat den Fehler inzwischen richtig behoben.** Die Korrektur steht in
**5.15.209** (Greg Kroah-Hartman, 01.06.2026) und besteht aus fuenf Commits:

| # | stable-5.15 | upstream | Titel |
|---|---|---|---|
| 01 | `da0f6cd551dc` | `841ecc979b18` | MIPS: mm: kmalloc tlb_vpn array to avoid stack overflow |
| 02 | `2eadfb3b649e` | `01cc50ea5167` | mips: mm: Allocate tlb_vpn array atomically |
| 03 | `0e39d8dd8762` | `8374c2cb83b9` | MIPS: Always record SEGBITS in cpu_data.vmbits |
| 04 | `88af0913282f` | `74283cfe2163` | MIPS: mm: Suppress TLB uniquification on EHINV hardware |
| 05 | `79ad8f65712f` | `540760b77b8f` | MIPS: mm: Rewrite TLB uniquification for the hidden bit feature |

Nummer 05 traegt `Fixes: 9f048fa48740`, also genau den Commit, von dem unsere
Analyse festhaelt, dass er den Fehler **nicht** behebt. Seine Beschreibung
deckt sich mit unserem Befund: Der Bootloader uebergibt den TLB so, wie er beim
Reset war, mit gesetztem Hidden Bit und moeglicherweise doppelten Eintraegen.
Das Zuruecksetzen der Page Sizes in `r4k_tlb_uniquify()` loest dann eine
Machine Check Exception aus und der Boot bleibt stehen. Rozycki nennt als
Beispiel den Mikrotik RB532. Dazu passt unsere Beobachtung, dass es am Board
haengt und nicht am Kern.

**Das ist nicht unser frueherer Arm D.** Der war ein Backport von vier
6.6-Commits (`231ac951faba`, `43fa022b56dc`, `591f030449ad`, `811b3dccfb0a`);
drei davon kommen in 5.15.209 gar nicht vor.

**Warum es uns nicht aufgefallen ist:** Die Analyse endete bei 5.15.203 und
hat nur in den OpenWrt-Stand geschaut, den **Gluon v2023.2.6** pinnt, und der
traegt `LINUX_VERSION-5.15 = .198`. Der Zweig `openwrt-23.05` selbst war da
laengst weiter: Er hat am 11.07.2026 auf 5.15.211 gehoben, samt Korrektur.
Die fruehere Fassung dieser README behauptete "OpenWrt 23.05 pinnt .198", das
war falsch, es war der Pin von Gluon.

**Damit ist Arm E beim naechsten Bau ueberholt.** Gluon hat die neue Basis am
22.09.2026 in den Zweig v2023.2.x uebernommen (freifunk-gluon/gluon#3841),
Kernel 5.15.211. Wer darauf baut, hat die Korrektur im Kernel und braucht
weder diesen Backport noch den 999er; der 999er muss dann sogar raus, weil er
an Code ansetzt, den 5.15.209 umgeschrieben hat.

## Was geprueft ist

- Die fuenf Patches wenden sich **sauber auf die Originalquellen von
  v5.15.198** an, in dieser Reihenfolge, ohne fuzz und ohne Reject (23.09.2026,
  gegen die sechs betroffenen Dateien aus dem stable-Git).
- **Kein OpenWrt-Patch aus 23.05 fasst dieselben Dateien an.** Der einzige
  MIPS-Treffer in `backport-5.15` (`330-v5.16-02`) arbeitet an
  `arch/mips/kernel/proc.c`.
- Betroffen sind `arch/mips/mm/tlb-r4k.c` (viermal),
  `arch/mips/kernel/cpu-probe.c`, `cpu-r3k-probe.c` sowie die Header
  `cpu-features.h`, `cpu-info.h` und `mipsregs.h`.

Nicht geprueft: dass es auch **kompiliert** und dass es das Geraet **bootet**.
Genau dafuer ist der Arm da.

## So wird daraus ein Lauf

1. `mips-tlb-arm-e.sh` und die fuenf `.patch`-Dateien nach `patches/kernel/`
   kopieren.
2. In `templates/common/prepare.sh` die Zeile
   `run_patch kernel/revert-mips-tlb-uniquify.sh ...` **ersetzen** durch
   `run_patch kernel/mips-tlb-arm-e.sh "MIPS: TLB-Uniquification aus 5.15.209 (Arm E)"`.
   Beide zusammen gehen nicht: Patch 04 setzt an dem Aufruf an, den der 999er
   entfernt.
3. Einen Lauf fuer **ath79-generic** bauen, eine Domain genuegt.

**Warum die Dateien hier liegen und nicht schon in `patches/`:**
`golden_fingerprint()` in `build.sh` hasht jede Datei unter `patches/` und
`templates/common`. Jede Datei dort, auch eine ungenutzte, verwirft den
Golden Tree und kostet den vollen Basisbau. Deshalb wandern sie erst dann
hinueber, wenn der Arm wirklich gebaut wird.

## Messung

Dieselbe Groesse wie bei Arm B, damit die Zahlen vergleichbar bleiben:
Kaltstarts ueber die fernschaltbare Dose, Image per TFTP ins RAM, der Flash
bleibt unangetastet. 20 Kaltstarts.

Referenzwerte aus `docs/mips-tlb-kaltstartfehler.md`:

| Arm | Kernel | TL-WR1043ND v2 |
|---|---|---|
| A | 5.15.198 ungepatcht | **0 von 20** |
| B | 5.15.198 mit 999er | 20 von 20 |
| E | 5.15.198 mit diesen fuenf | offen |

Geraet: **TL-WR1043ND v2 (QCA9558, 74Kc, 64 MB)**. Der Archer C25 waere der
zweite Beleg, ist aber seit 17.09.2026 Ersatzteilspender.

Faellt Arm E mit 20 von 20 aus, ersetzt er den 999er dauerhaft, und wir
tragen den Fehler nicht mehr als Eigenbau mit.
