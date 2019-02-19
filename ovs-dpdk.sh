#!/bin/bash
#
# Script to install OVS + DPDK on fresh installed Ubuntu 16.04.1
# melamin@paloaltnetworks.com
#

version="01"  
script_name="$0"

HELP() {
	echo ""
	echo "	Use this script to install and configure openvswitch + DPDK on Ubuntu server 16.04.1"
	echo "	The Script will add two ovs br with one uplink interface each as well as one vhost interface on each br"
	echo ""
	echo "	script version $version"
	echo "	usage: ${0##*/} [-h] <IFACE1> <IFACE2>"
	echo "		-h	Display this help and exit."
	echo "		<IFACE1>	First uplink data interface"
	echo "		<IFACE2>	Second uplink data interface"
	echo ""
	echo ""
	echo "	Example: "
	echo "		${0##*/} eth0 eth1"
	echo ""

}

options=":h"

while getopts $options FLAG
do
	case $FLAG in
		h)	HELP; exit 1;;
	        \?)	echo "	Unknown option: -$OPTARG" >&2; HELP; exit 1 ;;
        	:)	echo "	Missing option argument for -$OPTARG" >&2 ;HELP ; exit 1;;
	esac
done

if [[ $# -gt 1 ]]
then
	IFACE1=$1
	IFACE2=$2
else
	echo "	ERROR: The uplink interfaces ids are missing"
	HELP
	exit 1
fi


setconf()
{
    cf=config/common_linuxapp
    if grep -q ^$1= $cf; then
        sed -i "s:^$1=.*$:$1=$2:g" $cf
    else
        echo $1=$2 >> $cf
    fi
}

check_ubuntu_version()
{
	VERSION=$(lsb_release -r 2>/dev/null | awk '{print $2}')
	if [ "$VERSION" != "16.04" ]
	then
		echo "This OS is not Ubuntu 16.04. This is script is tested on Ubuntu 16.04.1."
		read -r -p "Do you want to continue? [y/N] " response
		if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
		then
			echo "At your own risk."
		else
			echo "Good decision!"
			exit
		fi
	fi
}

check_if_exist()
{	
	if [ ! -d /sys/class/net/$1 ]
	then
		echo "$1 is not available in the system."
		exit
	fi
}

check_ubuntu_version

check_if_exist $IFACE1
check_if_exist $IFACE2

mkdir -p ~/tmp

pushd ~/tmp

echo "installing build essential packages"
sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
apt-get update
apt-get install build-essential gcc pkg-config glib-2.0 libglib2.0-dev libsdl1.2-dev libaio-dev libcap-dev libattr1-dev libpixman-1-dev -y
apt-get build-dep qemu -y
apt-get install qemu-kvm libvirt-bin -y

echo "Downloading qemu 2.5.0"
wget http://wiki.qemu.org/download/qemu-2.5.0.tar.bz2

echo "Compiling and installing Qemu 2.5.0"
tar xjvf qemu-2.5.0.tar.bz2
cd qemu-2.5.0
./configure
make
make install

popd
pushd ~/tmp

echo "Downloading DPDK-2.2.0"
wget http://dpdk.org/browse/dpdk/snapshot/dpdk-2.2.0.tar.gz

echo "Compiling and installing DPDK v2.2.0"
tar xzvf dpdk-2.2.0.tar.gz
cd dpdk-2.2.0
setconf CONFIG_RTE_APP_TEST n
setconf CONFIG_RTE_BUILD_COMBINE_LIBS y
sed -i "/ROOTDIRS-y/s/app//g" GNUmakefile
make install T=x86_64-native-linuxapp-gcc

popd
pushd ~/tmp

echo "Downloading openvswitch v2.5.1"
wget http://openvswitch.org/releases/openvswitch-2.5.1.tar.gz

echo "Compiling and installing openvswitch v2.2.0"
tar xzvf openvswitch-2.5.1.tar.gz
cd openvswitch-2.5.1
DPDK_PATH=$(realpath ~/tmp/dpdk-2.2.0/x86_64-native-linuxapp-gcc/)
./configure --with-dpdk="$DPDK_PATH"
make
make install

popd

echo "Configuring hugepages"
rm /usr/local/var/run/openvswitch/vhost-user0 2>/dev/null 
rm /usr/local/var/run/openvswitch/vhost-user1 2>/dev/null 
echo 16384 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
mkdir /dev/hugepages 2>/dev/null 
mkdir /dev/hugepages/libvirt 2>/dev/null 
mkdir /dev/hugepages/libvirt/qemu 2>/dev/null 
mount -t hugetlbfs hugetlbfs /dev/hugepages/libvirt/qemu
killall ovsdb-server ovs-vswitchd


echo "Initializing the openvswitch Database"
mkdir -p /usr/local/etc/openvswitch 2>/dev/null 
mkdir -p /usr/local/var/run/openvswitch 2>/dev/null 
rm -f /var/run/openvswitch/vhost-user* 2>/dev/null 
rm -f /usr/local/etc/openvswitch/conf.db 2>/dev/null 

ovsdb-tool create /usr/local/etc/openvswitch/conf.db /usr/local/share/openvswitch/vswitch.ovsschema
ovsdb-server --remote=punix:/usr/local/var/run/openvswitch/db.sock \
--remote=db:Open_vSwitch,Open_vSwitch,manager_options \
--private-key=db:Open_vSwitch,SSL,private_key \
--certificate=db:Open_vSwitch,SSL,certificate \
--bootstrap-ca-cert=db:Open_vSwitch,SSL,ca_cert \
--pidfile --detach

echo "Initializing the openvswitch with DPDK"
ovs-vsctl --no-wait init
export DB_SOCK=/usr/local/var/run/openvswitch/db.sock

cd ~/tmp/dpdk-2.2.0/x86_64-native-linuxapp-gcc/kmod
modprobe uio
insmod igb_uio.ko


cd ~/tmp/dpdk-2.2.0/tools/

./dpdk_nic_bind.py --bind=igb_uio $IFACE1
./dpdk_nic_bind.py --bind=igb_uio $IFACE2


ovs-vswitchd --dpdk -c 0x3 -n 4 -- unix:$DB_SOCK --pidfile --detach
echo 50000 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

ovs-vsctl add-br data-br-0 -- set bridge data-br-0  datapath_type=netdev
ovs-vsctl add-port data-br-0 dpdk0 -- set Interface dpdk0 type=dpdk

ovs-vsctl add-br data-br-1 -- set bridge data-br-1  datapath_type=netdev
ovs-vsctl add-port data-br-1 dpdk1 -- set Interface dpdk1 type=dpdk

ovs-vsctl add-port data-br-0 vhost-user0 -- set Interface vhost-user0 type=dpdkvhostuser
ovs-vsctl add-port data-br-1 vhost-user1 -- set Interface vhost-user1 type=dpdkvhostuser

ovs-vsctl set Open_vSwitch . other_config:n-dpdk-rxqs=8
ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=0xffff


chmod 777 /usr/local/var/run/openvswitch/vhost-user0
chmod 777 /usr/local/var/run/openvswitch/vhost-user1

chmod 777 /dev/hugepages/libvirt/qemu

ovs-vsctl set Interface vhost-user0 options:n_rxq=8
ovs-vsctl set Interface vhost-user1 options:n_rxq=8

echo "Done"

echo "Now you can add the vhost-user0 and vhost-user1 interfaces to your PA-VM xml file. As per the following example:"
echo "
    <interface type='vhostuser'>
      <source type='unix' path='/usr/local/var/run/openvswitch/vhost-user0' mode='client'/>
		<model type='virtio'/>
		<driver name=’vhost’ queues=’8’/>
    </interface>
    <interface type='vhostuser'>
      <source type='unix' path='/usr/local/var/run/openvswitch/vhost-user1' mode='client'/>
		<model type='virtio'/>
		<driver name=’vhost’ qeueus=’8’>
    </interface>"
echo "You also need to add the following NUMA setting to the Guest VM XML."
echo "
 <cpu mode='host-model'>
    <model fallback='allow'/>
    <numa>
      <cell id='0' cpus='0,2,4,6' memory='8388608' unit='KiB' memAccess='shared'/>
      <cell id='1' cpus='1,3,5,7' memory='8388608' unit='KiB' memAccess='shared'/>
    </numa>
  </cpu>
"
