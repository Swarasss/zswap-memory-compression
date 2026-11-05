#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

int main(int argc, char *argv[]) {
long size_mb = 1024;
char type = 'z';

if (argc >= 2) {
   size_mb = atol(argv[1]);
}

if (argc >= 3) {
   type = argv[2][0];
}

int zswap_result =
    system("sudo bash -c 'echo Y > /sys/module/zswap/parameters/enabled'");

if (zswap_result != 0) {
    printf("Failed to enable ZSWAP.\n");
    return 1;
}

printf("ZSWAP enabled.\n");

long size = size_mb * 1024 * 1024;
struct timespec start, end;
clock_gettime(CLOCK_MONOTONIC, &start);
char *buf = malloc(size);

if (!buf) {
printf("Allocation failed!\n");
return 1;
}

if (type == 'z') {
  memset(buf, 0, size);
  printf("Allocated %ldMB of ZEROS\n", size_mb);
}

else if (type == 'o') {
    for (long i = 0; i < size; i++) {
        buf[i] = (char)((i % 5) + 1);
    }

    printf("Allocated %ldMB of repeating 1-2-3-4-5 pattern\n",
           size_mb);
}


 else if (type == 'r') {
    FILE *random_file = fopen("incompressible_seed.bin", "rb");

    if (random_file == NULL) {
        printf("Failed to open incompressible_seed.bin\n");
        free(buf);
        return 1;
    }

    const size_t seed_size = 64 * 1024 * 1024;
    char *seed = malloc(seed_size);

    if (seed == NULL) {
        printf("Seed allocation failed!\n");
        fclose(random_file);
        free(buf);
        return 1;
    }

    size_t bytes_read = fread(seed, 1, seed_size, random_file);
    fclose(random_file);

    if (bytes_read != seed_size) {
        printf("Failed to read complete incompressible seed file.\n");
        free(seed);
        free(buf);
        return 1;
    }

    size_t total_filled = 0;

    while (total_filled < (size_t)size) {
        size_t remaining = (size_t)size - total_filled;
        size_t copy_size =
            (remaining < seed_size) ? remaining : seed_size;

        memcpy(buf + total_filled, seed, copy_size);
        total_filled += copy_size;
    }

    free(seed);

    printf("Allocated %ldMB of RANDOM data using "
           "64MB cyclic high-entropy seed\n",
           size_mb);
 
}


clock_gettime(CLOCK_MONOTONIC, &end);

double elapsed_ms =
    (end.tv_sec - start.tv_sec) * 1000.0 +
    (end.tv_nsec - start.tv_nsec) / 1000000.0;

printf("Allocation/fill time: %.2f ms\n", elapsed_ms);
pid_t pid = getpid();

char command[256];

if (type == 'o') {
    snprintf(command, sizeof(command),
             "~/test_ones_on.sh %d %ld",
             pid, size_mb);
}
else if (type == 'r') {
    snprintf(command, sizeof(command),
             "~/test_random.sh %d %ld",
             pid, size_mb);
}

int script_result = system(command);

if (script_result != 0) {
    printf("Measurement script failed.\n");
}


free(buf);
return 0;
}
  
