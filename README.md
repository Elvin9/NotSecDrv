# NotSecDrv - A PoC code for CVE-2018-7249
### General Description
An issue was discovered in secdrv.sys as shipped in Microsoft Windows Vista, Windows 7, Windows 8, and Windows 8.1 before KB3086255, and as shipped in Macrovision SafeDisc. Two carefully timed calls to IOCTL 0xCA002813 can cause a race condition that leads to a use-after-free. When exploited, an unprivileged attacker can run arbitrary code in the kernel.

The vulnerability was reported to Microsoft, and since it does not affect an up-to-date Windows machine (only version prior to KB3086255), they will not take any action. Was tested and exploited successfully on Windows 7 x86.

Also related to [CVE-2018-7250](https://github.com/Elvin9/SecDrvPoolLeak).

### Screenshot
![Alt text](https://github.com/Elvin9/NotSecDrv/raw/master/VirtualBox_Testing_NotSecDrv.png)

### Details

This documents my little research about the secdrv.sys driver. All the described behaviors of the driver were reversed engineered and might be incorrect / inaccurate.

Offset 0x4 of the input buffer to the IOCTL (0x0CA002813) contains a number that I will refer to as the TYPE. 
The main handler function of this IOCTL (0x0CA002813), sub_11A88 receives 3 different types: 0x96, 0x97 and 0x98.

* **0x96** allocates a PagedPool chunk, stores it in an array of size 0x64, initializes it (sort of :)), and copies a part of it to the user supplied buffer at offset 0x10.
* **0x97** uses a previously allocated chunk, that was allocated with 0x96 (it find the right chunk in the mentiones array by a tag),
and uses it to encrypt the user input buffer with some sort of a modified xor encryption routine. It then calls a function that is stored in another structure, which is pointed by a field in the allocated chunk.
* **0x98** frees a chunk that was allocated with 0x96. It finds the right chunk by searching the tag given to it in the allocation process.

#### Info Leak (CVE-2018-7250)
After IOCTL type 0x96 allocated a new chunk and initialized it, but not fully, it copies the chunk to usermode. 16 bits in the newly allocated chunk were not initialized, and contain data from previous PagedPool allocations. The uninitialized bits are then copies to usermode at .text:00011BE9 by the REP MOVSD instruction. PoC code [here](https://github.com/Elvin9/SecDrvPoolLeak).

#### Arbitrary Code Execution (CVE-2018-7249)
When IOCTL type 0x97 is called, it finds the needed chunk, that was previously allocated with type 0x96, by its tag. If the allocation was already freed by IOCTL type 0x97, DeviceIoControl returns an error. The vulnerability here is, that the allocation used by type 0x97, can be freed DURING its operation (since no synchronization mechanisms are used) thus being used-after-freed if the race is won.
If an attacker manages to free the chunk during the operation of IOCTL type 0x97 (using type 0x98), and allocate a new chunk, controlled by him, in the exact same memory location,	he can override a pointer to another structure, that contains a function pointer that can be used to finally hijack the driver's execution flow and execute arbitrary code in ring 0.
Because the encryption routine is done on a user supplied buffer, which can be huge in size, the encryption can take a long time to execute, thus providing a perfect time window	for IOCTL type 0x98 to free the chunk while still in use. The time windows can be so long (more than 1 second!), that the race can be won reliably on the first attempt. The use-after-free starts at .text:00011B68, and the actual call, that will be hijacked to jump to the shellcode, happens at .text:00011B86.
	
The steps taken to successfully exploit this vulnerability are as following:
* Free all previous chunks with the tag we plan to use later, making sure all IOCTLs operate on the same PagedPool chunk.
* Spray the PagedPool and create holes that match the size of the allocations in IOCTL type 0x96 (0x30 bytes). This is necessary in order to later reliably allocate a fake replacement
			instead of the freed one.
* Allocate a chunk with IOCTL type 0x96. This chunk will be allocated in one of the holes created previously.
* Allocate large region of user space memory and call IOCTL type 0x97. The large memory region will ensure that the thread that frees the allocation, has enough time to win the race.
* Start a new thread that will call IOCTL type 0x98 and free the chunk that the other thread is operating on.
* Spray the pool again from the new thread (after the chunk was freed) in order to replace the freed chunk with an attacker controlled allocation. This fake chunk should contain valid pointers to the necessary structures.
* Put the shellcode's address at the correct offset of the function pointer in the fake structure we created, and wait for it to be called (it will be called from IOCTL type 0x97, after it finishes the encryption).
* Enjoy! 
  
  
### Test Enviroment
**OS:** Windows 7 Kernel Version 7600 MP (1 procs) Free x86 compatible Built by: 7600.16385.x86fre.win7_rtm.090713-1255
**VM:** 4GB RAM, 1 CPU
**Hardware:** Windows 10 Pro 64 bit, Motherboard Gigabyte Z370 HD3, 16GB RAM, Intel i5-8400 2.80GHz (6 CPUs)

