#!/bin/bash


API_Token_ID="snapshot@pve!AutoSnap"
API_Token_Secret="<TOKEN>"

SNAP_PREFIX="autosnap"              # Prefix für den Snapshot-Namen
SNAP_DESCRIPTION="Auto Snapshot"    # Beschreibung für den Snapshot
SNAP_TAG=""                         # Optional: Tag für VM-Filterung
INTERVAL_MINUTES=15                 # Intervall in Minuten


# Ende der Konfiguration

NOW_TS=$(date +%s)

get_running_vms_with_node() {
  curl -s -k -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
    "https://localhost:8006/api2/json/cluster/resources?type=vm" | \
    jq -r '.data[] | select(.status == "running") | "\(.vmid) \(.node)"'
}
get_snapshots_for_vm() {
  local node="$1"
  local vmid="$2"

  curl -s -k -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
    "https://localhost:8006/api2/json/nodes/${node}/qemu/${vmid}/snapshot" | \
    jq -r '.data[]?.name'
}

has_tag() {
  local NODE="$1"
  local VMID="$2"
  local TAG="$3"

  if curl -s -k -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
    "https://localhost:8006/api2/json/nodes/${NODE}/qemu/${VMID}/config" | \
    jq -e --arg tag "$TAG" '.data.tags and (.data.tags | split(";") | index($tag))' > /dev/null; then
    return 0  # Tag gefunden
  else
    return 1  # Tag nicht gefunden
  fi
}

create_snapshot() {
  local NODE=$1
  local VMID=$2
  local SNAPNAME=$3
  local DESCRIPTION=$4
  curl -s -k -X POST \
    -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
    -d "snapname=${SNAPNAME}&description=${DESCRIPTION}" \
    "https://localhost:8006/api2/json/nodes/${NODE}/qemu/${VMID}/snapshot"
}

delete_snapshot() {
    local NODE=$1
    local VMID=$2
    local SNAPNAME=$3

    # Snapshot löschen und Task-ID extrahieren
    local response
    response=$(curl -s -k -X DELETE \
        -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
        "https://localhost:8006/api2/json/nodes/${NODE}/qemu/${VMID}/snapshot/${SNAPNAME}")

    local TASKID
    TASKID=$(echo "$response" | jq -r '.data')

    if [[ -z "$TASKID" || "$TASKID" == "null" ]]; then
        echo "[ERROR] Snapshot $SNAPNAME (VM $VMID) konnte nicht gelöscht werden."
        return 1
    fi

    echo "Warte auf Abschluss der Snapshot-Löschung ($SNAPNAME)..."

    # Warte auf Abschluss des Tasks
    while true; do
        local status
        status=$(curl -s -k \
            -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
            "https://localhost:8006/api2/json/nodes/${NODE}/tasks/${TASKID}/status" | jq -r '.data.status')

        if [[ "$status" == "stopped" ]]; then
            echo "[OK] Snapshot $SNAPNAME (VM $VMID) gelöscht."
            break
        fi

        sleep 1
    done
}

keep_snapshot() {
    local snap_time="$1"

    # Snapshot-Zeit in Sekunden
    local snap_ts
    snap_ts=$(date -d "$snap_time" +%s)

    # Alter in Minuten
    local age_min=$(( (NOW_TS - snap_ts) / 60 ))

    if (( age_min < 75 )); then
        return 0  # behalten (alle)
    elif (( age_min < 195 )); then
        # 30-Minuten-Raster behalten
        local minute=$(date -d "$snap_time" +%M)
        if (( 10#$minute % 30 == 0 )); then
            return 0
        fi
    else
        # nur stündlich behalten
        local minute=$(date -d "$snap_time" +%M)
        if (( 10#$minute == 0 )); then
            return 0
        fi
    fi

    return 1  # löschen
}

check_vm_lock() {
  local node=$1
  local vmid=$2
  local max_checks=${3:-5}
  local count=0

  while (( count < max_checks )); do
    # Lock-Abfrage via API
    local locks
    locks=$(curl -s -k -H "Authorization: PVEAPIToken=${API_Token_ID}=${API_Token_Secret}" \
      "https://localhost:8006/api2/json/nodes/${node}/qemu/${vmid}/status/current" | jq -r '.data.locks // empty')

    if [[ -z "$locks" ]]; then
      # Kein Lock gefunden
      return 0
    fi

    # Lock gefunden, warten und erneut prüfen
    sleep 1
    ((count++))
  done

  # Nach max_checks immer noch Lock vorhanden
  return 1
}


MIN=$(date +%-M)

TODAY=$(date +%Y%m%d)

SNAP_MIN=$(( (MIN / INTERVAL_MINUTES) * INTERVAL_MINUTES ))
SNAP_TIME=$(date +%Y%m%d%H)$(printf "%02d" $SNAP_MIN)
SNAP_NAME="${SNAP_PREFIX}-${SNAP_TIME}"


while read -r VMID NODE; do
    # Überprüfen, ob VM den Tag hat und die variabeln gesetzt sind
    if [[ -n "$SNAP_TAG" ]] && ! has_tag "$NODE" "$VMID" "$SNAP_TAG"; then
        continue
    fi

	echo "Snapshot für VMID=$VMID auf Node=$NODE"
	# Hier z. B. Snapshot per API ausführen
	if [[ "$1" == "-clean" ]] || [[ $(date +%-M) -le 2 ]]; then
		for SNAPSHOTNAME in $(get_snapshots_for_vm "$NODE" "$VMID" | grep "^${SNAP_PREFIX}-"); do

			SNAP_TIME_STR=${SNAPSHOTNAME#$SNAP_PREFIX-}
			if [[ ! $SNAP_TIME_STR =~ ^[0-9]{12}$ ]]; then
				echo "[WARN] Unbekanntes Snapshot-Format: $SNAPSHOTNAME"
				continue
			fi

			SNAP_DATE_FMT="${SNAP_TIME_STR:0:4}-${SNAP_TIME_STR:4:2}-${SNAP_TIME_STR:6:2} ${SNAP_TIME_STR:8:2}:${SNAP_TIME_STR:10:2}:00"

			if [[ "$SNAPSHOTNAME" != "$SNAP_PREFIX-$TODAY"* ]]; then
				echo "[DEL] $SNAPSHOTNAME (VM $VMID) To Old"
				if check_vm_lock "$NODE" "$VMID" 1; then delete_snapshot "$NODE" "$VMID" "$SNAPSHOTNAME"; fi
			elif ! keep_snapshot "$SNAP_DATE_FMT" ; then
				echo "[DEL] $SNAPSHOTNAME (VM $VMID) Rentention"
				if check_vm_lock "$NODE" "$VMID" 1; then delete_snapshot "$NODE" "$VMID" "$SNAPSHOTNAME"; fi
			else
				echo "[KEEP] $SNAPSHOTNAME (VM $VMID)"
			fi
		done
		if [[ "$1" != "-clean" ]]; then
			sleep 3
		fi
	fi
	
	
	if [[ "$1" != "-clean" ]]; then
		if [ $(get_snapshots_for_vm "$NODE" "$VMID" | grep -c "$SNAP_NAME") -eq 0 ]; then	
			if check_vm_lock "$NODE" "$VMID"; then
			  echo "Kein Lock auf VM $VMID, erstelle Snapshot..."
			  create_snapshot "$NODE" "$VMID" "$SNAP_NAME" "$SNAP_DESCRIPTION"
			else
			  echo "VM $VMID ist gelocked, Snapshot-Erstellung abgebrochen."
			fi
		fi
	fi


done < <(get_running_vms_with_node)

