#!/bin/sh

# Terminal Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m'

TARGET_DIR="drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768"

FILE_PV="$TARGET_DIR/mtk_cpufreq_opp_pv_table.h"
FILE_OPP="$TARGET_DIR/mtk_cpufreq_opp_table.h"
FILE_UPOWER="drivers/misc/mediatek/base/power/include/upower_v2/mtk_unified_power_data_mt6768.h"

if [ ! -d "$TARGET_DIR" ]; then
    printf "${RED}Error: Directory '%s' not found.${NC}\n" "$TARGET_DIR"
    exit 1
fi

printf "${CYAN}Type 'reset' to restore stock values, or press Enter to continue:${NC} "
read CMD_INPUT

if [ "$CMD_INPUT" = "reset" ]; then
    TARGET_L=0
    TARGET_B=0
    TARGET_BOTTOM_L=0
    TARGET_BOTTOM_B=0
    DROP_BOTTOM="y"
else
    TARGET_BOTTOM_L=0
    TARGET_BOTTOM_B=0
    printf "${CYAN}Minimize Table Compression: Do you want to drop the bottom OPP floor? (y/n): ${NC}"
    read DROP_BOTTOM

    if [ "$DROP_BOTTOM" = "y" ] || [ "$DROP_BOTTOM" = "Y" ]; then
        printf "${YELLOW}Enter Little (L) BOTTOM OPP adjustment in mV (e.g., -25): ${NC}"
        read TARGET_BOTTOM_L
        printf "${YELLOW}Enter Big (B) BOTTOM OPP adjustment in mV (e.g., -25): ${NC}"
        read TARGET_BOTTOM_B
    fi

    printf "${YELLOW}Enter Little (L) TOP adjustment in mV (e.g., -200): ${NC}"
    read TARGET_L
    printf "${YELLOW}Enter Big (B) TOP adjustment in mV (e.g., -250): ${NC}"
    read TARGET_B
fi

# Validation
for val in "$TARGET_L" "$TARGET_B" "$TARGET_BOTTOM_L" "$TARGET_BOTTOM_B"; do
    if ! echo "$val" | grep -qE '^[-+]?[0-9]+$'; then
        printf "${RED}Error: '%s' is not a valid integer.${NC}\n" "$val"
        exit 1
    fi
done

printf "${CYAN}[INFO] CCI Voltage: Automatically synchronized with Little cluster.${NC}\n"

# Perform Calculations and generate the 48 values
NEW_VPROCS_LINE=$(awk -v t_l="$TARGET_L" -v t_b="$TARGET_B" -v tb_l="$TARGET_BOTTOM_L" -v tb_b="$TARGET_BOTTOM_B" '
BEGIN {
    # Stock values for G75
    # Little freqs and vprocs
    stock_freq[0,0] = 1800; stock_vproc[0,0] = 81
    stock_freq[0,1] = 1625; stock_vproc[0,1] = 69
    stock_freq[0,2] = 1500; stock_vproc[0,2] = 63
    stock_freq[0,3] = 1450; stock_vproc[0,3] = 61
    stock_freq[0,4] = 1375; stock_vproc[0,4] = 57
    stock_freq[0,5] = 1325; stock_vproc[0,5] = 55
    stock_freq[0,6] = 1275; stock_vproc[0,6] = 53
    stock_freq[0,7] = 1175; stock_vproc[0,7] = 48
    stock_freq[0,8] = 1100; stock_vproc[0,8] = 44
    stock_freq[0,9] = 1050; stock_vproc[0,9] = 42
    stock_freq[0,10] = 999; stock_vproc[0,10] = 39
    stock_freq[0,11] = 950; stock_vproc[0,11] = 37
    stock_freq[0,12] = 900; stock_vproc[0,12] = 35
    stock_freq[0,13] = 850; stock_vproc[0,13] = 32
    stock_freq[0,14] = 774; stock_vproc[0,14] = 28
    stock_freq[0,15] = 500; stock_vproc[0,15] = 24

    # Big freqs and vprocs
    stock_freq[1,0] = 2000; stock_vproc[1,0] = 94
    stock_freq[1,1] = 1950; stock_vproc[1,1] = 92
    stock_freq[1,2] = 1900; stock_vproc[1,2] = 90
    stock_freq[1,3] = 1850; stock_vproc[1,3] = 88
    stock_freq[1,4] = 1800; stock_vproc[1,4] = 85
    stock_freq[1,5] = 1710; stock_vproc[1,5] = 80
    stock_freq[1,6] = 1621; stock_vproc[1,6] = 75
    stock_freq[1,7] = 1532; stock_vproc[1,7] = 69
    stock_freq[1,8] = 1443; stock_vproc[1,8] = 64
    stock_freq[1,9] = 1354; stock_vproc[1,9] = 59
    stock_freq[1,10] = 1295; stock_vproc[1,10] = 55
    stock_freq[1,11] = 1176; stock_vproc[1,11] = 48
    stock_freq[1,12] = 1087; stock_vproc[1,12] = 43
    stock_freq[1,13] = 998;  stock_vproc[1,13] = 37
    stock_freq[1,14] = 909;  stock_vproc[1,14] = 32
    stock_freq[1,15] = 850;  stock_vproc[1,15] = 28

    # CCI freqs and vprocs
    stock_freq[2,0] = 1277; stock_vproc[2,0] = 81
    stock_freq[2,1] = 1120; stock_vproc[2,1] = 64
    stock_freq[2,2] = 1049; stock_vproc[2,2] = 60
    stock_freq[2,3] = 1014; stock_vproc[2,3] = 58
    stock_freq[2,4] = 961;  stock_vproc[2,4] = 54
    stock_freq[2,5] = 909;  stock_vproc[2,5] = 51
    stock_freq[2,6] = 856;  stock_vproc[2,6] = 48
    stock_freq[2,7] = 821;  stock_vproc[2,7] = 45
    stock_freq[2,8] = 768;  stock_vproc[2,8] = 42
    stock_freq[2,9] = 733;  stock_vproc[2,9] = 40
    stock_freq[2,10] = 698; stock_vproc[2,10] = 37
    stock_freq[2,11] = 663; stock_vproc[2,11] = 35
    stock_freq[2,12] = 628; stock_vproc[2,12] = 33
    stock_freq[2,13] = 593; stock_vproc[2,13] = 31
    stock_freq[2,14] = 558; stock_vproc[2,14] = 28
    stock_freq[2,15] = 500; stock_vproc[2,15] = 24

    targets[0] = t_l; targets[1] = t_b
    bot_targets[0] = tb_l; bot_targets[1] = tb_b
    names[0] = "Little (L)"; names[1] = "Big (B)   "; names[2] = "CCI       "

    for (j=0; j<2; j++) {
        if (targets[j] < 0) { max_steps[j] = int((targets[j] / 6.25) - 0.5) }
        else { max_steps[j] = int((targets[j] / 6.25) + 0.5) }
        actual_mv[j] = max_steps[j] * 6.25

        if (bot_targets[j] < 0) { bot_steps[j] = int((bot_targets[j] / 6.25) - 0.5) }
        else { bot_steps[j] = int((bot_targets[j] / 6.25) + 0.5) }
        actual_bot_mv[j] = bot_steps[j] * 6.25
    }
    
    max_steps[2] = max_steps[0]; actual_mv[2] = actual_mv[0]
    bot_steps[2] = bot_steps[0]; actual_bot_mv[2] = actual_bot_mv[0]

    for (c = 0; c < 3; c++) {
        max_f = stock_freq[c,0]
        min_f = stock_freq[c,15]
        curr_steps = max_steps[c]
        curr_bot_steps = bot_steps[c]
        floor_vproc = stock_vproc[c,15] + curr_bot_steps

        for (i = 0; i < 16; i++) {
            if (c == 2) {
                f_mid = 1014
                if (stock_freq[c,i] > f_mid) {
                    calculated_vprocs[c,i] = stock_vproc[c,i]
                } else if (stock_freq[c,i] == f_mid) {
                    calculated_vprocs[c,i] = calculated_vprocs[0,0]
                } else {
                    ratio = (f_mid == min_f) ? 0 : (stock_freq[c,i] - min_f) / (f_mid - min_f)
                    val = floor_vproc + (ratio * (calculated_vprocs[0,0] - floor_vproc))
                    calculated_vprocs[c,i] = int(val + 0.5)
                }
            } else {
                ratio = (max_f == min_f) ? 0 : (stock_freq[c,i] - min_f) / (max_f - min_f)
                change = curr_bot_steps + ratio * (curr_steps - curr_bot_steps)
                step_change = (change < 0) ? int(change - 0.5) : int(change + 0.5)
                calculated_vprocs[c,i] = stock_vproc[c,i] + step_change
                if (calculated_vprocs[c,i] < floor_vproc) calculated_vprocs[c,i] = floor_vproc
            }
        }

        for (i = 1; i < 16; i++) {
            if (calculated_vprocs[c,i] >= calculated_vprocs[c,i-1] && calculated_vprocs[c,i] > floor_vproc) {
                calculated_vprocs[c,i] = calculated_vprocs[c,i-1] - 1
                if (calculated_vprocs[c,i] < floor_vproc) calculated_vprocs[c,i] = floor_vproc
            }
        }

        for (i = 14; i >= 0; i--) {
            if (calculated_vprocs[c,i] <= calculated_vprocs[c,i+1]) {
                calculated_vprocs[c,i] = calculated_vprocs[c,i+1] + 1
                overlap_corrections++
                limit_hit = 1
            }
        }
    }

    # Print summary to stderr
    printf("\n\033[1;36m=== Voltages Applied ===\033[0m\n") > "/dev/stderr"
    for (j=0; j<2; j++) {
        vt = calculated_vprocs[j,0]; vb = calculated_vprocs[j,15]
        printf(" %s : Top: %7.2f mV (%.2fV) | Bot: %7.2f mV (%.2fV)\n", 
            names[j], actual_mv[j], (vt * 6.25 + 500) / 1000, actual_bot_mv[j], (vb * 6.25 + 500) / 1000) > "/dev/stderr"
    }
    printf("\033[1;36m==========================================\033[0m\n\n") > "/dev/stderr"

    if (limit_hit == 1) {
        printf("\033[1;33m[!] UNDERVOLT LIMIT REACHED (TABLE COMPRESSION)\033[0m\n") > "/dev/stderr"
        printf("    A bottom-up +1 correction was applied %d times to maintain monotonicity.\n", overlap_corrections) > "/dev/stderr"
    }

    # Print the space-separated values
    out_str = ""
    for (c = 0; c < 3; c++) {
        for (i = 0; i < 16; i++) {
            out_str = out_str calculated_vprocs[c,i] " "
        }
    }
    print out_str
}')

if [ -z "$NEW_VPROCS_LINE" ]; then
    printf "${RED}Error: Failed to calculate new voltages.${NC}\n"
    exit 1
fi

# 1. Update FILE_PV in-place
awk -v new_vprocs_str="$NEW_VPROCS_LINE" '
BEGIN {
    split(new_vprocs_str, new_vprocs, " ")
    count = 1
    in_tbl = 0
}
/static unsigned int FY_G75Tbl/ { in_tbl = 1; print; next }
/^};/ { if (in_tbl) { in_tbl = 0; print; next } }
in_tbl && /\{/ && /,/ {
    orig = $0
    c1 = index(orig, ",")
    rem = substr(orig, c1+1)
    c2 = index(rem, ",") + c1
    printf "%s %d%s\n", substr(orig, 1, c1), new_vprocs[count], substr(orig, c2)
    count++
    next
}
{ print }
' "$FILE_PV" > "${FILE_PV}.tmp" && mv "${FILE_PV}.tmp" "$FILE_PV"

# 2. Update FILE_OPP in-place (Only targeting G75!)
awk -v new_vprocs_str="$NEW_VPROCS_LINE" '
BEGIN {
    split(new_vprocs_str, new_vprocs, " ")
}
$1 == "#define" && $2 ~ /^CPU_DVFS_VOLT[0-9]+_VPROC[1-3]_G75$/ {
    name = $2
    idx_volt = name; sub(/.*VOLT/, "", idx_volt); sub(/_VPROC.*/, "", idx_volt)
    idx_vproc = name; sub(/.*_VPROC/, "", idx_vproc); sub(/_G75.*/, "", idx_vproc)
    global_idx = (idx_vproc - 1) * 16 + idx_volt
    new_val = new_vprocs[global_idx] * 625 + 50000
    printf "#define %-30s %5d\t\t/* 10uV */\n", name, new_val
    next
}
{ print }
' "$FILE_OPP" > "${FILE_OPP}.tmp" && mv "${FILE_OPP}.tmp" "$FILE_OPP"

# 3. Update FILE_UPOWER in-place
awk -v new_vprocs_str="$NEW_VPROCS_LINE" '
BEGIN {
    split(new_vprocs_str, new_vprocs, " ")
    in_struct = 0
    row_idx = 0
    cluster_offset = 0
}
/struct upower_tbl upower_tbl_l_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 0; print; next }
/struct upower_tbl upower_tbl_cluster_l_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 0; print; next }
/struct upower_tbl upower_tbl_b_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 16; print; next }
/struct upower_tbl upower_tbl_cluster_b_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 16; print; next }
/struct upower_tbl upower_tbl_cci_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 32; print; next }
in_struct && /\.volt = [0-9]+/ {
    if (row_idx < 16) {
        new_val = new_vprocs[cluster_offset + (16 - row_idx)] * 625 + 50000
        sub(/\.volt = [0-9]+/, ".volt = " new_val)
        row_idx++
    }
}
/^};/ { if (in_struct) in_struct = 0 }
{ print }
' "$FILE_UPOWER" > "${FILE_UPOWER}.tmp" && mv "${FILE_UPOWER}.tmp" "$FILE_UPOWER"

# Touch to trigger recompilation
touch "$TARGET_DIR"/*.c "$TARGET_DIR"/*.h drivers/misc/mediatek/base/power/include/upower_v2/*.h

if [ "$CMD_INPUT" = "reset" ]; then
    printf "\n${GREEN}[✓] Success! Restored stock CPU values.${NC}\n"
else
    printf "\n${GREEN}[✓] Success! Tables & Energy Model updated.${NC}\n"
fi
