#!/bin/bash
# Виконати на інстансі app.
# Аргументи: внутрішній IP hosts-server і посилання на репозиторій.
#   bash app.sh 10.166.0.2 https://github.com/yuliiayaresko/parcs-factorization.git
set -e

if [ $# -lt 2 ]; then
  echo "Використання: bash app.sh ВНУТРІШНІЙ_IP_HOSTS_SERVER ПОСИЛАННЯ_НА_РЕПОЗИТОРІЙ"
  exit 1
fi

SERVER_IP="$1"
REPO="$2"

sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-8-jdk git make

rm -rf lab
git clone -q "$REPO" lab
cd lab

echo "$SERVER_IP" > out/server
echo "— адреса hosts-server записана у out/server: $(cat out/server)"
echo "— вхідні дані:"
cat out/input

make
