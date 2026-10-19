#!/bin/bash
# Виконати на інстансі hosts-server.
# Аргументи — внутрішні IP усіх демонів.
#   bash hosts-server.sh 10.166.0.4 10.166.0.5
set -e

if [ $# -eq 0 ]; then
  echo "Вкажіть внутрішні IP демонів, наприклад: bash hosts-server.sh 10.166.0.4 10.166.0.5"
  exit 1
fi

sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-8-jdk

wget -q https://github.com/lionell/labs/raw/master/parcs/HostsServer/TCPHostsServer.jar

rm -f hosts.list
for ip in "$@"; do
  echo "$ip" >> hosts.list
done

echo "— hosts.list:"
cat hosts.list

nohup java -jar TCPHostsServer.jar > hosts.log 2>&1 &
sleep 2

echo "— сервер запущено, журнал:"
cat hosts.log
echo "— внутрішня адреса цієї машини (знадобиться для out/server):"
hostname -I | awk '{print $1}'
