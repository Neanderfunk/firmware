#!/bin/bash
#
# Arm E: die fuenf MIPS-mm-Commits aus 5.15.209 statt unseres Holzhammers.
#
# Unser Produktionspatch 999-mips-tlb-r4k-no-uniquify.patch nimmt den Aufruf
# von r4k_tlb_uniquify() heraus. Upstream hat den Fehler inzwischen richtig
# behoben, veroeffentlicht in 5.15.209 (01.06.2026). OpenWrt 23.05 pinnt
# 5.15.198 und bekommt davon nichts mit, deshalb dieser Backport.
#
# Der entscheidende Commit ist 540760b77b8f "MIPS: mm: Rewrite TLB
# uniquification for the hidden bit feature" (Fixes: 9f048fa48740). Er
# beschreibt genau unseren Fall: Der Bootloader uebergibt den TLB so, wie er
# beim Reset war, mit gesetztem Hidden Bit und moeglichen Doppeleintraegen;
# das Zuruecksetzen der Page Sizes in r4k_tlb_uniquify() loest dann eine
# Machine Check Exception aus und der Boot bleibt stehen.
#
# ACHTUNG: Arm E und der 999er schliessen sich aus. 04 setzt am selben
# Aufruf an, den der 999er entfernt. Vor dem Lauf also in
# templates/common/prepare.sh die Zeile
#   run_patch kernel/revert-mips-tlb-uniquify.sh ...
# durch diesen Aufruf ersetzen, nicht ergaenzen.
#
# Die fuenf Patches wenden sich sauber auf v5.15.198 an, gegen die
# Originalquellen geprueft am 23.09.2026, ohne fuzz und ohne Reject. Kein
# OpenWrt-Patch aus 23.05 fasst dieselben Dateien an; der einzige MIPS-Treffer
# in backport-5.15 (330-v5.16-02) arbeitet an arch/mips/kernel/proc.c.
#
# Messgroesse ist dieselbe wie bei Arm B: Kaltstarts ueber die schaltbare
# Dose, Image per TFTP ins RAM, Flash unangetastet. Ungepatchtes 5.15.198
# bootet auf dem TL-WR1043ND v2 in 0 von 20 Faellen.
#
. "$(dirname "${BASH_SOURCE[0]}")/../lib-patch.sh"

echo "MIPS: TLB-Uniquification aus 5.15.209 backporten (Arm E)"

enter_dir openwrt

for PATCHDATEI in \
  332-v6.18-01-MIPS-mm-kmalloc-tlb_vpn-array-to-avoid-stack-overflow.patch \
  332-v6.18-02-mips-mm-Allocate-tlb_vpn-array-atomically.patch \
  332-v6.18-03-MIPS-Always-record-SEGBITS-in-cpu_data-vmbits.patch \
  332-v6.18-04-MIPS-mm-Suppress-TLB-uniquification-on-EHINV-hardware.patch \
  332-v6.18-05-MIPS-mm-Rewrite-TLB-uniquification-for-the-hidden-bit.patch
do
  copy_into_tree "$PATCH_DIR/$PATCHDATEI" \
    "target/linux/generic/backport-5.15/$PATCHDATEI"
done
