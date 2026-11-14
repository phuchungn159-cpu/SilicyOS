/* ==========================================================================
 * silicy-ctl.c — Apple Silicon SMC Telemetry, Battery Guard & Power Engine
 * Target: Apple M1/M2/M3 (Asahi Linux 16KB Page Size + CachyOS BORE)
 * Constraints: Pure C11, Zero Heap Allocation, Raw FD Syscalls (open/pread/
 *              pwrite/sched_setaffinity), < 400KB RSS, < 0.1ms execution.
 * ========================================================================== */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static char g_sysroot[192] = "";

static void init_sysroot_from_env(void) {
    if (!environ) {
        return;
    }
    const char *prefix = "SILICY_SYSROOT=";
    const size_t plen = 15;
    for (char **ep = environ; *ep != NULL; ++ep) {
        if (strncmp(*ep, prefix, plen) == 0) {
            const char *val = *ep + plen;
            size_t vlen = strlen(val);
            if (vlen > 0 && vlen < sizeof(g_sysroot)) {
                memcpy(g_sysroot, val, vlen);
                while (vlen > 0 && g_sysroot[vlen - 1] == '/') {
                    g_sysroot[--vlen] = '\0';
                }
            }
            break;
        }
    }
}

static void build_path(char *dst, size_t dst_sz, const char *rel_path) {
    if (g_sysroot[0] != '\0') {
        snprintf(dst, dst_sz, "%s%s", g_sysroot, rel_path);
    } else {
        snprintf(dst, dst_sz, "%s", rel_path);
    }
}

static int pin_current_process(uint32_t cpu_mask) {
#ifdef __linux__
    cpu_set_t set;
    CPU_ZERO(&set);
    for (int i = 0; i < 32; ++i) {
        if (cpu_mask & (1u << i)) {
            CPU_SET(i, &set);
        }
    }
    return sched_setaffinity(0, sizeof(set), &set);
#else
    (void)cpu_mask;
    return 0;
#endif
}

static ssize_t sysfs_pread_str(const char *rel_path, char *buf, size_t buf_sz) {
    char full_path[320];
    build_path(full_path, sizeof(full_path), rel_path);

    int fd = open(full_path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        buf[0] = '\0';
        return -1;
    }

    ssize_t n = pread(fd, buf, buf_sz - 1, 0);
    close(fd);

    if (n <= 0) {
        buf[0] = '\0';
        return -1;
    }

    buf[n] = '\0';
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == ' ' || buf[n - 1] == '\t')) {
        buf[--n] = '\0';
    }
    return n;
}

static int sysfs_pwrite_str(const char *rel_path, const char *data, int create_file, mode_t mode) {
    char full_path[320];
    build_path(full_path, sizeof(full_path), rel_path);

    int flags = O_WRONLY | O_TRUNC | O_CLOEXEC;
    if (create_file) {
        flags |= O_CREAT;
    }

    int fd = open(full_path, flags, mode);
    if (fd < 0) {
        return -1;
    }

    size_t len = strlen(data);
    ssize_t written = pwrite(fd, data, len, 0);
    if (written < 0 && errno == ESPIPE) {
        written = write(fd, data, len);
    }
    close(fd);
    return (written == (ssize_t)len) ? 0 : -1;
}

static int64_t parse_i64(const char *s, int64_t fallback) {
    if (!s || *s == '\0') {
        return fallback;
    }
    while (*s == ' ' || *s == '\t') {
        ++s;
    }
    int neg = 0;
    if (*s == '-') {
        neg = 1;
        ++s;
    } else if (*s == '+') {
        ++s;
    }
    if (*s < '0' || *s > '9') {
        return fallback;
    }
    int64_t val = 0;
    while (*s >= '0' && *s <= '9') {
        val = (val * 10) + (*s - '0');
        ++s;
    }
    return neg ? -val : val;
}

static int64_t sysfs_pread_i64(const char *rel_path, int64_t fallback) {
    char buf[64];
    if (sysfs_pread_str(rel_path, buf, sizeof(buf)) < 0) {
        return fallback;
    }
    return parse_i64(buf, fallback);
}

static void write_stdout(const char *s) {
    size_t len = strlen(s);
    if (len > 0) {
        ssize_t r = write(STDOUT_FILENO, s, len);
        (void)r;
    }
}

static void write_stderr(const char *s) {
    size_t len = strlen(s);
    if (len > 0) {
        ssize_t r = write(STDERR_FILENO, s, len);
        (void)r;
    }
}

static int char_lower(int c) {
    if (c >= 'A' && c <= 'Z') {
        return c + ('a' - 'A');
    }
    return c;
}

static int str_contains_ci(const char *haystack, const char *needle) {
    if (!haystack || !needle || *needle == '\0') {
        return 0;
    }
    size_t nlen = strlen(needle);
    for (const char *h = haystack; *h != '\0'; ++h) {
        size_t i = 0;
        while (i < nlen && h[i] != '\0' && char_lower((unsigned char)h[i]) == char_lower((unsigned char)needle[i])) {
            ++i;
        }
        if (i == nlen) {
            return 1;
        }
    }
    return 0;
}

static int is_non_soc_hwmon(const char *name) {
    if (!name || *name == '\0') {
        return 0;
    }
    if (str_contains_ci(name, "battery") ||
        str_contains_ci(name, "nvme") ||
        str_contains_ci(name, "ac-adapter") ||
        str_contains_ci(name, "usb") ||
        str_contains_ci(name, "charger")) {
        return 1;
    }
    return 0;
}

static int is_preferred_soc_hwmon(const char *name) {
    if (!name || *name == '\0') {
        return 0;
    }
    if (str_contains_ci(name, "macsmc") ||
        str_contains_ci(name, "soc") ||
        str_contains_ci(name, "apple") ||
        str_contains_ci(name, "cpu") ||
        str_contains_ci(name, "die") ||
        str_contains_ci(name, "core") ||
        str_contains_ci(name, "thermal")) {
        return 1;
    }
    return 0;
}

static double read_soc_temperature_c(void) {
    char name_path[128];
    char temp_path[128];
    char sensor_name[64];

    /* Pass 1: Explicit SoC / Apple SMC hwmon devices (skipping battery & NVMe) */
    for (int i = 0; i < 16; ++i) {
        snprintf(name_path, sizeof(name_path), "/sys/class/hwmon/hwmon%d/name", i);
        if (sysfs_pread_str(name_path, sensor_name, sizeof(sensor_name)) <= 0) {
            continue;
        }
        if (is_non_soc_hwmon(sensor_name) || !is_preferred_soc_hwmon(sensor_name)) {
            continue;
        }
        for (int t = 1; t <= 4; ++t) {
            snprintf(temp_path, sizeof(temp_path), "/sys/class/hwmon/hwmon%d/temp%d_input", i, t);
            int64_t mc = sysfs_pread_i64(temp_path, -1);
            if (mc > 5000 && mc < 130000) {
                return (double)mc / 1000.0;
            }
        }
    }

    /* Pass 2: Any hwmon sensor that is not explicitly a battery or NVMe sensor */
    for (int i = 0; i < 16; ++i) {
        snprintf(name_path, sizeof(name_path), "/sys/class/hwmon/hwmon%d/name", i);
        sysfs_pread_str(name_path, sensor_name, sizeof(sensor_name));
        if (is_non_soc_hwmon(sensor_name)) {
            continue;
        }
        snprintf(temp_path, sizeof(temp_path), "/sys/class/hwmon/hwmon%d/temp1_input", i);
        int64_t mc = sysfs_pread_i64(temp_path, -1);
        if (mc > 5000 && mc < 130000) {
            return (double)mc / 1000.0;
        }
    }

    /* Pass 3: Thermal zone or fallback hwmon */
    int64_t tz = sysfs_pread_i64("/sys/class/thermal/thermal_zone0/temp", -1);
    if (tz > 5000 && tz < 130000) {
        return (double)tz / 1000.0;
    }
    for (int i = 0; i < 16; ++i) {
        snprintf(temp_path, sizeof(temp_path), "/sys/class/hwmon/hwmon%d/temp1_input", i);
        int64_t mc = sysfs_pread_i64(temp_path, -1);
        if (mc > 5000 && mc < 130000) {
            return (double)mc / 1000.0;
        }
    }
    return 36.0;
}

static void read_power_profile(char *out, size_t out_sz) {
    if (sysfs_pread_str("/etc/silicy-power-profile", out, out_sz) > 0) {
        return;
    }
    if (sysfs_pread_str("/run/silicy-power-profile", out, out_sz) > 0) {
        return;
    }
    snprintf(out, out_sz, "balanced");
}

static void read_meminfo_stats(double *ram_gb_out, double *zram_mb_out) {
    char buf[2048];
    *ram_gb_out = 0.0;
    *zram_mb_out = 0.0;

    if (sysfs_pread_str("/proc/meminfo", buf, sizeof(buf)) <= 0) {
        return;
    }

    int64_t mem_total_kb = 0;
    int64_t mem_avail_kb = 0;
    int64_t swap_total_kb = 0;
    int64_t swap_free_kb = 0;

    const char *p = buf;
    while (*p != '\0') {
        if (strncmp(p, "MemTotal:", 9) == 0) {
            mem_total_kb = parse_i64(p + 9, 0);
        } else if (strncmp(p, "MemAvailable:", 13) == 0) {
            mem_avail_kb = parse_i64(p + 13, 0);
        } else if (strncmp(p, "SwapTotal:", 10) == 0) {
            swap_total_kb = parse_i64(p + 10, 0);
        } else if (strncmp(p, "SwapFree:", 9) == 0) {
            swap_free_kb = parse_i64(p + 9, 0);
        }
        while (*p != '\0' && *p != '\n') {
            ++p;
        }
        if (*p == '\n') {
            ++p;
        }
    }

    if (mem_total_kb > mem_avail_kb) {
        *ram_gb_out = (double)(mem_total_kb - mem_avail_kb) / 1048576.0;
    }
    if (swap_total_kb > swap_free_kb) {
        *zram_mb_out = (double)(swap_total_kb - swap_free_kb) / 1024.0;
    }
}

static void sanitize_json_token(char *s) {
    if (!s) {
        return;
    }
    for (; *s != '\0'; ++s) {
        if ((unsigned char)*s < 0x20 || *s == '"' || *s == '\\') {
            *s = '_';
        }
    }
}

static void detect_clusters(uint32_t *ecore_mask, uint32_t *pcore_mask, char *ecore_str, size_t e_sz, char *pcore_str, size_t p_sz);

static int cmd_telemetry(int argc, char **argv) {
    /* Pin telemetry reader to Apple Silicon E-Cores dynamically (0-3 fallback) */
    uint32_t ecore_mask = 0x0Fu, pcore_mask = 0xF0u;
    char ecore_str[96], pcore_str[96];
    detect_clusters(&ecore_mask, &pcore_mask, ecore_str, sizeof(ecore_str), pcore_str, sizeof(pcore_str));
    pin_current_process(ecore_mask);

    int64_t power_uw = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/power_now", 0);
    if (power_uw < 0) {
        power_uw = -power_uw;
    }
    if (power_uw == 0) {
        int64_t cur_ua = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/current_now", 0);
        int64_t vol_uv = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/voltage_now", 0);
        if (cur_ua < 0) {
            cur_ua = -cur_ua;
        }
        if (cur_ua > 0 && vol_uv > 0) {
            power_uw = (cur_ua / 1000) * (vol_uv / 1000);
        }
    }
    double power_w = (double)power_uw / 1000000.0;
    if (power_w > 240.0) {
        power_w = 240.0;
    }

    int64_t capacity = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/capacity", 100);
    if (capacity < 0) {
        capacity = 0;
    } else if (capacity > 100) {
        capacity = 100;
    }

    char status[32];
    if (sysfs_pread_str("/sys/class/power_supply/macsmc-battery/status", status, sizeof(status)) <= 0) {
        snprintf(status, sizeof(status), "Discharging");
    }
    sanitize_json_token(status);

    int64_t threshold = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/charge_control_end_threshold", -1);
    if (threshold <= 0) {
        threshold = sysfs_pread_i64("/etc/silicy-battery.conf", 80);
    }

    int64_t cycles = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/cycle_count", 0);
    double temp_c = read_soc_temperature_c();

    char profile[32];
    read_power_profile(profile, sizeof(profile));
    sanitize_json_token(profile);

    char out[768];
    if (argc >= 3) {
        if (strcmp(argv[2], "--power") == 0 || strcmp(argv[2], "power") == 0) {
            snprintf(out, sizeof(out), "%.1fW\n", power_w);
            write_stdout(out);
            return 0;
        }
        if (strcmp(argv[2], "--temp") == 0 || strcmp(argv[2], "temp") == 0) {
            snprintf(out, sizeof(out), "%.0f°C\n", temp_c);
            write_stdout(out);
            return 0;
        }
        if (strcmp(argv[2], "--memory") == 0 || strcmp(argv[2], "memory") == 0) {
            double ram_gb = 0.0, zram_mb = 0.0;
            read_meminfo_stats(&ram_gb, &zram_mb);
            snprintf(out, sizeof(out), "%.2fG · zram %.0fM\n", ram_gb, zram_mb);
            write_stdout(out);
            return 0;
        }
    }

    snprintf(
        out,
        sizeof(out),
        "{\"text\":\"%.1fW · %.0f°C\",\"alt\":\"%s\",\"tooltip\":\"Apple SMC Telemetry | Profile: %s | Power: %.1fW (%s) | SoC: %.1fC | Battery: %lld%% (Limit: %lld%%, Cycles: %lld)\",\"class\":\"%s\",\"percentage\":%lld,\"power_watts\":%.2f,\"temp_c\":%.1f,\"capacity\":%lld,\"status\":\"%s\",\"charge_threshold\":%lld,\"cycle_count\":%lld,\"profile\":\"%s\"}\n",
        power_w,
        temp_c,
        profile,
        profile,
        power_w,
        status,
        temp_c,
        (long long)capacity,
        (long long)threshold,
        (long long)cycles,
        profile,
        (long long)capacity,
        power_w,
        temp_c,
        (long long)capacity,
        status,
        (long long)threshold,
        (long long)cycles,
        profile
    );
    write_stdout(out);
    return 0;
}

static int cmd_battery_guard(int argc, char **argv) {
    if (argc < 3) {
        write_stderr("Usage: silicy-ctl battery-guard <60|80|100|status>\n");
        return 1;
    }

    if (strcmp(argv[2], "status") == 0) {
        int64_t cur = sysfs_pread_i64("/sys/class/power_supply/macsmc-battery/charge_control_end_threshold", -1);
        if (cur <= 0) {
            cur = sysfs_pread_i64("/etc/silicy-battery.conf", 80);
        }
        char msg[64];
        snprintf(msg, sizeof(msg), "%lld\n", (long long)cur);
        write_stdout(msg);
        return 0;
    }

    if (strcmp(argv[2], "60") != 0 && strcmp(argv[2], "80") != 0 && strcmp(argv[2], "100") != 0) {
        write_stderr("[silicy-ctl] ERROR: Invalid threshold. Allowed values: 60, 80, 100.\n");
        return 1;
    }
    int64_t limit = parse_i64(argv[2], 80);

    char payload[16];
    snprintf(payload, sizeof(payload), "%lld\n", (long long)limit);

    errno = 0;
    int rc_sys = sysfs_pwrite_str(
        "/sys/class/power_supply/macsmc-battery/charge_control_end_threshold",
        payload,
        0,
        0664
    );
    int err_sys = errno;

    errno = 0;
    int rc_cfg = sysfs_pwrite_str("/etc/silicy-battery.conf", payload, 1, 0664);
    int err_cfg = errno;

    if ((rc_sys < 0 && (err_sys == EACCES || err_sys == EPERM)) ||
        (rc_cfg < 0 && (err_cfg == EACCES || err_cfg == EPERM)) ||
        (rc_sys < 0 && rc_cfg < 0)) {
        write_stderr("[silicy-ctl] ERROR: Failed to write charge threshold to macsmc sysfs or /etc/silicy-battery.conf (check permissions).\n");
        return 1;
    }

    char log_buf[192];
    snprintf(
        log_buf,
        sizeof(log_buf),
        "[silicy-ctl] macsmc charge_control_end_threshold set to %lld%% (persisted to /etc/silicy-battery.conf)\n",
        (long long)limit
    );
    write_stdout(log_buf);
    return 0;
}

static void detect_clusters(uint32_t *ecore_mask, uint32_t *pcore_mask, char *ecore_str, size_t e_sz, char *pcore_str, size_t p_sz) {
    uint32_t e_mask = 0;
    uint32_t p_mask = 0;
    size_t e_off = 0;
    size_t p_off = 0;
    ecore_str[0] = '\0';
    pcore_str[0] = '\0';

    char rel_path[128];
    for (int cpu = 0; cpu < 32; ++cpu) {
        snprintf(rel_path, sizeof(rel_path), "/sys/devices/system/cpu/cpu%d/cpu_capacity", cpu);
        int64_t cap = sysfs_pread_i64(rel_path, -1);
        if (cap < 0) {
            continue;
        }
        if (cap < 650) {
            e_mask |= (1u << cpu);
            int n = snprintf(ecore_str + e_off, e_sz - e_off, "%s%d", (e_off > 0 ? "," : ""), cpu);
            if (n > 0 && (size_t)n < e_sz - e_off) {
                e_off += (size_t)n;
            }
        } else {
            p_mask |= (1u << cpu);
            int n = snprintf(pcore_str + p_off, p_sz - p_off, "%s%d", (p_off > 0 ? "," : ""), cpu);
            if (n > 0 && (size_t)n < p_sz - p_off) {
                p_off += (size_t)n;
            }
        }
    }

    if (e_mask == 0 || p_mask == 0) {
        e_mask = 0x0Fu;
        p_mask = 0xF0u;
        snprintf(ecore_str, e_sz, "0-3");
        snprintf(pcore_str, p_sz, "4-7");
    }

    *ecore_mask = e_mask;
    *pcore_mask = p_mask;
}

static void toggle_compositor_blur(int enable_blur) {
    if (g_sysroot[0] != '\0') {
        /* Skip live IPC calls when operating inside a staging sysroot */
        return;
    }
    int has_hypr = 0;
    if (environ) {
        for (char **ep = environ; *ep != NULL; ++ep) {
            if (strncmp(*ep, "HYPRLAND_INSTANCE_SIGNATURE=", 28) == 0) {
                has_hypr = 1;
                break;
            }
        }
    }
    if (!has_hypr) {
        return;
    }

    pid_t pid = fork();
    if (pid == 0) {
        int devnull = open("/dev/null", O_WRONLY | O_CLOEXEC);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        const char *val = enable_blur ? "true" : "false";
        char *const args[] = {"hyprctl", "keyword", "decoration:blur:enabled", (char *)val, NULL};
        execve("/usr/bin/hyprctl", args, environ);
        _exit(0);
    } else if (pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
    }
}

static int try_sysfs_write(const char *rel_path, const char *data, int create_file, mode_t mode, int *perm_err_count) {
    errno = 0;
    int rc = sysfs_pwrite_str(rel_path, data, create_file, mode);
    if (rc < 0 && (errno == EACCES || errno == EPERM)) {
        *perm_err_count += 1;
    }
    return rc;
}

static int cmd_power_profile(int argc, char **argv) {
    if (argc < 3) {
        write_stderr("Usage: silicy-ctl power-profile <eco|balanced|burst|status>\n");
        return 1;
    }

    const char *mode = argv[2];
    if (strcmp(mode, "status") == 0) {
        char cur[32];
        read_power_profile(cur, sizeof(cur));
        write_stdout(cur);
        write_stdout("\n");
        return 0;
    }

    int is_eco = (strcmp(mode, "eco") == 0);
    int is_bal = (strcmp(mode, "balanced") == 0);
    int is_bst = (strcmp(mode, "burst") == 0);

    if (!is_eco && !is_bal && !is_bst) {
        write_stderr("[silicy-ctl] ERROR: Unknown power profile. Allowed: eco, balanced, burst.\n");
        return 1;
    }

    uint32_t ecore_mask = 0, pcore_mask = 0;
    char ecore_str[96], pcore_str[96];
    detect_clusters(&ecore_mask, &pcore_mask, ecore_str, sizeof(ecore_str), pcore_str, sizeof(pcore_str));

    char gov_path[128];
    char max_path[128];
    char min_path[128];
    char info_max_path[128];
    char freq_buf[64];
    int perm_errs = 0;

    for (int cpu = 0; cpu < 32; ++cpu) {
        uint32_t bit = (1u << cpu);
        if (!(ecore_mask & bit) && !(pcore_mask & bit)) {
            continue;
        }
        int is_pcore = (pcore_mask & bit) != 0;

        snprintf(gov_path, sizeof(gov_path), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_governor", cpu);
        snprintf(max_path, sizeof(max_path), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_max_freq", cpu);
        snprintf(min_path, sizeof(min_path), "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_min_freq", cpu);
        snprintf(info_max_path, sizeof(info_max_path), "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", cpu);

        if (is_eco) {
            try_sysfs_write(gov_path, is_pcore ? "powersave\n" : "schedutil\n", 0, 0644, &perm_errs);
            if (is_pcore) {
                int64_t max_khz = sysfs_pread_i64(info_max_path, 3200000);
                int64_t min_khz = sysfs_pread_i64(min_path, 600000);
                int64_t cap_khz = (max_khz * 55) / 100;
                if (cap_khz < min_khz) {
                    cap_khz = min_khz;
                }
                snprintf(freq_buf, sizeof(freq_buf), "%lld\n", (long long)cap_khz);
                try_sysfs_write(max_path, freq_buf, 0, 0644, &perm_errs);
            }
        } else if (is_bal) {
            int64_t max_khz = sysfs_pread_i64(info_max_path, -1);
            if (max_khz > 0) {
                snprintf(freq_buf, sizeof(freq_buf), "%lld\n", (long long)max_khz);
                try_sysfs_write(max_path, freq_buf, 0, 0644, &perm_errs);
            }
            try_sysfs_write(gov_path, "schedutil\n", 0, 0644, &perm_errs);
        } else if (is_bst) {
            int64_t max_khz = sysfs_pread_i64(info_max_path, -1);
            if (max_khz > 0) {
                snprintf(freq_buf, sizeof(freq_buf), "%lld\n", (long long)max_khz);
                try_sysfs_write(max_path, freq_buf, 0, 0644, &perm_errs);
            }
            try_sysfs_write(gov_path, is_pcore ? "performance\n" : "schedutil\n", 0, 0644, &perm_errs);
        }
    }

    if (is_eco) {
        pin_current_process(ecore_mask);
        try_sysfs_write("/sys/fs/cgroup/ecores_background/cpuset.cpus", ecore_str, 0, 0644, &perm_errs);
        try_sysfs_write("/sys/fs/cgroup/pcores_interactive/cpuset.cpus", ecore_str, 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_bore", "1\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_penalty_offset", "28\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_smoothness_long", "3\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/vm/dirty_writeback_centisecs", "9000\n", 0, 0644, &perm_errs);
        toggle_compositor_blur(0);
    } else if (is_bal) {
        pin_current_process(ecore_mask | pcore_mask);
        try_sysfs_write("/sys/fs/cgroup/ecores_background/cpuset.cpus", ecore_str, 0, 0644, &perm_errs);
        try_sysfs_write("/sys/fs/cgroup/pcores_interactive/cpuset.cpus", pcore_str, 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_bore", "1\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_penalty_offset", "22\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_smoothness_long", "1\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_smoothness_short", "0\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/vm/dirty_writeback_centisecs", "1500\n", 0, 0644, &perm_errs);
        toggle_compositor_blur(1);
    } else if (is_bst) {
        pin_current_process(pcore_mask);
        try_sysfs_write("/sys/fs/cgroup/ecores_background/cpuset.cpus", ecore_str, 0, 0644, &perm_errs);
        try_sysfs_write("/sys/fs/cgroup/pcores_interactive/cpuset.cpus", pcore_str, 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_bore", "1\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_penalty_offset", "16\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_smoothness_long", "0\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/kernel/sched_burst_smoothness_short", "0\n", 0, 0644, &perm_errs);
        try_sysfs_write("/proc/sys/vm/dirty_writeback_centisecs", "1500\n", 0, 0644, &perm_errs);
        toggle_compositor_blur(1);
    }

    char mode_line[32];
    snprintf(mode_line, sizeof(mode_line), "%s\n", mode);
    int rc_etc = try_sysfs_write("/etc/silicy-power-profile", mode_line, 1, 0664, &perm_errs);
    /* Mirror runtime state into /run when writable without failing unprivileged wheel callers */
    (void)sysfs_pwrite_str("/run/silicy-power-profile", mode_line, 1, 0664);

    if (perm_errs > 0 || rc_etc < 0) {
        write_stderr("[silicy-ctl] ERROR: Insufficient permissions to update all power profile nodes.\n");
        return 1;
    }

    char log_buf[224];
    snprintf(
        log_buf,
        sizeof(log_buf),
        "[silicy-ctl] Power profile switched to '%s' (E-cores: %s | P-cores: %s)\n",
        mode,
        ecore_str,
        pcore_str
    );
    write_stdout(log_buf);
    return 0;
}

static int cmd_keyboard_mode(int argc, char **argv) {
    if (argc < 3) {
        write_stderr("Usage: silicy-ctl keyboard-mode <mac|pc|status>\n");
        return 1;
    }

    if (strcmp(argv[2], "status") == 0) {
        char cur[32];
        if (sysfs_pread_str("/etc/silicy-kb-mode", cur, sizeof(cur)) <= 0 &&
            sysfs_pread_str("/run/silicy-kb-mode", cur, sizeof(cur)) <= 0) {
            snprintf(cur, sizeof(cur), "Mac (Command)");
        }
        write_stdout(cur);
        write_stdout("\n");
        return 0;
    }

    const char *primary_src = NULL;
    const char *fallback_src = NULL;
    const char *label = NULL;
    if (strcmp(argv[2], "mac") == 0) {
        primary_src = "/usr/share/silicyos/keyd/mac-mode.conf";
        fallback_src = "/etc/keyd/mac-mode.conf";
        label = "Mac (Command)\n";
    } else if (strcmp(argv[2], "pc") == 0) {
        primary_src = "/usr/share/silicyos/keyd/pc-mode.conf";
        fallback_src = "/etc/keyd/pc-mode.conf";
        label = "PC (Ctrl)\n";
    } else {
        write_stderr("[silicy-ctl] ERROR: Invalid keyboard mode. Allowed: mac, pc, status.\n");
        return 1;
    }

    char cfg_buf[4096];
    int perm_errs = 0;
    ssize_t cfg_len = sysfs_pread_str(primary_src, cfg_buf, sizeof(cfg_buf) - 2);
    if (cfg_len <= 0) {
        cfg_len = sysfs_pread_str(fallback_src, cfg_buf, sizeof(cfg_buf) - 2);
    }
    if (cfg_len <= 0) {
        write_stderr("[silicy-ctl] ERROR: Missing readable keyd preset template.\n");
        return 1;
    }

    size_t len = (size_t)cfg_len;
    cfg_buf[len] = '\n';
    cfg_buf[len + 1] = '\0';
    int rc_keyd = try_sysfs_write("/etc/keyd/default.conf", cfg_buf, 1, 0664, &perm_errs);
    int rc_etc = try_sysfs_write("/etc/silicy-kb-mode", label, 1, 0664, &perm_errs);
    /* Mirror runtime state into /run when writable without failing unprivileged wheel callers */
    (void)sysfs_pwrite_str("/run/silicy-kb-mode", label, 1, 0664);

    if (perm_errs > 0 || rc_keyd < 0 || rc_etc < 0) {
        write_stderr("[silicy-ctl] ERROR: Insufficient permissions to switch keyd configuration.\n");
        return 1;
    }

    write_stdout("[silicy-ctl] Keyboard mode updated.\n");
    return 0;
}

static void print_usage(void) {
    write_stdout(
        "silicy-ctl - Apple Silicon SMC Hardware & CachyOS BORE Controller\n"
        "Usage:\n"
        "  silicy-ctl telemetry [--json|--power|--temp|--memory]\n"
        "  silicy-ctl battery-guard <60|80|100|status>\n"
        "  silicy-ctl power-profile <eco|balanced|burst|status>\n"
        "  silicy-ctl keyboard-mode <mac|pc|status>\n"
    );
}

int main(int argc, char **argv) {
    init_sysroot_from_env();

    if (argc < 2) {
        print_usage();
        return 1;
    }

    if (strcmp(argv[1], "telemetry") == 0) {
        return cmd_telemetry(argc, argv);
    }
    if (strcmp(argv[1], "battery-guard") == 0) {
        return cmd_battery_guard(argc, argv);
    }
    if (strcmp(argv[1], "power-profile") == 0) {
        return cmd_power_profile(argc, argv);
    }
    if (strcmp(argv[1], "keyboard-mode") == 0) {
        return cmd_keyboard_mode(argc, argv);
    }
    if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_usage();
        return 0;
    }

    write_stderr("[silicy-ctl] ERROR: Unknown subcommand.\n");
    print_usage();
    return 1;
}
