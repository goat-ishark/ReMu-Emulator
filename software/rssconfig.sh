echo 'vm.nr_hugepages=2048' > /etc/sysctl.d/hugepages.conf
sysctl --system
mount -t hugetlbfs none /dev/hugepages
modprobe vfio-pci
export DPDK_DIR=/usr/src/dpdk-22.11
$DPDK_DIR/usertools/dpdk-devbind.py --bind=vfio-pci 0000:01:00.0
