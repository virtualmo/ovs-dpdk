# Installing OVS+DPDK on Ubuntu 16.04
This script can be used to automate the installation of the openvswitch with DPDK on ubuntu server.
The script is tested on Ubuntu 16.04

The script will download, compile and install:
OvS version:  2.5.1
DPDK version: 2.2.0
Qemu Version: 2.5.0

The script will also create two openvswitch bridges and two vhost-user ports that can be attached to the Guest VM.

Example Setup will look like the following:
![Example](https://raw.githubusercontent.com/mohanadelamin/ovs-dpdk/master/Setup.png)

## Usage

1- Run the script on fresh ubuntu 16.04.1
```bash
git clone https://github.com/mohanadelamin/ovs-dpdk.git
cd ovs-dpdk
chmod +x ovs-dpdk.sh
sudo ./ovs-dpdk.sh eth0 eth1
```

2- Add the vhost-user0 and vhost-user1 ports to your guest VM xml file.
```bash
    <interface type='vhostuser'>
      <source type='unix' path='/usr/local/var/run/openvswitch/vhost-user0' mode='client'/>
		<model type='virtio'/>
		<driver name=’vhost’ queues=’8’/>
    </interface>
    <interface type='vhostuser'>
      <source type='unix' path='/usr/local/var/run/openvswitch/vhost-user1' mode='client'/>
		<model type='virtio'/>
		<driver name=’vhost’ qeueus=’8’>
    </interface>
```

3- Add the following Numa setting to your guest VM xml file.
```bash
 <cpu mode='host-model'>
    <model fallback='allow'/>
    <numa>
      <cell id='0' cpus='0,2,4,6' memory='8388608' unit='KiB' memAccess='shared'/>
      <cell id='1' cpus='1,3,5,7' memory='8388608' unit='KiB' memAccess='shared'/>
    </numa>
  </cpu>
```