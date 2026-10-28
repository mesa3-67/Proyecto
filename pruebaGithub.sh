#!/bin/bash

if [ "$(whoami)" == "root" ]; then
	echo "PUEDES CONTINUAR"; sleep 5
	clear
else
	echo "NECESITAS SUPER USUARIO"; exit
fi

apt update && apt full-upgrade -y
