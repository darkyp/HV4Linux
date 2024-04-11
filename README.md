# HV4Linux
 Hyper-V for Linux or WSL2 without WSL2

# Purpose

After using WSL2 for some experiments, I quickly realized some of its limitations when I decided to use it in production.
<p>In short - got an old Linux machine running multiple php-cli console scripts doing various things, that I wanted to move to another more powerful machine still 
having enough room for other tasks. This other machine is a Windows 10 one. Why Windows - well, I have my reasons.
<p>For the above to happen, first I needed for the WSL to work with the VLANs available on the host. I do not want for the WSL to have access to all the VLANs, 
just some of them. Moreover I do not want the host to have access or be accessible from some of these VLANs that WSL needs. WSLAttachSwitch does not work in my case. All the VLANs are
on the same Network Adapter. So I created <a href="https://github.com/darkyp/HVNetService/">this</a> other project...
<p>I continued playing and soon found myself full of other ideas. For example - access the WSL console from the host only, no SSH; have the scripts working in a multi-tabbed interface; 
closing WSL should no HUP the scripts' TTYs and will not kill them, then later starting it would show the TTYs with the still running script (Linux screen like functionality but dressed in a Windows UI). 
And I do not want to have the host drives mounted (Plan9).
<br>Is this be possible? As it turns out, it is. 
<p>So here came this project.

# WSL2 internals / behind the scenes
WSL2 runs the Linux kernel in a hypervisor and provides it with various services through Windows kernel-mode vmbus, Hyper-V sockets (vsock in Linux) and somewhere there come named pipes as well.
Hyper-V sockets and named pipes are user-mode accessible and thus more easy to exploit.
<p>The Linux kernel is aware of the above fact and cooperates nicely with Hyper-V. MS did their job for patching/configuring the kernel. However they do not provide the internals (source code)
for the init process that the Linux kernel loads and executes once it did its initial job. And this init process is a single file that has hardly anything to do with the widely known initramfs 
images that have entire fs tree. WSL2 is actually this init process and the protocol for communicating with it for it to do useful things (Linux kernel syscalls) - such as start a process, attach network interfaces, 
mount block devices, shutdown, reboot etc.
<p>WSL2 is using Windows public APIs. While public, there is still much work for MS to do to document them properly and fill them with examples. And there are still some parts of it that are not public - probably because they
might change. While those some parts are not public, this does not mean they cannot be used :) And this is what this project uses.
<p>The APIs in use are the <a href="https://learn.microsoft.com/en-us/virtualization/api/hcs/overview">Host Compute System API</a>. WSL2 uses <a href="https://learn.microsoft.com/en-us/virtualization/api/hcs/reference/hcscreatecomputesystem">HcsCreateComputeSystem</a> to create the VM, then a couple of <a href="https://learn.microsoft.com/en-us/virtualization/api/hcs/reference/hcsmodifycomputesystem">HcsModifyComputeSystem</a> calls to attach various things to the VM, such as the storage, 
network adapters, shares etc. Finally it calls <a href="https://learn.microsoft.com/en-us/virtualization/api/hcs/reference/hcsstartcomputesystem">HcsStartComputeSystem</a>.
<p>While WSL2 provisions for looking at the Linux kernel boot process, it is not readily available. It is available through VirtioSerial device that is terminated on the host end on a named pipe. 
One can connect to the named pipe and look at <u>part</u> of the boot process. Why a <u>part</u>? Because the Linux kernel VirtioSerial driver is initialized later in the boot process and thus 
early kernel log messages are not available. Yes, we have dmesg after it boots, still...
<br>However it is possible to direct the kernel to have its console attached not to a VirtioSerial but a com port, again terminated on a named pipe. And the 16550 UART is available to the kernel
right from the start, so one can see the full boot process provided WSL2 can be configured so.

# HV4L
So what this project does is provide one with WSL2 without WSL2. It calls the necessary APIs to create and boot the Linux kernel VM. I have provided a custom init process that mounts the rootfs chroots to it
and tries to execute /init from the mounted rootfs that can as well be a bash script. If /init is not found, a /bin/bash shell is started for maintenance. If this fails - well, kernel panic.
<p>The above description should be enough to get you started with a basic system. There are more tools in this repository that will have their description later...
<p>For an easier start install WSL2, grab the kernel (\Program Files\WindowsApps\MicrosoftCorporationII.WindowsSubsystemForLinux...), some distribution's VHD file and initrd.img from this repo and set them up as a VM in the app.
You can uninstall WSL2 after that.
<p>...or download a ready package that I prepared with a base debian jessie from <a href="https://drive.google.com/file/d/1toTUbE-izzFPZd46OFTQ716E3mqndg_c/view">here</a>. The package has three configurations all using the same files - a read/write (the first one) and two read/only ones that can be started at the same time. For the networking to work, install NPCap and modify the /network file with the name of your Windows adapter.

# TODO
<p>More to come...
