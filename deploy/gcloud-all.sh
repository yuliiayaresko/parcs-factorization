#!/bin/bash
# Повне розгортання ПАРКС у Google Cloud і запуск експерименту.
# Виконувати в Google Cloud Shell:
#
#   curl -sL https://raw.githubusercontent.com/yuliiayaresko/parcs-factorization/main/deploy/gcloud-all.sh -o gcloud-all.sh
#   bash gcloud-all.sh
#
# Налаштування можна перевизначити змінними оточення, наприклад:
#   DAEMONS=2 DAEMON_MACHINE=e2-micro bash gcloud-all.sh

set -e

ZONE="${ZONE:-europe-north1-a}"
REGION="${REGION:-europe-north1}"
DAEMONS="${DAEMONS:-4}"

# Демони рахують — їм потрібні ядра. Hosts-server і app лише координують і майже
# весь час простоюють, тому для них вистачає найменшої машини.
DAEMON_MACHINE="${DAEMON_MACHINE:-e2-small}"
COORD_MACHINE="${COORD_MACHINE:-e2-micro}"

REPO="${REPO:-https://github.com/yuliiayaresko/parcs-factorization.git}"
IMAGE_FAMILY="${IMAGE_FAMILY:-debian-12}"
IMAGE_PROJECT="${IMAGE_PROJECT:-debian-cloud}"

# Java 17: саме вона є в репозиторіях сучасного Debian. Бібліотека parcs.jar
# зібрана під Java 5, її байт-код виконується на 17 без змін.
JDK_PACKAGE="${JDK_PACKAGE:-openjdk-17-jdk-headless}"

say() { echo; echo "=== $* ==="; }

gcloud config set compute/zone "$ZONE" --quiet
gcloud config set compute/region "$REGION" --quiet

# ----------------------------------------------------------------- квота на vCPU
# У щойно створеному проєкті регіональна квота CPUS зазвичай 8, іноді 12 або 24.
# Шість машин по e2-small — це 12 vCPU, тобто створення впаде на середині
# з помилкою QUOTA_EXCEEDED, залишивши частину інстансів висіти й тарифікуватися.
# Тому кількість демонів підбирається під наявну квоту ще до створення.

say "Перевірка квоти на vCPU в регіоні $REGION"

cpus_of() {
  gcloud compute machine-types describe "$1" --zone="$ZONE" --format='value(guestCpus)' 2>/dev/null || echo 2
}

QUOTA_LINE=$(gcloud compute regions describe "$REGION" \
  --flatten="quotas[]" --format="value(quotas.metric,quotas.limit,quotas.usage)" 2>/dev/null \
  | grep '^CPUS' | head -1 || true)

DAEMON_CPUS=$(cpus_of "$DAEMON_MACHINE")
COORD_CPUS=$(cpus_of "$COORD_MACHINE")

if [ -n "$QUOTA_LINE" ]; then
  QUOTA_LIMIT=$(echo "$QUOTA_LINE" | awk '{print int($2)}')
  QUOTA_USED=$(echo "$QUOTA_LINE" | awk '{print int($3)}')
  AVAILABLE=$((QUOTA_LIMIT - QUOTA_USED))
  echo "квота CPUS: $QUOTA_LIMIT, зайнято $QUOTA_USED, вільно $AVAILABLE"

  BUDGET=$((AVAILABLE - 2 * COORD_CPUS))
  if [ "$BUDGET" -lt "$DAEMON_CPUS" ]; then
    echo
    echo "Вільної квоти не вистачає навіть на одного демона."
    echo "Попроси збільшення тут:"
    echo "  https://console.cloud.google.com/iam-admin/quotas?service=compute.googleapis.com"
    echo "Потрібна метрика CPUS у регіоні $REGION, достатньо 12."
    exit 1
  fi

  FITS=$((BUDGET / DAEMON_CPUS))
  if [ "$FITS" -lt "$DAEMONS" ]; then
    echo
    echo "Квоти вистачає лише на $FITS демонів замість $DAEMONS — зменшую."
    echo "Щоб зняти повну картину на 8 воркерах, потрібні 4 демони."
    echo "Збільшення квоти (метрика CPUS, регіон $REGION, значення 12):"
    echo "  https://console.cloud.google.com/iam-admin/quotas?service=compute.googleapis.com"
    DAEMONS="$FITS"
  fi
else
  echo "квоту прочитати не вдалося — продовжую з DAEMONS=$DAEMONS"
fi

DAEMON_NAMES=""
for i in $(seq 1 "$DAEMONS"); do
  DAEMON_NAMES="$DAEMON_NAMES daemon-$i"
done

WORKER_CORES=$((DAEMONS * DAEMON_CPUS))

say "Налаштування"
echo "зона:          $ZONE"
echo "демонів:       $DAEMONS ($DAEMON_NAMES )"
echo "машина демона: $DAEMON_MACHINE ($DAEMON_CPUS vCPU)"
echo "машина коорд.: $COORD_MACHINE ($COORD_CPUS vCPU)"
echo "ядер під воркери: $WORKER_CORES"
echo "образ:         $IMAGE_FAMILY"
echo "репозиторій:   $REPO"
if [ "$WORKER_CORES" -lt 8 ]; then
  echo
  echo "Увага: ядер менше, ніж найбільша кількість воркерів у out/input (8)."
  echo "Рядок для 8 воркерів покаже падіння ефективності через перепідписку ядер."
fi

# Скрипт можна запускати повторно. Сесія Cloud Shell вмирає разом із закритою
# вкладкою браузера, і тоді скрипт обривається на середині, а створені інстанси
# лишаються висіти й тарифікуватися. Тому створюються лише ті машини, яких ще немає.

say "Створення інстансів"

EXISTING=$(gcloud compute instances list --format='value(name)' 2>/dev/null || true)
have() { echo "$EXISTING" | grep -qx "$1"; }

missing_coord=""
for host in hosts-server app; do
  if have "$host"; then echo "$host уже існує — пропускаю"; else missing_coord="$missing_coord $host"; fi
done

missing_daemons=""
for host in $DAEMON_NAMES; do
  if have "$host"; then echo "$host уже існує — пропускаю"; else missing_daemons="$missing_daemons $host"; fi
done

if [ -n "$missing_coord" ]; then
  # shellcheck disable=SC2086
  gcloud compute instances create $missing_coord \
    --machine-type="$COORD_MACHINE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --quiet
fi

if [ -n "$missing_daemons" ]; then
  # shellcheck disable=SC2086
  gcloud compute instances create $missing_daemons \
    --machine-type="$DAEMON_MACHINE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --quiet
fi

say "Правило брандмауера"
gcloud compute firewall-rules create allow-parcs \
  --direction=INGRESS --priority=1000 --network=default \
  --action=ALLOW --rules=tcp:2222,tcp:3333 --source-ranges=10.0.0.0/8 \
  --quiet || echo "правило вже існує — пропускаємо"

internal_ip() {
  gcloud compute instances describe "$1" --format='get(networkInterfaces[0].networkIP)'
}

ssh_raw() {
  local host="$1"; shift
  gcloud compute ssh "$host" --zone="$ZONE" --quiet --command "$*"
}

# Свіжостворена машина кілька десятків секунд не приймає ssh: спершу вона
# завантажується, потім чекає, доки з метаданих приїде публічний ключ.
# Доти ssh виходить із кодом 255. Помилка тимчасова, тому кожна команда
# повторюється кілька разів, перш ніж вважатися невдалою.
run_on() {
  local host="$1"; shift
  local attempt
  for attempt in 1 2 3 4 5; do
    if ssh_raw "$host" "$@"; then
      return 0
    fi
    echo "  спроба $attempt для $host не вдалася, повтор через 15 с"
    sleep 15
  done
  echo "Не вдалося виконати команду на $host після 5 спроб."
  return 1
}

say "Чекаємо, доки машини приймуть SSH"
for host in hosts-server app $DAEMON_NAMES; do
  ready=no
  for attempt in $(seq 1 40); do
    if ssh_raw "$host" "true" >/dev/null 2>&1; then
      echo "$host готовий"
      ready=yes
      break
    fi
    sleep 5
  done
  if [ "$ready" = "no" ]; then
    echo "$host так і не прийняв ssh за 200 секунд."
    echo "Перевір стан машини:  gcloud compute instances list"
    echo "Скрипт можна просто запустити ще раз — створене він не чіпатиме."
    exit 1
  fi
done

say "Демони"
DAEMON_IPS=""
for i in $(seq 1 "$DAEMONS"); do
  host="daemon-$i"
  ip=$(internal_ip "$host")
  DAEMON_IPS="$DAEMON_IPS $ip"
  echo "--- $host ($ip)"
  # pkill — щоб повторний запуск не підняв другий демон на тому самому порту 2222
  run_on "$host" "
    sudo apt-get update -qq &&
    sudo apt-get install -y -qq $JDK_PACKAGE wget &&
    wget -q -O Daemon.jar https://github.com/lionell/labs/raw/master/parcs/Daemon/Daemon.jar &&
    pkill -f '[D]aemon.jar' || true &&
    (nohup java -jar Daemon.jar > daemon.log 2>&1 &) &&
    sleep 2 && cat daemon.log
  "
done

say "Hosts-server"
HS_IP=$(internal_ip hosts-server)
echo "адреса hosts-server: $HS_IP"
echo "демони:"
echo "$DAEMON_IPS" | tr ' ' '\n' | sed '/^$/d;s/^/  /'

run_on hosts-server "
  sudo apt-get update -qq &&
  sudo apt-get install -y -qq $JDK_PACKAGE wget &&
  wget -q -O TCPHostsServer.jar https://github.com/lionell/labs/raw/master/parcs/HostsServer/TCPHostsServer.jar &&
  printf '%s\n' $DAEMON_IPS > hosts.list &&
  cat hosts.list &&
  pkill -f '[T]CPHostsServer.jar' || true &&
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
