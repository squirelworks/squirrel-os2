# Unix / POSIX / Solaris personality (scaffold)

Covers traditional Unix, System V, and Solaris/Illumos binaries that are not pure Linux.

Most work shares the ELF loader and syscall translation tables with the `linux` personality.  
Solaris-specific syscalls or structures are added only when a concrete need appears.

Status: directory only.
