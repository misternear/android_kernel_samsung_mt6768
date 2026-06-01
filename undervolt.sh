#!/bin/sh

# ==============================================================================
#  MT6768 CPU/CCI Undervolt & Energy Model Synchronization Tool
#  Automated Voltage Rail & UPOWER Table Patcher
# ==============================================================================

# Terminal Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m'

# --- Configuration ---
TARGET_DIR="drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768"

FILE_PV="$TARGET_DIR/mtk_cpufreq_opp_pv_table.h"
FILE_OPP="$TARGET_DIR/mtk_cpufreq_opp_table.h"
FILE_UPOWER="drivers/misc/mediatek/base/power/include/upower_v2/mtk_unified_power_data_mt6768.h"

BAK_PV="${FILE_PV}.bak"
BAK_OPP="${FILE_OPP}.bak"
BAK_UPOWER="${FILE_UPOWER}.bak"
TEMP_VPROC="$TARGET_DIR/temp_g75_vprocs.txt"

if [ ! -d "$TARGET_DIR" ]; then
    printf "${RED}Error: Directory '%s' not found.${NC}\n" "$TARGET_DIR"
    exit 1
fi

if [ ! -f "$BAK_PV" ]; then cp "$FILE_PV" "$BAK_PV"; fi
if [ ! -f "$BAK_OPP" ]; then cp "$FILE_OPP" "$BAK_OPP"; fi
if [ ! -f "$BAK_UPOWER" ]; then cp "$FILE_UPOWER" "$BAK_UPOWER"; fi

printf "${CYAN}Type 'reset' to restore stock backups, or press Enter to continue:${NC} "
read CMD_INPUT

if [ "$CMD_INPUT" = "reset" ]; then
    cp "$BAK_PV" "$FILE_PV"
    cp "$BAK_OPP" "$FILE_OPP"
    cp "$BAK_UPOWER" "$FILE_UPOWER"
    printf "${GREEN}Success! Restored original stock tables.${NC}\n"
    exit 0
fi

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

for val in "$TARGET_L" "$TARGET_B" "$TARGET_BOTTOM_L" "$TARGET_BOTTOM_B"; do
    if ! echo "$val" | grep -qE '^[-+]?[0-9]+$'; then
        printf "${RED}Error: '%s' is not a valid integer.${NC}\n" "$val"
        exit 1
    fi
done
printf "${CYAN}[INFO] CCI Voltage: Automatically synchronized with Little cluster.${NC}\n"

rm -f "$TEMP_VPROC"

# ==========================================
# STEP 1: Process with Anti-Compression
# ==========================================
awk -v t_l="$TARGET_L" -v t_b="$TARGET_B" -v tb_l="$TARGET_BOTTOM_L" -v tb_b="$TARGET_BOTTOM_B" -v temp_file="$TEMP_VPROC" '
BEGIN {
    in_tbl = 0; count = 0; cluster_idx = 0;
    top_little_vproc = -1; cci_mid_vproc = -1;
    overlap_corrections = 0; limit_hit = 0;

    targets[0] = t_l; targets[1] = t_b; 
    bot_targets[0] = tb_l; bot_targets[1] = tb_b;
    names[0] = "Little (L)"; names[1] = "Big (B)   "; names[2] = "CCI       ";

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
}

/static unsigned int FY_G75Tbl/ { in_tbl = 1; print; next }
/^};/ { if (in_tbl) { in_tbl = 0; print; next } }

in_tbl && /\{/ && /,/ {
    block_lines[count] = $0
    p1 = index($0, "{"); p2 = index($0, ",")
    f_str = substr($0, p1+1, p2-p1-1); gsub(/[^0-9]/, "", f_str)
    freqs[count] = f_str + 0
    rem = substr($0, p2+1); p3 = index(rem, ",")
    v_str = substr(rem, 1, p3-1); gsub(/[^0-9]/, "", v_str)
    vprocs[count] = v_str + 0
    count++
    
    if (count == 16) {
        max_f = freqs[0]; min_f = freqs[15];
        curr_steps = max_steps[cluster_idx];
        curr_bot_steps = bot_steps[cluster_idx];
        
        # New shifted floor
        floor_vproc = vprocs[15] + curr_bot_steps;
        
        # --- PASS 1: Base Calculation (Tilted Curve) ---
        for (i = 0; i < 16; i++) {
            if (cluster_idx == 2) {
                f_mid = 1014
                if (freqs[i] > f_mid) {
                    calculated_vprocs[i] = vprocs[i]
                } else if (freqs[i] == f_mid) {
                    calculated_vprocs[i] = little_vprocs_saved[0]
                } else {
                    ratio = (f_mid == min_f) ? 0 : (freqs[i] - min_f) / (f_mid - min_f)
                    val = floor_vproc + (ratio * (little_vprocs_saved[0] - floor_vproc))
                    calculated_vprocs[i] = int(val + 0.5)
                }
            } else {
                ratio = (max_f == min_f) ? 0 : (freqs[i] - min_f) / (max_f - min_f)
                
                # Interpolate offset between extreme top undervolt and lowered floor
                change = curr_bot_steps + ratio * (curr_steps - curr_bot_steps)
                step_change = (change < 0) ? int(change - 0.5) : int(change + 0.5)
                
                calculated_vprocs[i] = vprocs[i] + step_change
                if (calculated_vprocs[i] < floor_vproc) calculated_vprocs[i] = floor_vproc
            }
        }

        # --- PASS 2: Top-Down Smoothing ---
        for (i = 1; i < 16; i++) {
            if (calculated_vprocs[i] >= calculated_vprocs[i-1] && calculated_vprocs[i] > floor_vproc) {
                calculated_vprocs[i] = calculated_vprocs[i-1] - 1;
                if (calculated_vprocs[i] < floor_vproc) calculated_vprocs[i] = floor_vproc;
            }
        }

        # --- PASS 3: Bottom-Up Anti-Compression ---
        for (i = 14; i >= 0; i--) {
            if (calculated_vprocs[i] <= calculated_vprocs[i+1]) {
                calculated_vprocs[i] = calculated_vprocs[i+1] + 1;
                overlap_corrections++;
                limit_hit = 1;
            }
        }

        for (i = 0; i < 16; i++) {
            if (i == 0) { top_vprocs[cluster_idx] = calculated_vprocs[i] }
            if (i == 15) { bot_vprocs[cluster_idx] = calculated_vprocs[i] }
            if (cluster_idx == 0 && freqs[i] == 1800) { top_little_vproc = calculated_vprocs[i] }
            if (cluster_idx == 2 && freqs[i] == 1014) { cci_mid_vproc = calculated_vprocs[i] }

            if (cluster_idx == 0) {
                little_freqs[i]       = freqs[i]
                little_vprocs_saved[i] = calculated_vprocs[i]
            }

            print calculated_vprocs[i] >> temp_file

            orig = block_lines[i]; c1 = index(orig, ","); rem = substr(orig, c1+1); c2 = index(rem, ",") + c1
            printf "%s %2d%s\n", substr(orig, 1, c1), calculated_vprocs[i], substr(orig, c2)
        }
        count = 0; cluster_idx++
    }
    next
}

END {
    printf("\n\033[1;36m=== Voltages Applied ===\033[0m\n") > "/dev/stderr"
    for (j=0; j<2; j++) {
        vt = top_vprocs[j]; vb = bot_vprocs[j]
        printf(" %s : Top: %7.2f mV (%.2fV) | Bot: %7.2f mV (%.2fV)\n", 
            names[j], actual_mv[j], (vt * 6.25 + 500) / 1000, actual_bot_mv[j], (vb * 6.25 + 500) / 1000) > "/dev/stderr"
    }
    printf("\033[1;36m==========================================\033[0m\n\n") > "/dev/stderr"

    if (limit_hit == 1) {
        printf("\033[1;33m[!] UNDERVOLT LIMIT REACHED (TABLE COMPRESSION)\033[0m\n") > "/dev/stderr"
        printf("    A bottom-up +1 correction was applied %d times to maintain monotonicity.\n", overlap_corrections) > "/dev/stderr"
        printf("    Hint: Lower the bottom OPP further to stop this.\n\n") > "/dev/stderr"
    }
}
{ print }
' "$BAK_PV" > "${FILE_PV}.tmp"

if [ ! -f "$TEMP_VPROC" ]; then
    printf "${RED}Error: Failed to process backup files.${NC}\n"
    rm -f "${FILE_PV}.tmp"
    exit 1
fi

# ==========================================
# STEP 2 & 3: Process OPP Table & UPOWER
# ==========================================
awk -v temp_file="$TEMP_VPROC" '
BEGIN {
    i = 0
    while ((getline line < temp_file) > 0) { new_vprocs[i] = line; i++ }
    close(temp_file)
}
$1 == "#define" && $2 ~ /^CPU_DVFS_VOLT[0-9]+_VPROC[1-3](_.*)?$/ {
    name = $2
    idx_volt = name; sub(/.*VOLT/, "", idx_volt); sub(/_VPROC.*/, "", idx_volt)
    idx_vproc = name; sub(/.*_VPROC/, "", idx_vproc); sub(/_.*/, "", idx_vproc)
    global_idx = (idx_vproc - 1) * 16 + idx_volt
    if (global_idx in new_vprocs) {
        new_val = new_vprocs[global_idx] * 625 + 50000
        printf "#define %-30s %5d\t\t/* 10uV */\n", name, new_val
        next
    }
}
{ print }
' "$BAK_OPP" > "${FILE_OPP}.tmp"

awk -v temp_file="$TEMP_VPROC" '
BEGIN {
    i = 0
    while ((getline line < temp_file) > 0) { new_vprocs[i] = line; i++ }
    close(temp_file); in_struct = 0; row_idx = 0; cluster_offset = 0;
}
/struct upower_tbl upower_tbl_l_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 0; print; next }
/struct upower_tbl upower_tbl_cluster_l_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 0; print; next }
/struct upower_tbl upower_tbl_b_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 16; print; next }
/struct upower_tbl upower_tbl_cluster_b_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 16; print; next }
/struct upower_tbl upower_tbl_cci_G75 =/ { in_struct = 1; row_idx = 0; cluster_offset = 32; print; next }
in_struct && /\.volt = [0-9]+/ {
    if (row_idx < 16) {
        new_val = new_vprocs[cluster_offset + (15 - row_idx)] * 625 + 50000
        sub(/\.volt = [0-9]+/, ".volt = " new_val)
        row_idx++
    }
}
/^};/ { if (in_struct) in_struct = 0 }
{ print }
' "$BAK_UPOWER" > "${FILE_UPOWER}.tmp"

mv "${FILE_PV}.tmp" "$FILE_PV"
mv "${FILE_OPP}.tmp" "$FILE_OPP"
mv "${FILE_UPOWER}.tmp" "$FILE_UPOWER"
rm -f "$TEMP_VPROC"

touch "$TARGET_DIR"/*.c "$TARGET_DIR"/*.h drivers/misc/mediatek/base/power/include/upower_v2/*.h
printf "\n${GREEN}[✓] Success! Tables & Energy Model updated.${NC}\n"
