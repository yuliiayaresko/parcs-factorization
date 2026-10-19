#!/bin/bash
# Виконати на кожному інстансі daemon-*.
# Ставить Java 8, качає готовий демон ПАРКС і запускає його у фоні на порту 2222.
set -e

sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-8-jdk

wget -q https://github.com/lionell/labs/raw/master/parcs/Daemon/Daemon.jar

nohup java -jar Daemon.jar > daemon.log 2>&1 &
sleep 2

echo "— демон запущено, журнал:"
cat daemon.log
echo "— внутрішня адреса цієї машини (знадобиться для hosts.list):"
hostname -I | awk '{print $1}'
