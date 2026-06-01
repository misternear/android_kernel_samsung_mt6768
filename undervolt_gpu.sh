#!/bin/sh

# ==============================================================================
#  MT6768 GPU Undervolt & DVFS Table Patcher
# ==============================================================================

# Terminal Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m'

# --- Configuration ---
TARGET_DIR="drivers/misc/mediatek/base/power/mt6768"
FILE_C="$TARGET_DIR/mtk_gpufreq_core.c"
FILE_H="$TARGET_DIR/mtk_gpufreq_core.h"
BAK_C="${FILE_C}.bak"
BAK_H="${FILE_H}.bak"
TEMP_C="$TARGET_DIR/temp_c_out.c"
TEMP_H="$TARGET_DIR/temp_h_out.h"

if [ ! -d "$TARGET_DIR" ]; then
    printf "${RED}Error: Directory '%s' not found. Run from kernel root.${NC}\n" "$TARGET_DIR"
    exit 1
fi

# Ensure backups exist
for f in "$FILE_C" "$FILE_H"; do
    if [ ! -f "$f" ]; then printf "${RED}Error: Could not find %s${NC}\n" "$f"; exit 1; fi
    if [ ! -f "${f}.bak" ]; then cp "$f" "${f}.bak"; fi
done

echo "${CYAN}Type 'reset' to restore stock driver/tables, or press Enter to continue:${NC}"
read CMD_INPUT
if [ "$CMD_INPUT" = "reset" ]; then
    cp "$BAK_C" "$FILE_C" && cp "$BAK_H" "$FILE_H"
    touch "$TARGET_DIR"/*.h "$TARGET_DIR"/*.c
    printf "${GREEN}Success! Restored original stock files.${NC}\n"
    exit 0
fi

# 1. PARSE STOCK VALUES FROM BACKUP HEADER
STOCK_FREQ0=$(awk '$1=="#define" && $2=="SEG_GPU_DVFS_FREQ0" {gsub(/[()]/,"",$3); print $3+0; exit}' "$BAK_H")
STOCK_VOLT0=$(awk '$1=="#define" && $2=="SEG_GPU_DVFS_VOLT0" {gsub(/[()]/,"",$3); print $3+0; exit}' "$BAK_H")
STOCK_BOT_VOLT=$(awk 'BEGIN{m=0} $1=="#define" && $2~/^SEG_GPU_DVFS_VOLT[0-9]/{gsub(/[()]/,"",$3); v=$3+0; if(v>0&&(m==0||v<m)) m=v} END{print m}' "$BAK_H")
STOCK_FREQ_MHZ=$((STOCK_FREQ0 / 1000))
STOCK_VOLT_MV=$((STOCK_VOLT0 / 100))
STOCK_BOT_MV=$((STOCK_BOT_VOLT / 100))

# 2. USER INPUTS
while true; do
    printf "${YELLOW}States (4-32): ${NC}" && read NUM_STATES
    if [ "$NUM_STATES" -ge 4 ] && [ "$NUM_STATES" -le 32 ] 2>/dev/null; then
        break
    fi
    printf "${RED}Error: States must be an integer between 4 and 32.${NC}\n"
done
printf "${YELLOW}Freq Adjustment (Stock top: ${STOCK_FREQ_MHZ} MHz | enter +/- MHz delta): ${NC}" && read TARGET_FREQ
printf "${YELLOW}Volt Adjustment (Stock top: ${STOCK_VOLT_MV} mV, floor: ${STOCK_BOT_MV} mV | enter +/- mV): ${NC}" && read TARGET_VOLT

MAX_IDX=$((NUM_STATES - 1))

# 2. PATCH THE C DRIVER
awk -v max_idx="$MAX_IDX" '
BEGIN { in_table = 0 }
/static struct g_opp_table_info g_opp_table_segment\[\] = \{/ {
    print $0
    for(i = 0; i <= max_idx; i++) {
        printf("\tGPUOP(SEG_GPU_DVFS_FREQ%-2d, SEG_GPU_DVFS_VOLT%-2d, SEG_GPU_DVFS_VSRAM%-2d),\n", i, i, i)
    }
    in_table = 1; next
}
in_table == 1 && /^\};/ { in_table = 0; print $0; next }
in_table == 1 { next }
{
    if ($0 ~ /g_segment_min_opp_idx[ \t]*=[ \t]*[0-9]+;/)
        sub(/[0-9]+;/, max_idx ";", $0)
    print $0
}' "$BAK_C" > "$TEMP_C" && mv "$TEMP_C" "$FILE_C"

# 3. PATCH THE HEADER
# Voltage uses a power curve (exp 1.6) — mid-OPPs lifted above linear line.
# VSRAM uses its own anchored curve: +150mV at top tapering to +50mV at bottom,
# matching real MT6768 hand-tuned behaviour. Floor auto-tracks the undervolt.
awk -v t_freq="$TARGET_FREQ" -v t_volt="$TARGET_VOLT" \
    -v stock_bot_volt="$STOCK_BOT_VOLT" -v num_states="$NUM_STATES" '
BEGIN {
    max_orig_idx   = 0
    target_max_idx = num_states - 1
    CURVE_EXP      = 1.6   # >1 = convex curve (mid OPPs get more voltage)
    ABS_HW_MIN     = 60000 # 600 mV hard floor (in 10 uV units)
}
{
    lines[NR] = $0
    if ($1 == "#define" && $2 ~ /^SEG_GPU_DVFS_/) {
        is_macro[NR] = 1
        if ($2 ~ /^SEG_GPU_DVFS_FREQ/) {
            idx = $2; sub(/SEG_GPU_DVFS_FREQ/, "", idx); val = $3; gsub(/[()]/, "", val)
            orig_freq[idx+0] = val+0
            if ((idx+0) > max_orig_idx) max_orig_idx = (idx+0)
        }
        if ($2 ~ /^SEG_GPU_DVFS_VOLT/) {
            idx = $2; sub(/SEG_GPU_DVFS_VOLT/, "", idx); val = $3; gsub(/[()]/, "", val)
            orig_volt[idx+0] = val+0
        }
    }
}
END {
    # mV input -> internal 10 uV units (1 mV = 100 units)
    volt_offset = t_volt * 100

    # Auto-floor: stock bottom OPP slides down by the same undervolt offset
    floor_v = stock_bot_volt + volt_offset
    if (floor_v < ABS_HW_MIN) floor_v = ABS_HW_MIN

    # Frequency: linear steps across target OPP count
    new_top_f   = orig_freq[0] + (t_freq * 1000)
    new_bot_f   = orig_freq[max_orig_idx]
    f_step_size = (new_top_f - new_bot_f) / target_max_idx

    # Voltage anchors
    V_top   = orig_volt[0] + volt_offset
    V_range = V_top - floor_v

    # Compute frequency and voltage for each OPP; save curve position for VSRAM
    for (i = 0; i <= target_max_idx; i++) {
        new_freq[i] = int(new_top_f - (i * f_step_size) + 0.5)

        # Position: 1.0 = top OPP, 0.0 = bottom OPP
        v_linear    = (target_max_idx == 0) ? 1.0 : (target_max_idx - i) / target_max_idx
        v_curved    = v_linear ^ CURVE_EXP
        curve_pos[i] = v_curved   # reused for VSRAM below

        raw_v       = floor_v + (v_curved * V_range)
        new_volt[i] = int((raw_v / 625) + 0.5) * 625
        if (new_volt[i] < floor_v) new_volt[i] = floor_v
    }

    # Bottom-up monotonicity pass: each OPP at least 1 step (6.25 mV) above next
    for (i = target_max_idx - 1; i >= 0; i--) {
        if (new_volt[i] <= new_volt[i+1])
            new_volt[i] = new_volt[i+1] + 625
    }

    # VSRAM: own anchored curve — +15000 (150mV) at top tapering to +5000 (50mV)
    # at bottom, mirroring real MT6768 hand-tuned tables.
    VSRAM_top   = V_top + 10000
    VSRAM_bot   = floor_v + 5000
    if (VSRAM_bot < 60000) VSRAM_bot = 60000   # absolute VSRAM floor: 600 mV
    VSRAM_range = VSRAM_top - VSRAM_bot

    for (i = 0; i <= target_max_idx; i++) {
        raw_vsram    = VSRAM_bot + (curve_pos[i] * VSRAM_range)
        new_vsram[i] = int((raw_vsram / 625) + 0.5) * 625
        if (new_vsram[i] < VSRAM_bot) new_vsram[i] = VSRAM_bot
        # Hard minimum gap: VSRAM must be >= VGPU + 50 mV (5000 units)
        if (new_vsram[i] < new_volt[i] + 5000)
            new_vsram[i] = int(((new_volt[i] + 5000) / 625) + 0.5) * 625
    }

    # Output generation
    inserted = 0
    for (k = 1; k <= NR; k++) {
        if (is_macro[k]) {
            if (!inserted) {
                print "/* GENERATED: " num_states " STATES | volt offset: " t_volt " mV | freq offset: " t_freq " MHz | exp=" CURVE_EXP " */"
                for (i = 0; i <= target_max_idx; i++) printf "#define SEG_GPU_DVFS_FREQ%-10d(%d)\n", i, new_freq[i]
                print ""
                for (i = 0; i <= target_max_idx; i++) printf "#define SEG_GPU_DVFS_VOLT%-10d(%d)\n", i, new_volt[i]
                print ""
                for (i = 0; i <= target_max_idx; i++) printf "#define SEG_GPU_DVFS_VSRAM%-9d(%d)\n", i, new_vsram[i]
                inserted = 1
            }
            continue
        }
        if (inserted && lines[k] == "" && is_macro[k+1]) continue
        print lines[k]
    }
}' "$BAK_H" > "$TEMP_H" && mv "$TEMP_H" "$FILE_H"

touch "$TARGET_DIR"/*.c "$TARGET_DIR"/*.h
printf "\n${GREEN}[✓] Success! GPU Tables updated in $TARGET_DIR.${NC}\n"
