# Proxmox-AutoSnapShot

## User & Gruppe mit Berechtigung anlegen

Es muss im Proxmox ein User mit den Berechtigung auf VM.Audit & VM.Snapshot angelegt werden.
Ich habe dafür eine Extra Rolle `Snapshot` angelegt die die beiden Rollen zugewiesen bekommen hat.

Dann habe ich eine Gruppe `Snapshot` angelegt und der Gruppe dann `/vms` die Rolle `Snapshot` zugewiesen.

## API Zugriff erstellen

Dann habe ich ein API Token für den User `snapshot@pve` mit dem Namen `AutoSnap` angelegt.

Im Code muss der User mit Tokenname angegeben werden. In diesem Beispiel muss in der Variable `API_Token_ID` der Wert `snapshot@pve!AutoSnap` und den Secret muss in der Variable `API_Token_Secret` angegeben werden. (ACHTUNG Secret wird bei Proxmox nur einmal angezeigt)

## Aufruf mittels Systemd Timer

Im Ordner systemd sind Beispiel Timer & Service.
Der .service wird dann immer entsprechend von dem .timer aufgerufen.

Um dies zu aktivieren:

```
ln -s /opt/autosnap/systemd/autosnap.service /etc/systemd/system/autosnap.service
ln -s /opt/autosnap/systemd/autosnap.timer /etc/systemd/system/autosnap.timer
ln -s /opt/autosnap/systemd/cleanup.service /etc/systemd/system/cleanup.service
ln -s /opt/autosnap/systemd/cleanup.timer /etc/systemd/system/cleanup.timer
chmod +x /opt/autosnap/autosnap.sh
systemctl daemon-reload
systemctl enable --now autosnap.timer
systemctl enable --now cleanup.timer
```
In diesem Beispeil ist es so aufgebaut das Montag - Freitag von 06:00-18:00 Uhr alle 15 Minuten ein Snapshot ausgelöst wird.
Der Clean läuft Täglich um 05:00 Uhr morgens.

## Funktionsbeschreibung 
Das Script erstellt Snapshots von laufenden VMs auf Proxmox-Servern.
Es wird ein Snapshot-Name im Format autosnap-YYYYMMDDHHMM erstellt.
Das Script überprüft, ob ein Snapshot bereits existiert, und löscht alte Snapshots basierend auf einem festgelegten Zeitintervall.
Snapshots werden alle 15 Minuten erstellt, wobei nur die letzten 2 Stunden und stündliche Snapshots der letzten 24 Stunden behalten werden.
Das Script kann mit dem Parameter -clean aufgerufen werden, um alte Snapshots zu löschen, ohne neue Snapshots zu erstellen.
Es wird auch überprüft, ob die VM gelockt ist, bevor ein Snapshot erstellt oder gelöscht wird.

## Parameter
### Ohne Parameter
Wird `/opt/autosnap/autosnap.sh` so aufgerufen, wird ein Snapshot erstellt. Das Script ist so aufgebaut, dass immer der Zeitstempel auf 15min abgerundet wird und als Snapshotname verwendet wird.

Beispiel 16.05.2025 09:23 wird autosnap-202505160915 verwendet.
Bei jeder vollen Stunde, läuft automatisch vorher ein Cleanup

### Mit -clean Parameter
Es wird nur ein Cleanup durchgeführt.
Es werden alle Snapshots der Letzten Stunde behalten.
Bei 1-3 Stunden alten Snapshots werden nur die zur vollen Stunde & 30 Minuten behalten.
Alles was älter als 3 Stunden ist wird auf Stündlich reduziert.

Alle Snapshots die nicht vom aktuellen Tag sind werden gelöscht.

Grundbedingung ist, dass die Snapshots immer mit `autosnap-` beginnen. Alle anderen Snapshots werden ignoriert.


## TAGS

Das Script ist so aufgebaut, dass es auf ein TAG in Proxmox achten kann und das dann nur bei den VM`s mit Tag AutoSnapshot aktiviert.
Im Default ist dies aber aus und es wird für ALLE VM´s genutzt.