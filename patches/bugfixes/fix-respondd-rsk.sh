#!/bin/bash
#
# Setzt die respondd-Listener-Adresse auf den Wert von Gluon 2016.x zurueck.
#
# Was sich aendert: respondd lauscht auf ff02::1 und ff02::2:1001, jeweils auf
# den Mesh- und den Client-Schnittstellen. Gluon selbst sieht seit 2021.x
# ff02::2:1001 auf den Mesh-Schnittstellen und ff05::2:1001 auf den
# Client-Schnittstellen vor.
#
# Warum: Der Patch ist fuer die aeltere unserer beiden Karten da, nicht fuer die
# Knoten. Deren Abfrage-VM hat netzwerkseitig keine Schnittstelle in den
# Client-Netzen der Domains und kann respondd-Anfragen deshalb nicht auf der
# Schnittstelle senden, die Gluon seit 2021.x dafuer vorsieht. Die Adressen von
# Gluon 2016.x sind die Umgehung dafuer.
#
# Damit ist er an diese eine Abfrage gebunden: Braucht die aeltere Karte sie
# nicht mehr, ist zu pruefen, ob der Patch ersatzlos entfallen kann.
#
# Wird aus dem Gluon-Verzeichnis heraus aufgerufen, so wie prepare.sh es tut:
#   pushd ../gluon ; ../patches/bugfixes/fix-respondd-rsk.sh ; popd

. "$(dirname "${BASH_SOURCE[0]}")/../lib-patch.sh"

echo "respondd: Listener-Adresse auf den Gluon-2016.x-Wert"

apply_patch "$PATCH_DIR/fix-respondd-rsk.patch" \
  "package/gluon-respondd/files/etc/init.d/gluon-respondd" \
  'ff02::1'
