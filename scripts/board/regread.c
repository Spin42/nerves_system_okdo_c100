// Read-only 32-bit register reads through /dev/mem: regread <hexaddr>...
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
  int fd = open("/dev/mem", O_RDONLY | O_SYNC);
  if (fd < 0) { perror("open /dev/mem"); return 1; }
  long page = sysconf(_SC_PAGESIZE);
  for (int i = 1; i < argc; i++) {
    uint64_t addr = strtoull(argv[i], NULL, 16);
    uint64_t base = addr & ~(uint64_t)(page - 1);
    void *map = mmap(NULL, page, PROT_READ, MAP_SHARED, fd, base);
    if (map == MAP_FAILED) { printf("0x%08llx: mmap failed\n", (unsigned long long)addr); continue; }
    volatile uint32_t *reg = (volatile uint32_t *)((char *)map + (addr - base));
    printf("0x%08llx: 0x%08x\n", (unsigned long long)addr, *reg);
    fflush(stdout);
    munmap(map, page);
  }
  close(fd);
  return 0;
}
