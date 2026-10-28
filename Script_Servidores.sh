#!/bin/bash



V="\e[1;32m"
R="\e[1;31m"
A="\e[1;33m"
AZUL="\e[1;34m"
F="\e[0m"



if [ "$(whoami)" == "root" ]; then
	echo -e "$V PUEDES CONTINUAR $F"; sleep 3
	echo " ";
	clear
else
	echo -e "$R NECESITAS SUPER USUARIO $FIN"; sleep 3
	clear; exit 1
fi


    if command -V curl &> /dev/null; then
echo -e "$V Paquete para instalación acitvo $F"
  else
      sudo apt install curl -y 
    fi 

echo -e "$AZUL ======================================================================================== $F"
echo -e "$V Verificando las dependencias necesarias $F"

curl https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh > /dev/null 2>&1 


echo -e "$AZUL ================================================================================================ $F"
echo -e "$V Configurando conexion de servidor $F"

read -p "Numero de la ip de UBUNTU:" ip_ubuntu
tee "/etc/netdata/stream.conf" << EOF > /dev/null 2>&1 
[stream]
enabled = yes
destination = $ip_ubuntu:19999
api key = 66093669-c72d-4a5f-8bfc-35d14b3cfa5b
EOF





echo -e "$V CONFIGURANDO LAS METRICAS DE LECTURA $R CPU y RAM  $F"
       cd /etc/netdata
       sudo tee health.d/cpu.conf > /dev/null  << 'EOF'
       template: 10min_cpu_usage
         on: system.cpu
      class: Utilization
       type: System
  component: CPU
host labels: _os=linux
     lookup: average -10m unaligned of user,system,softirq,irq,guest
      units: %
      every: 5s
       warn: $this > (($status >= $WARNING)  ? (75) : (85))
       crit: $this > (($status == $CRITICAL) ? (86) : (95))
      delay: down 15m multiplier 1.5 max 1h
    summary: System CPU utilization
       info: Average CPU utilization over the last 10 minutes (excluding iowait, nice and steal)
         to: sysadmin

   template: 10min_cpu_iowait
         on: system.cpu
      class: Utilization
       type: System
  component: CPU
host labels: _os=linux
     lookup: average -10m unaligned of iowait
      units: %
      every: 1m
       warn: $this > (($status >= $WARNING)  ? (20) : (40))
      delay: up 30m down 30m multiplier 1.5 max 2h
    summary: System CPU iowait time
       info: Average CPU iowait time over the last 10 minutes
         to: silent
   template: 20min_steal_cpu
         on: system.cpu
      class: Utilization
       type: System
  component: CPU
host labels: _os=linux
     lookup: average -20m unaligned of steal
      units: %
      every: 5m
       warn: $this > (($status >= $WARNING)  ? (5)  : (10))
      delay: down 1h multiplier 1.5 max 2h
    summary: System CPU steal time
       info: Average CPU steal time over the last 20 minutes
         to: silent
EOF
     cd /etc/netdata
     sudo tee health.d/ram.conf > /dev/null << 'EOF'   
 alarm: ram_in_use
         on: system.ram
      class: Utilization
       type: System
  component: Memory
host labels: _os=linux
       calc: $used * 100 / ($used + $cached + $free + $buffers)
      units: %
      every: 5s
       warn: $this > (($status >= $WARNING)  ? (75) : (85))
       crit: $this > (($status == $CRITICAL) ? (86) : (95))
      delay: down 15m multiplier 1.5 max 1h
    summary: System memory utilization
       info: System memory utilization
         to: sysadmin

      alarm: ram_available
         on: mem.available
      class: Utilization
       type: System
  component: Memory
host labels: _os=linux
       calc: $avail * 100 / ($system.ram.used + $system.ram.cached + $system.ram.free + $system.ram.buffers)
      units: %
      every: 10s
       warn: $this < (($status >= $WARNING)  ? (15) : (10))
      delay: down 15m multiplier 1.5 max 1h
    summary: System available memory
       info: Percentage of estimated amount of RAM available for userspace processes, without causing swapping
         to: silent
         
 alarm: oom_kill
         on: mem.oom_kill
      class: Errors
       type: System
  component: Memory
host labels: _os=linux
     lookup: sum -30m unaligned
      units: kills
      every: 5m
       warn: $this > 0
      delay: down 10m
    summary: System OOM kills
       info: Number of out of memory kills in the last 30 minutes
         to: silent
EOF

     
echo -e "$R REINCIO DEL SISTEMA $F"
     systemctl daemon-reload
     systemctl restart netdata
     systemctl enable netdata 
     sudo netdatacli reload-health    
     
     if command -V figlet &> /dev/null; then
     figlet "$V NETDATA $F"
     else
     sudo apt install figlet -y /dev/null 2>&1
     figlet "$V NETDATA $F"
     fi
     
         
         
         
         
         
