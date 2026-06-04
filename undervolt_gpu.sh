#!/bin/sh

# Terminal Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m'

TARGET_DIR="drivers/misc/mediatek/base/power/mt6768"
FILE_C="$TARGET_DIR/mtk_gpufreq_core.c"
FILE_H="$TARGET_DIR/mtk_gpufreq_core.h"

if [ ! -d "$TARGET_DIR" ]; then
    printf "${RED}Error: Directory '%s' not found. Run from kernel root.${NC}\n" "$TARGET_DIR"
    exit 1
fi

if [ ! -f "$FILE_C" ] || [ ! -f "$FILE_H" ]; then
    printf "${RED}Error: Could not find driver files in '%s'.${NC}\n" "$TARGET_DIR"
    exit 1
fi

echo "${CYAN}Type 'reset' to restore stock driver/tables, or press Enter to continue:${NC}"
read CMD_INPUT
if [ "$CMD_INPUT" = "reset" ]; then
    NUM_STATES=32
    TARGET_FREQ=0
    TARGET_VOLT=0
else
    # User inputs
    while true; do
        printf "${YELLOW}States (4-32): ${NC}" && read NUM_STATES
        if [ "$NUM_STATES" -ge 4 ] && [ "$NUM_STATES" -le 32 ] 2>/dev/null; then
            break
        fi
        printf "${RED}Error: States must be an integer between 4 and 32.${NC}\n"
    done
    printf "${YELLOW}Freq Adjustment (Stock top: 1000 MHz | enter +/- MHz delta): ${NC}" && read TARGET_FREQ
    printf "${YELLOW}Volt Adjustment (Stock top: 950 mV, floor: 612.5 mV | enter +/- mV): ${NC}" && read TARGET_VOLT
fi

MAX_IDX=$((NUM_STATES - 1))

# 1. Patch mtk_gpufreq_core.c in place
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
}' "$FILE_C" > "${FILE_C}.tmp" && mv "${FILE_C}.tmp" "$FILE_C"

# 2. Patch mtk_gpufreq_core.h in place using stock values hardcoded in the script
awk -v t_freq="$TARGET_FREQ" -v t_volt="$TARGET_VOLT" -v num_states="$NUM_STATES" '
BEGIN {
    # Hardcoded Stock Freqs (KHz) and Volts (10uV)
    stock_freq[0]=1000000; stock_volt[0]=95000
    stock_freq[1]=975000;  stock_volt[1]=92500
    stock_freq[2]=950000;  stock_volt[2]=90000
    stock_freq[3]=925000;  stock_volt[3]=87500
    stock_freq[4]=900000;  stock_volt[4]=85000
    stock_freq[5]=875000;  stock_volt[5]=82500
    stock_freq[6]=850000;  stock_volt[6]=80000
    stock_freq[7]=823000;  stock_volt[7]=79375
    stock_freq[8]=796000;  stock_volt[8]=78125
    stock_freq[9]=769000;  stock_volt[9]=76875
    stock_freq[10]=743000; stock_volt[10]=75625
    stock_freq[11]=716000; stock_volt[11]=75000
    stock_freq[12]=690000; stock_volt[12]=73750
    stock_freq[13]=663000; stock_volt[13]=72500
    stock_freq[14]=637000; stock_volt[14]=71250
    stock_freq[15]=611000; stock_volt[15]=70625
    stock_freq[16]=586000; stock_volt[16]=70000
    stock_freq[17]=560000; stock_volt[17]=69375
    stock_freq[18]=535000; stock_volt[18]=68750
    stock_freq[19]=509000; stock_volt[19]=68125
    stock_freq[20]=484000; stock_volt[20]=66875
    stock_freq[21]=467000; stock_volt[21]=66875
    stock_freq[22]=450000; stock_volt[22]=66250
    stock_freq[23]=434000; stock_volt[23]=65625
    stock_freq[24]=417000; stock_volt[24]=65000
    stock_freq[25]=400000; stock_volt[25]=64375
    stock_freq[26]=383000; stock_volt[26]=64375
    stock_freq[27]=366000; stock_volt[27]=63750
    stock_freq[28]=349000; stock_volt[28]=63125
    stock_freq[29]=332000; stock_volt[29]=62500
    stock_freq[30]=315000; stock_volt[30]=61875
    stock_freq[31]=299000; stock_volt[31]=61250

    target_max_idx = num_states - 1
    CURVE_EXP      = 1.6
    ABS_HW_MIN     = 60000

    # Offset calculations
    volt_offset = t_volt * 100
    floor_v = 61250 + volt_offset
    if (floor_v < ABS_HW_MIN) floor_v = ABS_HW_MIN

    new_top_f = 1000000 + (t_freq * 1000)
    new_bot_f = 299000
    f_step_size = (new_top_f - new_bot_f) / target_max_idx

    V_top = 95000 + volt_offset
    V_range = V_top - floor_v

    for (i = 0; i <= target_max_idx; i++) {
        new_freq[i] = int(new_top_f - (i * f_step_size) + 0.5)
        v_linear    = (target_max_idx == 0) ? 1.0 : (target_max_idx - i) / target_max_idx
        v_curved    = v_linear ^ CURVE_EXP
        curve_pos[i] = v_curved
        raw_v       = floor_v + (v_curved * V_range)
        new_volt[i] = int((raw_v / 625) + 0.5) * 625
        if (new_volt[i] < floor_v) new_volt[i] = floor_v
    }

    for (i = target_max_idx - 1; i >= 0; i--) {
        if (new_volt[i] <= new_volt[i+1])
            new_volt[i] = new_volt[i+1] + 625
    }

    VSRAM_top = V_top + 10000
    VSRAM_bot = floor_v + 5000
    if (VSRAM_bot < 60000) VSRAM_bot = 60000
    VSRAM_range = VSRAM_top - VSRAM_bot

    for (i = 0; i <= target_max_idx; i++) {
        raw_vsram = VSRAM_bot + (curve_pos[i] * VSRAM_range)
        new_vsram[i] = int((raw_vsram / 625) + 0.5) * 625
        if (new_vsram[i] < VSRAM_bot) new_vsram[i] = VSRAM_bot
        if (new_vsram[i] < new_volt[i] + 5000)
            new_vsram[i] = int(((new_volt[i] + 5000) / 625) + 0.5) * 625
    }
}
# Skip any existing generated macros/defines
$1 == "#define" && $2 ~ /^SEG_GPU_DVFS_(FREQ|VOLT|VSRAM)[0-9]+/ { next }
# Insert the newly calculated definitions right before FIXED_VSRAM_VOLT
$1 == "#define" && $2 == "FIXED_VSRAM_VOLT" {
    print "/* GENERATED: " num_states " STATES | volt offset: " t_volt " mV | freq offset: " t_freq " MHz | exp=" CURVE_EXP " */"
    for (i = 0; i <= target_max_idx; i++) printf "#define SEG_GPU_DVFS_FREQ%-10d(%d)\n", i, new_freq[i]
    print ""
    for (i = 0; i <= target_max_idx; i++) printf "#define SEG_GPU_DVFS_VOLT%-10d(%d)\n", i, new_volt[i]
    print ""
    for (i = 0; i <= target_max_idx; i++) printf "#define SEG_GPU_DVFS_VSRAM%-9d(%d)\n", i, new_vsram[i]
    print ""
}
{ print }
' "$FILE_H" > "${FILE_H}.tmp" && mv "${FILE_H}.tmp" "$FILE_H"

touch "$TARGET_DIR"/*.c "$TARGET_DIR"/*.h
if [ "$CMD_INPUT" = "reset" ]; then
    printf "\n${GREEN}[✓] Success! Restored stock GPU driver/tables.${NC}\n"
else
    printf "\n${GREEN}[✓] Success! GPU Tables updated in $TARGET_DIR.${NC}\n"
fi
