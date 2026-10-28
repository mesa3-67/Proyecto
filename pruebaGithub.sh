#!/bin/bash

if [ "$(whoami)" == "root" ]; then
	echo "PUEDES CONTINUAR"; sleep 5
	clear
else
	echo "NECESITAS SUPER USUARIO"; exit 1
fi

sudo apt update
sudo apt full-upgrade -y
