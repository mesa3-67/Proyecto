#!/bin/bash

V="\e[1;32m"
R="\e[1;31m"
A="\e[1;34m"
F="\e[0m"



if [ "$(whoami)" == "root" ]; then
  echo -e "$V Bienvenido $R $HOSTNAME👤 $V podemos comenzar $F"
  else
  echo -e "$R Debes ingresar como super $LUZ  usuario🫆$F"
  exit 1
fi

apt update
