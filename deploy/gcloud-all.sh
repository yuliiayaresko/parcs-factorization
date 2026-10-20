#!/bin/bash
# Повне розгортання ПАРКС у Google Cloud і запуск експерименту.
# Виконувати в Google Cloud Shell:
#
#   curl -sL https://raw.githubusercontent.com/yuliiayaresko/parcs-factorization/main/deploy/gcloud-all.sh -o gcloud-all.sh
#   bash gcloud-all.sh
#
# Налаштування можна перевизначити змінними оточення, наприклад:
#   DAEMONS=2 MACHINE=e2-micro bash gcloud-all.sh

set -e

ZONE="${ZONE:-europe-north1-a}"
REGION="${REGION:-europe-north1}"
DAEMONS="${DAEMONS:-4}"
MACHINE="${MACHINE:-e2-small}"
REPO="${REPO:-https://github.com/yuliiayaresko/parcs-factorization.git}"
IMAGE_FAMILY="${IMAGE_FAMILY:-debian-12}"
IMAGE_PROJECT="${IMAGE_PROJECT:-debian-cloud}"

# Java 17: саме вона є в репозиторіях сучасного Debian. Бібліотека parcs.jar
# зібрана під Java 5, її байт-код виконується на 17 без змін.
JDK_PACKAGE="${JDK_PACKAGE:-openjdk-17-jdk-headless}"

say() { echo; echo "=== $* ==="; }

DAEMON_NAMES=""
for i in $(seq 1 "$DAEMONS"); do
  DAEMON_NAMES="$DAEMON_NAMES daemon-$i"
done

say "Налаштування"
echo "зона:        $ZONE"
echo "машина:      $MACHINE"
echo "демонів:     $DAEMONS ($DAEMON_NAMES )"
echo "образ:       $IMAGE_FAMILY"
echo "репозиторій: $REPO"

gcloud config set compute/zone "$ZONE" --quiet
gcloud config set compute/region "$REGION" --quiet

say "Створення інстансів"
# shellcheck disable=SC2086
gcloud compute instances create hosts-server app $DAEMON_NAMES \
  --machine-type="$MACHINE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --quiet

say "Правило брандмауера"
gcloud compute firewall-rules create allow-parcs \
  --direction=INGRESS --priority=1000 --network=default \
  --action=ALLOW --rules=tcp:2222,tcp:3333 --source-ranges=10.0.0.0/8 \
  --quiet || echo "правило вже існує — пропускаємо"

internal_ip() {
  gcloud compute instances describe "$1" --format='get(networkInterfaces[0].networkIP)'
}

run_on() {
  local host="$1"; shift
  gcloud compute ssh "$host" --zone="$ZONE" --quiet --command "$*"
}

say "Чекаємо, доки машини приймуть SSH"
for host in hosts-server app $DAEMON_NAMES; do
  for attempt in $(seq 1 30); do
    if run_on "$host" "true" >/dev/null 2>&1; then
      echo "$host готовий"
      break
    fi
    sleep 5
  done
done

say "Демони"
DAEMON_IPS=""
for i in $(seq 1 "$DAEMONS"); do
  host="daemon-$i"
  ip=$(internal_ip "$host")
  DAEMON_IPS="$DAEMON_IPS $ip"
  echo "--- $host ($ip)"
  run_on "$host" "
    sudo apt-get update -qq &&
    sudo apt-get install -y -qq $JDK_PACKAGE wget &&
    wget -q -O Daemon.jar https://github.com/lionell/labs/raw/master/parcs/Daemon/Daemon.jar &&
    (nohup java -jar Daemon.jar > daemon.log 2>&1 &) &&
    sleep 2 && cat daemon.log
  "
done

say "Hosts-server"
HS_IP=$(internal_ip hosts-server)
HOSTS_LIST=$(echo $DAEMON_IPS | tr ' ' '\n' | sed '/^$/d')
echo "адреса hosts-server: $HS_IP"
echo "демони:"
echo "$HOSTS_LIST" | sed 's/^/  /'

run_on hosts-server "
  sudo apt-get update -qq &&
  sudo apt-get install -y -qq $JDK_PACKAGE wget &&
  wget -q -O TCPHostsServer.jar https://github.com/lionell/labs/raw/master/parcs/HostsServer/TCPHostsServer.jar &&
  printf '%s\n' $DAEMON_IPS > hosts.list &&
  cat hosts.list &&
  (nohup java -jar TCPHostsServer.jar > hosts.log 2>&1 &) &&
  sleep 2 && cat hosts.log
"

say "Застосунок"
run_on app "
  sudo apt-get update -qq &&
  sudo apt-get install -y -qq $JDK_PACKAGE git make &&
  rm -rf lab &&
  git clone -q $REPO lab &&
  cd lab &&
  echo $HS_IP > out/server &&
  echo 'адреса hosts-server:' \$(cat out/server) &&
  make
"

say "Готово"
echo "Щоб забрати CSV із результатами:"
echo "  gcloud compute scp app:~/lab/out/results.csv . --zone=$ZONE"
echo
echo "Інстанси тарифікуються. Коли закінчиш, видали їх:"
echo "  gcloud compute instances delete hosts-server app$DAEMON_NAMES --zone=$ZONE --quiet"
