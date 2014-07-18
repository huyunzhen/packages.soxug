#!/bin/sh
#20_07_2007
COL1=11
COL2=11
COL3=12


if cat /proc/net/dev | grep "eth0:" ; then
   INTERFACE1="eth0"
else
   INTERFACE1=""
fi

echo "************************************************************"
echo "Configurando a interface «$INTERFACE1»"
echo "************************************************************"
if [ "$INTERFACE1" != "" ]; then
     MAC=`cat /sys/class/net/"$INTERFACE1"/address | tr [a-z] [A-Z]`
     IP=`cat /etc/network/interfaces | sed -n "/iface\ $INTERFACE1/{n;p;}" | cut -f2 -d " "`

     IP2=`grep $MAC /etc/configurarRed/datosred.dat | cut -f1`
     NAME2=`grep $MAC /etc/configurarRed/datosred.dat | cut -f2`
     #MAC2=`grep $MAC /etc/configurarRed/datosred.dat | cut -f3`

     echo "******  RESUMO DE CONFIGURACION PARA ESTE EQUIPO **********"
     echo "* MAC do equipo: $MAC  | IP actual do equipo: $IP"
     echo "* "
     echo "* MAC no fichero de datos: $MAC2"
     echo "* IP no fichero de datos: $IP2"
     echo "* NOME no fichero de datos: $NAME2"
     echo "************************************************************"

     echo `echo "$IP" | grep "$IP2"`
     if echo "$IP" | grep "$IP2"
      then
          echo "CONFIGURACION DE REDE CORRECTA."
      else
          echo " * Aplicando a configuración do nome do equipo..."
          echo "$NAME2" > /etc/hostname  
	  echo " * cambiando /etc/hosts ..."
head -1 /etc/hosts > /tmp/host
echo "127.0.1.1   	$NAME2" >> /tmp/host
tail -7 /etc/hosts >> /tmp/host
mv /etc/hosts /etc/hosts.old
cp /tmp/host /etc/hosts
rm /tmp/host
	  echo "etc hosts cambiado ."
cat /etc/hosts
          echo " * Aplicando os parámetros da configuración de rede..."
#cambiamos la ip del equipo
          sed "s/DIRECCION_IP/$IP2/g" /etc/configurarRed/interfaces > /etc/network/interfaces.new
          echo " * Aplicando a configuración do DNS ..."
          echo " - Configuración de rede rematada con ÉXITO"
      fi
else
   echo " * Interface de rede «$INTERFACE1» NON DISPOÑÍBEL"
fi

if [ -e /etc/network/interfaces.new ]; then
   cp /etc/network/interfaces.new /etc/network/interfaces
   rm /etc/network/interfaces.new
fi

sudo service networking restart
